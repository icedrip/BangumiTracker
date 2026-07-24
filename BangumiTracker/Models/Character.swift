import Foundation

// MARK: - Character Search

nonisolated struct CharacterSearchResult: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let images: CharacterImages?
    let actors: [CharacterActor]?

    enum CodingKeys: String, CodingKey {
        case id, name, images, actors
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        images = try c.decodeIfPresent(CharacterImages.self, forKey: .images)
        actors = try c.decodeIfPresent([CharacterActor].self, forKey: .actors)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }
}

nonisolated struct CharacterImages: Codable, Sendable {
    let large: String?
    let medium: String?
    let small: String?
    let grid: String?

    var imageURL: String? {
        // Prefer `large`: Bangumi's character `medium` is a tiny (~50px)
        // thumbnail, which undersamples a 36pt avatar on 3x (needs 108px) —
        // CachedAsyncImage's downsampler can't upscale, so a 50px source
        // renders soft regardless of the targetSize. `large` is the full
        // upload; the downsampler caps the decoded size for memory.
        (large ?? medium ?? small)?.httpsScheme
    }
}

nonisolated struct CharacterActor: Codable, Sendable {
    let id: Int
    let name: String
    let images: PersonImages?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        images = try c.decodeIfPresent(PersonImages.self, forKey: .images)
    }

    enum CodingKeys: String, CodingKey { case id, name, images }
}

nonisolated struct PagedCharacterSearch: Codable, Sendable {
    let data: [CharacterSearchResult]
    let total: Int
}

// MARK: - Person Search

nonisolated struct PersonSearchResult: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let images: PersonImages?
    let career: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, images, career
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        images = try c.decodeIfPresent(PersonImages.self, forKey: .images)
        career = try c.decodeIfPresent([String].self, forKey: .career)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }

    var careerText: String {
        (career ?? []).map { c in
            switch c {
            case "producer": "制作人"
            case "mangaka": "漫画家"
            case "artist": "艺术家"
            case "seiyu": "声优"
            case "writer": "作家"
            case "illustrator": "插画师"
            case "actor": "演员"
            default: c
            }
        }.joined(separator: " / ")
    }
}

nonisolated struct PersonImages: Codable, Sendable {
    let large: String?
    let medium: String?
    let small: String?
    let grid: String?

    var imageURL: String? {
        // Prefer `large`: Bangumi's character `medium` is a tiny (~50px)
        // thumbnail, which undersamples a 36pt avatar on 3x (needs 108px) —
        // CachedAsyncImage's downsampler can't upscale, so a 50px source
        // renders soft regardless of the targetSize. `large` is the full
        // upload; the downsampler caps the decoded size for memory.
        (large ?? medium ?? small)?.httpsScheme
    }
}

nonisolated struct PagedPersonSearch: Codable, Sendable {
    let data: [PersonSearchResult]
    let total: Int
}

// MARK: - Subject Characters (GET /v0/subjects/{id}/characters)

nonisolated struct SubjectCharacter: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    /// Character type (1=人物, 4=机体/组织, …) — NOT the in-subject role.
    let type: Int
    /// The character's role in this subject — "主角" / "配角" / "客串" as a
    /// raw string from the API. Previously `roleText` derived from `type`
    /// (1→主角, 2→配角, 3→客串), but `type` is the character *kind* (almost
    /// always 1=人物), so every character rendered as "主角".
    let relation: String
    let images: CharacterImages?
    let actors: [CharacterActor]?

    enum CodingKeys: String, CodingKey {
        case id, name, type, relation, images, actors
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? 0
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? ""
        images = try c.decodeIfPresent(CharacterImages.self, forKey: .images)
        actors = try c.decodeIfPresent([CharacterActor].self, forKey: .actors)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }

    var roleText: String { relation }
}

// MARK: - Subject Persons (GET /v0/subjects/{id}/persons)

nonisolated struct SubjectPerson: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let images: PersonImages?
    let career: [String]?
    let position: String?

    enum CodingKeys: String, CodingKey {
        case id, name, images, career, position
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        images = try c.decodeIfPresent(PersonImages.self, forKey: .images)
        career = try c.decodeIfPresent([String].self, forKey: .career)
        position = try c.decodeIfPresent(String.self, forKey: .position)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }
}

// MARK: - Character Detail (GET /v0/characters/{id})

nonisolated struct CharacterDetail: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let summary: String?
    let images: CharacterImages?
    let actors: [CharacterActor]?
    let infobox: [InfoboxItem]?

    enum CodingKeys: String, CodingKey {
        case id, name, images, actors, infobox, summary
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        images = try c.decodeIfPresent(CharacterImages.self, forKey: .images)
        actors = try c.decodeIfPresent([CharacterActor].self, forKey: .actors)
        infobox = try c.decodeIfPresent([InfoboxItem].self, forKey: .infobox)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }
}

nonisolated struct InfoboxItem: Codable, Sendable {
    let key: String?
    let value: InfoboxValue?

    enum CodingKeys: String, CodingKey { case key, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        value = try c.decodeIfPresent(InfoboxValue.self, forKey: .value)
    }
}

nonisolated enum InfoboxValue: Codable, Sendable {
    case string(String)
    case array([String])
    /// Bangumi infobox values can also be an array of {k, v} objects —
    /// e.g. a character's aliases: `[{"k":"日文","v":"綾波レイ"}, ...]`.
    /// The previous decoder only handled `String` and `[String]`, so any
    /// kv-array infobox row threw and took down the whole `CharacterDetail`
    /// / `PersonDetail` decode ("加载失败" on the detail page).
    case kvArray([InfoboxKV])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([String].self) {
            self = .array(arr)
        } else if let kvArr = try? c.decode([InfoboxKV].self) {
            self = .kvArray(kvArr)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            // Unknown shape — don't break the whole page over one infobox row.
            self = .string("")
        }
    }

    var displayText: String {
        switch self {
        case .string(let s): s
        case .array(let arr): arr.joined(separator: " / ")
        case .kvArray(let arr): arr.compactMap { $0.v }.joined(separator: " / ")
        }
    }
}

nonisolated struct InfoboxKV: Codable, Sendable {
    let k: String?
    let v: String?

    enum CodingKeys: String, CodingKey { case k, v }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` so a non-string k/v (rare, but possible) doesn't fail the
        // whole kv-array decode — the row just renders with a blank.
        k = try? c.decodeIfPresent(String.self, forKey: .k)
        v = try? c.decodeIfPresent(String.self, forKey: .v)
    }
}

// MARK: - Person Detail (GET /v0/persons/{id})

nonisolated struct PersonDetail: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let nameCn: String
    let summary: String?
    let images: PersonImages?
    let career: [String]?
    let infobox: [InfoboxItem]?

    enum CodingKeys: String, CodingKey {
        case id, name, images, career, infobox, summary
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        images = try c.decodeIfPresent(PersonImages.self, forKey: .images)
        career = try c.decodeIfPresent([String].self, forKey: .career)
        infobox = try c.decodeIfPresent([InfoboxItem].self, forKey: .infobox)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }

    var careerText: String {
        (career ?? []).map { c in
            switch c {
            case "producer": "制作人"
            case "mangaka": "漫画家"
            case "artist": "艺术家"
            case "seiyu": "声优"
            case "writer": "作家"
            case "illustrator": "插画师"
            case "actor": "演员"
            default: c
            }
        }.joined(separator: " / ")
    }
}

// MARK: - Related Subjects (GET /v0/subjects/{id}/subjects)

nonisolated struct RelatedSubject: Codable, Identifiable, Sendable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let images: SubjectImages?
    let relation: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, images, relation
        case nameCn = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try c.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        images = try c.decodeIfPresent(SubjectImages.self, forKey: .images)
        relation = try c.decodeIfPresent(String.self, forKey: .relation)
    }

    var displayName: String { nameCn.isEmpty ? name : nameCn }
    var imageURL: String? { (images?.common ?? images?.medium ?? images?.large)?.httpsScheme }
}
