import Foundation
import Observation

struct BecauseYouWatchResult: Codable, Sendable {
    let referenceSubjectId: Int?
    let referenceTitle: String?
    let referenceTag: String
    let subjects: [Subject]
}

struct TimeCapsuleResult: Codable, Sendable {
    let year: Int
    let subjects: [Subject]
}

@MainActor
@Observable
final class HomeViewModel {
    var todayPick: Subject?
    var becauseYouWatch: BecauseYouWatchResult?
    var hiddenGems: [Subject] = []
    var timeCapsule: TimeCapsuleResult?
    var wantToWatchList: [UserSubjectCollection] = []

    /// URLs of all visible subject images, for Kingfisher prefetching.
    var visibleImageURLs: [String] {
        var urls: [String] = []
        if let pick = todayPick, let url = pick.imageURL { urls.append(url) }
        if let byw = becauseYouWatch { urls.append(contentsOf: byw.subjects.compactMap(\.imageURL)) }
        urls.append(contentsOf: hiddenGems.compactMap(\.imageURL))
        if let tc = timeCapsule { urls.append(contentsOf: tc.subjects.compactMap(\.imageURL)) }
        urls.append(contentsOf: wantToWatchList.compactMap { $0.subject?.imageURL })
        return urls
    }
    var sortOrder: WantToWatchSort = .collectedAt {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }
    /// Which collection status the home list shows. Defaults to 想看 (the wish
    /// list); a Profile stat-card tap sets this to 已看 / 搁置 so the home list
    /// becomes a filtered view of that status, and a "返回想看清单" affordance
    /// resets it. Recommendations are unaffected — only the list section.
    var collectionStatus: CollectionType = .wish
    /// Per-subject local "added to wish" timestamps for the current user. Populated
    /// after each wish-list fetch; sort falls back to API `updatedAt` for items with
    /// no local record (i.e. added before this feature shipped or from another device).
    private var wishCollectedAtMap: [Int: Date] = [:]
    var isLoading = false
    var errorMessage: String?
    var actionError: String?

    /// Tracks the in-flight overlay-fetch task so View.onDisappear can cancel it.
    private var overlayFetchTask: Task<Void, Never>?

    private let api: BangumiAPIClient
    private let cache: LocalCacheService
    private let fileCache = FileCache(subdirectory: "dev.bangumi.home")

    private static let todayPickCacheKey = "cache.home.todayPick"
    private static let becauseYouWatchCacheKey = "cache.home.becauseYouWatch"
    private static let hiddenGemsCacheKey = "cache.home.hiddenGems"
    private static let timeCapsuleCacheKey = "cache.home.timeCapsule"
    private static let sortOrderKey = "home.wishSort"
    /// yyyyMMdd of the last successful recommendation refresh. Used to skip
    /// the auto-fetch on view re-appear within the same day — the user only
    /// wants the recommendation rails to roll over once per day, or when
    /// they pull-to-refresh / tap 换一批.
    private static let recommendationsLastLoadedDayKey = "cache.home.recommendationsLastLoadedDay"

    private static let fallbackTagPool = [
        "科幻", "治愈", "悬疑", "原创", "校园",
        "热血", "搞笑", "奇幻", "战斗", "日常",
        "百合", "音乐", "运动", "机战", "剧情"
    ]

    init(api: BangumiAPIClient, cache: LocalCacheService) {
        self.api = api
        self.cache = cache
        if let raw = UserDefaults.standard.string(forKey: Self.sortOrderKey) {
            // The case names changed from priority/dateAdded/rating to
            // collectedAt/rank — map old values onto the closest new equivalent
            // so users who chose a non-default sort don't get reset on upgrade.
            let migrated: WantToWatchSort? = switch raw {
            case "priority", "dateAdded", "collectedAt": .collectedAt
            case "rating", "rank": .rank
            default: nil
            }
            if let migrated {
                self.sortOrder = migrated
            }
        }
        if let cached = fileCache.read(Subject.self, forKey: CacheKeys.Home.todayPick) {
            self.todayPick = cached
        }
        if let cached = fileCache.read(BecauseYouWatchResult.self, forKey: CacheKeys.Home.becauseYouWatch) {
            self.becauseYouWatch = cached
        }
        if let cached = fileCache.read([Subject].self, forKey: CacheKeys.Home.hiddenGems) {
            self.hiddenGems = cached
        }
        if let cached = fileCache.read(TimeCapsuleResult.self, forKey: CacheKeys.Home.timeCapsule) {
            self.timeCapsule = cached
        }
    }

    /// Full load — used on pull-to-refresh and on auth-state changes. Always
    /// reloads every rail and stamps today's date so the per-appear loader
    /// skips redundant work for the rest of the day.
    func loadAll() async {
        isLoading = true
        errorMessage = nil
        async let pick: () = loadTodayPick()
        async let bywatch: () = loadBecauseYouWatch()
        async let gems: () = loadHiddenGems()
        async let capsule: () = loadTimeCapsule()
        async let wishes: () = loadWantToWatch()
        async let allCols: () = loadAllCollectionsForOverlay()
        _ = await (pick, bywatch, gems, capsule, wishes, allCols)
        UserDefaults.standard.set(Self.todayString(), forKey: Self.recommendationsLastLoadedDayKey)
        isLoading = false
    }

    /// Per-appear load — used by HomeView's `.task`. Refreshes the user's
    /// want-to-watch list and collection overlay on every appear (these
    /// reflect changes made on the subject-detail screen), but only refreshes
    /// the four recommendation rails (今日精选 / 因为你在追 / 宝藏佳作 /
    /// 时光胶囊) once per calendar day. Without this guard, popping back from
    /// a detail view re-shuffles the rails on every return.
    func loadOnAppear() async {
        async let wishes: () = loadWantToWatch()
        async let allCols: () = loadAllCollectionsForOverlay()
        _ = await (wishes, allCols)

        let today = Self.todayString()
        let lastLoadedDay = UserDefaults.standard.string(forKey: Self.recommendationsLastLoadedDayKey)
        guard lastLoadedDay != today else { return }

        isLoading = true
        errorMessage = nil
        async let pick: () = loadTodayPick()
        async let bywatch: () = loadBecauseYouWatch()
        async let gems: () = loadHiddenGems()
        async let capsule: () = loadTimeCapsule()
        _ = await (pick, bywatch, gems, capsule)
        UserDefaults.standard.set(today, forKey: Self.recommendationsLastLoadedDayKey)
        isLoading = false
    }

    /// Populates the SwiftData cache with the user's collections across all states
    /// so carousel cards can render the correct status badge.  Skips the fetch if
    /// the cache was loaded within the last 5 minutes to avoid a full-collection
    /// fetch (~500+ items) on every tab switch.
    private func loadAllCollectionsForOverlay() async {
        guard await api.hasToken() else { return }
        let cachedCount = cache.cachedCollectionCount()
        if cachedCount > 0 {
            // Check if we have recent-enough data — 5 min staleness window.
            if cache.lastCollectionCacheAt?.timeIntervalSinceNow ?? 0 > -300 {
                return
            }
        }
        if let collections = try? await api.fetchUserCollections() {
            try? cache.cacheCollections(collections)
        }
    }

    /// 今日精选：用今天的日期作为种子，从高分作品池里挑一部，整天稳定。
    func loadTodayPick() async {
        do {
            var filter = SubjectSearchFilter()
            filter.type = [SubjectType.anime.rawValue]
            filter.rating = [">=8.0"]
            filter.rank = [">0"]
            let pool = try await api.searchSubjects(keyword: "", filter: filter, sort: "rank")
            guard !pool.isEmpty else { return }
            let seed = Self.dailySeed()
            let pick = pool[seed % pool.count]
            todayPick = pick
            fileCache.write(pick, forKey: CacheKeys.Home.todayPick)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 因为你在追《X》：从用户在看列表里随机挑一部（且尽量避开上次的 pick），
    /// 用它的 metaTag 找相似作品。每次实际调用都会换一部《X》——跨天自动刷新
    /// 和点「换一批」时都会生效；同一天内重复进入首页不会重拉（见 loadOnAppear）。
    /// 未登录或在看为空时，退化成"标签巡游"，从预设标签池里随机抽一个标签。
    func loadBecauseYouWatch() async {
        do {
            var referenceTitle: String?
            var referenceSubjectId: Int?
            var seedTag: String?
            if await api.hasToken() {
                let watching = (try? await api.fetchUserCollections(type: CollectionType.watching.rawValue)) ?? []
                // 随机挑一部在追作品作为参考，且尽量避开上次的 pick，
                // 这样每日切换和点「换一批」时《X》也会真正换一部。
                // pool 为空（只有一部/刚好的那部就是上次那部）时回退到完整列表。
                let previousId = becauseYouWatch?.referenceSubjectId
                let pool = watching.filter { $0.subjectId != previousId }
                if let pick = (pool.isEmpty ? watching : pool).randomElement(),
                   let slim = pick.subject {
                    referenceTitle = slim.displayName
                    referenceSubjectId = pick.subjectId
                    if let detail = try? await api.fetchSubject(id: pick.subjectId) {
                        seedTag = detail.metaTags.first ?? detail.tags.first?.name
                    }
                }
            }
            let tag = seedTag ?? Self.fallbackTagPool.randomElement() ?? "原创"

            var filter = SubjectSearchFilter()
            filter.type = [SubjectType.anime.rawValue]
            filter.metaTags = [tag]
            filter.rank = [">0"]
            let results = try await api.searchSubjects(keyword: "", filter: filter, sort: "heat")
            // 排掉作为参考的那部本身（避免推荐自己）
            let filtered = results.filter { $0.displayName != referenceTitle }
            let trimmed = Array(filtered.prefix(15)).shuffled().prefix(8)
            let result = BecauseYouWatchResult(
                referenceSubjectId: referenceSubjectId,
                referenceTitle: referenceTitle,
                referenceTag: tag,
                subjects: Array(trimmed)
            )
            becauseYouWatch = result
            fileCache.write(result, forKey: CacheKeys.Home.becauseYouWatch)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 冷门佳作：评分高、排名靠后的作品，每次刷新都重新随机。
    func loadHiddenGems() async {
        do {
            var filter = SubjectSearchFilter()
            filter.type = [SubjectType.anime.rawValue]
            filter.rating = [">=7.5"]
            filter.rank = [">200", "<1500"]
            let pool = try await api.searchSubjects(keyword: "", filter: filter, sort: "rank")
            let trimmed = Array(pool.shuffled().prefix(8))
            hiddenGems = trimmed
            fileCache.write(trimmed, forKey: CacheKeys.Home.hiddenGems)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 时光胶囊：随机选 5-15 年前的某一年，挑当年高分作品。
    func loadTimeCapsule() async {
        do {
            let currentYear = Calendar.current.component(.year, from: Date())
            let yearsAgo = Int.random(in: 5...15)
            let year = currentYear - yearsAgo

            var filter = SubjectSearchFilter()
            filter.type = [SubjectType.anime.rawValue]
            filter.airDate = [">=\(year)-01-01", "<\(year + 1)-01-01"]
            filter.rating = [">=7.5"]
            let pool = try await api.searchSubjects(keyword: "", filter: filter, sort: "rank")
            let trimmed = Array(pool.shuffled().prefix(8))
            let result = TimeCapsuleResult(year: year, subjects: trimmed)
            timeCapsule = result
            fileCache.write(result, forKey: CacheKeys.Home.timeCapsule)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadWantToWatch() async {
        guard await api.hasToken() else {
            wantToWatchList = []
            wishCollectedAtMap = [:]
            return
        }
        do {
            let collections = try await api.fetchUserCollections(type: collectionStatus.rawValue)
            wantToWatchList = collections
            try cache.cacheCollections(collections)
            // Local "added to wish" timestamps only exist for 想看 items; for other
            // statuses the sort falls back to API `updated_at` (empty map → fallback).
            if collectionStatus == .wish, let userId = try? await api.resolveUserId() {
                wishCollectedAtMap = cache.wishCollectedAtMap(
                    userId: userId,
                    subjectIds: collections.map(\.subjectId)
                )
            } else {
                wishCollectedAtMap = [:]
            }
        } catch BangumiAPIError.unauthorized {
            wantToWatchList = []
            wishCollectedAtMap = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Switches the home list to a different collection status (from a Profile
    /// stat-card tap) and reloads it. Recommendations are untouched.
    func setCollectionStatus(_ status: CollectionType) async {
        guard collectionStatus != status else { return }
        collectionStatus = status
        // Clear the previous status's rows immediately so the header title and
        // the list can't disagree during the fetch window — otherwise the new
        // header (e.g. "我的已看作品") briefly sits over the old status's items.
        // loadWantToWatch repopulates; on failure the empty state + error shows.
        wantToWatchList = []
        wishCollectedAtMap = [:]
        await loadWantToWatch()
    }

    func startWatching(_ collection: UserSubjectCollection) async {
        let original = wantToWatchList
        wantToWatchList.removeAll { $0.subjectId == collection.subjectId }

        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.type = CollectionType.watching.rawValue
            try await api.updateCollection(subjectId: collection.subjectId, payload: payload)
            // Keep the cache in sync so carousel cards and the Watching tab reflect
            // the new state without a full refetch.
            cache.updateCachedCollectionType(subjectId: collection.subjectId, type: .watching)
            // Item left the wish list — drop its local timestamp so a future re-add
            // gets a fresh stamp instead of resurrecting the old one.
            if let userId = try? await api.resolveUserId() {
                cache.clearWishCollectedAt(userId: userId, subjectId: collection.subjectId)
                wishCollectedAtMap.removeValue(forKey: collection.subjectId)
            }
        } catch {
            wantToWatchList = original
            errorMessage = error.localizedDescription
        }
    }

    /// Moves a list item to another status (搁置 / 抛弃) via the long-press
    /// menu. Optimistic remove + cache sync, rolled back on failure.
    func setStatus(_ collection: UserSubjectCollection, to type: CollectionType) async {
        let original = wantToWatchList
        wantToWatchList.removeAll { $0.subjectId == collection.subjectId }
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.type = type.rawValue
            try await api.updateCollection(subjectId: collection.subjectId, payload: payload)
            cache.updateCachedCollectionType(subjectId: collection.subjectId, type: type)
            if let userId = try? await api.resolveUserId() {
                cache.clearWishCollectedAt(userId: userId, subjectId: collection.subjectId)
                wishCollectedAtMap.removeValue(forKey: collection.subjectId)
            }
        } catch {
            wantToWatchList = original
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the collection entirely (long-press 删除). Optimistic remove +
    /// cache removal, rolled back on failure.
    func deleteCollection(_ collection: UserSubjectCollection) async {
        let original = wantToWatchList
        wantToWatchList.removeAll { $0.subjectId == collection.subjectId }
        do {
            try await api.deleteCollection(subjectId: collection.subjectId)
            cache.removeCachedCollection(subjectId: collection.subjectId)
            if let userId = try? await api.resolveUserId() {
                cache.clearWishCollectedAt(userId: userId, subjectId: collection.subjectId)
                wishCollectedAtMap.removeValue(forKey: collection.subjectId)
            }
        } catch {
            wantToWatchList = original
            errorMessage = error.localizedDescription
        }
    }

    func addToWishlist(_ subject: Subject) async {
        do {
            let service = CollectionService(api: api, cache: cache)
            try await service.addToWishlist(subjectId: subject.id)
            if let userId = try? await api.resolveUserId() {
                service.recordWishCollectedAt(userId: userId, subjectId: subject.id)
            }
            await loadWantToWatch()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func toggleSort() {
        let all = WantToWatchSort.allCases
        if let idx = all.firstIndex(of: sortOrder) {
            sortOrder = all[(idx + 1) % all.count]
        }
    }

    /// Wipes user-specific state on logout. The "因为你在追《X》" rail derives
    /// from the user's watching list, so its cached blob is dropped too. The
    /// other recommendation rails (今日精选 / 宝藏佳作 / 时光胶囊) are
    /// public-facing and kept as-is.
    func clearOnLogout() {
        wantToWatchList = []
        wishCollectedAtMap = [:]
        // Reset to the default wish-list view — otherwise a Profile stat-card
        // tap (e.g. 已看) persists across logout/re-login and Home reopens to a
        // non-default status instead of 想看清单.
        collectionStatus = .wish
        becauseYouWatch = nil
        UserDefaults.standard.removeObject(forKey: Self.becauseYouWatchCacheKey)
    }

    /// Returns the user's collection state for a given subject (from the SwiftData cache).
    /// Returns `nil` if the subject isn't collected — callers can render the
    /// uncollected quick-add ("+ 想看") state.
    func collectionType(for subjectId: Int) -> CollectionType? {
        guard let raw = cache.getCachedCollection(subjectId: subjectId)?.collectionType else { return nil }
        return CollectionType(rawValue: raw)
    }

    /// Local "added to wish" timestamp for a subject, or nil if there's no
    /// local record (the row then falls back to API `updated_at`).
    func wishCollectedAt(for subjectId: Int) -> Date? {
        wishCollectedAtMap[subjectId]
    }

    var sortedWantToWatchList: [UserSubjectCollection] {
        switch sortOrder {
        case .collectedAt:
            return wantToWatchList.sorted { collectedAtSortKey($0) > collectedAtSortKey($1) }
        case .rank:
            // Unranked / new items have rank == 0 — sink them to the bottom while
            // keeping ranked items in ascending order (rank 1 = top of the genre).
            return wantToWatchList.sorted { rankSortKey($0) < rankSortKey($1) }
        }
    }

    private func collectedAtSortKey(_ c: UserSubjectCollection) -> Date {
        if let local = wishCollectedAtMap[c.subjectId] { return local }
        if let s = c.updatedAt, let parsed = Self.iso8601Parse(s) { return parsed }
        return .distantPast
    }

    private func rankSortKey(_ c: UserSubjectCollection) -> Int {
        let r = c.subject?.rank ?? 0
        return r == 0 ? .max : r
    }

    /// Bangumi returns `updated_at` as ISO 8601 with fractional seconds in some
    /// fields and without in others — try the strict form first, fall back to
    /// the no-fraction form before giving up.
    private static func iso8601Parse(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    private static func dailySeed() -> Int {
        return abs(todayString().hashValue)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}
