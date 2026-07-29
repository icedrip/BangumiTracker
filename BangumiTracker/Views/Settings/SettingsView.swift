import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.bangumiAPI) private var api
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeViewModel.self) private var home
    @Environment(ProfileViewModel.self) private var profile
    @Environment(\.sessionCoordinator) private var coordinator
    @Environment(WatchingViewModel.self) private var watching

    @AppStorage(PreferenceKey.theme) private var theme = AppTheme.light.rawValue
    @AppStorage(PreferenceKey.defaultView) private var defaultView = DefaultListView.list.rawValue
    @AppStorage(PreferenceKey.startPage) private var startPage = StartPage.home.rawValue
    @AppStorage(PreferenceKey.scoreDisplay) private var scoreDisplay = ScoreDisplay.ten.rawValue
    @AppStorage(PreferenceKey.nsfwVisible) private var nsfwVisible = false

    @State private var showLogoutConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var statusMessage: String?
    @State private var showFeedback = false

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { t in
                        Text(t.displayName).tag(t.rawValue)
                    }
                }
                Picker("默认视图", selection: $defaultView) {
                    ForEach(DefaultListView.allCases, id: \.rawValue) { v in
                        Text(v.displayName).tag(v.rawValue)
                    }
                }
                Picker("评分粒度", selection: $scoreDisplay) {
                    ForEach(ScoreDisplay.allCases, id: \.rawValue) { s in
                        Text(s.displayName).tag(s.rawValue)
                    }
                }
            }

            Section("通用") {
                Picker("启动页", selection: $startPage) {
                    ForEach(StartPage.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }
                Toggle("显示 18+ 内容", isOn: $nsfwVisible)
            }

            Section("账号") {
                if auth.isAuthenticated {
                    Button("更换登录 / 重新授权") {
                        Task { await reauthorize() }
                    }
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                    // Anchored on the logout button itself so the popover's
                    // source point lands on this row (not a sibling button).
                    .confirmationDialog("退出登录?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                        Button("退出登录", role: .destructive) {
                            Task { await logout() }
                        }
                        Button("取消", role: .cancel) {}
                    }
                } else {
                    Button("登录 Bangumi 账号") {
                        auth.presentLogin = true
                    }
                }
            }

            Section("数据") {
                Button("清除本地缓存") {
                    showClearCacheConfirm = true
                }
                .confirmationDialog("清除本地缓存?", isPresented: $showClearCacheConfirm, titleVisibility: .visible) {
                    Button("清除", role: .destructive) {
                        clearCache()
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("将删除已缓存的条目和收藏。搜索历史不会被清除。")
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0.0 (Build 1)")
                NavigationLink(value: AppRoute.license) {
                    Label("开源许可", systemImage: "doc.text")
                }
                Button("意见反馈") {
                    showFeedback = true
                }
            }

            if let statusMessage {
                Section { Text(statusMessage).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        // Auto-clear the inline status banner so a stale "已退出登录" /
        // "本地缓存已清除" doesn't linger indefinitely.
        .task(id: statusMessage) {
            guard statusMessage != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { statusMessage = nil }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView(username: profile.userInfo?.username) {
                statusMessage = "感谢反馈,已提交"
            }
        }
    }

    private func logout() async {
        await coordinator?.endSession(showAlert: false)
        statusMessage = "已退出登录"
    }

    /// "重新授权": a logout + immediate login-sheet presentation (PRD 5.2.7
    /// describes this as a logout/re-login flow, not just re-opening the sheet
    /// over the stale session).
    private func reauthorize() async {
        await coordinator?.endSession(showAlert: false)
        auth.presentLogin = true
    }

    private func clearCache() {
        let cache = LocalCacheService(modelContext: modelContext)
        cache.clearAllCache()
        Task {
            await api.clearResponseCache()
            statusMessage = "本地缓存已清除"
        }
    }
}
