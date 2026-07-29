import SwiftUI

struct ListRow: View {
    let collection: UserSubjectCollection
    /// Local "added to wish" timestamp (PRD wants 添加于, not Bangumi's
    /// unreliable `updated_at`). Nil for non-wish or items without a local record.
    var addedAt: Date? = nil
    var onStartWatching: (() -> Void)?
    var onSetStatus: ((CollectionType) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var startActionLabel: String {
        guard let subject = collection.subject,
              let st = SubjectType(rawValue: subject.type) else { return "标记观看" }
        return st.startActionLabel
    }

    var body: some View {
        NavigationLink(value: AppRoute.subjectDetail(id: collection.subjectId)) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.subject?.displayName ?? "作品 #\(collection.subjectId)")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Text(metaText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let rating = collection.subject?.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text(String(format: "%.1f", rating.score))
                        }
                        .foregroundColor(.orange)
                        .font(.subheadline.weight(.semibold))
                    }

                    Text(timestampText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Haptics.success()
                    onStartWatching?()
                } label: {
                    Text(startActionLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onStartWatching {
                Button {
                    onStartWatching()
                } label: {
                    Label(startActionLabel, systemImage: "play.fill")
                }
            }
            if let onSetStatus {
                Button {
                    onSetStatus(.onHold)
                } label: {
                    Label("搁置", systemImage: "pause.circle")
                }
                Button(role: .destructive) {
                    onSetStatus(.dropped)
                } label: {
                    Label("抛弃", systemImage: "xmark.circle")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private var thumbnail: some View {
        CachedAsyncImage(
            urlString: collection.subject?.imageURL,
            fallbackText: collection.subject?.displayName ?? "",
            targetSize: CGSize(width: 64, height: 91)
        )
        .frame(width: 64, height: 91)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metaText: String {
        guard let subject = collection.subject else { return "" }
        let typeName = SubjectType(rawValue: subject.type)?.displayName ?? ""
        let year = subject.date?.prefix(4) ?? ""
        return "\(year) / \(typeName)"
    }

    private var timestampText: String {
        if let addedAt {
            let cal = Calendar.current
            return "添加于 \(cal.component(.month, from: addedAt))月\(cal.component(.day, from: addedAt))日"
        }
        if let updated = collection.updatedAt {
            return "更新于 \(updated.prefix(10))"
        }
        return ""
    }
}
