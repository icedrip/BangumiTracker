import Foundation
import WidgetKit

/// Widget 数据条目的通用封装
struct WidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSubjectItem]
    let imageData: [Int: Data]
    let placeholder: Bool
}

/// TimelineProvider 的通用工具方法
enum WidgetProvider {

    static func readItems(from key: String) -> [WidgetSubjectItem] {
        guard let defaults = UserDefaults(suiteName: AppGroupKeys.appGroupID),
              let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WidgetRecommendationData.self, from: data) else {
            return []
        }
        return decoded.items
    }

    static func readWatchingItems() -> (items: [WidgetSubjectItem], isAuthenticated: Bool) {
        guard let defaults = UserDefaults(suiteName: AppGroupKeys.appGroupID),
              let data = defaults.data(forKey: AppGroupKeys.watchingData),
              let decoded = try? JSONDecoder().decode(WidgetWatchingData.self, from: data) else {
            return ([], false)
        }
        return (decoded.items, decoded.isAuthenticated)
    }

    /// 从 App Group 共享文件缓存读取图片数据
    /// App 在写入 widget 数据时会一并下载并缓存封面图
    static func loadImages(for items: [WidgetSubjectItem]) -> [Int: Data] {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupKeys.appGroupID) else {
            return [:]
        }
        let cacheDir = container.appendingPathComponent("widget_images", isDirectory: true)
        var result: [Int: Data] = [:]
        for item in items {
            let fileURL = cacheDir.appendingPathComponent("\(item.id).jpg")
            if let data = try? Data(contentsOf: fileURL) {
                result[item.id] = data
            }
        }
        return result
    }

    static func timeline(for key: String) -> Timeline<WidgetEntry> {
        let items = readItems(from: key)
        if items.isEmpty {
            let entry = WidgetEntry(date: Date(), items: [], imageData: [:], placeholder: true)
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600)))
        }
        let images = loadImages(for: items)
        let entry = WidgetEntry(date: Date(), items: items, imageData: images, placeholder: false)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600)))
    }
}
