import SwiftUI
import Kingfisher

struct CachedAsyncImage: View {
    let urlString: String?
    var fallbackText: String = ""
    var targetSize: CGSize? = nil
    /// Fired once the load terminates (true on success, false on failure).
    /// Lets callers gate effects (e.g. starting a pan) on the image being ready.
    var onLoad: ((Bool) -> Void)? = nil

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let urlString, let url = URL(string: urlString.httpsScheme) {
            KFImage(url)
                .placeholder {
                    ZStack {
                        // Same fill as SkeletonCard / the failure fallback so
                        // loading→failure is just the spinner vanishing, not a
                        // color shift.
                        Color(.systemGray5)
                        ProgressView()
                    }
                }
                .setProcessor(processor)
                .cacheOriginalImage()
                .fade(duration: 0.15)
                .onFailureView { fallbackPlaceholder }
                .onSuccess { _ in onLoad?(true) }
                .onFailure { _ in onLoad?(false) }
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            fallbackPlaceholder
        }
    }

    /// Downsamples the image at decode time to ~the displayed frame size in
    /// physical pixels (targetSize points × displayScale). DownsamplingImageProcessor
    /// decodes straight to the target via CGImageSource (no full-source bitmap)
    /// and never upscales — if the source is smaller than the target it returns
    /// the source as-is and SwiftUI's `.fill` upscales at render (free, GPU-side).
    ///
    /// For SQUARE frames (avatars) with portrait/landscape sources, capping the
    /// *max* dimension would leave the *min* dimension short of the frame, and
    /// `.fill` would upscale the short side (1.4× soft). So square frames bump
    /// the max dimension by 1.5× — enough that a 2:3 portrait's short side
    /// covers the frame after `.fill` crops. Non-square frames (cards, hero)
    /// match their source aspect and skip the bump (it'd over-downsample for
    /// no coverage gain). Baking the scale into the size also changes the
    /// processor's cache identifier, forcing a fresh fetch at full resolution.
    private var processor: ImageProcessor {
        if let targetSize {
            let scale = displayScale == 0 ? 1 : displayScale
            let maxDim = max(targetSize.width, targetSize.height) * scale
            let isSquare = abs(targetSize.width - targetSize.height) < 1
            let coverFactor: CGFloat = isSquare ? 1.5 : 1.0
            let size = maxDim * coverFactor
            return DownsamplingImageProcessor(size: CGSize(width: size, height: size))
        }
        return DefaultImageProcessor.default
    }

    private var fallbackPlaceholder: some View {
        ZStack {
            Color(.systemGray5)
            if !fallbackText.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(fallbackText)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(4)
                }
            }
        }
    }
}
