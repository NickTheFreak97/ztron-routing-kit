/// Which SwiftUI container a ``ZNavigator`` drives.
///
/// The explicit cases exist for one reason: parity must be testable on the simulators available today, which all
/// run iOS 17 or later. The same scenario suite runs against ``navigationStack`` and ``navigationView`` and must
/// produce the same stack, the same identities and the same appear/disappear sequences.
public enum ZNavigationBackend: Sendable, Equatable {
    /// `NavigationStack` where it exists (iOS 16, macOS 13, tvOS 16, watchOS 9), else `NavigationView`.
    case automatic
    /// Explicit `NavigationStack` bound to the navigator's stack.
    case navigationStack
    /// Explicit `NavigationView` with a recursive chain of hidden `isActive` links. Works on every OS, which is
    /// what lets the parity suite exercise the iOS 15 code path on current simulators.
    case navigationView

    /// `automatic` resolved for the running OS; the explicit cases unchanged.
    public var resolved: ZNavigationBackend {
        switch self {
        case .automatic:
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                return .navigationStack
            } else {
                return .navigationView
            }
        case .navigationStack, .navigationView:
            return self
        }
    }
}
