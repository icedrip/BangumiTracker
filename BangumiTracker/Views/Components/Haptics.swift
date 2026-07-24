import UIKit

/// Thin wrapper over UIKit feedback generators so view actions can fire haptics
/// with a single call. Precise (fires exactly on user action) unlike
/// `.sensoryFeedback(trigger:)` which can fire on any value change.
///
/// Generators are held in static constants and `prepare()`d once, per Apple's
/// guidance to reuse generators rather than allocating per call (allocation
/// adds latency on the haptic path and the generators are designed to be
/// long-lived).
enum Haptics {
    private static let notification = UINotificationFeedbackGenerator()
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }

    static func light() {
        lightImpact.impactOccurred()
    }

    static func medium() {
        mediumImpact.impactOccurred()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
    }
}
