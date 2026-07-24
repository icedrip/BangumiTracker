import SwiftUI

/// Centered "couldn't load + retry" affordance shared by the list/scroll views
/// (Watching / Explore / Calendar). Shown in place of content when a load fails
/// and there is no cached/partial data to fall back on.
struct ErrorRetryView: View {
    var message: String = "无法加载"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Text("重试")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
