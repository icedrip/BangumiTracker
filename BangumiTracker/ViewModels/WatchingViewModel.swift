import Foundation
import Observation

@MainActor
@Observable
final class WatchingViewModel {
    var todayUpdates: [Subject] = []
    var watchingList: [UserSubjectCollection] = []
    var episodeProgress: [Int: (watched: Int, total: Int)] = [:]
    var isLoading = false
    var errorMessage: String?
    var actionError: String?

    private let api: BangumiAPIClient
    private let cache: LocalCacheService
    /// Subject IDs whose markNext / markAll request is in flight. Prevents a
    /// double-tap from picking the same "first unwatched" episode twice (which
    /// would PUT the same episodeId redundantly and skip the next one).
    private var inflightProgressUpdates: Set<Int> = []
    /// `subjectId -> air weekday (1=Mon … 7=Sun)`, built from `/calendar`. The
    /// watching collection list (`SlimSubject`) carries no `air_weekday`, so the
    /// only source for "when does this air" is cross-referencing the calendar.
    private var weekdayBySubject: [Int: Int] = [:]

    init(api: BangumiAPIClient, cache: LocalCacheService) {
        self.api = api
        self.cache = cache
        let cachedCollections = cache.getCachedCollections(type: .watching)
        if !cachedCollections.isEmpty {
            self.watchingList = cachedCollections.map(UserSubjectCollection.init(from:))
        }
    }

    func loadAll() async {
        isLoading = true
        errorMessage = nil
        // Load the watching collection list first: today's-updates is filtered
        // against it, and the by-air-day sort key is derived by cross-referencing
        // it with /calendar. Per-episode progress (the slow fan-out) runs in
        // parallel with today's-updates once the list is known.
        await loadWatchingCollections()
        async let t: () = loadTodayUpdates()
        async let p: () = refreshProgress(for: watchingList)
        _ = await (t, p)
        isLoading = false
    }

    func loadWatchingCollections() async {
        do {
            let collections = try await api.fetchUserCollections(type: CollectionType.watching.rawValue)
            watchingList = sortByAirWeekday(collections)
            cache.cacheCollections(collections)
            await WidgetDataService.writeWatchingData(from: watchingList)
        } catch BangumiAPIError.unauthorized {
            watchingList = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTodayUpdates() async {
        do {
            let calendar = try await api.fetchCalendar()
            buildWeekdayLookup(calendar)
            let watchingIds = Set(watchingList.map { $0.subjectId })
            let weekday = currentWeekday()
            let today = calendar.first(where: { $0.weekday.id == weekday })
            // Only shows the user's *followed* works that air today — the raw
            // calendar day lists every airing title site-wide.
            todayUpdates = (today?.items ?? [])
                .filter { watchingIds.contains($0.id) }
                .map(Subject.init(from:))
            // The weekday lookup just became available — re-sort so today's
            // airing works float to the top of the full list.
            watchingList = sortByAirWeekday(watchingList)
            // Do NOT clear errorMessage here: loadWatchingCollections may have
            // set it when the (authed) collections endpoint failed, while this
            // (public) /calendar endpoint still succeeds. Wiping it would mask
            // the real load failure and leave the user on an empty state with
            // no retry. loadAll clears errorMessage at its top; per-action
            // success paths (setStatus) clear their own.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshProgress(for collections: [UserSubjectCollection]) async {
        // Limit concurrency to ~4 in-flight requests. A bare `addTask` per item
        // fans out N concurrent `fetchEpisodeCollection` calls (one per watching
        // title), which blows past Bangumi's ~1 req/s soft ceiling and 429s on a
        // 50-title list. Batching keeps the fan-out bounded; the response cache
        // (15min TTL) makes subsequent loads instant, so this only paces first
        // paint of a cold watching list.
        let batchSize = 4
        for start in stride(from: 0, to: collections.count, by: batchSize) {
            let end = min(start + batchSize, collections.count)
            let chunk = collections[start..<end]
            await withTaskGroup(of: (Int, Int, Int)?.self) { group in
                for collection in chunk {
                    group.addTask { [api] in
                        do {
                            let eps = try await api.fetchEpisodeCollection(subjectId: collection.subjectId)
                            let main = eps.filter { $0.episode.type == .main }
                            let watched = main.filter { $0.type == .watched }.count
                            return (collection.subjectId, watched, main.count)
                        } catch {
                            return nil
                        }
                    }
                }
                for await result in group {
                    if let (id, watched, total) = result {
                        episodeProgress[id] = (watched, total)
                    }
                }
            }
        }
    }

    func markNextEpisode(_ collection: UserSubjectCollection) async {
        let subjectId = collection.subjectId
        guard !inflightProgressUpdates.contains(subjectId) else { return }
        inflightProgressUpdates.insert(subjectId)
        defer { inflightProgressUpdates.remove(subjectId) }
        do {
            let eps = try await api.fetchEpisodeCollection(subjectId: subjectId)
            let mainEps = eps.filter { $0.episode.type == .main }
            guard let next = mainEps.first(where: { $0.type != .watched }) else { return }
            try await api.updateEpisodeCollection(subjectId: subjectId, episodeId: next.episode.id, type: .watched)

            let watched = mainEps.filter { $0.type == .watched }.count + 1
            episodeProgress[subjectId] = (watched, mainEps.count)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func markAllWatched(_ collection: UserSubjectCollection) async {
        let subjectId = collection.subjectId
        guard !inflightProgressUpdates.contains(subjectId) else { return }
        inflightProgressUpdates.insert(subjectId)
        defer { inflightProgressUpdates.remove(subjectId) }
        do {
            let eps = try await api.fetchEpisodeCollection(subjectId: subjectId)
            let unwatched = eps.filter { $0.episode.type == .main && $0.type != .watched }
            guard !unwatched.isEmpty else { return }
            try await api.batchUpdateEpisodeCollections(
                subjectId: subjectId,
                episodes: unwatched.map { ($0.episode.id, EpisodeCollectionType.watched) }
            )
            let mainCount = eps.filter { $0.episode.type == .main }.count
            episodeProgress[subjectId] = (mainCount, mainCount)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Moves a watching item to another collection status (搁置 / 抛弃). Optimistic:
    /// removes from the in-memory list + rewrites the SwiftData cache type so
    /// other tabs (Home, Explore) stay consistent; rolls back on failure.
    func setStatus(_ collection: UserSubjectCollection, to type: CollectionType) async {
        guard let idx = watchingList.firstIndex(where: { $0.subjectId == collection.subjectId }) else { return }
        let removed = watchingList.remove(at: idx)
        cache.updateCachedCollectionType(subjectId: collection.subjectId, type: type)
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.type = type.rawValue
            try await api.updateCollection(subjectId: collection.subjectId, payload: payload)
            actionError = nil
            await WidgetDataService.writeWatchingData(from: watchingList)
        } catch {
            // `watchingList` may have been replaced by a concurrent refresh
            // (pull-to-refresh / auth-state `.task`) during the `await`, so
            // `idx` can be stale and the array shorter. Restore the item only
            // if it's no longer present (a refresh may have re-added it) and
            // never insert at an out-of-bounds index — append as a fallback.
            if !watchingList.contains(where: { $0.subjectId == removed.subjectId }) {
                if idx <= watchingList.count {
                    watchingList.insert(removed, at: idx)
                } else {
                    watchingList.append(removed)
                }
            }
            cache.updateCachedCollectionType(subjectId: collection.subjectId, type: .watching)
            actionError = error.localizedDescription
        }
    }

    func progress(for subjectId: Int) -> (watched: Int, total: Int) {
        episodeProgress[subjectId] ?? (0, 0)
    }

    /// 中文名映射 1=一 … 7=日. `static let` so it isn't reallocated per call
    /// (CalendarView uses the same pattern).
    private static let weekdayChars = ["一", "二", "三", "四", "五", "六", "日"]

    /// Validated air weekday for a subject (1=Mon…7=Sun), or nil if unknown or
    /// out of range. Shared by weekdayLabel / airsToday / airDaySortKey so the
    /// `(1...7).contains` guard lives in one place - airDaySortKey previously
    /// used a weaker `w != 0` that accepted values the other two rejected.
    private func airWeekday(for subjectId: Int) -> Int? {
        guard let w = weekdayBySubject[subjectId], (1...7).contains(w) else { return nil }
        return w
    }

    /// Today's weekday (1=Mon…7=Sun). Exposed so per-item callers (the watching
    /// grid) can hoist it out of a ForEach instead of recomputing a Calendar on
    /// every card.
    var todayWeekday: Int { currentWeekday() }

    /// "每周X更新" label for a watching item, or nil if its air weekday is
    /// unknown (not currently airing / not in the calendar payload).
    func weekdayLabel(for subjectId: Int) -> String? {
        guard let w = airWeekday(for: subjectId) else { return nil }
        return "每周\(Self.weekdayChars[w - 1])更新"
    }

    /// True if this subject's air weekday (per /calendar) matches today — used
    /// to highlight "今天更新" on the watching grid. Falls back to false when the
    /// air weekday is unknown (finished / not airing).
    func airsToday(_ subjectId: Int, today: Int) -> Bool {
        guard let w = airWeekday(for: subjectId) else { return false }
        return w == today
    }

    func addToWishlist(_ subject: Subject) async {
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.type = CollectionType.wish.rawValue
            try await api.updateCollection(subjectId: subject.id, payload: payload)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func buildWeekdayLookup(_ calendar: [CalendarDay]) {
        weekdayBySubject = Dictionary(
            calendar.flatMap { day in day.items.map { ($0.id, day.weekday.id) } },
            uniquingKeysWith: { _, b in b }
        )
    }

    /// Sorts so today's airing works come first, then tomorrow's, …, yesterday's
    /// last; works with no known air weekday (finished / not airing) sink to the
    /// bottom. `weekdayBySubject` is empty until `/calendar` loads, so the first
    /// pass is a no-op and the list is re-sorted in `loadTodayUpdates`.
    private func sortByAirWeekday(_ collections: [UserSubjectCollection]) -> [UserSubjectCollection] {
        let today = currentWeekday()
        return collections.sorted { a, b in
            airDaySortKey(a.subjectId, today: today) < airDaySortKey(b.subjectId, today: today)
        }
    }

    private func airDaySortKey(_ subjectId: Int, today: Int) -> Int {
        guard let w = airWeekday(for: subjectId) else { return 7 }
        return (w - today + 7) % 7 // today=0, tomorrow=1, …, yesterday=6
    }

    private func currentWeekday() -> Int {
        // Bangumi: 1=Monday ... 7=Sunday
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: Date()) // 1=Sun, 2=Mon ... 7=Sat
        return weekday == 1 ? 7 : weekday - 1
    }

    /// Wipes user-specific state on logout. todayUpdates is public airing data
    /// and stays put; watchingList and per-subject progress are user-specific.
    func clearOnLogout() {
        watchingList = []
        episodeProgress = [:]
        inflightProgressUpdates = []
        weekdayBySubject = [:]
    }
}
