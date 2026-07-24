import Foundation
import SwiftData
import OSLog

@MainActor
final class LocalCacheService {
    private let modelContext: ModelContext
    private static let logger = Logger(subsystem: "z.zy.BangumiTracker", category: "LocalCache")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Subjects

    func cacheSubjects(_ subjects: [Subject]) {
        for subject in subjects {
            upsertSubject(subject)
        }
        save()
    }

    @discardableResult
    private func upsertSubject(_ subject: Subject) -> CachedSubject {
        if let existing = getCachedSubject(id: subject.id) {
            existing.type = subject.type
            existing.name = subject.name
            existing.nameCn = subject.nameCn
            existing.summary = subject.summary
            existing.date = subject.date
            existing.platform = subject.platform
            existing.imageCommon = subject.imageURL
            existing.eps = subject.eps
            existing.totalEpisodes = subject.totalEpisodes
            existing.ratingScore = subject.rating?.score ?? 0
            // Preserve a known rank when the upcoming payload reports 0 — list
            // endpoints sometimes omit `rank` even when we already have it from
            // a detail fetch (or vice versa).
            if subject.rank > 0 { existing.rank = subject.rank }
            existing.metaTags = subject.metaTags
            existing.cachedAt = Date()
            return existing
        }
        let model = CachedSubject(
            id: subject.id,
            type: subject.type,
            name: subject.name,
            nameCn: subject.nameCn,
            summary: subject.summary,
            date: subject.date,
            platform: subject.platform,
            imageCommon: subject.imageURL,
            eps: subject.eps,
            totalEpisodes: subject.totalEpisodes,
            ratingScore: subject.rating?.score ?? 0,
            rank: subject.rank,
            metaTags: subject.metaTags
        )
        modelContext.insert(model)
        return model
    }

    func getCachedSubject(id: Int) -> CachedSubject? {
        let predicate = #Predicate<CachedSubject> { $0.id == id }
        var descriptor = FetchDescriptor<CachedSubject>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func getCachedSubjects(ids: [Int]) -> [CachedSubject] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let predicate = #Predicate<CachedSubject> { idSet.contains($0.id) }
        let descriptor = FetchDescriptor<CachedSubject>(predicate: predicate)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Collections

    func cacheCollections(_ collections: [UserSubjectCollection]) {
        for collection in collections {
            upsertCollection(collection)
        }
        save()
    }

    private func upsertCollection(_ collection: UserSubjectCollection) {
        // Also cache the SlimSubject so cached collections have subject data
        if let slim = collection.subject {
            let subject = Subject(from: slim)
            upsertSubject(subject)
        }
        if let existing = getCachedCollection(subjectId: collection.subjectId) {
            existing.subjectType = collection.subjectType
            existing.rate = collection.rate
            existing.collectionType = collection.type
            existing.comment = collection.comment
            existing.tags = collection.tags
            existing.isPrivate = collection.isPrivate
            existing.cachedAt = Date()
            return
        }
        let model = CachedUserCollection(
            subjectId: collection.subjectId,
            subjectType: collection.subjectType,
            rate: collection.rate,
            collectionType: collection.type,
            comment: collection.comment,
            tags: collection.tags,
            isPrivate: collection.isPrivate
        )
        modelContext.insert(model)
    }

    func getCachedCollections(type: CollectionType? = nil) -> [CachedUserCollection] {
        let descriptor: FetchDescriptor<CachedUserCollection>
        if let type {
            let raw = type.rawValue
            descriptor = FetchDescriptor<CachedUserCollection>(
                predicate: #Predicate { $0.collectionType == raw },
                sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<CachedUserCollection>(
                sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]
            )
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getCachedCollection(subjectId: Int) -> CachedUserCollection? {
        let predicate = #Predicate<CachedUserCollection> { $0.subjectId == subjectId }
        var descriptor = FetchDescriptor<CachedUserCollection>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Updates a cached collection's type (e.g. wish → watching) without a full refetch.
    /// Used after optimistic mutations so other views reading the cache stay in sync.
    func updateCachedCollectionType(subjectId: Int, type: CollectionType) {
        guard let cached = getCachedCollection(subjectId: subjectId) else { return }
        cached.collectionType = type.rawValue
        cached.cachedAt = Date()
        save()
    }

    /// Upserts a cached collection's type, creating a minimal row if the subject
    /// isn't cached yet. Used after an optimistic add from a context that has no
    /// full collection object (e.g. Explore's "+想看" from a `Subject`) so other
    /// tabs reading the cache see the new status without waiting for a refetch.
    /// `updateCachedCollectionType` is a no-op when the row is missing; this one
    /// creates it. The row is enriched with real data on the next collection list fetch.
    func upsertCachedCollectionType(subjectId: Int, type: CollectionType, subjectType: Int = 0) {
        if let cached = getCachedCollection(subjectId: subjectId) {
            cached.collectionType = type.rawValue
            cached.cachedAt = Date()
        } else {
            modelContext.insert(CachedUserCollection(
                subjectId: subjectId,
                subjectType: subjectType,
                collectionType: type.rawValue
            ))
        }
        save()
    }

    /// Drops a cached collection entirely (after a delete) so other tabs stop
    /// showing it as collected. Subject cache is left intact (public data).
    func removeCachedCollection(subjectId: Int) {
        if let cached = getCachedCollection(subjectId: subjectId) {
            modelContext.delete(cached)
            save()
        }
    }

    // MARK: - Wish Collected-At (per-user local timestamp)

    /// Stamps the moment the user added this subject to their wish list. Called only
    /// when we know it's a fresh add (HomeViewModel.addToWishlist, SubjectDetail
    /// status transition into .wish). The bulk wish-list fetch does NOT seed —
    /// items without a record fall back to API `updated_at` at sort time.
    func recordWishCollectedAt(userId: Int, subjectId: Int, at date: Date = Date()) {
        guard userId > 0 else { return }
        if let existing = fetchWishCollectedAt(userId: userId, subjectId: subjectId) {
            existing.collectedAt = date
        } else {
            modelContext.insert(WishCollectedAt(userId: userId, subjectId: subjectId, collectedAt: date))
        }
        save()
    }

    /// Drops the local timestamp when a subject leaves the wish list (e.g. moves to
    /// watching, dropped, or the collection is deleted). Re-adding to wish later
    /// gets a fresh stamp via `recordWishCollectedAt`.
    func clearWishCollectedAt(userId: Int, subjectId: Int) {
        guard userId > 0 else { return }
        if let existing = fetchWishCollectedAt(userId: userId, subjectId: subjectId) {
            modelContext.delete(existing)
            save()
        }
    }

    /// Looks up locally-known wish timestamps for the given subject ids. Returns a
    /// map keyed by subjectId; missing entries mean "no local record" — callers
    /// should fall back to the API's `updated_at`.
    func wishCollectedAtMap(userId: Int, subjectIds: [Int]) -> [Int: Date] {
        guard userId > 0, !subjectIds.isEmpty else { return [:] }
        let idSet = Set(subjectIds)
        let predicate = #Predicate<WishCollectedAt> {
            $0.userId == userId && idSet.contains($0.subjectId)
        }
        let descriptor = FetchDescriptor<WishCollectedAt>(predicate: predicate)
        guard let rows = try? modelContext.fetch(descriptor) else { return [:] }
        // `uniquingKeysWith` (not `uniqueKeysWithValues:`) so a duplicate
        // (userId, subjectId) row — from a past bug or a migration — degrades
        // to a non-deterministic pick instead of trapping. All writers are
        // @MainActor-serialized so dups shouldn't occur, but this is the
        // load-bearing sort path for the wish list and shouldn't crash.
        return Dictionary(rows.map { ($0.subjectId, $0.collectedAt) }, uniquingKeysWith: { _, latest in latest })
    }

    private func fetchWishCollectedAt(userId: Int, subjectId: Int) -> WishCollectedAt? {
        let predicate = #Predicate<WishCollectedAt> {
            $0.userId == userId && $0.subjectId == subjectId
        }
        var descriptor = FetchDescriptor<WishCollectedAt>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Search History

    func addSearchHistory(keyword: String, searchType: String = "subject") {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let predicate = #Predicate<SearchHistory> {
            $0.keyword == trimmed && $0.searchType == searchType
        }
        let descriptor = FetchDescriptor<SearchHistory>(predicate: predicate)
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.searchedAt = Date()
        } else {
            modelContext.insert(SearchHistory(keyword: trimmed, searchType: searchType))
        }

        // Cap at 20 entries per type
        let allDescriptor = FetchDescriptor<SearchHistory>(
            predicate: #Predicate { $0.searchType == searchType },
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        if let all = try? modelContext.fetch(allDescriptor), all.count > 20 {
            for item in all[20...] {
                modelContext.delete(item)
            }
        }
        save()
    }

    func getSearchHistory(searchType: String? = nil) -> [SearchHistory] {
        let descriptor: FetchDescriptor<SearchHistory>
        if let searchType {
            descriptor = FetchDescriptor<SearchHistory>(
                predicate: #Predicate { $0.searchType == searchType },
                sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<SearchHistory>(
                sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
            )
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func clearSearchHistory() {
        try? modelContext.delete(model: SearchHistory.self)
        save()
    }

    // MARK: - Cache Management

    func updateCachedSubjectEpisodeCount(id: Int, count: Int) {
        guard count > 0 else { return }
        if let cached = getCachedSubject(id: id) {
            cached.totalEpisodes = count
            save()
        }
    }

    func clearAllCache() {
        try? modelContext.delete(model: CachedSubject.self)
        try? modelContext.delete(model: CachedUserCollection.self)
        // Wish timestamps are per-user cache state too — clear them so a
        // "清除本地缓存" actually resets the wish-list sort ordering rather
        // than leaving stale stamps from a prior session. (SearchHistory is
        // intentionally preserved, per the confirm-dialog copy.)
        try? modelContext.delete(model: WishCollectedAt.self)
        save()
    }

    // MARK: - Save

    private func save() {
        do {
            try modelContext.save()
        } catch {
            // Log via OSLog (print only reaches stderr) so the failure is
            // visible in Console / `simctl log` — a swallowed SwiftData error
            // here would otherwise silently drop un-persisted writes.
            Self.logger.error("save failed: \(error.localizedDescription)")
        }
    }
}
