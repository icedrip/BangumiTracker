import SwiftUI

struct TagChip: View {
    let label: String
    var isAddButton: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isAddButton ? .blue : .primary)
                // Single-line so FlowLayout wraps chips, not their text. A chip
                // wider than the row is then truncated with … by FlowLayout's
                // oversized-clamp instead of growing taller and breaking the
                // uniform row height.
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}
