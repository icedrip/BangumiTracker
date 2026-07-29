import SwiftUI

/// A compact CTA card shown in place of login-gated sections (the subject
/// detail tracking area, the Watching tab body) when the user isn't
/// authenticated. The button presents the root `LoginView` sheet via
/// `auth.presentLogin` — the same entry point `SettingsView` and the Profile
/// header use — so there's a single login path across the app.
struct LoginPromptCard: View {
    var icon: String
    var title: String
    var description: String

    @Environment(AuthService.self) private var auth

    var body: some View {
        DetailSectionCard(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                auth.presentLogin = true
            } label: {
                Text("登录 Bangumi")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }
}
