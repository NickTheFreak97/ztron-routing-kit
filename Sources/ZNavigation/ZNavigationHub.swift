import Combine
import SwiftUI

/// The navigators of an app, one per tab, reachable from outside the view tree.
///
/// Deep links (Spotlight, URL schemes, state restoration) arrive at the `App` or the app delegate, which do not own
/// the navigators. The hub is created there, put in the environment with ``SwiftUICore/View/zNavigationHub(_:)``,
/// and every ``ZNavigationScope`` registers its navigator on first appearance. Navigators are held weakly: a tab's
/// navigator lives exactly as long as that tab's view.
///
/// A navigation requested before its navigator exists (a cold start from Spotlight) is kept and replayed when the
/// navigator registers.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public final class ZNavigationHub: ObservableObject {
    private struct Entry {
        weak var navigator: ZNavigator?
    }

    private var entries: [Entry] = []
    private var pending: (route: ZRoute, models: [ZRoute: ZRouteModels])?

    public init() {}

    /// The registered navigators, in registration order.
    public var navigators: [ZNavigator] {
        self.entries.compactMap(\.navigator)
    }

    /// Registers `navigator`, replacing a previous navigator with the same root. Replays a pending navigation that
    /// `navigator` owns.
    public func register(_ navigator: ZNavigator) {
        self.prune()
        if self.entries.contains(where: { $0.navigator === navigator }) {
            return
        }
        self.objectWillChange.send()
        self.entries.removeAll { $0.navigator?.root == navigator.root }
        self.entries.append(Entry(navigator: navigator))
        if let pending = self.pending, pending.route.hasPrefix(navigator.root) {
            self.pending = nil
            navigator.navigate(to: pending.route, carrying: pending.models)
        }
    }

    public func unregister(_ navigator: ZNavigator) {
        self.prune()
        guard self.entries.contains(where: { $0.navigator === navigator }) else { return }
        self.objectWillChange.send()
        self.entries.removeAll { $0.navigator === navigator }
    }

    /// The navigator whose root is exactly `root`.
    public func navigator(for root: ZRoute) -> ZNavigator? {
        self.navigators.first { $0.root == root }
    }

    /// The registered navigator whose root is the longest prefix of `route`.
    public func navigator(owning route: ZRoute) -> ZNavigator? {
        self.navigators
            .filter { route.hasPrefix($0.root) }
            .max { $0.root.segments.count < $1.root.segments.count }
    }

    /// Hands `absolute` to the navigator that owns it. Returns that navigator, or `nil` when none owns the path yet,
    /// in which case the navigation is kept for the next matching ``register(_:)``.
    @discardableResult
    public func navigate(to absolute: [String], carrying models: [ZRoute: ZRouteModels] = [:]) -> ZNavigator? {
        self.navigate(to: ZRoute(absolute), carrying: models)
    }

    /// Hands `route` to the navigator that owns it. Returns that navigator, or `nil` when none owns the route yet,
    /// in which case the navigation is kept for the next matching ``register(_:)``.
    @discardableResult
    public func navigate(to route: ZRoute, carrying models: [ZRoute: ZRouteModels] = [:]) -> ZNavigator? {
        guard let navigator = self.navigator(owning: route) else {
            self.pending = (route, models)
            return nil
        }
        self.pending = nil
        return navigator.navigate(to: route, carrying: models) ? navigator : nil
    }

    /// Asks every registered navigator's model resolver which route `key` opens, then navigates there.
    @discardableResult
    public func navigate(toKey key: String, carrying models: [ZRoute: ZRouteModels] = [:]) async -> ZNavigator? {
        for navigator in self.navigators {
            if let route = try? await navigator.resolver.models.route(forKey: key) {
                return self.navigate(to: route, carrying: models)
            }
        }
        return nil
    }

    private func prune() {
        self.entries.removeAll { $0.navigator == nil }
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
private struct ZNavigationHubKey: EnvironmentKey {
    static let defaultValue: ZNavigationHub? = nil
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension EnvironmentValues {
    /// The app's ``ZNavigationHub``, if one was installed with `zNavigationHub(_:)`.
    public var zNavigationHub: ZNavigationHub? {
        get { self[ZNavigationHubKey.self] }
        set { self[ZNavigationHubKey.self] = newValue }
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension View {
    /// Makes `hub` the ``ZNavigationHub`` every ``ZNavigationScope`` below registers with.
    public func zNavigationHub(_ hub: ZNavigationHub) -> some View {
        self.environment(\.zNavigationHub, hub)
    }
}
