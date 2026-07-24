import SwiftUI

struct SkeletonCard: View {
    /// Match `SubjectCard.flexibleWidth` so the BrowseView skeleton fills its
    /// grid cell with the same 0.7 aspect ratio instead of leaving the same
    /// dead middle strip the real card was fixed for.
    var flexibleWidth: Bool = false

    private static let cardWidth: CGFloat = 140
    private static let cardHeight: CGFloat = 200

    var body: some View {
        if flexibleWidth {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .aspectRatio(Self.cardWidth / Self.cardHeight, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .shimmer()
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .shimmer()
        }
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        .white.opacity(0.4),
                        .clear
                    ]),
                    startPoint: .init(x: phase, y: 0),
                    endPoint: .init(x: phase + 1, y: 0)
                )
                .mask(content)
            )
            .onAppear { startShimmerIfNeeded() }
            .onChange(of: reduceMotion) { _, isOn in
                // onAppear only fires once; mirror its guard against a runtime
                // Reduce Motion toggle so an already-running shimmer freezes and
                // a later disable resumes it.
                if isOn {
                    phase = -1
                } else {
                    startShimmerIfNeeded()
                }
            }
    }

    private func startShimmerIfNeeded() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
