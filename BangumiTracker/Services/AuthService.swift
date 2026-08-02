import Foundation
import Security
import AuthenticationServices
import OSLog

enum AuthError: Error, LocalizedError {
    case userCancelled
    case keychainError(OSStatus)
    case invalidResponse
    case missingClientID
    case oauthFailed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled: "用户取消授权"
        case .keychainError(let status): "Keychain 错误 (\(status))"
        case .invalidResponse: "OAuth 响应无效"
        case .missingClientID: "未配置 OAuth client_id，请改用手动粘贴 Access Token"
        case .oauthFailed(let msg): "授权失败：\(msg)"
        }
    }
}

extension Notification.Name {
    /// Posted by `BangumiAPIClient` when the server rejects a presented token
    /// (HTTP 401). Observed by `AppRootView`, which refreshes or invalidates the
    /// session. Posted synchronously (thread-safe); the observer hops to MainActor.
    static nonisolated let bangumiUnauthorized = Notification.Name("com.bangumitracker.unauthorized")
    /// Posted when user taps a widget item — triggers deep-link navigation in ContentView.
    static nonisolated let widgetOpenSubject = Notification.Name("com.bangumitracker.widgetOpenSubject")
}

/// Persisted credential bundle stored in the Keychain.
///
/// Personal access tokens (from `next.bgm.tv/demo/access-token`) have
/// `refreshToken == nil` and `expiresAt == nil` — they don't expire and can't
/// be refreshed. OAuth tokens carry both, so a near-expiry/401'd token can be
/// silently renewed instead of forcing a re-login.
struct AuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

/// Why a token-endpoint call failed, so the 401 handler can tell a retryable
/// blip (network drop, 5xx) from a dead refresh_token (4xx) and avoid wiping
/// credentials on a transient failure.
private enum TokenEndpointError: Error {
    case transient
    case permanent
}

@MainActor
@Observable
final class AuthService {
    static let tokenAccount = "com.bangumitracker.oauth.accessToken"
    static let tokenService = "com.bangumitracker.bangumi"

    /// Mirror of a valid token being present — set on init, mutated by
    /// save/delete/invalidate to drive UI. Reflects *validity*, not just
    /// keychain presence: a 401 the refresh can't recover from clears it.
    var isAuthenticated: Bool

    /// True once the server rejected the token (401) and refresh failed/was
    /// unavailable. Drives the global "登录已失效" alert.
    var sessionExpired: Bool = false

    /// Drives the login sheet — set by the expired-token alert's "去登录"
    /// action or by SettingsView. Presented as a `LoginView` sheet at the
    /// app root so the recovery path works from any tab.
    var presentLogin: Bool = false

    /// In-memory mirror of the Keychain token. Populated once in `init` from
    /// the same Keychain read that sets `isAuthenticated`, then kept in sync by
    /// save/delete. Without this, `loadToken()` re-ran a `SecItemCopyMatching`
    /// + JSON decode on every cold launch (init discards, then `.task` re-reads
    /// for `api.setToken`) and again on every 401 — `attemptRefresh` would hit
    /// the Keychain a third time for a token already sitting in the API client.
    @ObservationIgnored private var cachedToken: AuthToken?

    init() {
        let token = AuthService.loadTokenUnsafely()
        self.cachedToken = token
        self.isAuthenticated = token != nil
    }

    // MARK: - OAuth configuration

    /// OAuth credentials from `DevSecrets` (the gitignored local secrets file).
    /// Available in BOTH Debug and Release: these compile into the app binary so
    /// OAuth login + token refresh work for real users (mobile OAuth public
    /// clients embed client_id/secret in the binary — standard practice). They
    /// are NOT in git because `DevSecrets.swift` is gitignored. Until both are
    /// filled in, OAuth is unavailable and the UI falls back to manual
    /// access-token paste. Register an app at https://bgm.tv/dev/app with the
    /// redirect URI `bangumitracker://oauth/callback`.
    static var oauthClientID: String? {
        let v = DevSecrets.oauthClientID
        return v.isEmpty ? nil : v
    }

    static var oauthClientSecret: String? {
        let v = DevSecrets.oauthClientSecret
        return v.isEmpty ? nil : v
    }

    static var oauthConfigured: Bool { oauthClientID != nil && oauthClientSecret != nil }

    // The URL scheme is intentionally shared with Release (not split like the
    // bundle id): bgm.tv allows only one callback URL per OAuth app, so a dev-only
    // scheme would require a separate OAuth app. ASWebAuthenticationSession captures
    // the redirect per-session, so the two coexisting builds don't steal each
    // other's callbacks. Data isolation comes from the bundle-id split (Keychain/
    // SwiftData/UserDefaults live in separate containers).
    private static let redirectURI = "bangumitracker://oauth/callback"
    private static let callbackScheme = "bangumitracker"

    @ObservationIgnored private var presentationProvider: AuthPresentationProvider?

    /// Launches an `ASWebAuthenticationSession` against bgm.tv and exchanges the
    /// returned code for a full token bundle (access + refresh + expiry).
    /// Throws `.missingClientID` until OAuth client_id/secret are configured.
    func startOAuth(presentationAnchor: ASPresentationAnchor) async throws -> AuthToken {
        guard let clientID = Self.oauthClientID, let clientSecret = Self.oauthClientSecret else {
            throw AuthError.missingClientID
        }

        var components = URLComponents(string: "https://bgm.tv/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
        ]
        guard let authURL = components?.url else { throw AuthError.invalidResponse }

        let provider = AuthPresentationProvider(anchor: presentationAnchor)
        self.presentationProvider = provider
        // Clear on every exit path — including user-cancel and any throw out of
        // the continuation / token exchange below — so the provider (which
        // retains the ASPresentationAnchor) doesn't linger on this long-lived
        // service until the next successful startOAuth overwrites it.
        defer { self.presentationProvider = nil }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: AuthError.oauthFailed(error.localizedDescription))
                    }
                    return
                }
                guard let url else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard
            let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.invalidResponse }

        let token = try await exchangeToken(
            grantType: "authorization_code",
            credential: code,
            clientID: clientID,
            clientSecret: clientSecret
        )
        try saveToken(token)
        return token
    }

    /// Outcome of a refresh attempt. The caller (the 401 handler) decides what
    /// to do per case — critically, a `transientFailure` must NOT destroy the
    /// stored credentials, since a retry would likely succeed and the
    /// refresh_token may still be valid.
    enum RefreshOutcome {
        case refreshed(AuthToken)
        /// No `refresh_token` (personal access token) or OAuth unconfigured —
        /// refresh is impossible. The caller should verify the session is
        /// actually dead before wiping the token.
        case noRefreshToken
        /// Network drop or 5xx from the token endpoint — retryable. Do NOT
        /// invalidate; the refresh_token is likely still good.
        case transientFailure
        /// 4xx from the token endpoint — the refresh_token is revoked/invalid.
        /// Safe to invalidate.
        case permanentFailure
    }

    /// Attempts to refresh an expired OAuth access token. Does NOT persist the
    /// result — the caller saves it only after re-checking the session
    /// generation hasn't flipped (a concurrent paste would otherwise be
    /// overwritten by the stale refresh). No-op (`.noRefreshToken`) for
    /// personal tokens (no `refresh_token`) or when OAuth isn't configured.
    func attemptRefresh() async -> RefreshOutcome {
        guard Self.oauthConfigured,
              let current = currentToken(),
              let refreshToken = current.refreshToken,
              let clientID = Self.oauthClientID,
              let clientSecret = Self.oauthClientSecret else {
            return .noRefreshToken
        }
        do {
            let token = try await exchangeToken(
                grantType: "refresh_token",
                credential: refreshToken,
                clientID: clientID,
                clientSecret: clientSecret
            )
            return .refreshed(token)
        } catch TokenEndpointError.permanent {
            return .permanentFailure
        } catch {
            // `.transient` (network/5xx) or any unexpected error — treat as
            // retryable so a momentary blip can't wipe a valid refresh_token.
            return .transientFailure
        }
    }

    /// Shared token-endpoint call for both `authorization_code` and
    /// `refresh_token` grants. The `credential` param is the auth code or the
    /// refresh token, respectively. Throws `TokenEndpointError` so the caller
    /// can distinguish a retryable blip from a dead refresh_token.
    /// Codable response from the bgm.tv OAuth token endpoint.
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func exchangeToken(
        grantType: String,
        credential: String,
        clientID: String,
        clientSecret: String
    ) async throws -> AuthToken {
        guard let url = URL(string: "https://bgm.tv/oauth/access_token") else {
            throw AuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("BangumiTracker/1.0 (https://github.com/bangumi)", forHTTPHeaderField: "User-Agent")

        var params: [String: String] = [
            "grant_type": grantType,
            "client_id": clientID,
            "client_secret": clientSecret,
        ]
        params[grantType == "refresh_token" ? "refresh_token" : "code"] = credential
        if grantType == "authorization_code" {
            params["redirect_uri"] = Self.redirectURI
        }
        // application/x-www-form-urlencoded requires escaping reserved chars
        // `&`, `=`, `+` (a `+` decodes as space; `&`/`=` split fields).
        // `.urlQueryAllowed` leaves those unescaped — use the RFC 3986
        // unreserved set (alphanumerics + `-._~`) so everything else is
        // percent-encoded. A code or refresh_token containing any of those
        // chars would otherwise be corrupted in the POST body.
        request.httpBody = params
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Network failure — retryable, the refresh_token may still be valid.
            throw TokenEndpointError.transient
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenEndpointError.transient
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            // 4xx (invalid_grant / revoked refresh_token) → permanent. 5xx → transient.
            throw (400...499).contains(httpResponse.statusCode)
                ? TokenEndpointError.permanent
                : TokenEndpointError.transient
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = tokenResponse.expiresIn.map { Date(timeIntervalSinceNow: $0) }
        return AuthToken(accessToken: tokenResponse.accessToken, refreshToken: tokenResponse.refreshToken, expiresAt: expiresAt)
    }

    /// Percent-encodes a string for `application/x-www-form-urlencoded` bodies,
    /// escaping everything except RFC 3986 unreserved characters.
    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - Keychain

    /// The current token. Served from the in-memory cache (populated at init /
    /// save) so callers don't each pay a Keychain round-trip + JSON decode for
    /// bytes already in memory.
    func currentToken() -> AuthToken? { cachedToken }

    private static func loadTokenUnsafely() -> AuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        // OAuth path: JSON-encoded AuthToken.
        if let token = try? JSONDecoder().decode(AuthToken.self, from: data) {
            return token
        }
        // Migration: older builds stored a raw access-token string.
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return AuthToken(accessToken: raw, refreshToken: nil, expiresAt: nil)
        }
        return nil
    }

    func saveToken(_ token: AuthToken) throws {
        guard let data = try? JSONEncoder().encode(token) else { throw AuthError.invalidResponse }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.tokenService,
            kSecAttrAccount as String: Self.tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.keychainError(status) }
        cachedToken = token
        isAuthenticated = true
        sessionExpired = false
    }

    /// Convenience for the manual-paste path: a personal access token carries
    /// no refresh token and never expires.
    func saveAccessToken(_ accessToken: String) throws {
        try saveToken(AuthToken(accessToken: accessToken, refreshToken: nil, expiresAt: nil))
    }

    /// DEBUG dev-fallback only: apply the dev token in-memory WITHOUT persisting
    /// it to the Keychain. A fresh install otherwise ends up with the dev token
    /// in the Keychain and shows "logged in" with a token the user never
    /// entered, and a stale dev token lingers after logout. The token is held
    /// in `cachedToken` (not just a bool) so the rest of the service treats it
    /// like a real token — `loadToken()` returns it, and a 401 can verify it
    /// rather than helplessly alerting with nothing to clear.
    func applyEphemeralToken(_ token: AuthToken) {
        cachedToken = token
        isAuthenticated = true
        sessionExpired = false
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.tokenService,
            kSecAttrAccount as String: Self.tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        cachedToken = nil
        isAuthenticated = false
    }
}

@MainActor
private final class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }
}
