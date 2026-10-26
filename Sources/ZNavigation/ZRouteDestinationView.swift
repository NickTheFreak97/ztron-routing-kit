import Combine
import SwiftUI

/// Per-destination state: the screen resolved once, the models resolved once, both for the lifetime of one push.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
final class ZDestinationState: ObservableObject {
    enum Phase {
        case loading
        case ready(AnyView, ZRouteModels)
        case failed(String)
    }

    @Published private(set) var phase: Phase
    let route: ZRoute

    /// The resolver's per-destination objects (a compatibility breadcrumb, a per-screen scope): one bag per
    /// destination, stable for its lifetime.
    let scope: ZRouteModels
    private let screen: ZResolvedScreen?

    init(route: ZRoute, navigator: ZNavigator) {
        self.route = route
        self.scope = navigator.resolver.scope(for: route)
        self.screen = navigator.resolver.screen(for: route)
        guard let screen = self.screen else {
            self.phase = .failed("no registered route for \(route.id)")
            return
        }
        if let models = navigator.models(for: route) {
            // Carried (or cached) models: render in the same frame, exactly like today's link sites.
            self.phase = .ready(AnyView(screen.makeView()), models)
        } else {
            self.phase = .loading
        }
    }

    /// Deep link without carried models: await the model resolver, then invoke the closure once.
    func resolveIfNeeded(using navigator: ZNavigator) async {
        guard case .loading = self.phase, let screen = self.screen else { return }
        do {
            let models = try await navigator.resolver.models.models(for: self.route)
            guard !Task.isCancelled else { return }
            self.phase = .ready(AnyView(screen.makeView()), models)
        } catch {
            guard !Task.isCancelled else { return }
            self.phase = .failed("models for \(self.route.id) failed: \(error)")
        }
    }
}

/// Resolves once per push, injects once per push. The same view serves both backends.
///
/// The navigator is passed explicitly rather than read from the environment so that the state can resolve
/// synchronously inside the `@StateObject` initialiser, which gives carried models a first frame with the real
/// screen instead of a loading frame.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public struct ZRouteDestinationView: View {
    public let route: ZRoute
    private let navigator: ZNavigator

    /// Created once per identity, which is once per push: `NavigationStack` hosts one destination per path entry and
    /// the legacy chain gives each level the identity of its route.
    @StateObject private var state: ZDestinationState

    public init(route: ZRoute, navigator: ZNavigator) {
        self.route = route
        self.navigator = navigator
        self._state = StateObject(wrappedValue: ZDestinationState(route: route, navigator: navigator))
    }

    public var body: some View {
        self.content
            .task(id: self.route) { await self.state.resolveIfNeeded(using: self.navigator) }
    }

    @ViewBuilder
    private var content: some View {
        switch self.state.phase {
        case .ready(let view, let models):
            models.merging(self.state.scope).inject(into: view)
        case .loading:
            ProgressView()
        case .failed(let reason):
            ZRouteUnavailableView(route: self.route, reason: reason)
        }
    }
}

/// Shown instead of crashing when a route has no registration or its models cannot be loaded.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct ZRouteUnavailableView: View {
    let route: ZRoute
    let reason: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.square.dashed").font(.largeTitle)
            Text("This page is unavailable").font(.headline)
            Text(self.route.id).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(self.reason).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityIdentifier("ZRouteUnavailableView")
    }
}
