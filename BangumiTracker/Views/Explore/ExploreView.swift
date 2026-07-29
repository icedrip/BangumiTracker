import SwiftUI

struct ExploreView: View {
    @Environment(ExploreViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LargeNavHeader(title: "发现")

                // Fake search bar
                NavigationLink(value: AppRoute.search) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("搜索作品、声优、导演...")
                            .font(.body)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, .horizontalPadding)

                // 按季度浏览
                Text("按季度浏览")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, .horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.seasonOptions, id: \.self) { season in
                            NavigationLink(value: seasonRoute(season)) {
                                chipLabel(season)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, .horizontalPadding)
                }

                // 按类型浏览
                Text("按类型浏览")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, .horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SubjectType.allCases, id: \.rawValue) { type in
                            NavigationLink(value: AppRoute.browse(BrowseConfig(
                                title: type.displayName,
                                type: type.rawValue,
                                year: nil,
                                month: nil,
                                sort: "rank"
                            ))) {
                                chipLabel(type.displayName, larger: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, .horizontalPadding)
                }

                // Calendar entry
                NavigationLink(value: AppRoute.calendar) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开播日历")
                                .font(.body.weight(.semibold))
                            Text("查看本周放送时间表")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, .horizontalPadding)

                if let msg = viewModel.errorMessage, viewModel.rankings.isEmpty && viewModel.popularSubjects.isEmpty {
                    // Total load failure — surface a retry rather than leaving
                    // both carousels stuck on skeletons.
                    ErrorRetryView(message: msg) {
                        Task { await viewModel.loadAll() }
                    }
                    .padding(.top, 24)
                } else {
                    // 排行榜
                    SectionHeader(
                        title: "排行榜",
                        trailingLabel: "全部",
                        trailingRoute: .browse(BrowseConfig(title: "排行榜", type: nil, year: nil, month: nil, sort: "rank"))
                    )
                    .padding(.horizontal, .horizontalPadding)

                    carousel(subjects: viewModel.rankings, placeholderCount: 5)

                    // 热门高分
                    SectionHeader(
                        title: "热门高分",
                        trailingLabel: "全部",
                        trailingRoute: .browse(BrowseConfig(title: "热门高分", type: nil, year: nil, month: nil, sort: "heat"))
                    )
                    .padding(.horizontal, .horizontalPadding)

                    carousel(subjects: viewModel.popularSubjects, placeholderCount: 5)
                }
            }
            .padding(.vertical, .tightSpacing)
        }
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadAll()
        }
        .task {
            await viewModel.loadAll()
        }
        .errorToast(Bindable(viewModel).actionError)
        .prefetchImages(urls: viewModel.visibleImageURLs)
    }

    // MARK: - Helpers

    private func seasonRoute(_ season: String) -> AppRoute {
        if let parsed = viewModel.parsedSeason(season) {
            return .browse(BrowseConfig(title: season, type: nil, year: parsed.year, month: parsed.month, sort: "rank"))
        }
        // "全部" — no season filter.
        return .browse(BrowseConfig(title: season, type: nil, year: nil, month: nil, sort: "rank"))
    }

    private func chipLabel(_ text: String, larger: Bool = false) -> some View {
        Text(text)
            .font(.system(size: larger ? 14 : 13, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, larger ? 16 : 12)
            .padding(.vertical, larger ? 8 : 6)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color(.separator), lineWidth: 1)
            )
    }

    private func carousel(subjects: [Subject], placeholderCount: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if subjects.isEmpty {
                    ForEach(0..<placeholderCount, id: \.self) { _ in SkeletonCard() }
                } else {
                    ForEach(subjects) { subject in
                        SubjectCard(
                            subject: subject,
                            collectionType: viewModel.collectionType(for: subject.id)
                        ) {
                            Task { await viewModel.addToWishlist(subject) }
                        }
                    }
                }
            }
            .padding(.horizontal, .horizontalPadding)
        }
    }
}
