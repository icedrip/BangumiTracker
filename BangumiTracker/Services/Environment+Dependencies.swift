import SwiftUI
import OSLog

private struct BangumiAPIClientKey: EnvironmentKey {
    static let defaultValue: BangumiAPIClient = {
        Logger(subsystem: "z.zy.BangumiTracker", category: "di").warning(
            "BangumiAPIClient accessed without environment injection — returning orphan instance"
        )
        return BangumiAPIClient()
    }()
}

extension EnvironmentValues {
    var bangumiAPI: BangumiAPIClient {
        get { self[BangumiAPIClientKey.self] }
        set { self[BangumiAPIClientKey.self] = newValue }
    }
}

private struct TabSelectionKey: EnvironmentKey {
    static let defaultValue = Binding<Int>.constant(0)
}

private struct SessionCoordinatorKey: EnvironmentKey {
    static let defaultValue: SessionCoordinator? = nil
}

extension EnvironmentValues {
    var tabSelection: Binding<Int> {
        get { self[TabSelectionKey.self] }
        set { self[TabSelectionKey.self] = newValue }
    }

    var sessionCoordinator: SessionCoordinator? {
        get { self[SessionCoordinatorKey.self] }
        set { self[SessionCoordinatorKey.self] = newValue }
    }
}

extension View {
    /// Re-injects the app's root `@Observable` services into a `.sheet` /
    /// `.fullScreenCover` content closure. Apply to every sheet/cover whose
    /// content reads `@Environment(AuthService.self)` or `@Environment(\.bangumiAPI)`.
    ///
    /// On iOS 26.5 the LoginView sheet did not inherit the `AuthService` injected
    /// on the presenting view (empirically reproduced), so
    /// `@Environment(AuthService.self)` trapped — "No Observable object of type
    /// AuthService found" — at sheet-body update (EXC_BREAKPOINT/SIGTRAP in
    /// `EnvironmentValues.subscript.getter`). `@Environment(\.bangumiAPI)` would
    /// *not* trap (its EnvironmentKey has a `defaultValue`), but it would silently
    /// bind a throwaway `BangumiAPIClient()` with no token: a `setToken` from the
    /// sheet would land on a disconnected instance and login would silently no-op.
    /// Re-inject both.
    func bangumiRootEnvironment(auth: AuthService, api: BangumiAPIClient) -> some View {
        self
            .environment(auth)
            .environment(\.bangumiAPI, api)
    }
}
