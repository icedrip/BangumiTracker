import Foundation

/// Coordinates the 401-recovery / session-expiry / re-login flow that was
/// previously embedded in AppRootView. Separating it from the DI bootstrap
/// keeps the root view focused on wiring and makes the recovery ladder testable.
@MainActor
@Observable
final class SessionCoordinator {
    private let api: BangumiAPIClient
    private let auth: AuthService

    /// Load-time ViewModel references; set once by AppRootView after creation.
    /// Needed for the 401 recovery ladder to clear per-user state on permanent
    /// failure (home list, profile stats, watching progress).
    var homeViewModel: HomeViewModel?
    var profileViewModel: ProfileViewModel?
    var watchingViewModel: WatchingViewModel?

    /// Serializes concurrent 401 handling: a token rejection can fan out across
    /// several in-flight requests, but we only want one refresh attempt / one
    /// alert per generation.
    private var handlingUnauthorized = false

    init(api: BangumiAPIClient, auth: AuthService) {
        self.api = api
        self.auth = auth
    }

    // MARK: - 401 Recovery Ladder

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
    func handleUnauthorized(forGeneration generation: Int) async {
        // Stale: a newer token was already applied (refresh/paste). Drop.
        if await api.currentGeneration() != generation { return }
        guard !handlingUnauthorized else { return }
        handlingUnauthorized = true
        defer { handlingUnauthorized = false }

        switch await auth.attemptRefresh() {
        case .refreshed(let refreshed):
            guard await api.currentGeneration() == generation else { return }
            do {
                try auth.saveToken(refreshed)
                await api.setToken(refreshed.accessToken)
            } catch {
                auth.sessionExpired = true
            }
        case .transientFailure:
            break
        case .noRefreshToken:
            if await sessionConfirmedDead() {
                await endSession(showAlert: true)
            }
        case .permanentFailure:
            await endSession(showAlert: true)
        }
    }

    /// Probes `/v0/me` to confirm the current token is genuinely rejected.
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

    /// Full session teardown, shared by manual logout and the 401-driven expiry
    /// path so both clear the same state: Keychain token, the API client's
    /// in-memory token (and its cache generation), the response cache, and the
    /// per-user view-model/UserDefaults blobs.
    func endSession(showAlert: Bool) async {
        auth.deleteToken()
        await api.setToken(nil)
        homeViewModel?.clearOnLogout()
        profileViewModel?.clearOnLogout()
        watchingViewModel?.clearOnLogout()
        await api.clearResponseCache()
        WidgetDataService.clearAll()
        if showAlert { auth.sessionExpired = true }
    }

    /// Widget data refresh on foreground launch.
    func refreshWidgetData() async {
        let calendar = try? await api.fetchCalendar()
        if let calendar { await WidgetDataService.writeRecommendationData(from: calendar) }
        if auth.isAuthenticated {
            let watching = try? await api.fetchUserCollections(type: CollectionType.watching.rawValue)
            if let watching { await WidgetDataService.writeWatchingData(from: watching) }
        } else {
            WidgetDataService.writeAuthState(isAuthenticated: false)
        }
    }
}
