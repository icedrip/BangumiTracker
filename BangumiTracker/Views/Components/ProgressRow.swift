import SwiftUI

struct ProgressRow: View {
    let collection: UserSubjectCollection
    let watchedCount: Int
    let totalCount: Int
    /// "每周X更新" label from the calendar cross-reference, nil if unknown.
    var airWeekdayText: String? = nil
    var onPlusOne: (() -> Void)?

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(watchedCount) / Double(totalCount)
    }

    var isComplete: Bool {
        watchedCount >= totalCount && totalCount > 0
    }

    var body: some View {
        NavigationLink(value: AppRoute.subjectDetail(id: collection.subjectId)) {
            HStack(spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(collection.subject?.displayName ?? "作品 #\(collection.subjectId)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let rating = collection.subject?.rating, rating.score > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", rating.score))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                    }

                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    ProgressView(value: progress)
                        .tint(isComplete ? .green : .blue)
                        .padding(.top, 8)

                    Text(progressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                Button {
                    guard !isComplete else { return }
                    Haptics.light()
                    onPlusOne?()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(isComplete ? Color.green : Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isComplete ? "已看完" : "进度+1")
                .accessibilityAddTraits(.isButton)
                .disabled(isComplete)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        CachedAsyncImage(
            urlString: collection.subject?.imageURL,
            fallbackText: collection.subject?.displayName ?? "",
            targetSize: CGSize(width: 56, height: 80)
        )
        .frame(width: 56, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitleText: String {
        guard let subject = collection.subject else { return "" }
        let typeName = SubjectType(rawValue: subject.type)?.displayName ?? ""
        // "TV动画 / 每周二更新" when the air weekday is known, else just the type.
        if let airWeekdayText {
            return "\(typeName) / \(airWeekdayText)"
        }
        return typeName
    }

    private var watchedVerb: String {
        guard let subject = collection.subject,
              let st = SubjectType(rawValue: subject.type) else { return "看" }
        return st.actionVerb
    }

    private var completionForm: String {
        guard let subject = collection.subject,
              let st = SubjectType(rawValue: subject.type) else { return "看完" }
        return st.completionForm
    }

    private var progressText: String {
        let verb = watchedVerb
        if isComplete {
            return "已\(verb) \(watchedCount)/\(totalCount) 集 · 全部\(completionForm)!"
        }
        return "已\(verb) \(watchedCount)/\(totalCount) 集"
    }
}
