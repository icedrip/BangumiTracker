import Foundation
import UIKit
import WidgetKit

/// 负责将组件所需数据从 App 写入共享 UserDefaults，并刷新 Widget timeline。
@MainActor
enum WidgetDataService {

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupKeys.appGroupID)
    }

    private static var imageCacheDir: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupKeys.appGroupID) else { return nil }
        let dir = container.appendingPathComponent("widget_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 写入今日放送数据（Widget 1 + Widget 2 未登录降级）
    static func writeRecommendationData(from calendarDays: [CalendarDay]) async {
        guard let defaults else { return }
        let today = currentWeekday()
        guard let todayDay = calendarDays.first(where: { $0.weekday.id == today }) else {
            defaults.removeObject(forKey: AppGroupKeys.recommendData)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let items = todayDay.items.map { subject in
            WidgetSubjectItem(
                id: subject.id,
                title: subject.displayName,
                imageURL: subject.imageURL,
                type: subject.type,
                progress: subject.totalEpisodes.map { "全\($0)话" },
                subjectDate: subject.date
            )
        }
        let data = WidgetRecommendationData(items: items, refreshedAt: Date())
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: AppGroupKeys.recommendData)
        }
        await cacheImages(for: items)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 写入追番进度数据（Widget 2 已登录状态）
    static func writeWatchingData(from collections: [UserSubjectCollection]) async {
        guard let defaults else { return }
        let items = collections.map { collection -> WidgetSubjectItem in
            let totalEps = collection.subject?.totalEpisodes ?? collection.subject?.eps ?? 0
            let progress: String?
            let subjectType = SubjectType(rawValue: collection.subjectType)
            switch subjectType {
            case .anime, .real:
                progress = totalEps > 0 ? "已看 \(collection.epStatus)/\(totalEps) 话" : nil
            case .book:
                progress = totalEps > 0 ? "已读 \(collection.volStatus)/\(totalEps) 卷" : nil
            case .music, .game, nil:
                progress = nil
            }
            return WidgetSubjectItem(
                id: collection.subjectId,
                title: collection.subject?.displayName ?? "未知",
                imageURL: collection.subject?.imageURL,
                type: collection.subjectType,
                progress: progress,
                subjectDate: collection.subject?.date
            )
        }
        let data = WidgetWatchingData(items: items, isAuthenticated: true, refreshedAt: Date())
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: AppGroupKeys.watchingData)
            defaults.set(true, forKey: AppGroupKeys.isAuthenticated)
        }
        await cacheImages(for: items)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 写入登录状态（登录/登出时）
    static func writeAuthState(isAuthenticated: Bool) {
        guard let defaults else { return }
        defaults.set(isAuthenticated, forKey: AppGroupKeys.isAuthenticated)
        if !isAuthenticated {
            defaults.removeObject(forKey: AppGroupKeys.watchingData)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 清空所有 widget 数据（登出时）
    static func clearAll() {
        guard let defaults else { return }
        defaults.removeObject(forKey: AppGroupKeys.recommendData)
        defaults.removeObject(forKey: AppGroupKeys.watchingData)
        defaults.set(false, forKey: AppGroupKeys.isAuthenticated)
        clearImageCache()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Image Cache

    /// 预下载封面图到 App Group 共享目录（widget 侧从该目录读取）
    private static func cacheImages(for items: [WidgetSubjectItem]) async {
        guard let cacheDir = imageCacheDir else { return }
        let toDownload = items.filter { item in
            guard let urlString = item.imageURL, URL(string: urlString) != nil else { return false }
            let fileURL = cacheDir.appendingPathComponent("\(item.id).jpg")
            return !FileManager.default.fileExists(atPath: fileURL.path)
        }
        guard !toDownload.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for item in toDownload {
                group.addTask {
                    guard let urlString = item.imageURL, let url = URL(string: urlString) else { return }
                    let fileURL = cacheDir.appendingPathComponent("\(item.id).jpg")
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        try data.write(to: fileURL)
                    } catch {
                        // 图片下载失败可忽略，widget 会显示占位
                    }
                }
            }
        }
    }

    /// 清空共享图片缓存
    private static func clearImageCache() {
        guard let cacheDir = imageCacheDir else { return }
        try? FileManager.default.removeItem(at: cacheDir)
    }

    // MARK: - Helpers

    /// Bangumi 星期映射: 1=Monday ... 7=Sunday
    private static func currentWeekday() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }
}
