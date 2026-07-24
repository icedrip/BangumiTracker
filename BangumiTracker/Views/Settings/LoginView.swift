import SwiftUI
import AuthenticationServices

/// Login sheet presented at the app root (driven by `AuthService.presentLogin`),
/// triggered either by SettingsView's login buttons or the "登录已失效" 401 alert.
/// Offers OAuth when configured, plus the always-available manual access-token paste.
struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.bangumiAPI) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var tokenInput = ""
    @State private var statusMessage: String?
    @State private var isAuthorizing = false
    @State private var isSavingToken = false

    var body: some View {
        NavigationStack {
            Form {
                // Method 1: OAuth 授权
                if AuthService.oauthConfigured {
                    // First-time users may not realize OAuth and Access Token
                    // are alternatives — frame them as "pick one" up front so
                    // they don't think both are required. Styled as a guidance
                    // row (icon + primary text) so it reads as an intro, not a
                    // stray caption blending into the footers below.
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("任选以下一种方式登录即可")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                        }
                    }
                    Section {
                        Button {
                            Task { await startOAuth() }
                        } label: {
                            HStack(spacing: 10) {
                                if isAuthorizing { ProgressView() }
                                Text("使用 Bangumi 账号授权登录")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isAuthorizing)
                    } header: {
                        Text("OAuth 授权")
                    } footer: {
                        Text("跳转到 Bangumi 网站完成授权后自动返回。")
                    }
                } else {
                    Section {
                        Text("在线授权登录暂不可用，请在下方使用 Access Token 登录。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // Method 2: Access Token — symmetric with OAuth: its own
                // inline login button (no nav-bar 保存), and the "how to get
                // a token" link lives in this section's footer rather than a
                // standalone info section.
                Section {
                    TextField("粘贴 Access Token", text: $tokenInput, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await saveToken() }
                    } label: {
                        HStack(spacing: 10) {
                            if isSavingToken { ProgressView() }
                            Text("使用 Access Token 登录")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAuthorizing || isSavingToken)
                } header: {
                    Text("Access Token")
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("没有 Token？从下方链接生成后粘贴到上方。")
                        Link("打开 next.bgm.tv/demo/access-token", destination: URL(string: "https://next.bgm.tv/demo/access-token")!)
                    }
                }

                if let statusMessage {
                    Section { Text(statusMessage).font(.footnote).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("登录 Bangumi")
            .navigationBarTitleDisplayMode(.inline)
            // Auto-clear the inline status banner so a stale error / info
            // message doesn't linger over the form.
            .task(id: statusMessage) {
                guard statusMessage != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { statusMessage = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func startOAuth() async {
        guard let anchor = Self.topAnchor() else {
            statusMessage = "无法获取窗口，请改用粘贴 Access Token"
            return
        }
        isAuthorizing = true
        defer { isAuthorizing = false }
        do {
            let token = try await auth.startOAuth(presentationAnchor: anchor)
            await api.setToken(token.accessToken)
            dismiss()
        } catch AuthError.userCancelled {
            // User dismissed the web sheet — stay on the login form.
        } catch {
            statusMessage = "授权失败：\(error.localizedDescription)"
        }
    }

    private func saveToken() async {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Guard the async gap between the keychain write and `await api.setToken`
        // so a double-tap can't fire a second saveToken (whose keychain write
        // would hit a duplicate and flash a misleading "登录失败").
        guard !isSavingToken else { return }
        isSavingToken = true
        defer { isSavingToken = false }
        do {
            try auth.saveAccessToken(trimmed)
            await api.setToken(trimmed)
            dismiss()
        } catch {
            statusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    /// Find the key window to anchor `ASWebAuthenticationSession`. The session
    /// needs a presentation anchor even when launched from inside a sheet.
    private static func topAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
    }
}
