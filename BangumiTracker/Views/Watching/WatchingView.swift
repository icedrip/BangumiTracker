import SwiftUI

struct WatchingView: View {
    @Environment(WatchingViewModel.self) private var viewModel
    @Environment(AuthService.self) private var auth
    @Environment(\.tabSelection) private var tabSelection
    @AppStorage(PreferenceKey.defaultView) private var defaultView = DefaultListView.list.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LargeNavHeader(title: "在看")

                if auth.isAuthenticated {
                    // 今日更新
                    Text("今日更新")
                        .font(.title2.weight(.bold))
                        .padding(.horizontal, .horizontalPadding)

                    todaySection

                    // 全部在看
                    HStack {
                        Text("全部在看")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Picker("", selection: $defaultView) {
                            ForEach(DefaultListView.allCases, id: \.rawValue) { v in
                                Image(systemName: v.iconName).tag(v.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    .padding(.horizontal, .horizontalPadding)

                    watchingSection
                } else {
                    LoginPromptCard(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "登录后查看你在看的作品",
                        description: "登录 Bangumi 账号，同步你的观看进度与今日更新"
                    )
                    .padding(.horizontal, .horizontalPadding)
                }
            }
            .padding(.vertical, .tightSpacing)
        }
        .navigationTitle("在看")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadAll()
        }
        // Re-fire on auth flips so the watching list populates immediately
        // after login (and clears on logout) without a pull-to-refresh.
        .task(id: auth.isAuthenticated) {
            await viewModel.loadAll()
        }
        .errorToast(Bindable(viewModel).actionError)
        .prefetchImages(urls: viewModel.visibleImageURLs)
    }

    @ViewBuilder
    private var todaySection: some View {
        if viewModel.isLoading && viewModel.todayUpdates.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonCard() }
                }
                .padding(.horizontal, .horizontalPadding)
            }
        } else if viewModel.todayUpdates.isEmpty {
            Text("今日暂无更新")
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.todayUpdates) { subject in
                        SubjectCard(subject: subject) {
                            Task { await viewModel.addToWishlist(subject) }
                        }
                    }
                }
                .padding(.horizontal, .horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private var watchingSection: some View {
        if let msg = viewModel.errorMessage, viewModel.watchingList.isEmpty && viewModel.todayUpdates.isEmpty {
            ErrorRetryView(message: msg) {
                Task { await viewModel.loadAll() }
            }
        } else if viewModel.isLoading && viewModel.watchingList.isEmpty {
            // Cold start before the watching list arrives — avoid flashing the
            // empty state for a logged-in user with a brief skeleton.
            LazyVStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in WatchingSkeletonRow() }
            }
            .padding(.horizontal, .horizontalPadding)
        } else if viewModel.watchingList.isEmpty {
            EmptyStateView(
                icon: "play.square.stack",
                title: "还没有正在追的作品",
                description: "去发现页找到感兴趣的作品开始追番吧",
                actionLabel: "去发现页"
            ) {
                tabSelection.wrappedValue = 1
            }
        } else {
            if defaultView == DefaultListView.grid.rawValue {
                // Two equal-width flexible columns so each card fills its cell
                // (the old `adaptive(minimum: 140)` + fixed 140pt card left a
                // ~33pt dead strip on the right of every row).
                // `today` is hoisted out of the ForEach so currentWeekday()
                // (which builds a Calendar) runs once per render, not per card.
                let today = viewModel.todayWeekday
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.watchingList) { collection in
                        let progress = viewModel.progress(for: collection.subjectId)
                        WatchingGridCard(
                            collection: collection,
                            watchedCount: progress.watched,
                            totalCount: progress.total,
                            airWeekdayText: viewModel.weekdayLabel(for: collection.subjectId),
                            airsToday: viewModel.airsToday(collection.subjectId, today: today)
                        )
                            // Parity with the list row's context menu — grid users
                            // otherwise lose quick access to mark-all / 搁置 / 抛弃
                            // and must push into detail for every status change.
                            .contextMenu { collectionContextMenu(collection) }
                    }
                }
                .padding(.horizontal, .horizontalPadding)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.watchingList) { collection in
                        let progress = viewModel.progress(for: collection.subjectId)
                        ProgressRow(
                            collection: collection,
                            watchedCount: progress.watched,
                            totalCount: progress.total,
                            airWeekdayText: viewModel.weekdayLabel(for: collection.subjectId)
                        ) {
                            Task { await viewModel.markNextEpisode(collection) }
                        }
                        .contextMenu { collectionContextMenu(collection) }
                    }
                }
                .padding(.horizontal, .horizontalPadding)
            }
        }
    }
    /// Shared context menu for a watching item - used by both the grid card and
    /// the list row so mark-all / 搁置 / 抛弃 stay in sync.
    @ViewBuilder
    private func collectionContextMenu(_ collection: UserSubjectCollection) -> some View {
        let subjectType = collection.subject.flatMap { SubjectType(rawValue: $0.type) }
        let markAllLabel = "全部标记\(CollectionType.watched.displayName(for: subjectType))"
        Button {
            Task { await viewModel.markAllWatched(collection) }
        } label: {
            Label(markAllLabel, systemImage: "checkmark.circle")
        }
        Button {
            Task { await viewModel.setStatus(collection, to: .onHold) }
        } label: {
            Label("搁置", systemImage: "pause.circle")
        }
        Button(role: .destructive) {
            Task { await viewModel.setStatus(collection, to: .dropped) }
        } label: {
            Label("抛弃", systemImage: "xmark.circle")
        }
    }
}

private struct WatchingSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 56, height: 80)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 160, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 6)
            }
            Spacer()
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 40, height: 40)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shimmer()
    }
}

private struct WatchingGridCard: View {
    let collection: UserSubjectCollection
    let watchedCount: Int
    let totalCount: Int
    let airWeekdayText: String?
    let airsToday: Bool

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        // Clamp to 1.0 for parity with ProgressSection.progressRatio - a stale
        // or partially-fetched episodeProgress could otherwise yield watched >
        // total and overflow the bar past 100%.
        return min(1, Double(watchedCount) / Double(totalCount))
    }

    private var isComplete: Bool {
        totalCount > 0 && watchedCount >= totalCount
    }

    var body: some View {
        NavigationLink(value: AppRoute.subjectDetail(id: collection.subjectId)) {
            VStack(spacing: 0) {
                poster
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// 2:3 poster that fills the card width. `Color.clear.aspectRatio` establishes
    /// a flexible 2:3 box; the image (already `.resizable().aspectRatio(.fill)`
    /// via CachedAsyncImage) fills it and `.clipped()` crops the overflow.
    private var poster: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay(
                CachedAsyncImage(
                    urlString: collection.subject?.imageURL,
                    fallbackText: collection.subject?.displayName ?? "",
                    targetSize: CGSize(width: 180, height: 270)
                )
            )
            .overlay(alignment: .topTrailing) {
                if let rating = collection.subject?.rating, rating.score > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text(String(format: "%.1f", rating.score))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(6)
                }
            }
            .clipped()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.subject?.displayName ?? "作品 #\(collection.subjectId)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .tint(isComplete ? .green : .blue)
                Text(totalCount > 0 ? "\(watchedCount)/\(totalCount)" : "—")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }

            Text(subtitleText)
                .font(.system(size: 10, weight: airsToday ? .semibold : .regular))
                .foregroundColor(airsToday ? .orange : .secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Third footer line: "今天更新" (highlighted) when airing today, else the
    /// weekly cadence, falling back to the subject type when neither is known —
    /// keeps every card's footer at a uniform three-line height.
    private var subtitleText: String {
        if airsToday { return "今天更新" }
        if let airWeekdayText { return airWeekdayText }
        return SubjectType(rawValue: collection.subject?.type ?? 0)?.displayName ?? ""
    }
}
