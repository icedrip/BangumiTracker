import SwiftUI

struct EpisodeChip: View {
    let episodeNumber: Int
    let isWatched: Bool
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack {
                Text("第\(episodeNumber)集")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if isWatched {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundColor(isWatched ? .white : .primary)
            .background(isWatched ? Color.green : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isWatched ? Color.green : Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
