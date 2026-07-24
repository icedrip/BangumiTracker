import SwiftUI
import WidgetKit

// MARK: - Placeholder

struct PlaceholderView: View {
    let kind: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundColor(.secondary)
            Text(kind).font(.caption).foregroundColor(.secondary)
            Text("暂无数据").font(.caption2).foregroundStyle(.tertiary)
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - List (medium / large)

struct WidgetItemListView: View {
    let items: [WidgetSubjectItem]
    let imageData: [Int: Data]
    let maxItems: Int

    var body: some View {
        let displayItems = Array(items.prefix(maxItems))
        VStack(alignment: .leading, spacing: 10) {
            ForEach(displayItems) { item in
                Link(destination: URL(string: "bangumitracker://subject/\(item.id)")!) {
                    WidgetItemRow(item: item, imageData: imageData[item.id])
                }
            }
        }
        .padding(16)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Row

struct WidgetItemRow: View {
    let item: WidgetSubjectItem
    let imageData: Data?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .overlay(Image(systemName: subjectTypeIcon).font(.caption2).foregroundColor(.secondary))
                }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 54)
            .cornerRadius(4)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.caption).fontWeight(.medium).lineLimit(2)
                if let p = item.progress { Text(p).font(.caption2).foregroundColor(.secondary) }
                if let d = item.subjectDate { Text(d).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
    }

    private var subjectTypeIcon: String {
        switch item.type {
        case 2: "film"
        case 1: "book"
        case 3: "music.note"
        case 4: "gamecontroller"
        case 6: "video"
        default: "questionmark"
        }
    }
}

// MARK: - Small Card

struct WidgetItemCard: View {
    let item: WidgetSubjectItem
    let imageData: Data?

    var body: some View {
        Link(destination: URL(string: "bangumitracker://subject/\(item.id)")!) {
            ZStack(alignment: .bottomLeading) {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .overlay(Image(systemName: "film").font(.title2).foregroundColor(.secondary))
                }
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.55), location: 0.4),
                        .init(color: .black.opacity(0.85), location: 1.0),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .frame(height: 80)
                Text(item.title)
                    .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .padding([.horizontal, .bottom], 10)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}
