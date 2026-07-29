import SwiftUI

struct ProfileView: View {
    @Environment(ProfileViewModel.self) private var viewModel
    @Environment(AuthService.self) private var auth
    @Environment(HomeViewModel.self) private var homeViewModel
    @Environment(\.tabSelection) private var tabSelection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LargeNavHeader(title: "我的")

                // Profile header — full-width to match the stat cards below.
                // When not authenticated, a chevron marks the card as the login
                // entry point; tapping anywhere presents the login sheet (root
                // LoginView bound to auth.presentLogin in BangumiTrackerApp).
                // Wrapped in a Button (not bare onTapGesture) so VoiceOver
                // announces it as a button, keyboard/Switch Control can
                // activate it, and the press highlight renders.
                let headerContent = HStack(spacing: 16) {
                    avatarView
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.userInfo?.nickname ?? "未登录")
                            .font(.title2.weight(.bold))
                        Text(viewModel.userInfo.map { "@\($0.username) · Bangumi 用户" } ?? "请先登录 Bangumi 账号")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    if !auth.isAuthenticated {
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .padding(.horizontal, .horizontalPadding)

                if auth.isAuthenticated {
                    headerContent
                } else {
                    Button {
                        auth.presentLogin = true
                    } label: {
                        headerContent
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("登录 Bangumi 账号")
                }

                // Stats
                if viewModel.errorMessage != nil && viewModel.stats.isEmpty {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(ProfileViewModel.displayedStatTypes, id: \.rawValue) { type in
                                StatCard(
                                    label: type.displayName,
                                    count: 0,
                                    color: type.displayColor,
                                    showError: true
                                )
                            }
                        }
                        Text("无法加载，下拉刷新")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, .horizontalPadding)
                } else if viewModel.stats.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(ProfileViewModel.displayedStatTypes, id: \.rawValue) { type in
                            StatCard(label: type.displayName, count: 0, color: type.displayColor)
                        }
                    }
                    .padding(.horizontal, .horizontalPadding)
                } else {
                    HStack(spacing: 8) {
                        ForEach(viewModel.stats) { stat in
                            StatCard(
                                label: stat.type.displayName,
                                count: stat.count,
                                color: stat.type.displayColor
                            ) {
                                statTapped(stat.type)
                            }
                        }
                    }
                    .padding(.horizontal, .horizontalPadding)
                }

                // Viewing profile — derived from the watched collection
                Text("观看画像")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, .horizontalPadding)

                ProfileInsightCard(insights: viewModel.insights, genres: viewModel.genres)
                    .padding(.horizontal, .horizontalPadding)

                // Settings
                Text("设置")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, .horizontalPadding)

                SettingsGroup {
                    NavigationLink(value: AppRoute.settings) {
                        SettingsRow(label: "应用设置", showDivider: false)
                    }
                }
                .padding(.horizontal, .horizontalPadding)

                SettingsGroup {
                    SettingsRow(label: "版本", value: "1.0.0", showChevron: false)
                }
                .padding(.horizontal, .horizontalPadding)
            }
            .padding(.vertical, .tightSpacing)
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadAll()
        }
        // Re-fire on auth flips so login/logout immediately reflects in the
        // header and stat cards without a manual pull-to-refresh.
        .task(id: auth.isAuthenticated) {
            await viewModel.loadAll()
        }
    }

    /// Stat-card tap → jump to the matching list (PRD 5.2.6 "跳转首页对应状态筛选").
    /// 想看 / 已看 / 搁置 set the home list's status filter and switch to Home;
    /// 在看 switches to the Watching tab directly.
    private func statTapped(_ type: CollectionType) {
        switch type {
        case .watching:
            tabSelection.wrappedValue = 2
        case .wish, .watched, .onHold:
            Task { await homeViewModel.setCollectionStatus(type) }
            tabSelection.wrappedValue = 0
        case .dropped:
            break
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = viewModel.userInfo?.avatar.large ?? viewModel.userInfo?.avatar.medium {
            CachedAsyncImage(
                urlString: url,
                fallbackText: viewModel.userInfo?.nickname.prefix(1).uppercased() ?? "?",
                targetSize: CGSize(width: 64, height: 64)
            )
        } else {
            // Default avatar placeholder (no Bangumi default-image asset bundled).
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(.secondary.opacity(0.4))
        }
    }
}
