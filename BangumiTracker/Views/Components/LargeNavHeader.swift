import SwiftUI

/// Prototype-style large title bar where the title and trailing action share
/// a baseline. Replaces the system `.navigationBarTitleDisplayMode(.large)`
/// when its title-on-its-own-row layout doesn't match the design.
struct LargeNavHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, .horizontalPadding)
        .frame(minHeight: 44)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

extension LargeNavHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// 44×44 hit target wrapper for icon buttons in `LargeNavHeader`.
struct NavBarIconButton<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        label()
            .font(.title2.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
