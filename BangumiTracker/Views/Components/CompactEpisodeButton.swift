import SwiftUI

struct CompactEpisodeButton: View {
    let episodeNumber: Int
    let isWatched: Bool
    var subjectType: SubjectType? = nil
    var onTap: (() -> Void)?

    private var watchedVerb: String {
        subjectType?.actionVerb ?? "看"
    }

    /// The unit label for this subject type (集 / 曲 / 话). Falls back to "集"
    /// for unknown types since anime is the dominant use case.
    private var unitLabel: String {
        guard let st = subjectType else { return "集" }
        switch st {
        case .music: return "曲"
        case .book: return "话"
        default: return "集"
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text("\(episodeNumber)")
                .font(.system(size: 14, weight: isWatched ? .bold : .medium))
                .foregroundColor(isWatched ? .white : .primary)
                // 44pt minimum hit target (HIG). Width is capped by the 7-column
                // grid cell (~42pt on an iPhone), but the height is no longer
                // under the 36pt minimum that made taps finicky.
                .frame(minWidth: 44, minHeight: 44)
                .background(isWatched ? Color.green : Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isWatched ? Color.green : Color(.separator), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(episodeNumber) \(unitLabel)")
        .accessibilityValue(isWatched ? "已\(watchedVerb)" : "未\(watchedVerb)")
        .accessibilityAddTraits(.isButton)
    }
}
