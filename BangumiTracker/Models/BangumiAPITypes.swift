import Foundation

// MARK: - Calendar Day

nonisolated struct CalendarDay: Codable, Sendable {
    let weekday: WeekdayInfo
    let items: [SlimSubject]
}

nonisolated struct WeekdayInfo: Codable, Sendable {
    let en: String
    let cn: String
    let ja: String
    let id: Int
}

// MARK: - User Info

nonisolated struct UserInfo: Codable, Identifiable, Sendable {
    let id: Int
    let username: String
    let nickname: String
    let avatar: UserAvatar
    let sign: String?

    nonisolated struct UserAvatar: Codable, Sendable {
        let large: String?
        let medium: String?
        let small: String?
    }
}

// MARK: - Search Filter

nonisolated struct SubjectSearchFilter: Codable, Sendable {
    var type: [Int]?
    var metaTags: [String]?
    var airDate: [String]?
    var rating: [String]?
    var ratingCount: [String]?
    var rank: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case metaTags = "meta_tags"
        case airDate = "air_date"
        case rating
        case ratingCount = "rating_count"
        case rank
    }
}
