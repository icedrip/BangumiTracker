import Foundation

nonisolated struct Episode: Codable, Identifiable, Sendable {
    let id: Int
    let type: EpisodeType
    let name: String
    let nameCn: String
    let sort: Double
    let ep: Double?
    let airdate: String
    let duration: String
    let durationSeconds: Int?
    let desc: String
    let disc: Int

    enum CodingKeys: String, CodingKey {
        case id, type, name, sort, ep, airdate, duration, desc, disc
        case nameCn = "name_cn"
        case durationSeconds = "duration_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = (try? c.decode(EpisodeType.self, forKey: .type)) ?? .main
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        sort = try c.decodeIfPresent(Double.self, forKey: .sort) ?? 0
        ep = try c.decodeIfPresent(Double.self, forKey: .ep)
        airdate = try c.decodeIfPresent(String.self, forKey: .airdate) ?? ""
        duration = try c.decodeIfPresent(String.self, forKey: .duration) ?? ""
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        desc = try c.decodeIfPresent(String.self, forKey: .desc) ?? ""
        disc = try c.decodeIfPresent(Int.self, forKey: .disc) ?? 0
    }

    /// Display number for the episode grid. Prefers `sort` — Bangumi's
    /// canonical ordering field — because multi-season franchises with
    /// absolute numbering carry the absolute episode number in `sort`
    /// (e.g. 凡人修仙传第五季's first episode is `sort=177`, `ep=1`), while
    /// single-season shows have `sort == ep` so preferring `sort` is a
    /// no-op there. Falls back to `ep` only when `sort` is missing,
    /// non-positive, or fractional (e.g. a 0.5 recap slot).
    var episodeNumber: Int? {
        if sort >= 1, sort == sort.rounded() { return Int(sort) }
        if let ep, ep >= 1 { return Int(ep) }
        // Fractional `sort` (rare recap slot) with no usable `ep`: truncate
        // sort rather than return nil, so the grid shows the slot's number
        // instead of "0" (matches the old `?? Int(sort)` fallback).
        return sort >= 1 ? Int(sort) : nil
    }
}

nonisolated struct PagedEpisode: Codable, Sendable {
    let data: [Episode]
    let total: Int
}
