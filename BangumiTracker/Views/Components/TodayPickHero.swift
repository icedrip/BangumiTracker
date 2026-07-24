import SwiftUI

struct TodayPickHero: View {
    let subject: Subject?

    var body: some View {
        if let subject {
            NavigationLink(value: AppRoute.subjectDetail(id: subject.id)) {
                TodayPickCard(subject: subject)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemGray5))
            .frame(height: 240)
            .padding(.horizontal, 16)
    }
}

private struct TodayPickCard: View {
    let subject: Subject

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isImageLoaded = false

    /// Image block is rendered taller than the card so it can pan vertically
    /// and reveal the top/bottom of a portrait cover that `.aspectRatio(.fill)`
    /// would otherwise crop. Safe pan range = half the extra height.
    private let overscan: CGFloat = 1.4
    private let panDuration: Double = 8

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let blockHeight = geo.size.height * overscan
                let panRange = (blockHeight - geo.size.height) / 2

                CachedAsyncImage(
                    urlString: subject.imageURL,
                    fallbackText: subject.displayName,
                    targetSize: CGSize(width: geo.size.width, height: blockHeight),
                    onLoad: { ok in if ok { isImageLoaded = true } }
                )
                    .frame(width: geo.size.width, height: blockHeight)
                    .panningOffset(panRange: panRange, enabled: isImageLoaded && !reduceMotion, duration: panDuration)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.0),
                    .black.opacity(0.35),
                    .black.opacity(0.7),
                    .black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    Text("今日精选")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)

                Text(subject.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)

                HStack(spacing: 10) {
                    if let rating = subject.rating, rating.score > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating.score))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: Capsule())
                    }
                    if let date = subject.date, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .onChange(of: subject.id) { _, _ in isImageLoaded = false }
    }
}

/// Slow vertical pan for a cover-image block rendered taller than its clipped
/// frame, revealing the top/bottom of a portrait cover that
/// `.aspectRatio(.fill)` would otherwise crop.
///
/// `PhaseAnimator` drives the cycle and pauses when the view is offscreen
/// (unlike `withAnimation(.repeatForever)` started in `onAppear`, which keeps
/// the runloop spinning even when the card is covered by a pushed view, in a
/// background tab, or scrolled away). The animator is only attached once
/// `enabled` is true, so the pan waits for the image to load and stops
/// entirely under Reduce Motion — toggling either at runtime rebuilds this
/// branch and attaches/detaches the animator reactively.
private struct PanningOffset: ViewModifier {
    let panRange: CGFloat
    let enabled: Bool
    let duration: Double

    func body(content: Content) -> some View {
        if enabled {
            // 3-phase cycle starts at 0 (centered) so attaching the animator
            // when the image finishes loading doesn't jump the offset.
            content.phaseAnimator([CGFloat(0), panRange, -panRange]) { view, offset in
                view.offset(y: offset)
            } animation: { _ in
                .easeInOut(duration: duration)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Slow vertical pan between `-panRange` and `+panRange`. No-op unless `enabled`.
    func panningOffset(panRange: CGFloat, enabled: Bool, duration: Double) -> some View {
        modifier(PanningOffset(panRange: panRange, enabled: enabled, duration: duration))
    }
}
