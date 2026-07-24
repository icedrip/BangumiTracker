import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailingLabel: String? = nil
    var onTrailingTap: (() -> Void)?
    /// When set, the trailing label pushes this route instead of calling
    /// `onTrailingTap` (avoids nesting a Button inside a NavigationLink).
    var trailingRoute: AppRoute? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .default))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let trailingLabel {
                if let trailingRoute {
                    NavigationLink(value: trailingRoute) {
                        Text(trailingLabel)
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onTrailingTap?()
                    } label: {
                        Text(trailingLabel)
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
