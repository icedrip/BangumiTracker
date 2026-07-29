import SwiftUI

struct SubjectCard: View {
    let subject: Subject
    var collectionType: CollectionType? = nil
    /// `true` makes the card fill its container width (height derived from the
    /// poster aspect ratio) for a filling grid cell - `BrowseView`'s 2-column
    /// ranking grid. Default `false` keeps the fixed 140×200 size used by the
    /// horizontal rails (Explore/Home/Watching today-updates). Declared before
    /// `onAdd` so call sites can still use `onAdd`'s trailing closure.
    var flexibleWidth: Bool = false
    var onAdd: (() -> Void)?

    @Environment(AuthService.self) private var auth

    /// Optimistic state for the quick-add tap. Seeded from `collectionType`
    /// so the status badge reflects the latest known status from the parent.
    @State private var optimisticType: CollectionType?

    private static let cardWidth: CGFloat = 140
    private static let cardHeight: CGFloat = 200

    var body: some View {
        NavigationLink(value: AppRoute.subjectDetail(id: subject.id)) {
            Group {
                if flexibleWidth {
                    fillCellCard
                } else {
                    fixedRailCard
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .onChange(of: collectionType) { _, newValue in
            optimisticType = newValue
        }
    }

    /// Fixed 140×200 card for horizontal rails. The image gets an explicit frame
    /// at its native display size (also the downsampling `targetSize`).
    private var fixedRailCard: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(
                urlString: subject.imageURL,
                fallbackText: subject.displayName,
                targetSize: CGSize(width: Self.cardWidth, height: Self.cardHeight)
            )
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .clipped()

            bottomOverlay
                .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .bottomLeading)

            statusButton
                .padding(8)
                .accessibilityLabel(subject.nsfw ? "\(subject.displayName)，18+内容" : subject.displayName)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    /// Width-filling card for grid cells. A `Color.clear.aspectRatio` box derives
    /// height from the cell width so the poster keeps the same 0.7 crop as the
    /// rail card while filling its column - same technique as `WatchingGridCard`.
    /// Without this, `.flexible()` columns hand the card a ~174pt cell but the
    /// old fixed 140pt frame left a ~46pt dead strip down the middle of each row.
    private var fillCellCard: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(Self.cardWidth / Self.cardHeight, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(
                        urlString: subject.imageURL,
                        fallbackText: subject.displayName,
                        // Downsampling cap slightly above the largest expected
                        // cell width (~174pt × displayScale) so bigger grid cards
                        // don't render softer than the 140pt rail card.
                        targetSize: CGSize(width: 180, height: 260)
                    )
                )
                .overlay(alignment: .bottomLeading) { bottomOverlay }
                .clipped()

            statusButton
                .padding(8)
        }
        .frame(maxWidth: .infinity)
    }

    private var subjectDisplayType: SubjectType? {
        SubjectType(rawValue: subject.type)
    }

    private var displayedType: CollectionType? {
        optimisticType ?? collectionType
    }


    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)

            if let rating = subject.rating, rating.score > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                    Text(String(format: "%.1f", rating.score))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundColor(.orange)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 10, bottom: 10, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var statusButton: some View {
        Group {
            // The quick-add button and the collected-status capsule are both
            // collection features — hide both when unauthenticated. The card
            // stays a NavigationLink to detail, where LoginPromptCard explains
            // the login gate; surfacing a non-functional "+ 想看" on every
            // browse card would just noise up the grid.
            if auth.isAuthenticated {
                if displayedType == nil {
                    // Uncollected: a [+ 想看] quick-add capsule (PRD 5.2.1). Tapping
                    // adds as 想看 without navigating — the parent NavigationLink is
                    // blocked by allowsHitTesting below.
                    Button {
                        Haptics.success()
                        optimisticType = .wish
                        onAdd?()
                    } label: {
                        Text("+ \(CollectionType.wish.displayName(for: subjectDisplayType))")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                } else {
                    // Collected: a status label capsule colored via
                    // `CollectionType.displayColor` (shared with ProfileView stat
                    // cards). Non-interactive — tap falls through to detail.
                    Text(statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(statusColor.opacity(0.92)))
                }
            }
        }
        // Only swallow the parent NavigationLink tap when the quick-add button
        // is actionable (logged-in + uncollected). Otherwise let the tap fall
        // through to nav.
        .allowsHitTesting(auth.isAuthenticated && displayedType == nil)
    }

    private var statusLabel: String {
        // Uses `CollectionType.collectedDisplayName` for the "已想看" / "已想玩"
        // pattern on wish badges, and regular displayName for other statuses.
        // Only read when displayedType != nil (the collected branch), so the
        // force-unwrap is safe.
        displayedType!.collectedDisplayName(for: subjectDisplayType)
    }

    private var statusColor: Color {
        // Canonical mapping lives on `CollectionType.displayColor`; the `?? .orange`
        // is unreachable (uncollected renders a Button, not this Text capsule).
        displayedType?.displayColor ?? .orange
    }
}

struct SubjectCardPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 140, height: 200)
    }
}
