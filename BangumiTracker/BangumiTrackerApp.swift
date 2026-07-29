import SwiftUI
import SwiftData
import Kingfisher

@main
struct BangumiTrackerApp: App {
    @State private var api = BangumiAPIClient(
        session: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 30
            return URLSession(configuration: config)
        }()
    )
    @State private var auth = AuthService()
    @State private var isReady = false

    init() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024     // 50 MB decoded
        cache.memoryStorage.config.expiration = .seconds(300)
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024           // 200 MB on disk
        cache.diskStorage.config.expiration = .days(14)

        // Bangumi's CDN occasionally returns no Cache-Control header; tell
        // Kingfisher to honor disk cache regardless of HTTP cache hints.
        // Cap each image request at 12s — URLSession's default 60s leaves a
        // hung fetch (e.g. Clash proxy stalling the TLS handshake to the
        // image CDN) spinning the CachedAsyncImage placeholder for a full
        // minute, which reads as "stuck on the loading animation". A 12s
        // ceiling lets it fail fast and fall back to the gray placeholder.
        KingfisherManager.shared.defaultOptions = [
            .diskCacheExpiration(.days(14)),
            .memoryCacheExpiration(.seconds(300)),
            .backgroundDecode,
            .requestModifier(AnyModifier { request in
                var request = request
                request.timeoutInterval = 12
                return request
            })
        ]

        // Remap any stale preference raw values whose enum cases were removed
        // (e.g. the old `.calendar` default view) before any @AppStorage reads them.
        DefaultListView.migrateStoredValue()
    }

    /// Development fallback token — used only in DEBUG builds when no token is saved in Keychain.
    /// The actual value lives in `DevSecrets.swift`, which is gitignored.
    private static var devFallbackToken: String {
        #if DEBUG
        return DevSecrets.bangumiAccessToken
        #else
        return ""
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if isReady {
                AppRootView(api: api, auth: auth)
            } else {
                ProgressView()
                    .task {
                        // `init` already populated AuthService's in-memory token
                        // cache from the same Keychain read that set
                        // isAuthenticated — read the cache here rather than
                        // paying a second SecItemCopyMatching + JSON decode on
                        // every cold launch (the read gates first paint).
                        if let token = auth.currentToken() {
                            await api.setToken(token.accessToken)
                        } else if !Self.devFallbackToken.isEmpty {
                            // DEBUG: apply the dev token in-memory only. Don't
                            // persist it to the Keychain — a fresh install
                            // otherwise shows "logged in" with a token the user
                            // never entered, and a stale dev token lingers after
                            // logout. A real login (paste/OAuth) writes the Keychain.
                            // The token is held in AuthService (not just a bool)
                            // so a 401 can verify it rather than alerting with
                            // nothing to clear.
                            auth.applyEphemeralToken(AuthToken(
                                accessToken: Self.devFallbackToken,
                                refreshToken: nil,
                                expiresAt: nil
                            ))
                            await api.setToken(Self.devFallbackToken)
                        }
                        isReady = true
                    }
            }
        }
        .modelContainer(for: [
            CachedSubject.self,
            CachedUserCollection.self,
            SearchHistory.self,
            WishCollectedAt.self
        ])
    }
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PreferenceKey.theme) private var themeRaw = AppTheme.light.rawValue
    let api: BangumiAPIClient
    let auth: AuthService

    @State private var homeViewModel: HomeViewModel?
    @State private var exploreViewModel: ExploreViewModel?
    @State private var watchingViewModel: WatchingViewModel?
    @State private var profileViewModel: ProfileViewModel?
    @State private var searchViewModel: SearchViewModel?
    @State private var coordinator: SessionCoordinator?

    var body: some View {
        @Bindable var auth = auth
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        ContentView()
            .environment(\.bangumiAPI, api)
            .environment(auth)
            .environment(coordinator ?? SessionCoordinator(api: api, auth: auth))
            .environment(homeViewModel ?? HomeViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .environment(exploreViewModel ?? ExploreViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .environment(watchingViewModel ?? WatchingViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .environment(profileViewModel ?? ProfileViewModel(api: api))
            .environment(searchViewModel ?? SearchViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .preferredColorScheme(theme.colorScheme)
            .dynamicTypeSize(DynamicTypeSize.xSmall...DynamicTypeSize.accessibility3)
            .onReceive(NotificationCenter.default.publisher(for: .bangumiUnauthorized)) { note in
                let gen = (note.userInfo?["generation"] as? Int) ?? -1
                Task { @MainActor in await coordinator?.handleUnauthorized(forGeneration: gen) }
            }
            .alert("登录已失效", isPresented: $auth.sessionExpired) {
                Button("去登录") {
                    auth.sessionExpired = false
                    auth.presentLogin = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("Access Token 已失效或过期，请重新登录。")
            }
            .sheet(isPresented: $auth.presentLogin) {
                LoginView()
                    .bangumiRootEnvironment(auth: auth, api: api)
            }
            .task {
                await coordinator?.refreshWidgetData()
            }
            .onAppear {
                if homeViewModel == nil { homeViewModel = HomeViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)) }
                if exploreViewModel == nil { exploreViewModel = ExploreViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)) }
                if watchingViewModel == nil { watchingViewModel = WatchingViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)) }
                if profileViewModel == nil { profileViewModel = ProfileViewModel(api: api) }
                if searchViewModel == nil { searchViewModel = SearchViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)) }
                // Wire coordinator to VMs after creation so the 401 ladder
                // can clear per-user state on permanent failure.
                let c = SessionCoordinator(api: api, auth: auth)
                c.homeViewModel = homeViewModel
                c.profileViewModel = profileViewModel
                c.watchingViewModel = watchingViewModel
                coordinator = c
            }
            .onOpenURL { url in
                guard url.scheme == "bangumitracker", url.host == "subject",
                      let subjectId = Int(url.lastPathComponent) else { return }
                NotificationCenter.default.post(
                    name: .widgetOpenSubject,
                    object: nil,
                    userInfo: ["subjectId": subjectId]
                )
            }
    }
}
