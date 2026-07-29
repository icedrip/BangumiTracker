import SwiftUI

struct TrendingHero: View {
    let subjects: [Subject]

    var body: some View {
        if subjects.isEmpty {
            placeholder
        } else {
            TabView {
                ForEach(subjects) { subject in
                    NavigationLink(value: AppRoute.subjectDetail(id: subject.id)) {
                        TrendingHeroCard(subject: subject)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, .horizontalPadding)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 260)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemGray5))
            .frame(height: 240)
            .padding(.horizontal, .horizontalPadding)
    }
}

private struct TrendingHeroCard: View {
    let subject: Subject

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                CachedAsyncImage(
                    urlString: subject.imageURL,
                    fallbackText: subject.displayName,
                    targetSize: CGSize(width: geo.size.width, height: geo.size.height)
                )
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
                Text("近期注目")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)

                Text(subject.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)

                HStack(spacing: 10) {
                    if let rating = subject.rating, rating.score > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating.score))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: Capsule())
                    }
                    if let date = subject.date, !date.isEmpty {
                        Text(date)
                            .font(.caption.weight(.medium))
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
    }
}
