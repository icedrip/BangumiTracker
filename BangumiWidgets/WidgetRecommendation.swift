import WidgetKit
import SwiftUI

struct TodayAiringWidget: Widget {
    let kind: String = "TodayAiring"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayAiringProvider()) { entry in
            TodayAiringWidgetView(entry: entry)
        }
        .configurationDisplayName("今日放送")
        .description("查看今天在播的作品")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TodayAiringProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), items: [], imageData: [:], placeholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let items = WidgetProvider.readItems(from: AppGroupKeys.recommendData)
        if items.isEmpty {
            completion(WidgetEntry(date: Date(), items: [], imageData: [:], placeholder: true))
        } else {
            let images = WidgetProvider.loadImages(for: items)
            completion(WidgetEntry(date: Date(), items: items, imageData: images, placeholder: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let timeline = WidgetProvider.timeline(for: AppGroupKeys.recommendData)
        completion(timeline)
    }
}

struct TodayAiringWidgetView: View {
    var entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.placeholder || entry.items.isEmpty {
            PlaceholderView(kind: "今日放送", icon: "tv")
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
