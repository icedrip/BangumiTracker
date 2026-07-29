import SwiftUI

/// A transient error banner shown at the top of a screen. Used to surface
/// action failures (rate / comment / tag / episode-mark) that would otherwise
/// be invisible when the main content is already loaded — `SubjectDetailView`
/// only renders `errorMessage` as a full-screen retry state when the subject
/// itself failed to load, so a failed comment save on a loaded page was
/// silently swallowed.
///
/// Display is driven by `.errorToast($message)`: the binding is consumed (set
/// to nil) the moment the toast appears, so a repeat of the same failure
/// re-triggers it. The toast auto-dismisss after 2.5s.
struct ErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.callout)
            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.red.opacity(0.92)))
        .padding(.horizontal, .horizontalPadding)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("错误：\(message)")
    }
}

/// Shows `ErrorToast` at the top whenever `message` becomes non-nil, then
/// auto-dismisses after 2.5s. The source binding is consumed on display so a
/// repeated failure re-triggers the toast even with an identical message.
extension View {
    func errorToast(_ message: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(message: message))
    }
}

private struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?

    @State private var shown: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let shown {
                    ErrorToast(message: shown)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shown)
            .onChange(of: message) { _, newValue in
                guard let newValue else { return }
                dismissTask?.cancel()
                shown = newValue
                // Consume the source so a repeat failure (even identical) flips
                // nil → value again and re-triggers this onChange.
                message = nil
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    shown = nil
                }
            }
    }
}
