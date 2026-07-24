import Foundation
import SwiftData

// MARK: - API DTOs

nonisolated struct UserSubjectCollection: Codable, Identifiable, Sendable {
    let subjectId: Int
    let subjectType: Int
    let rate: Int
    let type: Int
    let comment: String?
    let tags: [String]
    /// `var` so `SubjectDetailViewModel.adjustBookProgress` can apply an
    /// optimistic in-place update before the API round-trip (the stepper reads
    /// `collection?.epStatus` directly).
    var epStatus: Int
    var volStatus: Int
    let isPrivate: Bool
    let subject: SlimSubject?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case subjectId = "subject_id"
        case subjectType = "subject_type"
        case rate, type, comment, tags, subject
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case isPrivate = "private"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjectId = try c.decode(Int.self, forKey: .subjectId)
        subjectType = try c.decodeIfPresent(Int.self, forKey: .subjectType) ?? 0
        rate = try c.decodeIfPresent(Int.self, forKey: .rate) ?? 0
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? CollectionType.wish.rawValue
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        epStatus = try c.decodeIfPresent(Int.self, forKey: .epStatus) ?? 0
        volStatus = try c.decodeIfPresent(Int.self, forKey: .volStatus) ?? 0
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        subject = try c.decodeIfPresent(SlimSubject.self, forKey: .subject)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var id: Int { subjectId }
    var collectionType: CollectionType { CollectionType(rawValue: type) ?? .wish }
}

extension UserSubjectCollection {
    init(from cached: CachedUserCollection) {
        self.subjectId = cached.subjectId
        self.subjectType = cached.subjectType
        self.rate = cached.rate
        self.type = cached.collectionType
        self.comment = cached.comment
        self.tags = cached.tags
        // Books' ep/vol progress isn't cached (CachedUserCollection has no
        // such fields — anime/real progress lives in the per-episode cache,
        // and the watching list is anime/real-only). Cache-restored books
        // therefore show 0 until the detail page refetches the collection.
        self.epStatus = 0
        self.volStatus = 0
        self.isPrivate = cached.isPrivate
        self.subject = cached.subject.map { SlimSubject(from: $0) }
        self.updatedAt = nil
    }
}

extension SlimSubject {
    init(from cached: CachedSubject) {
        self.id = cached.id
        self.type = cached.type
        self.name = cached.name
        self.nameCn = cached.nameCn
        self.images = SubjectImages(
            large: nil,
            common: cached.imageCommon,
            medium: nil,
            small: nil,
            grid: nil
        )
        self.date = cached.date
        self.rating = cached.ratingScore > 0 ? SubjectRating(score: cached.ratingScore, total: 0) : nil
        self.rank = cached.rank
        self.eps = cached.eps
        self.totalEpisodes = cached.totalEpisodes
    }
}

nonisolated struct UserEpisodeCollection: Codable, Identifiable, Sendable {
    let episode: Episode
    let type: EpisodeCollectionType
    let updatedAt: Int?

    enum CodingKeys: String, CodingKey {
        case episode, type
        case updatedAt = "updated_at"
    }

    var id: Int { episode.id }
}

nonisolated struct PagedUserCollection: Codable, Sendable {
    let data: [UserSubjectCollection]
    let total: Int
}

nonisolated struct UserSubjectCollectionModifyPayload: Codable, Sendable {
    var type: Int?
    var rate: Int?
    var epStatus: Int?
    var volStatus: Int?
    var comment: String?
    var isPrivate: Bool?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case type, rate, comment, tags
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case isPrivate = "private"
    }
}

// MARK: - SwiftData Cache

@Model
final class CachedUserCollection {
    @Attribute(.unique) var subjectId: Int
    var subjectType: Int
    var rate: Int
    var collectionType: Int
    var comment: String?
    var tags: [String]
    var isPrivate: Bool
    var cachedAt: Date
    @Relationship(deleteRule: .nullify) var subject: CachedSubject?

    init(subjectId: Int, subjectType: Int, rate: Int = 0, collectionType: Int = CollectionType.wish.rawValue, comment: String? = nil, tags: [String] = [], isPrivate: Bool = false, subject: CachedSubject? = nil) {
        self.subjectId = subjectId
        self.subjectType = subjectType
        self.rate = rate
        self.collectionType = collectionType
        self.comment = comment
        self.tags = tags
        self.isPrivate = isPrivate
        self.cachedAt = Date()
        self.subject = subject
    }
}

/// Per-user, per-subject local timestamp for "added to wish list".
/// Bangumi's `updated_at` is unreliable (mutated by comment/tag/rate edits), so the
/// home wish-list "by collection time" sort uses this local stamp first and falls
/// back to API `updated_at` for items added before this record existed.
/// `(userId, subjectId)` is the natural composite key — uniqueness is enforced by
/// the upsert in `LocalCacheService` (fetch-then-insert), not by a `@Attribute(.unique)`,
/// since SwiftData's unique constraint is single-attribute only.
@Model
final class WishCollectedAt {
    var userId: Int
    var subjectId: Int
    var collectedAt: Date

    init(userId: Int, subjectId: Int, collectedAt: Date = Date()) {
        self.userId = userId
        self.subjectId = subjectId
        self.collectedAt = collectedAt
    }
}
