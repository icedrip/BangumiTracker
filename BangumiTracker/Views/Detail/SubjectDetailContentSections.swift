import SwiftUI

// MARK: - Tags

struct TagsSection: View {
    let tags: [String]

    var body: some View {
        DetailSectionCard {
            Text("标签")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
            // FlowLayout packs each chip at its natural width and wraps to the
            // next row when the next chip won't fit — unlike LazyVGrid's
            // adaptive(minimum:) columns, which force equal-width cells and
            // leave short tags over-padded with gaps on the right.
            FlowLayout(spacing: 8) {
                ForEach(deduped, id: \.self) { tag in
                    TagChip(label: tag)
                }
            }
        }
    }

    /// Bangumi's `meta_tags` occasionally returns duplicates (e.g. subject
    /// 9912 "日常" lists every tag twice). Dedupe preserving first-seen
    /// order so `ForEach` ids stay unique and no duplicate chips render.
    private var deduped: [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}

struct MyTagsSection: View {
    let tags: [String]
    let onAddTag: () -> Void

    var body: some View {
        DetailSectionCard {
            Text("我的标签")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(label: tag)
                }
                TagChip(label: "+ 添加标签", isAddButton: true, onTap: onAddTag)
            }
        }
    }
}

// MARK: - Review

struct ReviewSection: View {
    let isFiveStar: Bool
    /// Display-scale rating (1-5 in 5-star mode, 1-10 otherwise), already
    /// converted from the ViewModel's 10-scale `userRating`. Drives both the
    /// star highlight and the score ring so the two can't disagree.
    let rating: Int
    /// The current comment text — the same value the editor drafts from, so the
    /// bubble reflects an optimistic save instantly without waiting on a refetch.
    let comment: String
    let onRate: (Int) -> Void
    let onEditComment: () -> Void

    var body: some View {
        DetailSectionCard(spacing: 10) {
            Text("我的评价")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // `rating` is already in the display scale, so the ring reads it
                // directly. The previous `isFiveStar ? (rating + 1) / 2 : rating`
                // re-converted an already-converted value and systematically
                // under-reported in 5-star mode (3★ showed 2/5, 5★ showed 3/5).
                ScoreCircle(
                    displayRating: rating,
                    maxValue: isFiveStar ? 5 : 10
                )
                RatingStars(rating: rating, maxRating: isFiveStar ? 5 : 10, onRate: onRate)
            }

            if !comment.isEmpty {
                CommentBubble(comment: comment)
            }

            Button(action: onEditComment) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                    Text("编辑评价")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct ScoreCircle: View {
    let displayRating: Int
    let maxValue: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(CGFloat(displayRating) / CGFloat(maxValue), 0))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(displayRating)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
        }
        .frame(width: 36, height: 36)
        .animation(.easeInOut(duration: 0.2), value: displayRating)
    }
}

struct CommentBubble: View {
    let comment: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.6))
                .frame(width: 3)
                .padding(.trailing, 10)
            Text("\"\(comment)\"")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .italic()
                .lineSpacing(2)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
