import Foundation
import CryptoKit
import OSLog

// MARK: - API Error

enum BangumiAPIError: Error, LocalizedError {
    case notImplemented
    case unauthorized
    case networkTimeout
    case networkUnavailable
    case serverUnreachable
    case networkError(Error)
    case decodingError(Error)
    case httpError(Int)
    case rateLimited
    case invalidURL

    /// Structured error categories matching the PRD §5.3.5 taxonomy.
    var userFacingMessage: String {
        switch self {
        case .notImplemented:       return "功能尚未实现"
        case .unauthorized:         return "登录已过期，请重新登录"
        case .networkTimeout:       return "请求超时，请检查网络后重试"
        case .networkUnavailable:   return "网络连接不可用，请检查网络设置"
        case .serverUnreachable:    return "无法连接到服务器，请稍后重试"
        case .networkError:         return "网络请求失败，请稍后重试"
        case .decodingError:        return "数据解析异常，请稍后重试"
        case .httpError(let code):
            if (500...599).contains(code) { return "服务器暂时不可用，请稍后重试" }
            return "请求失败 (HTTP \(code))，请稍后重试"
        case .rateLimited:          return "请求过于频繁，请稍后再试"
        case .invalidURL:           return "请求地址无效"
        }
    }

    var errorDescription: String? { userFacingMessage }

    /// Maps a raw Error (typically URLError) to the structured BangumiAPIError taxonomy.
    /// Used by `performRequestWithFallback` so ViewModels consistently receive zh-CN messages.
    static func from(_ error: Error) -> BangumiAPIError {
        if let apiError = error as? BangumiAPIError { return apiError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:                           return .networkTimeout
            case .notConnectedToInternet,
                 .networkConnectionLost:              return .networkUnavailable
            case .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed:                    return .serverUnreachable
            default:                                  return .networkError(error)
            }
        }
        return .networkError(error)
    }

    var isRetryable: Bool {
        switch self {
        case .networkTimeout, .networkUnavailable, .serverUnreachable, .networkError: true
        case .httpError(let code): (500...599).contains(code)
        case .rateLimited, .unauthorized, .decodingError, .invalidURL, .notImplemented: false
        }
    }
}

// MARK: - API Client

actor BangumiAPIClient {
    private let session: URLSession
    private let baseURLs: [String]
    private static let defaultBaseURLs = [
        "https://api.bgm.tv",
        "https://bgmapi.anibt.net",
    ]
    private var token: String?
    private var currentUsername: String?
    private var currentUserId: Int?

    // MARK: - Response Cache (all bgm reads)
    // Generic TTL cache of raw response Data, keyed by method+path+query+bodyHash.
    // Covers every read endpoint uniformly (incl. POST search). Writes are never
    // cached; they invalidate the related read entries. See cacheTTL(for:).
    private struct CacheEntry: Codable, Sendable {
        let data: Data
        let cachedAt: Date
    }

    /// Hard cap on the in-memory + on-disk cache. When exceeded, the oldest
    /// entries (by cachedAt) are evicted down to ~90% of the cap.
    private let maxCacheEntries = 500
    /// Cooldown before respawning a background refresh after a failed attempt,
    /// so an outage doesn't spawn one fresh refresh per stale read.
    private let refreshFailureBackoff: TimeInterval = 30

    /// Longest TTL the policy in `cacheTTL(for:)` may grant. Centralised so
    /// the disk-load filter (and any future "max staleness" reasoning) stays
    /// aligned with the policy when TTLs are bumped.
    private static let maxTTL: TimeInterval = 24 * 3600

    private var cache: [String: CacheEntry] = [:]
    /// Tasks currently fetching a key (blocking or background). Used to dedup
    /// concurrent fetches and to cancel in-flight work on token change.
    private var inflightFetches: [String: Task<Data, Error>] = [:]
    /// Last failure time per key — gates background-refresh respawning.
    private var refreshFailureAt: [String: Date] = [:]
    /// Bumped on every account-changing setToken / clearResponseCache.
    /// In-flight fetches stamp the generation when started; if it has changed
    /// by the time they return, the response is neither written into the new
    /// generation's cache nor returned to the caller (prevents account A's
    /// data from surfacing in account B's session after a logout/login race).
    private var cacheGeneration: UInt64 = 0

    /// Off-actor disk load scheduled at init. Awaited at first cache touch so
    /// `init` doesn't block the main thread on a multi-MB JSON decode.
    private var cacheLoadTask: Task<[String: CacheEntry], Never>?
    /// Whether the first setToken (the launch-time "load saved token" call)
    /// has run. Distinguishing the initial call from a real account change
    /// lets us preserve the disk cache across app launches.
    private var initialTokenLoadDone = false

    private let cacheURL: URL = {
        // Caches dir: not iCloud-backed (the response cache is regenerable),
        // and the system can purge it under storage pressure — both are the
        // right semantics here. Application Support, by contrast, is backed
        // up to iCloud by default and would eat user quota.
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("bangumi_response_cache.json")
    }()

    // Coalescing serial disk writer: any state mutation flips dirty=true; a
    // single background loop snapshots+writes on the actor, then re-checks
    // the flag and loops. Bursts collapse into one write per drain cycle, and
    // writes are strictly ordered (vs the old per-call Task.detached which
    // could land an older snapshot on top of a newer one).
    private var diskWriteDirty: Bool = false
    private var diskWriterRunning: Bool = false

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    init(session: URLSession = .shared, baseURLs: [String] = BangumiAPIClient.defaultBaseURLs) {
        self.session = session
        self.baseURLs = baseURLs
        // Decode the on-disk cache off the main thread. The first request
        // that consults the cache awaits this task via awaitCacheLoadIfNeeded;
        // writes (no TTL) skip the wait entirely.
        let url = cacheURL
        self.cacheLoadTask = Task.detached(priority: .utility) {
            Self.loadCacheFromDisk(url: url)
        }
    }

    func setToken(_ token: String?) {
        let prev = self.token
        self.token = token
        self.currentUsername = nil
        self.currentUserId = nil

        if !initialTokenLoadDone {
            // Launch-time "load saved token from Keychain" call. There's no
            // previous account to compare against; preserve the disk cache
            // so the first paint can serve from it. Subsequent setToken
            // calls follow the normal path below.
            initialTokenLoadDone = true
            return
        }

        if prev == token {
            // No-op refresh (e.g. re-applying the same token). Nothing to drop.
            return
        }

        // Token = user identity, and it actually changed. Drop everything
        // tied to the previous account: cache, in-flight fetches (cancelled
        // — their responses must not land in the new account's cache),
        // failure cooldowns, and bump the generation so any task we couldn't
        // cancel discards its result on return.
        cache.removeAll()
        for task in inflightFetches.values { task.cancel() }
        inflightFetches.removeAll()
        refreshFailureAt.removeAll()
        cacheGeneration &+= 1
        // The pending disk load (if any) was written under the old account
        // — abandon it.
        cacheLoadTask?.cancel()
        cacheLoadTask = nil
        markDiskDirty()
    }

    func hasToken() -> Bool {
        token != nil
    }

    /// Current cache generation — bumped on every account-changing `setToken`.
    /// The 401 handler reads this to drop stale unauthorized notifications from
    /// requests that left with an already-replaced token (a refresh or paste
    /// bumps the generation).
    func currentGeneration() -> Int { Int(cacheGeneration) }

    private func resolveUsername() async throws -> String {
        if let cached = currentUsername { return cached }
        let me: UserInfo = try await request("/v0/me")
        currentUsername = me.username
        currentUserId = me.id
        return me.username
    }

    /// Resolves the numeric user id for the current token. Used as the per-user
    /// key for local-only state (e.g. WishCollectedAt). Reuses the same `/v0/me`
    /// hit as username resolution.
    func resolveUserId() async throws -> Int {
        if let cached = currentUserId { return cached }
        let me: UserInfo = try await request("/v0/me")
        currentUsername = me.username
        currentUserId = me.id
        return me.id
    }

    // MARK: - Subjects

    /// Browse subjects with optional season filter using POST /v0/search/subjects.
    /// Bangumi v0 has no plain GET /v0/subjects listing — season/type browsing is done via search filters.
    func fetchSubjects(type: Int? = nil, year: Int? = nil, month: Int? = nil, sort: String? = nil) async throws -> [Subject] {
        var filter = SubjectSearchFilter()
        if let type { filter.type = [type] }
        if let year, let month {
            let monthStr = String(format: "%02d", month)
            let nextMonth = month == 12 ? 1 : month + 1
            let nextYear = month == 12 ? year + 1 : year
            let nextMonthStr = String(format: "%02d", nextMonth)
            filter.airDate = [">=\(year)-\(monthStr)-01", "<\(nextYear)-\(nextMonthStr)-01"]
        } else if let year {
            filter.airDate = [">=\(year)-01-01", "<\(year + 1)-01-01"]
        }
        let payload = SearchSubjectsBody(keyword: "", sort: sort ?? "rank", filter: filter)
        let response: PagedSubject = try await request(
            "/v0/search/subjects",
            method: "POST",
            query: [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: "0")],
            body: payload
        )
        return response.data
    }

    func fetchSubject(id: Int) async throws -> Subject {
        try await request("/v0/subjects/\(id)")
    }

    // MARK: - Episodes

    func fetchEpisodes(subjectId: Int, type: Int? = nil) async throws -> [Episode] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "subject_id", value: String(subjectId)),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        if let type { query.append(URLQueryItem(name: "type", value: String(type))) }
        let response: PagedEpisode = try await request("/v0/episodes", query: query)
        return response.data
    }

    // MARK: - Search

    func searchSubjects(keyword: String, filter: SubjectSearchFilter? = nil, sort: String? = nil) async throws -> [Subject] {
        let payload = SearchSubjectsBody(keyword: keyword, sort: sort ?? "match", filter: filter ?? SubjectSearchFilter())
        let response: PagedSubject = try await request(
            "/v0/search/subjects",
            method: "POST",
            query: [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: "0")],
            body: payload
        )
        return response.data
    }

    // MARK: - Character & Person Search

    func searchCharacters(keyword: String) async throws -> [CharacterSearchResult] {
        let payload = SearchKeywordBody(keyword: keyword)
        let response: PagedCharacterSearch = try await request(
            "/v0/search/characters",
            method: "POST",
            query: [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: "0")],
            body: payload
        )
        return response.data
    }

    func searchPersons(keyword: String) async throws -> [PersonSearchResult] {
        let payload = SearchKeywordBody(keyword: keyword)
        let response: PagedPersonSearch = try await request(
            "/v0/search/persons",
            method: "POST",
            query: [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: "0")],
            body: payload
        )
        return response.data
    }

    // MARK: - Subject Characters & Persons & Related

    func fetchSubjectCharacters(subjectId: Int) async throws -> [SubjectCharacter] {
        try await request("/v0/subjects/\(subjectId)/characters")
    }

    func fetchSubjectPersons(subjectId: Int) async throws -> [SubjectPerson] {
        try await request("/v0/subjects/\(subjectId)/persons")
    }

    func fetchRelatedSubjects(subjectId: Int) async throws -> [RelatedSubject] {
        try await request("/v0/subjects/\(subjectId)/subjects")
    }

    // MARK: - Character & Person Detail

    func fetchCharacterDetail(id: Int) async throws -> CharacterDetail {
        try await request("/v0/characters/\(id)")
    }

    func fetchPersonDetail(id: Int) async throws -> PersonDetail {
        try await request("/v0/persons/\(id)")
    }

    // MARK: - Calendar

    func fetchCalendar() async throws -> [CalendarDay] {
        try await request("/calendar")
    }

    // MARK: - User Collections

    func fetchUserCollections(username: String = "-", type: Int? = nil) async throws -> [UserSubjectCollection] {
        // `-` 404s on the list endpoint for some accounts (e.g. numeric usernames),
        // so resolve to the real username — same gotcha as the single-collection GET.
        let user = username == "-" ? try await resolveUsername() : username
        // Auto-paginate: a single request is capped at 50, so users with more
        // (e.g. 51 wishes) would otherwise lose the tail. Loop until exhausted.
        // maxPages provides a safety net against runaway requests if the API's
        // total field is inconsistent.
        let pageSize = 50
        var offset = 0
        var all: [UserSubjectCollection] = []
        var pageCount = 0
        let maxPages = 100
        while true {
            pageCount += 1
            if pageCount > maxPages { break }
            var query: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            if let type { query.append(URLQueryItem(name: "type", value: String(type))) }
            let response: PagedUserCollection = try await request("/v0/users/\(user)/collections", query: query)
            all.append(contentsOf: response.data)
            offset += response.data.count
            if response.data.count < pageSize || offset >= response.total { break }
        }
        return all
    }

    /// Returns just the total count for a given collection type.
    /// Uses limit=1 to keep the payload small — Bangumi's `total` reflects the full result, not just the page.
    func fetchUserCollectionsCount(username: String = "-", type: Int) async throws -> Int {
        let user = username == "-" ? try await resolveUsername() : username
        let query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "type", value: String(type)),
        ]
        let response: PagedUserCollection = try await request("/v0/users/\(user)/collections", query: query)
        return response.total
    }

    func fetchUserCollection(username: String = "-", subjectId: Int) async throws -> UserSubjectCollection {
        let user = username == "-" ? try await resolveUsername() : username
        return try await request("/v0/users/\(user)/collections/\(subjectId)")
    }

    func updateCollection(subjectId: Int, payload: UserSubjectCollectionModifyPayload) async throws {
        try await requestVoid("/v0/users/-/collections/\(subjectId)", method: "POST", body: payload)
        // Setting collection.type can auto-mark episodes server-side, so drop
        // both halves of this subject's user state.
        invalidateCollections(subjectId: subjectId)
        invalidateEpisodeCollections(subjectId: subjectId)
    }

    func deleteCollection(subjectId: Int) async throws {
        try await requestVoid("/v0/users/-/collections/\(subjectId)", method: "DELETE")
        invalidateCollections(subjectId: subjectId)
        invalidateEpisodeCollections(subjectId: subjectId)
    }

    // MARK: - Episode Collections

    func fetchEpisodeCollection(subjectId: Int) async throws -> [UserEpisodeCollection] {
        // Auto-paginate: long-running titles (One Piece 1100+, Conan 1100+)
        // exceed a single page, and a capped request would silently truncate
        // their per-episode progress. Loop until `total` is covered.
        // maxPages provides a safety net against runaway requests if the API's
        // total field is inconsistent.
        let pageSize = 200
        var offset = 0
        var all: [UserEpisodeCollection] = []
        var pageCount = 0
        let maxPages = 100
        while true {
            pageCount += 1
            if pageCount > maxPages { break }
            let query: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            let response: PagedUserEpisodeCollection = try await request("/v0/users/-/collections/\(subjectId)/episodes", query: query)
            all.append(contentsOf: response.data)
            offset += response.data.count
            if response.data.count < pageSize || offset >= response.total { break }
        }
        return all
    }

    func updateEpisodeCollection(subjectId: Int, episodeId: Int, type: EpisodeCollectionType) async throws {
        let body = SingleEpisodeUpdate(type: type.rawValue)
        try await requestVoid("/v0/users/-/collections/-/episodes/\(episodeId)", method: "PUT", body: body)
        // Marking an episode bumps the parent collection's ep_status — drop
        // both the per-episode list AND the collection list/single caches.
        invalidateEpisodeCollections(subjectId: subjectId)
        invalidateCollections(subjectId: subjectId)
    }

    func batchUpdateEpisodeCollections(subjectId: Int, episodes: [(id: Int, type: EpisodeCollectionType)]) async throws {
        guard let firstType = episodes.first?.type else { return }
        let body = BatchEpisodeUpdate(
            episodeId: episodes.map(\.id),
            type: firstType.rawValue
        )
        try await requestVoid("/v0/users/-/collections/\(subjectId)/episodes", method: "PATCH", body: body)
        invalidateEpisodeCollections(subjectId: subjectId)
        invalidateCollections(subjectId: subjectId)
    }

    // MARK: - User

    func fetchMe() async throws -> UserInfo {
        let me: UserInfo = try await request("/v0/me")
        currentUsername = me.username
        currentUserId = me.id
        return me
    }

    // MARK: - Request Pipeline

    private func buildRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        bodyData: Data?,
        baseURL: String
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw BangumiAPIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw BangumiAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("BangumiTracker/1.0 (https://github.com/bangumi)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.httpBody = bodyData
        }
        return request
    }

    private func performRequest(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws -> Data {
        // Encode the body once and reuse the bytes for both URLRequest.httpBody
        // and the SHA256 in cacheKey — the previous version encoded twice on
        // every read.
        let bodyData: Data?
        if let body {
            bodyData = try encoder.encode(AnyEncodable(body))
        } else {
            bodyData = nil
        }

        // Writes (and anything without a TTL) bypass the cache entirely and
        // don't need to wait for the disk load.
        guard let ttl = cacheTTL(for: method, path: path) else {
            let generation = cacheGeneration
            return try await performRequestWithFallback(
                path: path, method: method, query: query, bodyData: bodyData,
                key: nil, generation: generation
            )
        }

        // Reads consult the cache, so make sure the disk snapshot has merged
        // in (no-op after the first call).
        await awaitCacheLoadIfNeeded()

        let key = cacheKey(path: path, method: method, query: query, bodyData: bodyData)
        let now = Date()
        if let entry = cache[key] {
            let age = now.timeIntervalSince(entry.cachedAt)
            if age < ttl {
                // Fresh — serve from cache; no URLRequest built, no network.
                return entry.data
            }
            if age < Self.staleWindow(for: ttl) {
                // Stale-while-revalidate: serve immediately, refresh in background.
                let request = try buildRequest(path: path, method: method, query: query, bodyData: bodyData, baseURL: baseURLs[0])
                scheduleBackgroundRefresh(key: key, request: request)
                return entry.data
            }
            // Past the stale window — fall through to a blocking refresh.
        }

        return try await performRequestWithFallback(
            path: path, method: method, query: query, bodyData: bodyData,
            key: key, generation: cacheGeneration
        )
    }

    private func performRequestWithFallback(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        bodyData: Data?,
        key: String?,
        generation: UInt64
    ) async throws -> Data {
        // Per-URL retry with exponential backoff: max 3 attempts (1s → 2s → 4s)
        // for retryable errors. The base-URL fallback chain still applies:
        // all 3 retries on baseURL[0] → all 3 on baseURL[1] → … → throw.
        let maxRetries = 3
        let baseDelay: TimeInterval = 1.0
        var lastError: Error?
        for baseURL in baseURLs {
            for attempt in 0..<maxRetries {
                if attempt > 0 {
                    try await Task.sleep(for: .seconds(baseDelay * pow(2.0, Double(attempt - 1))))
                }
                do {
                    let request = try buildRequest(
                        path: path, method: method, query: query, bodyData: bodyData,
                        baseURL: baseURL
                    )
                    let result = key != nil
                        ? try await fetchBlocking(key: key!, request: request)
                        : try await execute(request, generation: generation)
                    return result
                } catch {
                    let apiError = BangumiAPIError.from(error)
                    guard apiError.isRetryable else { throw apiError }
                    lastError = apiError
                }
            }
        }
        throw lastError ?? BangumiAPIError.serverUnreachable
    }

    /// Executes a URLRequest off-actor and maps the HTTP response. Never
    /// touches the cache. Marked `nonisolated` so background-refresh Tasks can
    /// hit the network without contending for the actor's executor.
    ///
    /// `generation` is the `cacheGeneration` the caller captured when the
    /// request was issued. On a 401 it's forwarded in the unauthorized
    /// notification, so the observer can drop stale 401s from requests that
    /// left with an already-replaced token — a refresh or paste bumps the
    /// generation, so a late-arriving 401 for the old generation is ignored
    /// instead of triggering a second refresh / re-login.
    private nonisolated func execute(_ request: URLRequest, generation: UInt64) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BangumiAPIError.networkError(NSError(domain: "", code: -1))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                // Only flag session-expiry when we actually presented a token.
                // A 401 with no Authorization header means the endpoint requires
                // auth and we're anonymous — the logged-out empty states already
                // cover that, no alert needed. Posting is thread-safe, so it's
                // fine to do from this `nonisolated`/off-actor call site; the
                // observer hops to MainActor before mutating auth state.
                if request.value(forHTTPHeaderField: "Authorization") != nil {
                    NotificationCenter.default.post(
                        name: .bangumiUnauthorized,
                        object: nil,
                        userInfo: ["generation": Int(generation)]
                    )
                }
                throw BangumiAPIError.unauthorized
            }
            if httpResponse.statusCode == 429 {
                throw BangumiAPIError.rateLimited
            }
            throw BangumiAPIError.httpError(httpResponse.statusCode)
        }
        return data
    }

    /// Blocking fetch with concurrent-call dedup: if a Task for `key` is
    /// already in flight (blocking or SWR refresh), await its result instead
    /// of firing a second identical request. Stamps the generation at start;
    /// on return, refuses to surface or cache the result if the generation
    /// has flipped (account-changing setToken / clearResponseCache).
    private func fetchBlocking(key: String, request: URLRequest) async throws -> Data {
        let generation = cacheGeneration
        if let existing = inflightFetches[key] {
            let data = try await existing.value
            if cacheGeneration != generation {
                // Token/account changed mid-flight — the response was issued
                // with the old token. Don't let it bleed into the new session.
                throw BangumiAPIError.unauthorized
            }
            return data
        }
        // `Task.detached` keeps the network work off the actor's executor —
        // the task body just calls `nonisolated execute(_:)` and the actor
        // is freed for other requests immediately.
        let task = Task.detached { try await self.execute(request, generation: generation) }
        inflightFetches[key] = task
        defer { inflightFetches.removeValue(forKey: key) }
        let data = try await task.value
        if cacheGeneration != generation {
            throw BangumiAPIError.unauthorized
        }
        storeIfCurrent(key: key, data: data, generation: generation)
        return data
    }

    private func scheduleBackgroundRefresh(key: String, request: URLRequest) {
        // Skip if a fetch is already in flight, or if a previous refresh
        // failed within the cooldown window — prevents a retry storm during
        // an outage where every stale read would otherwise spawn a new failure.
        if inflightFetches[key] != nil { return }
        if let lastFailure = refreshFailureAt[key],
           Date().timeIntervalSince(lastFailure) < refreshFailureBackoff {
            return
        }
        let generation = cacheGeneration
        let task = Task.detached { try await self.execute(request, generation: generation) }
        inflightFetches[key] = task
        Task { [weak self] in
            await self?.completeRefresh(key: key, generation: generation, task: task)
        }
    }

    private func completeRefresh(key: String, generation: UInt64, task: Task<Data, Error>) async {
        defer { inflightFetches.removeValue(forKey: key) }
        do {
            let data = try await task.value
            storeIfCurrent(key: key, data: data, generation: generation)
        } catch is CancellationError {
            // Cancelled by setToken — nothing to record.
        } catch {
            // Stamp failure time so we don't immediately respawn on the next stale read.
            refreshFailureAt[key] = Date()
        }
    }

    /// Common post-fetch hook: write to cache only if the generation hasn't
    /// flipped since the fetch started, and clear any prior failure record.
    private func storeIfCurrent(key: String, data: Data, generation: UInt64) {
        guard cacheGeneration == generation else { return }
        storeCache(key: key, data: data)
        refreshFailureAt.removeValue(forKey: key)
    }

    // MARK: - Cache Storage & Keys

    /// Stale-while-revalidate window. Centralised so the read path and the
    /// disk-load filter can't drift out of sync.
    private static func staleWindow(for ttl: TimeInterval) -> TimeInterval {
        ttl * 2
    }

    /// Per-endpoint TTL. Returns nil for requests that must not be cached (writes).
    /// Aggressive policy: stable metadata 24h, episodes 12h, calendar 6h, user
    /// state 15min, search 30min. staleWindow(for:) doubles each TTL before forced refresh.
    private func cacheTTL(for method: String, path: String) -> TimeInterval? {
        if method == "GET" {
            if path == "/calendar" { return 6 * 3600 }
            if path == "/v0/me" { return 3600 }
            if path == "/v0/episodes" { return 12 * 3600 }
            if path.hasPrefix("/v0/subjects/") { return 24 * 3600 } // detail + characters/persons/related
            if path.hasPrefix("/v0/characters/") { return 24 * 3600 }
            if path.hasPrefix("/v0/persons/") { return 24 * 3600 }
            if path.hasPrefix("/v0/users/") && path.contains("/collections") { return 15 * 60 } // list / single / episodes
            return 5 * 60 // conservative fallback for unknown GETs
        }
        if method == "POST" && path.hasPrefix("/v0/search/") { return 30 * 60 }
        return nil
    }

    private func cacheKey(
        path: String,
        method: String,
        query: [URLQueryItem],
        bodyData: Data?
    ) -> String {
        let queryStr = query
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let bodyHash: String
        if let bodyData {
            bodyHash = SHA256.hash(data: bodyData).compactMap { String(format: "%02x", $0) }.joined()
        } else {
            bodyHash = "-"
        }
        return "\(method)|\(path)|\(queryStr)|\(bodyHash)"
    }

    /// Path portion of a cache key (first two `|`-delimited fields after method).
    private static func path(forKey key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.count >= 2 ? String(parts[1]) : ""
    }

    private func storeCache(key: String, data: Data) {
        cache[key] = CacheEntry(data: data, cachedAt: Date())
        if cache.count > maxCacheEntries {
            evictOldest(targetCount: maxCacheEntries * 9 / 10)
        }
        markDiskDirty()
    }

    /// Drop the oldest entries (by cachedAt) until cache.count <= targetCount.
    /// O(N log N) per overflow, but called at most once per N/10 stores.
    private func evictOldest(targetCount: Int) {
        guard cache.count > targetCount else { return }
        let sorted = cache.sorted { $0.value.cachedAt < $1.value.cachedAt }
        let toRemove = sorted.prefix(cache.count - targetCount)
        for (key, _) in toRemove {
            cache.removeValue(forKey: key)
        }
    }

    /// Drop entries whose path matches. Used by write operations to invalidate
    /// the read caches they mutate.
    private func invalidateCache(wherePath matches: (String) -> Bool) {
        let toRemove = cache.keys.filter { matches(Self.path(forKey: $0)) }
        guard !toRemove.isEmpty else { return }
        for key in toRemove { cache.removeValue(forKey: key) }
        markDiskDirty()
    }

    /// Invalidate the collection list + single-collection caches for a subject
    /// (and any collection-type variant of the list, e.g. the count endpoint).
    private func invalidateCollections(subjectId: Int) {
        let idStr = String(subjectId)
        invalidateCache { path in
            let comps = path.split(separator: "/").map(String.init) // ["v0","users",user,"collections",...]
            guard comps.count >= 4, comps[0] == "v0", comps[1] == "users", comps[3] == "collections" else {
                return false
            }
            // list: /v0/users/{user}/collections  (count endpoint reuses this path)
            if comps.count == 4 { return true }
            // single: /v0/users/{user}/collections/{id}
            if comps.count == 5 { return comps[4] == idStr }
            return false
        }
    }

    /// Invalidate the per-episode watch-status cache for a subject.
    private func invalidateEpisodeCollections(subjectId: Int) {
        let idStr = String(subjectId)
        invalidateCache { path in
            // /v0/users/{user}/collections/{subjectId}/episodes
            let comps = path.split(separator: "/").map(String.init)
            guard comps.count == 6, comps[3] == "collections", comps[5] == "episodes" else { return false }
            return comps[4] == idStr
        }
    }

    func clearResponseCache() {
        cache.removeAll()
        for task in inflightFetches.values { task.cancel() }
        inflightFetches.removeAll()
        refreshFailureAt.removeAll()
        cacheGeneration &+= 1
        // A pending disk load would re-introduce the just-cleared entries.
        cacheLoadTask?.cancel()
        cacheLoadTask = nil
        markDiskDirty()
    }

    // MARK: - Cache Disk Persistence

    private nonisolated static func loadCacheFromDisk(url: URL) -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return [:]
        }
        // Per-entry TTL is no longer stored. Use the longest staleWindow the
        // policy could grant as a conservative upper bound — entries older
        // than that can never be served fresh by any current policy. Bump
        // `maxTTL` (in one place) when adding longer-lived endpoints.
        let now = Date()
        let cutoff = staleWindow(for: maxTTL)
        return stored.filter { _, entry in now.timeIntervalSince(entry.cachedAt) < cutoff }
    }

    /// First-touch hook for the cache: awaits the background disk-load if it
    /// hasn't merged in yet, then no-ops on subsequent calls. Only adopts the
    /// snapshot if the in-memory cache is still pristine — a real account
    /// change between init and first read bumps `cacheGeneration` and the
    /// snapshot is dropped on the floor.
    private func awaitCacheLoadIfNeeded() async {
        guard let task = cacheLoadTask else { return }
        cacheLoadTask = nil
        let loaded = await task.value
        if cache.isEmpty && cacheGeneration == 0 {
            cache = loaded
        }
    }

    private func markDiskDirty() {
        diskWriteDirty = true
        if !diskWriterRunning {
            diskWriterRunning = true
            Task { [weak self] in
                await self?.runDiskWriter()
            }
        }
    }

    /// Coalescing serial writer. Snapshots the cache on the actor, hops off
    /// to encode+write, then re-checks the dirty flag and loops. Bursts of
    /// mutations collapse into one write per drain cycle, and writes are
    /// strictly ordered.
    private func runDiskWriter() async {
        defer { diskWriterRunning = false }
        while diskWriteDirty {
            diskWriteDirty = false
            let snapshot = cache
            let url = cacheURL
            // Off-actor encode+atomic-write so a multi-MB serialise doesn't
            // pin the actor. Awaiting the detached task means the next loop
            // iteration sees any dirties that arrived during the IO.
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(snapshot) {
                    try? data.write(to: url, options: .atomic)
                }
            }.value
        }
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws -> T {
        let data = try await performRequest(path, method: method, query: query, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BangumiAPIError.decodingError(error)
        }
    }

    private func requestVoid(
        _ path: String,
        method: String = "POST",
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws {
        _ = try await performRequest(path, method: method, query: query, body: body)
    }
}

// MARK: - Search Body Types

private nonisolated struct SearchKeywordBody: Encodable, Sendable {
    let keyword: String
}

private nonisolated struct SearchSubjectsBody: Encodable, Sendable {
    let keyword: String
    let sort: String
    let filter: SubjectSearchFilter
}

private nonisolated struct SingleEpisodeUpdate: Encodable, Sendable {
    let type: Int
}

private nonisolated struct BatchEpisodeUpdate: Encodable, Sendable {
    let episodeId: [Int]
    let type: Int

    enum CodingKeys: String, CodingKey {
        case episodeId = "episode_id"
        case type
    }
}

private nonisolated struct PagedUserEpisodeCollection: Codable, Sendable {
    let data: [UserEpisodeCollection]
    let total: Int
}

// MARK: - Type-erased Encodable wrapper

private nonisolated struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
