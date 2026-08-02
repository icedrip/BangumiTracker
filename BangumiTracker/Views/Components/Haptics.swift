import UIKit

/// Thin wrapper over UIKit feedback generators so view actions can fire haptics
/// with a single call. Precise (fires exactly on user action) unlike
/// `.sensoryFeedback(trigger:)` which can fire on any value change.
///
/// Generators are created once and reused, per Apple's guidance to reuse
/// generators rather than allocating per call (allocation adds latency on the
/// haptic path and the generators are designed to be long-lived).
///
/// The generators' SDK initializers are `@MainActor`-isolated. Under Swift 6.0
/// a stored property default value that calls an isolated initializer fails
/// with "main actor-isolated default value in a nonisolated context", so
/// creation is deferred into the MainActor-isolated `make()` cache instead of
/// using stored default values.
@MainActor
enum Haptics {
    private struct Generators {
        let notification: UINotificationFeedbackGenerator
        let light: UIImpactFeedbackGenerator
        let medium: UIImpactFeedbackGenerator
        let selection: UISelectionFeedbackGenerator
    }

    private static var cached: Generators?
    private static func make() -> Generators {
        if let cached { return cached }
        let generators = Generators(
            notification: UINotificationFeedbackGenerator(),
            light: UIImpactFeedbackGenerator(style: .light),
            medium: UIImpactFeedbackGenerator(style: .medium),
            selection: UISelectionFeedbackGenerator()
        )
        cached = generators
        return generators
    }

    static func success() { make().notification.notificationOccurred(.success) }
    static func warning() { make().notification.notificationOccurred(.warning) }
    static func error() { make().notification.notificationOccurred(.error) }
    static func light() { make().light.impactOccurred() }
    static func medium() { make().medium.impactOccurred() }
    static func selection() { make().selection.selectionChanged() }
}
