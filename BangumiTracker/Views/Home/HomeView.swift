import SwiftUI

struct HomeView: View {
    @Environment(HomeViewModel.self) private var viewModel
    @Environment(AuthService.self) private var auth
    @Environment(\.tabSelection) private var tabSelection

    @State private var showLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LargeNavHeader(title: "首页")

                // 今日精选
                TodayPickHero(subject: viewModel.todayPick)
                    .padding(.top, 4)

                // 因为你在追《X》/ 标签巡游
                becauseYouWatchSection

                // 冷门佳作
                hiddenGemsSection

                // 时光胶囊
                timeCapsuleSection

                // 想看清单 (or a status-filtered view set from a Profile stat-card tap)
                wantToWatchHeader
                    .padding(.horizontal, .horizontalPadding)

                if viewModel.wantToWatchList.isEmpty {
                    if auth.isAuthenticated {
                        EmptyStateView(
                            icon: viewModel.collectionStatus == .wish ? "film.stack" : "tray",
                            title: wishListEmptyTitle,
                            description: wishListEmptyDescription,
                            actionLabel: viewModel.collectionStatus == .wish ? "去发现页看看" : "返回想看清单"
                        ) {
                            if viewModel.collectionStatus == .wish {
                                tabSelection.wrappedValue = 1
                            } else {
                                Task { await viewModel.setCollectionStatus(.wish) }
                            }
                        }
                    } else {
                        EmptyStateView(
                            icon: "person.crop.circle.badge.questionmark",
                            title: "登录后查看想看清单",
                            description: "登录 Bangumi 账号，即可同步你的想看清单",
                            actionLabel: "请登录查看"
                        ) {
                            showLogin = true
                        }
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.sortedWantToWatchList) { collection in
                            ListRow(
                                collection: collection,
                                addedAt: viewModel.wishCollectedAt(for: collection.subjectId),
                                onStartWatching: {
                                    Task { await viewModel.startWatching(collection) }
                                },
                                onSetStatus: { type in
                                    Task { await viewModel.setStatus(collection, to: type) }
                                },
                                onDelete: {
                                    Task { await viewModel.deleteCollection(collection) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, .horizontalPadding)
                }
            }
            .padding(.vertical, .tightSpacing)
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showLogin) {
            SettingsView()
        }
        .refreshable {
            await viewModel.loadAll()
        }
        // Bind to auth.isAuthenticated so logging in via the empty-state CTA
        // re-runs the loader without forcing the user to pull-to-refresh.
        // `loadOnAppear` only refreshes the recommendation rails once per
        // day — popping back from a detail view won't re-shuffle them.
        .task(id: auth.isAuthenticated) {
            await viewModel.loadOnAppear()
        }
        .errorToast(Bindable(viewModel).actionError)
        .prefetchImages(urls: viewModel.visibleImageURLs)
    }

    // MARK: - 想看清单 header

    /// Custom header so we can hang a Menu off the trailing edge — the standard
    /// SectionHeader only takes a tappable label, and the sort UX wants a popover
    /// list, not a cycle button.
    private var wantToWatchHeader: some View {
        @Bindable var vm = viewModel
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(wishListTitle)
                .font(.title2.weight(.bold))
            Spacer(minLength: 8)
            if viewModel.collectionStatus != .wish {
                Button {
                    Task { await viewModel.setCollectionStatus(.wish) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.semibold))
                        Text("想看清单")
                            .font(.subheadline)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Picker("排序", selection: $vm.sortOrder) {
                    ForEach(WantToWatchSort.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("排序: \(viewModel.sortOrder.displayName)")
                        .font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundColor(.blue)
            }
        }
    }

    private var wishListTitle: String {
        viewModel.collectionStatus == .wish
            ? "想看清单"
            : "我的\(viewModel.collectionStatus.displayName)作品"
    }

    private var wishListEmptyTitle: String {
        viewModel.collectionStatus == .wish
            ? "想看清单还是空的"
            : "还没有\(viewModel.collectionStatus.displayName)的作品"
    }

    private var wishListEmptyDescription: String {
        viewModel.collectionStatus == .wish
            ? "搜索作品或浏览上方推荐，发现感兴趣的加入想看吧"
            : "返回想看清单查看你的想看作品"
    }

    // MARK: - 因为你在追

    private var becauseYouWatchTitle: String {
        if let ref = viewModel.becauseYouWatch?.referenceTitle {
            return "因为你在追《\(ref)》"
        }
        if viewModel.becauseYouWatch != nil {
            return "标签巡游"
        }
        return "为你推荐"
    }

    private var becauseYouWatchSubtitle: String? {
        guard let result = viewModel.becauseYouWatch else { return nil }
        if result.referenceTitle != nil {
            return "同样有「\(result.referenceTag)」标签"
        }
        return "今天逛逛：\(result.referenceTag)"
    }

    private var becauseYouWatchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: becauseYouWatchTitle,
                subtitle: becauseYouWatchSubtitle,
                trailingLabel: "换一批"
            ) {
                Task { await viewModel.loadBecauseYouWatch() }
            }
            .padding(.horizontal, .horizontalPadding)

            carousel(
                subjects: viewModel.becauseYouWatch?.subjects ?? [],
                placeholderCount: 6
            )
        }
    }

    // MARK: - 冷门佳作

    private var hiddenGemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "宝藏佳作", subtitle: "7.5 分以上", trailingLabel: "换一批") {
                Task { await viewModel.loadHiddenGems() }
            }
            .padding(.horizontal, .horizontalPadding)

            carousel(subjects: viewModel.hiddenGems, placeholderCount: 6)
        }
    }

    // MARK: - 时光胶囊

    private var timeCapsuleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "时光胶囊",
                subtitle: viewModel.timeCapsule.map { "回到 \(String($0.year)) 年看看那年的好作品" },
                trailingLabel: "换一年"
            ) {
                Task { await viewModel.loadTimeCapsule() }
            }
            .padding(.horizontal, .horizontalPadding)

            carousel(subjects: viewModel.timeCapsule?.subjects ?? [], placeholderCount: 6)
        }
    }

    // MARK: - Helpers

    private func carousel(subjects: [Subject], placeholderCount: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if subjects.isEmpty {
                    ForEach(0..<placeholderCount, id: \.self) { _ in
                        SkeletonCard()
                    }
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
