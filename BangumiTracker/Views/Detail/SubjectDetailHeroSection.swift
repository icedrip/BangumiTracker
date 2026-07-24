import SwiftUI

// MARK: - Hero Section

struct HeroSection: View {
    let imageURL: String?
    let displayName: String
    let metaText: String
    let rating: SubjectRating?
    let onTap: () -> Void

    private static let coverHeight: CGFloat = 320

    /// Decode-time target size for the cover image. Width tracks the active
    /// window's screen width so Kingfisher's downsampler caches a tile sized
    /// for the device, not a fixed 440pt thumbnail. Recomputed each render so
    /// rotation / split view picks up the new width.
    private var targetSize: CGSize {
        let width = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.screen.bounds.width }
            .first ?? 440
        return CGSize(width: width, height: Self.coverHeight)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(
                urlString: imageURL,
                targetSize: targetSize
            )
                .frame(maxWidth: .infinity)
                .frame(height: Self.coverHeight, alignment: .center)
                .clipped()
                .overlay(Color.black.opacity(0.3))

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 24, weight: .bold))
                Text(metaText)
                    .font(.system(size: 14))
                    .opacity(0.9)
                if let rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text(String(format: "%.1f", rating.score))
                        if rating.total > 0 {
                            Text("· \(rating.total) 人评分")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.orange)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
