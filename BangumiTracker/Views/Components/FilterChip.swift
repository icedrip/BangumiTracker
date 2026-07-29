import SwiftUI

struct FilterChip: View {
    let label: String
    var isActive: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isActive ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.blue : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.blue : Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DiscoverChip: View {
    let label: String
    var isActive: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(isActive ? .white : .primary)
                .padding(.horizontal, .horizontalPadding)
                .padding(.vertical, .tightSpacing)
                .background(isActive ? Color.blue : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.blue : Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
