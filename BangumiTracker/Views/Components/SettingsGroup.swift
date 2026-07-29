import SwiftUI

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

struct SettingsRow: View {
    let label: String
    var value: String? = nil
    var showChevron: Bool = true
    var showDivider: Bool = true
    var onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onTap?()
            } label: {
                HStack {
                    Text(label)
                        .font(.body)
                        .foregroundColor(.primary)
                    Spacer()
                    if let value {
                        Text(value)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    if showChevron {
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .foregroundColor(Color(.systemGray4))
                    }
                }
                .padding(.horizontal, .horizontalPadding)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if showDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}
