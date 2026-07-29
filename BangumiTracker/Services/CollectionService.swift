import Foundation

/// Shared service for collection operations (wishlist / status-change / delete).
/// ViewModels call into this instead of duplicating the API + cache dance.
/// Stateless — safe to create per-ViewModel or share a single instance.
struct CollectionService {
    private let api: BangumiAPIClient
    private var cache: LocalCacheService?

    init(api: BangumiAPIClient, cache: LocalCacheService?) {
        self.api = api
        self.cache = cache
    }

    /// Adds `subjectId` to the user's wishlist. Throws on failure so the
    /// caller (ViewModel) can set `actionError` and handle its own side effects.
    func addToWishlist(subjectId: Int) async throws {
        var payload = UserSubjectCollectionModifyPayload()
        payload.type = CollectionType.wish.rawValue
        try await api.updateCollection(subjectId: subjectId, payload: payload)
    }

    /// Moves a collection item to another status.
    func setStatus(subjectId: Int, type: CollectionType) async throws {
        var payload = UserSubjectCollectionModifyPayload()
        payload.type = type.rawValue
        try await api.updateCollection(subjectId: subjectId, payload: payload)
    }

    /// Deletes a collection item entirely.
    func deleteCollection(subjectId: Int) async throws {
        try await api.deleteCollection(subjectId: subjectId)
    }

    /// Records a wish-collected-at timestamp for sorting purposes.
    func recordWishCollectedAt(userId: Int, subjectId: Int) {
        cache?.recordWishCollectedAt(userId: userId, subjectId: subjectId, at: Date())
    }

    /// Upserts the cached collection type (create-if-missing) for the in-memory overlay.
    func upsertCachedCollectionType(subjectId: Int, type: CollectionType, subjectType: Int = 0) {
        cache?.upsertCachedCollectionType(subjectId: subjectId, type: type, subjectType: subjectType)
    }

    /// Removes a cached collection entry.
    func removeCachedCollection(subjectId: Int) {
        cache?.removeCachedCollection(subjectId: subjectId)
    }
}
