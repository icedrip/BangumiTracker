import Foundation
import SwiftData

// MARK: - API DTOs

nonisolated struct SubjectImages: Codable, Sendable {
    let large: String?
    let common: String?
    let medium: String?
    let small: String?
    let grid: String?
}

nonisolated struct SubjectRating: Codable, Sendable {
    let score: Double
    let total: Int
}

nonisolated struct SubjectCollectionCount: Codable, Sendable {
    let wish: Int
    let collect: Int
    let doing: Int
    let onHold: Int
    let dropped: Int

    enum CodingKeys: String, CodingKey {
        case wish, collect, doing
        case onHold = "on_hold"
        case dropped
    }
}

nonisolated struct SubjectTag: Codable, Sendable {
    let name: String
    let count: Int
}

nonisolated struct SlimSubject: Codable, Identifiable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let images: SubjectImages?
    let date: String?
    let rating: SubjectRating?
    let rank: Int
    let eps: Int?
    let totalEpisodes: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, name, images, date, rating, rank, eps
        case nameCn = "name_cn"
        case totalEpisodes = "total_episodes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decode(Int.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        images = try c.decodeIfPresent(SubjectImages.self, forKey: .images)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        rating = try c.decodeIfPresent(SubjectRating.self, forKey: .rating)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        eps = try c.decodeIfPresent(Int.self, forKey: .eps)
        totalEpisodes = try c.decodeIfPresent(Int.self, forKey: .totalEpisodes)
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }

    var imageURL: String? {
        (images?.common ?? images?.medium ?? images?.large)?.httpsScheme
    }
}

nonisolated struct Subject: Codable, Identifiable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let summary: String
    let nsfw: Bool
    let date: String?
    let platform: String
    let images: SubjectImages?
    let eps: Int
    let totalEpisodes: Int
    let rating: SubjectRating?
    let rank: Int
    let collection: SubjectCollectionCount?
    let metaTags: [String]
    let tags: [SubjectTag]
    let series: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, name, summary, nsfw, date, platform, images, eps, rating, rank, collection, tags, series
        case nameCn = "name_cn"
        case totalEpisodes = "total_episodes"
        case metaTags = "meta_tags"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decode(Int.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        nsfw = try c.decodeIfPresent(Bool.self, forKey: .nsfw) ?? false
        date = try c.decodeIfPresent(String.self, forKey: .date)
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        images = try c.decodeIfPresent(SubjectImages.self, forKey: .images)
        eps = try c.decodeIfPresent(Int.self, forKey: .eps) ?? 0
        totalEpisodes = try c.decodeIfPresent(Int.self, forKey: .totalEpisodes) ?? 0
        rating = try c.decodeIfPresent(SubjectRating.self, forKey: .rating)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        collection = try c.decodeIfPresent(SubjectCollectionCount.self, forKey: .collection)
        metaTags = Self.dedupedMetaTags(try c.decodeIfPresent([String].self, forKey: .metaTags) ?? [])
        tags = try c.decodeIfPresent([SubjectTag].self, forKey: .tags) ?? []
        series = try c.decodeIfPresent(Bool.self, forKey: .series) ?? false
    }

    init(from slim: SlimSubject) {
        self.id = slim.id
        self.type = slim.type
        self.name = slim.name
        self.nameCn = slim.nameCn
        self.summary = ""
        self.nsfw = false
        self.date = slim.date
        self.platform = ""
        self.images = slim.images
        self.eps = slim.eps ?? 0
        self.totalEpisodes = slim.totalEpisodes ?? 0
        self.rating = slim.rating
        self.rank = slim.rank
        self.collection = nil
        self.metaTags = []
        self.tags = []
        self.series = false
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }

    var imageURL: String? {
        (images?.common ?? images?.medium ?? images?.large)?.httpsScheme
    }
}

nonisolated struct PagedSubject: Codable, Sendable {
    let data: [Subject]
    let total: Int
}

nonisolated extension String {
    var httpsScheme: String {
        if hasPrefix("http://") {
            replacingOccurrences(of: "http://", with: "https://")
        } else {
            self
        }
    }
}

// MARK: - SwiftData Cache

@Model
final class CachedSubject {
    @Attribute(.unique) var id: Int
    var type: Int
    var name: String
    var nameCn: String
    var summary: String
    var date: String?
    var platform: String
    var imageCommon: String?
    var eps: Int
    var totalEpisodes: Int
    var ratingScore: Double
    var rank: Int
    var metaTags: [String]
    var cachedAt: Date

    init(id: Int, type: Int, name: String, nameCn: String, summary: String, date: String?, platform: String, imageCommon: String?, eps: Int, totalEpisodes: Int, ratingScore: Double, rank: Int, metaTags: [String] = []) {
        self.id = id
        self.type = type
        self.name = name
        self.nameCn = nameCn
        self.summary = summary
        self.date = date
        self.platform = platform
        self.imageCommon = imageCommon
        self.eps = eps
        self.totalEpisodes = totalEpisodes
        self.ratingScore = ratingScore
        self.rank = rank
        self.metaTags = metaTags
        self.cachedAt = Date()
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }
}

extension Subject {
    /// Bangumi's `meta_tags` occasionally returns duplicates (e.g. subject
    /// 9912 "日常" lists every tag twice). Dedupe at the decode/cache
    /// boundary so every consumer — SwiftData cache, search, detail — gets
    /// clean data instead of each view re-dedupeing at render time.
    nonisolated private static func dedupedMetaTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }

    init(from cached: CachedSubject) {
        self.id = cached.id
        self.type = cached.type
        self.name = cached.name
        self.nameCn = cached.nameCn
        self.summary = cached.summary
        self.nsfw = false
        self.date = cached.date
        self.platform = cached.platform
        self.images = SubjectImages(
            large: nil,
            common: cached.imageCommon,
            medium: nil,
            small: nil,
            grid: nil
        )
        self.eps = cached.eps
        self.totalEpisodes = cached.totalEpisodes
        self.rating = cached.ratingScore > 0 ? SubjectRating(score: cached.ratingScore, total: 0) : nil
        self.rank = cached.rank
        self.collection = nil
        self.metaTags = Self.dedupedMetaTags(cached.metaTags)
        self.tags = []
        self.series = false
    }
}
