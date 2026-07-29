import SwiftUI

struct SynopsisSection: View {
    let summary: String
    @State private var isExpanded = false

    /// Long enough that 4 collapsed lines would truncate it — short synopses
    /// don't get a toggle (nothing to expand). Character count is a width-
    /// independent heuristic; precise truncation detection isn't worth the
    /// GeometryReader dance for a release note.
    private var canExpand: Bool { summary.count > 100 }
    private let collapsedLineLimit = 4

    var body: some View {
        DetailSectionCard {
            Text("简介")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Text(summary)
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundColor(.secondary)
                // Only clamp when there's a toggle to reveal the rest — a short
                // but heavily-newlined summary (count ≤ 100, >4 lines) would
                // otherwise truncate with no way to expand.
                .lineLimit(canExpand && !isExpanded ? collapsedLineLimit : nil)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
            if canExpand {
                Button(isExpanded ? "收起" : "展开全文") {
                    isExpanded.toggle()
                }
                .font(.callout.weight(.medium))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
