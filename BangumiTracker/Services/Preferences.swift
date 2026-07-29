import SwiftUI

enum AppTheme: String, CaseIterable, Sendable {
    case light, dark, system

    var displayName: String {
        switch self {
        case .light: "浅色模式"
        case .dark: "深色模式"
        case .system: "跟随系统"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum DefaultListView: String, CaseIterable, Sendable {
    case list, grid

    var displayName: String {
        switch self {
        case .list: "列表"
        case .grid: "网格"
        }
    }

    var iconName: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }

    /// Remaps a previously-persisted raw value that no longer maps to a case —
    /// e.g. the removed `.calendar` — onto a valid default, so the segmented /
    /// Form pickers in SettingsView and WatchingView don't render with no
    /// selection after an upgrade. Idempotent; call once at launch.
    static func migrateStoredValue() {
        let key = PreferenceKey.defaultView
        guard let raw = UserDefaults.standard.string(forKey: key),
              DefaultListView(rawValue: raw) == nil else { return }
        UserDefaults.standard.set(DefaultListView.list.rawValue, forKey: key)
    }
}

enum StartPage: String, CaseIterable, Sendable {
    case home, discover, watching

    var displayName: String {
        switch self {
        case .home: "首页"
        case .discover: "发现"
        case .watching: "在看"
        }
    }
}

enum ScoreDisplay: String, CaseIterable, Sendable {
    case ten = "10"
    case fiveStar = "5star"

    var displayName: String {
        switch self {
        case .ten: "10分制"
        case .fiveStar: "5星制"
        }
    }
}

enum PreferenceKey {
    static let theme = "pref.theme"
    static let defaultView = "pref.defaultView"
    static let startPage = "pref.startPage"
    static let scoreDisplay = "pref.scoreDisplay"
    static let nsfwVisible = "pref.nsfwVisible"
}
