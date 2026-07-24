import SwiftUI

/// Arranges subviews left-to-right, wrapping to the next row when the next
/// subview won't fit in the remaining width — like text wrapping. Each
/// subview keeps its natural size, so this is the right layout for variable-
/// width capsules (tag/genre chips) that should flow onto multiple rows at a
/// uniform height instead of being squeezed into one `HStack` and wrapping
/// their own text.
///
/// Give each child a single-line label (e.g. `.lineLimit(1)`) so a chip's
/// height doesn't grow with its text — the flow then wraps *chips*, not text.
/// A chip wider than the available row width is proposed the remaining width
/// so its text truncates with `…` rather than overflowing and being clipped
/// mid-character by an outer clip shape.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    struct Cache {
        /// Natural size of each subview, measured once with `.unspecified`
        /// (proposal-independent, so stable across layout passes).
        var sizes: [CGSize] = []
        /// The arrangement last computed, plus the width it was computed
        /// against — reused by `placeSubviews` when the allocated width
        /// matches, recomputed otherwise.
        var rows: [Row] = []
        var arrangedWidth: CGFloat = .infinity
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        cache.rows = arrange(sizes: cache.sizes, maxWidth: maxWidth)
        cache.arrangedWidth = maxWidth
        return totalSize(rows: cache.rows, maxWidth: maxWidth)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // Recompute against bounds.width — the width the parent actually
        // allocated, which can differ from the proposal used in sizeThatFits.
        if bounds.width != cache.arrangedWidth {
            cache.rows = arrange(sizes: cache.sizes, maxWidth: bounds.width)
            cache.arrangedWidth = bounds.width
        }
        var y = bounds.minY
        for row in cache.rows {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                // Clamp a chip wider than the remaining row width to that
                // width so it truncates with … instead of extending past
                // bounds.maxX (where an outer clipShape would cut it
                // mid-character with no indicator).
                let remaining = bounds.maxX - x
                let placed: CGSize
                if remaining.isFinite && size.width > remaining {
                    placed = CGSize(width: max(0, remaining), height: size.height)
                } else {
                    placed = size
                }
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(placed)
                )
                x += placed.width + spacing
            }
            y += row.height + spacing
        }
    }

    // MARK: - Private

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Groups subview indices into rows that each fit within `maxWidth`.
    private func arrange(sizes: [CGSize], maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            let projectedWidth = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width
            // Wrap to a new row only if this view doesn't fit AND the current
            // row already has a view — never leave an empty row above a lone
            // oversized chip; it truncates to the row width at placement time.
            if projectedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = projectedWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private func totalSize(rows: [Row], maxWidth: CGFloat) -> CGSize {
        guard !rows.isEmpty else { return .zero }
        let contentWidth = rows.map(\.width).max() ?? 0
        let width = maxWidth.isFinite ? min(contentWidth, maxWidth) : contentWidth
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(rows.count - 1)
        return CGSize(width: width, height: height)
    }
}
