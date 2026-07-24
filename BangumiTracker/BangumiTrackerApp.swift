import SwiftUI
import SwiftData
import Kingfisher

@main
struct BangumiTrackerApp: App {
    @State private var api = BangumiAPIClient()
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

    /// Serializes concurrent 401 handling: a token rejection can fan out across
    /// several in-flight requests, but we only want one refresh attempt / one
    /// alert per generation.
    @State private var handlingUnauthorized = false

    var body: some View {
        @Bindable var auth = auth
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        ContentView()
            .environment(\.bangumiAPI, api)
            .environment(auth)
            .environment(homeViewModel ?? HomeViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .environment(exploreViewModel ?? ExploreViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .environment(watchingViewModel ?? WatchingViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .environment(profileViewModel ?? ProfileViewModel(api: api))
            .environment(searchViewModel ?? SearchViewModel(api: api, cache: LocalCacheService(modelContext: modelContext)))
            .preferredColorScheme(theme.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: .bangumiUnauthorized)) { note in
                // The generation the failing request was issued under. A refresh
                // or paste bumps the generation, so a late 401 from an
                // already-replaced token is dropped here.
                let gen = (note.userInfo?["generation"] as? Int) ?? -1
                Task { @MainActor in await handleUnauthorized(forGeneration: gen) }
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
                // Sheet content doesn't inherit the root @Observable services —
                // re-inject. See `bangumiRootEnvironment` for why both are needed.
                LoginView()
                    .bangumiRootEnvironment(auth: auth, api: api)
            }
            .onAppear {
                if homeViewModel == nil {
                    homeViewModel = HomeViewModel(api: api, cache: LocalCacheService(modelContext: modelContext))
                }
                if exploreViewModel == nil {
                    exploreViewModel = ExploreViewModel(api: api, cache: LocalCacheService(modelContext: modelContext))
                }
                if watchingViewModel == nil {
                    watchingViewModel = WatchingViewModel(api: api, cache: LocalCacheService(modelContext: modelContext))
                }
                if profileViewModel == nil {
                    profileViewModel = ProfileViewModel(api: api)
                }
                if searchViewModel == nil {
                    searchViewModel = SearchViewModel(api: api, cache: LocalCacheService(modelContext: modelContext))
                }
            }
            .task {
                await refreshWidgetData()
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

    /// 前台启动时刷新 widget 数据
    private func refreshWidgetData() async {
        let calendar = try? await api.fetchCalendar()
        if let calendar { await WidgetDataService.writeRecommendationData(from: calendar) }
        if auth.isAuthenticated {
            let watching = try? await api.fetchUserCollections(type: CollectionType.watching.rawValue)
            if let watching { await WidgetDataService.writeWatchingData(from: watching) }
        } else {
            WidgetDataService.writeAuthState(isAuthenticated: false)
        }
    }

    /// Handles a 401 posted by the API client. Generation-aware: a 401 from a
    /// request issued under an already-replaced token (a refresh or paste
    /// bumped the generation) is dropped, so a single token expiry doesn't
    /// trigger multiple refreshes or re-logins.
    ///
    /// Recovery ladder:
    ///   1. If a refresh_token exists, refresh silently. Save only if the
    ///      generation hasn't flipped mid-refresh (else a concurrent paste wins).
    ///   2. Transient refresh failure (network/5xx) → do NOT wipe; a retry
    ///      would likely succeed and the refresh_token may still be valid.
    ///   3. No refresh_token (personal token) → verify the session is actually
    ///      dead (GET /v0/me) before wiping. A transient 401 on one endpoint
    ///      must not destroy a valid, non-expiring personal token.
    ///   4. Permanent refresh failure, or verified-dead session → end session
    ///      and surface the re-login alert.
    private func handleUnauthorized(forGeneration generation: Int) async {
        // Stale: a newer token was already applied (refresh/paste). Drop.
        if await api.currentGeneration() != generation { return }
        guard !handlingUnauthorized else { return }
        handlingUnauthorized = true
        defer { handlingUnauthorized = false }

        switch await auth.attemptRefresh() {
        case .refreshed(let refreshed):
            // Re-check generation: a paste during the refresh await would have
            // bumped it, and that paste should win over the stale refresh.
            guard await api.currentGeneration() == generation else { return }
            do {
                try auth.saveToken(refreshed)
                await api.setToken(refreshed.accessToken)
            } catch {
                // Keychain write failed — surface as a normal alert.
                auth.sessionExpired = true
            }
        case .transientFailure:
            // Retryable. Don't destroy credentials; next 401 will retry.
            break
        case .noRefreshToken:
            // Personal token — can't refresh. Verify the token is actually
            // dead before wiping, so a transient/endpoint-specific 401 doesn't
            // destroy a valid non-expiring token.
            if await sessionConfirmedDead() {
                await endBangumiSession(
                    auth: auth, api: api,
                    home: homeViewModel, profile: profileViewModel, watching: watchingViewModel,
                    showAlert: true
                )
            }
        case .permanentFailure:
            await endBangumiSession(
                auth: auth, api: api,
                home: homeViewModel, profile: profileViewModel, watching: watchingViewModel,
                showAlert: true
            )
        }
    }

    /// Probes `/v0/me` to confirm the current token is genuinely rejected. A 200
    /// means the 401 was transient/endpoint-specific and the token is fine; a
    /// network error is inconclusive so we assume alive (don't wipe). Only a
    /// confirmed 401 returns true.
    private func sessionConfirmedDead() async -> Bool {
        do {
            _ = try await api.fetchMe()
            return false
        } catch BangumiAPIError.unauthorized {
            return true
        } catch {
            return false
        }
    }
}

/// Full session teardown, shared by manual logout and the 401-driven expiry
/// path so both clear the same state: Keychain token, the API client's
/// in-memory token (and its cache generation), the response cache, and the
/// per-user view-model/UserDefaults blobs. `showAlert` distinguishes "user
/// chose to log out" (no alert) from "the server rejected the token" (alert).
@MainActor
func endBangumiSession(
    auth: AuthService,
    api: BangumiAPIClient,
    home: HomeViewModel?,
    profile: ProfileViewModel?,
    watching: WatchingViewModel?,
    showAlert: Bool
) async {
    auth.deleteToken()
    await api.setToken(nil)
    home?.clearOnLogout()
    profile?.clearOnLogout()
    watching?.clearOnLogout()
    await api.clearResponseCache()
    WidgetDataService.clearAll()
    if showAlert { auth.sessionExpired = true }
}
