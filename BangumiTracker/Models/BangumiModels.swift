import Foundation
import SwiftUI

// MARK: - Subject Type

enum SubjectType: Int, Codable, CaseIterable, Sendable {
    case anime = 2
    case book = 1
    case music = 3
    case game = 4
    case real = 6

    var displayName: String {
        switch self {
        case .anime: "动画"
        case .book: "书籍"
        case .music: "音乐"
        case .game: "游戏"
        case .real: "三次元"
        }
    }

    /// The action verb for this subject type — used to derive collection
    /// status labels (想看/想读/想听/想玩 etc.).
    var actionVerb: String {
        switch self {
        case .anime, .real: "看"
        case .book: "读"
        case .music: "听"
        case .game: "玩"
        }
    }

    /// The completion form of the verb for "all complete" labels.
    /// For games, "通关" avoids the "玩完" double-entendre (colloquial
    /// Chinese for "done for / ruined").
    var completionForm: String {
        switch self {
        case .anime, .real: "看完"
        case .book: "读完"
        case .music: "听完"
        case .game: "通关"
        }
    }

    /// Label for the wish-list action button (e.g. anime→"标记观看", book→"标记阅读").
    var startActionLabel: String {
        switch self {
        case .anime, .real: "标记观看"
        case .book: "标记阅读"
        case .music: "标记收听"
        case .game: "标记游玩"
        }
    }
}

// MARK: - Collection Status

enum CollectionType: Int, Codable, CaseIterable, Sendable {
    case wish = 1
    case watched = 2
    case watching = 3
    case onHold = 4
    case dropped = 5

    var displayName: String {
        switch self {
        case .wish: "想看"
        case .watched: "看过"
        case .watching: "在看"
        case .onHold: "搁置"
        case .dropped: "抛弃"
        }
    }
}

extension CollectionType {
    /// Subject-type-aware display name. Uses the correct verb (看/读/听/玩)
    /// for wish, watched, and watching statuses; onHold/dropped are universal.
    /// Pass nil to default to anime/real (看) terminology.
    func displayName(for subjectType: SubjectType?) -> String {
        guard let st = subjectType else { return displayName }
        let verb = st.actionVerb
        switch self {
        case .wish:     return "想\(verb)"
        case .watched:  return "\(verb)过"
        case .watching: return "在\(verb)"
        case .onHold, .dropped: return displayName
        }
    }

    /// Collected-badge label for subject cards. For `.wish` adds a "已" prefix
    /// ("已想看" / "已想玩") to distinguish from the uncollected "+ 想X" quick-add
    /// button. Other statuses delegate to `displayName(for:)`.
    func collectedDisplayName(for subjectType: SubjectType?) -> String {
        if self == .wish { return "已\(displayName(for: subjectType))" }
        return displayName(for: subjectType)
    }

    /// Canonical color for this collection status — single source of truth shared
    /// by every status badge in the app (SubjectCard capsule, ProfileView stat
    /// cards). Do not re-derive per-view; add new cases here.
    var displayColor: Color {
        switch self {
        case .wish:     .orange
        case .watched:  .green
        case .watching: .blue
        case .onHold:   .gray
        case .dropped:  .red
        }
    }
}

// MARK: - Episode Collection Type

enum EpisodeCollectionType: Int, Codable, Sendable {
    case none = 0
    case wish = 1
    case watched = 2
    case dropped = 3
}

// MARK: - Episode Type

enum EpisodeType: Int, Codable, Sendable {
    case main = 0
    case sp = 1
    case op = 2
    case ed = 3
    case preview = 4
    case mad = 5
    case other = 6
}

// MARK: - Sort Order

enum WantToWatchSort: String, CaseIterable, Sendable {
    case collectedAt
    case rank

    var displayName: String {
        switch self {
        case .collectedAt: "收藏时间"
        case .rank: "排名"
        }
    }
}
