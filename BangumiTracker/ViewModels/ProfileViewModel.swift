import Foundation
import Observation

struct CollectionStats: Identifiable, Sendable {
    let id = UUID()
    let type: CollectionType
    let count: Int
}

/// One row of the subject-type breakdown — raw `type` (1=book, 2=anime, …)
/// plus how many of the user's watched subjects fall under it.
struct TypeCount: Codable, Sendable, Identifiable {
    let type: Int
    let count: Int
    var id: Int { type }
}

/// Self-insights derived from a single paged fetch of the watched collection.
/// The collection list embeds a `SlimSubject` per item carrying `type`, `date`,
/// and `rating`, so everything below needs no per-subject detail call.
struct ProfileInsights: Codable, Sendable {
    /// Items the user has rated that also carry a community average — the set
    /// over which `userAvgScore` and `siteAvgScore` are compared.
    var ratedCount: Int = 0
    var userAvgScore: Double = 0
    var siteAvgScore: Double = 0
    var typeBreakdown: [TypeCount] = []
    /// Air date within the last three calendar years vs. older.
    var recentCount: Int = 0
    var olderCount: Int = 0
}

@MainActor
@Observable
final class ProfileViewModel {
    var userInfo: UserInfo?
    var stats: [CollectionStats] = []
    var genres: [String] = []
    var insights = ProfileInsights()
    var isLoading = false
    var errorMessage: String?

    private let api: BangumiAPIClient

    private static let userInfoCacheKey = "cache.profile.userInfo"
    private static let statsCacheKey = "cache.profile.stats"
    private static let genresCacheKey = "cache.profile.genres"
    private static let insightsCacheKey = "cache.profile.insights"

    /// Stat cards shown on the profile header — PRD 5.2.6 lists 在看/想看/已看/搁置
    /// only (no 抛弃). Order matches the mockup.
    static let displayedStatTypes: [CollectionType] = [.watching, .wish, .watched, .onHold]

    init(api: BangumiAPIClient) {
        self.api = api
        if let info = loadCached(UserInfo.self, forKey: Self.userInfoCacheKey) {
            self.userInfo = info
        }
        if let cached = loadCached([CachedStat].self, forKey: Self.statsCacheKey) {
            self.stats = cached.map { CollectionStats(type: $0.type, count: $0.count) }
        }
        if let cached = loadCached([String].self, forKey: Self.genresCacheKey) {
            self.genres = cached
        }
        if let cached = loadCached(ProfileInsights.self, forKey: Self.insightsCacheKey) {
            self.insights = cached
        }
    }

    /// Reads + decodes a JSON blob from UserDefaults, or nil if absent / corrupt.
    private func loadCached<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Encodes + writes a value to UserDefaults. Cheap no-op on encode failure.
    private func saveCached<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func loadAll() async {
        isLoading = true
        errorMessage = nil
        await loadProfile()
        if userInfo != nil {
            async let s: () = loadStats()
            async let g: () = loadGenres()
            async let i: () = loadInsights()
            _ = await (s, g, i)
        }
        isLoading = false
    }

    func loadProfile() async {
        do {
            let info = try await api.fetchMe()
            userInfo = info
            saveCached(info, forKey: Self.userInfoCacheKey)
        } catch BangumiAPIError.unauthorized {
            userInfo = nil
            UserDefaults.standard.removeObject(forKey: Self.userInfoCacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadStats() async {
        guard let username = userInfo?.username else { return }
        do {
            var counts: [CollectionType: Int] = [:]
            try await withThrowingTaskGroup(of: (CollectionType, Int).self) { group in
                for type in Self.displayedStatTypes {
                    group.addTask { [api] in
                        let total = try await api.fetchUserCollectionsCount(username: username, type: type.rawValue)
                        return (type, total)
                    }
                }
                for try await (type, count) in group {
                    counts[type] = count
                }
            }
            stats = Self.displayedStatTypes.map { CollectionStats(type: $0, count: counts[$0] ?? 0) }
            let cached = stats.map { CachedStat(type: $0.type, count: $0.count) }
            saveCached(cached, forKey: Self.statsCacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Aggregates the *genre* tags of the user's currently-watching subjects —
    /// not the per-collection personal tags (`UserSubjectCollection.tags`),
    /// which most users never fill in. The collection list endpoint only returns
    /// a SlimSubject (no tags), so each subject's full detail is fetched to read
    /// its community `tags`. Scope is limited to the watching list to keep the
    /// request count small (~1 per watching title); the API client's response
    /// cache makes repeated profile opens cheap.
    func loadGenres() async {
        guard let username = userInfo?.username else { return }
        do {
            let collections = try await api.fetchUserCollections(
                username: username,
                type: CollectionType.watching.rawValue
            )
            var counts: [String: Int] = [:]
            // Cap concurrency to `batchSize` in-flight subject-detail requests so
            // a long watching list doesn't burst past Bangumi's ~1 req/s soft
            // ceiling and get 429'd (each failure is swallowed to [] below, which
            // would silently drop that title's genres). The 24h subject-detail
            // cache means warm opens skip the network entirely.
            let batchSize = 4
            var index = 0
            while index < collections.count {
                let upper = Swift.min(index + batchSize, collections.count)
                await withTaskGroup(of: [SubjectTag].self) { group in
                    for c in collections[index..<upper] {
                        group.addTask { [api] in
                            (try? await api.fetchSubject(id: c.subjectId).tags) ?? []
                        }
                    }
                    for await subjectTags in group {
                        // Cap per-subject so one heavily-tagged title can't flood
                        // the aggregate. Subject.tags arrives sorted by count desc.
                        for tag in subjectTags.prefix(8) {
                            counts[tag.name, default: 0] += 1
                        }
                    }
                }
                index = upper
            }
            genres = counts.sorted { $0.value > $1.value }.prefix(20).map(\.key)
            saveCached(genres, forKey: Self.genresCacheKey)
        } catch {
            // genres optional, swallow
        }
    }

    /// Derives the viewing-profile insights from a single paged fetch of the
    /// watched collection. The list response embeds a `SlimSubject` per item
    /// (type / date / rating), so this needs no per-subject detail call — the
    /// only extra requests are the pagination pages Bangumi caps at 50/req.
    func loadInsights() async {
        guard let username = userInfo?.username else { return }
        do {
            let collections = try await api.fetchUserCollections(
                username: username,
                type: CollectionType.watched.rawValue
            )
            var ratedCount = 0
            var userSum = 0.0
            var siteSum = 0.0
            var typeCounts: [Int: Int] = [:]
            var recentCount = 0
            var olderCount = 0
            let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
            for c in collections {
                // Rating tendency: compare your score to the site consensus over
                // the same set (items you've rated that also have a community avg).
                if c.rate > 0, let score = c.subject?.rating?.score, score > 0 {
                    ratedCount += 1
                    userSum += Double(c.rate)
                    siteSum += score
                }
                if let type = c.subject?.type {
                    typeCounts[type, default: 0] += 1
                }
                if let date = c.subject?.date, let year = Int(date.prefix(4)) {
                    if year >= currentYear - 2 { recentCount += 1 } else { olderCount += 1 }
                }
            }
            insights = ProfileInsights(
                ratedCount: ratedCount,
                userAvgScore: ratedCount > 0 ? userSum / Double(ratedCount) : 0,
                siteAvgScore: ratedCount > 0 ? siteSum / Double(ratedCount) : 0,
                typeBreakdown: typeCounts
                    .map { TypeCount(type: $0.key, count: $0.value) }
                    .sorted { $0.count > $1.count },
                recentCount: recentCount,
                olderCount: olderCount
            )
            saveCached(insights, forKey: Self.insightsCacheKey)
        } catch {
            // insights optional, swallow
        }
    }

    /// Wipes user-specific state and the UserDefaults blobs the init() seeds
    /// from. Without this, the next launch (or account switch) would surface
    /// the previous user's nickname/avatar/stats until /v0/me resolves.
    func clearOnLogout() {
        userInfo = nil
        stats = []
        genres = []
        insights = ProfileInsights()
        UserDefaults.standard.removeObject(forKey: Self.userInfoCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.statsCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.genresCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.insightsCacheKey)
    }
}

private struct CachedStat: Codable {
    let type: CollectionType
    let count: Int
}
