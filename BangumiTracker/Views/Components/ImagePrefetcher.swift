import SwiftUI
import Kingfisher

/// Prefetches Kingfisher images for a list of URL strings when the view appears.
/// Improves perceived scroll performance by starting image downloads before the
/// user scrolls to the corresponding SubjectCard.
struct ImagePrefetcherModifier: ViewModifier {
    let urls: [String]

    func body(content: Content) -> some View {
        content
            .task { prefetch() }
    }

    private func prefetch() {
        let valid = urls.compactMap { URL(string: $0.httpsScheme) }
        guard !valid.isEmpty else { return }
        ImagePrefetcher(urls: valid).start()
    }
}

extension View {
    func prefetchImages(urls: [String]) -> some View {
        modifier(ImagePrefetcherModifier(urls: urls))
    }
}
