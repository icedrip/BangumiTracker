import Foundation

// MARK: - Widget Shared Types
// These types are used by WidgetDataService (main app) and WidgetModels (widget extension).
// They are defined here so the main app target can compile WidgetDataService.swift.

/// 组件列表中的单个作品条目
struct WidgetSubjectItem: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let imageURL: String?
    let type: Int
    let progress: String?
    let subjectDate: String?
}

/// Widget 1 和 Widget 2 未登录降级使用的数据
struct WidgetRecommendationData: Codable, Sendable {
    let items: [WidgetSubjectItem]
    let refreshedAt: Date
}

/// Widget 2 登录用户使用的数据
struct WidgetWatchingData: Codable, Sendable {
    let items: [WidgetSubjectItem]
    let isAuthenticated: Bool
    let refreshedAt: Date
}

/// UserDefaults key 常量
enum AppGroupKeys {
    static let appGroupID = "group.z.zy.BangumiTracker"

    static let recommendData = "widget_recommend_data"
    static let watchingData = "widget_watching_data"
    static let isAuthenticated = "widget_is_authenticated"
}
