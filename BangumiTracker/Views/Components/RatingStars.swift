import SwiftUI

/// Value-based star rating control. The display (`rating`) is read-only here —
/// the owning view is the single source of truth, and `onRate` is the only
/// write path. This avoids a `@Binding` that lags the ViewModel's `userRating`
/// (the previous design kept a `@State rating = 0` synced via `onChange`,
/// which flashed empty stars on first paint and let the local value drift from
/// the server value on a failed save).
struct RatingStars: View {
    let rating: Int
    let maxRating: Int
    var onRate: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { index in
                Button {
                    onRate?(index)
                } label: {
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(index <= rating ? .orange : Color(.systemGray4))
                        .frame(width: 28, height: 28)
                        .background(index <= rating ? Color.orange.opacity(0.15) : Color(.systemGray6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(index) 星")
                .accessibilityAddTraits(.isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("评分 \(rating) / \(maxRating)")
    }
}
