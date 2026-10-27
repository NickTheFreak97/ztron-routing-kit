import RoutingKit
import SwiftUI

/// Path to models, used when nothing was carried by the pushing screen (deep links, restoration).
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public protocol ZRouteModelResolver {
    /// Whether this resolver can produce models for `route`. A structural answer: the trie answers "is there a screen".
    func canResolve(_ route: ZRoute) -> Bool

    /// Synchronous fast path: a cache hit, or "nothing needed". `nil` means "go async".
    ///
    /// It is what lets a destination render in the same frame when its models are already known, instead of
    /// showing a loading frame first.
    func cachedModels(for route: ZRoute) -> ZRouteModels?

    /// Loads the models for `route`. Called once per push, off the fast path only.
    func models(for route: ZRoute) async throws -> ZRouteModels

    /// An external identifier (a Spotlight item, a URL slug) to the full route it opens; `nil` when unknown.
    func route(forKey key: String) async throws -> ZRoute?
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension ZRouteModelResolver {
    public func cachedModels(for route: ZRoute) -> ZRouteModels? { nil }

    public func route(forKey key: String) async throws -> ZRoute? { nil }
}

/// A model resolver for apps whose screens need nothing beyond app-level objects.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct ZEmptyModelResolver: ZRouteModelResolver {
    public init() {}

    public func canResolve(_ route: ZRoute) -> Bool { true }

    public func cachedModels(for route: ZRoute) -> ZRouteModels? { ZRouteModels.empty }

    public func models(for route: ZRoute) async throws -> ZRouteModels { ZRouteModels.empty }
}

/// The registered view closure together with the `Parameters` the trie lookup filled for its route.
///
/// Returning the bare closure would lose the captured parameters (`parameters.get("game")` and the like), which
/// the registered closures read.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct ZResolvedScreen {
    public let parameters: Parameters
    public let build: (Parameters) -> any View

    public init(parameters: Parameters, build: @escaping (Parameters) -> any View) {
        self.parameters = parameters
        self.build = build
    }

    /// Invokes the registered closure. ``ZRouteDestinationView`` calls this exactly once per push.
    @MainActor
    public func makeView() -> any View { self.build(self.parameters) }
}

/// From a route to a screen, with the models that screen needs.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public protocol ZRouteResolver {
    /// Whether a screen is registered for `route`.
    func canResolve(_ route: ZRoute) -> Bool

    /// The registered closure, unchanged, plus its parameters.
    func screen(for route: ZRoute) -> ZResolvedScreen?

    /// Where the models come from when the pushing screen carried none.
    var models: any ZRouteModelResolver { get }

    /// Objects every destination at `route` receives in addition to its models, created once per push and stable
    /// for the destination's lifetime: a breadcrumb, a per-screen scope. Defaults to ``ZRouteModels/empty``.
    func scope(for route: ZRoute) -> ZRouteModels
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension ZRouteResolver {
    public func scope(for route: ZRoute) -> ZRouteModels { ZRouteModels.empty }
}

/// Wraps a `TrieRouter` whose output builds a view. No registration is touched.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class ZTrieRouteResolver: ZRouteResolver {
    public typealias Builder = (Parameters) -> any View

    private let router: TrieRouter<Builder>
    private let scopeProvider: ((ZRoute) -> ZRouteModels)?
    public let models: any ZRouteModelResolver

    /// Routes with fewer segments never resolve. ZombieTron registers `[.anything]` as a single-segment 404, and a
    /// route is never a single segment, so with the default of 2 that fallback cannot be mistaken for a screen.
    public let minimumSegments: Int

    /// - Parameters:
    ///   - router: The app's route table.
    ///   - models: Where the models come from when the pushing screen carried none.
    ///   - minimumSegments: See ``minimumSegments``.
    ///   - scope: Builds the per-destination objects of ``scope(for:)``; `nil` means none.
    public init(
        router: TrieRouter<Builder>,
        models: any ZRouteModelResolver = ZEmptyModelResolver(),
        minimumSegments: Int = 2,
        scope: ((ZRoute) -> ZRouteModels)? = nil
    ) {
        self.router = router
        self.models = models
        self.minimumSegments = minimumSegments
        self.scopeProvider = scope
    }

    public func canResolve(_ route: ZRoute) -> Bool {
        self.screen(for: route) != nil
    }

    public func screen(for route: ZRoute) -> ZResolvedScreen? {
        guard route.segments.count >= self.minimumSegments else { return nil }
        var parameters = Parameters()
        guard let build = self.router.route(path: route.segments, parameters: &parameters) else { return nil }
        return ZResolvedScreen(parameters: parameters, build: build)
    }

    public func scope(for route: ZRoute) -> ZRouteModels {
        self.scopeProvider?(route) ?? ZRouteModels.empty
    }
}
