import SwiftUI

// MARK: - Skeleton

struct DetailSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray5))
                .frame(height: 320)
                .shimmer()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 32)
                            .shimmer()
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 140, height: 16)
                            .shimmer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 4)
                            .shimmer()
                    }
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 40)
                        .shimmer()
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

                SkeletonSectionCard {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 16)
                        .shimmer()
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 40), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(0..<14, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(height: 36)
                                .shimmer()
                        }
                    }
                }

                SkeletonSectionCard {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 16)
                        .shimmer()
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 60)
                        .shimmer()
                }

                SkeletonSectionCard {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 16)
                        .shimmer()
                    HStack(spacing: 8) {
                        Capsule().fill(Color(.systemGray5)).frame(width: 50, height: 28).shimmer()
                        Capsule().fill(Color(.systemGray5)).frame(width: 60, height: 28).shimmer()
                        Capsule().fill(Color(.systemGray5)).frame(width: 45, height: 28).shimmer()
                    }
                }

                SkeletonSectionCard {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 16)
                        .shimmer()
                    HStack(spacing: 12) {
                        Circle().fill(Color(.systemGray5)).frame(width: 36, height: 36).shimmer()
                        HStack(spacing: 4) {
                            ForEach(0..<10, id: \.self) { _ in
                                Circle().fill(Color(.systemGray5)).frame(width: 20, height: 20).shimmer()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

struct SkeletonSectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
