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
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Text("重试")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, .tightSpacing)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
