import WidgetKit
import SwiftUI

struct WatchingProgressWidget: Widget {
    let kind: String = "WatchingProgress"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchingProgressProvider()) { entry in
            WatchingProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("追番进度")
        .description("查看正在追的作品进度")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct WatchingProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), items: [], imageData: [:], placeholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let (watchingItems, isAuthenticated) = WidgetProvider.readWatchingItems()
        let items: [WidgetSubjectItem]
        if isAuthenticated && !watchingItems.isEmpty {
            items = watchingItems
        } else {
            items = WidgetProvider.readItems(from: AppGroupKeys.recommendData)
        }
        if items.isEmpty {
            completion(WidgetEntry(date: Date(), items: [], imageData: [:], placeholder: true))
        } else {
            let images = WidgetProvider.loadImages(for: items)
            completion(WidgetEntry(date: Date(), items: items, imageData: images, placeholder: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let (watchingItems, isAuthenticated) = WidgetProvider.readWatchingItems()
        if isAuthenticated && !watchingItems.isEmpty {
            let images = WidgetProvider.loadImages(for: watchingItems)
            let entry = WidgetEntry(date: Date(), items: watchingItems, imageData: images, placeholder: false)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
        } else {
            let timeline = WidgetProvider.timeline(for: AppGroupKeys.recommendData)
            completion(timeline)
        }
    }
}

struct WatchingProgressWidgetView: View {
    var entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.placeholder || entry.items.isEmpty {
            PlaceholderView(kind: "追番进度", icon: "play.circle")
        } else if family == .systemSmall && entry.items.count >= 1 {
            WidgetItemCard(item: entry.items[0], imageData: entry.imageData[entry.items[0].id])
        } else {
            WidgetItemListView(
                items: entry.items,
                imageData: entry.imageData,
                maxItems: family == .systemMedium ? 2 : 5
            )
        }
    }
}
