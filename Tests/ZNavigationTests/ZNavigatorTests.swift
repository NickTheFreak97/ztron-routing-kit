import Combine
import SwiftUI
import XCTest

@testable import ZNavigation

/// Model-level behaviour of the navigator on both backends, without a window.
@MainActor
final class ZNavigatorTests: XCTestCase {
    private typealias Mini = NavMiniatureResolver

    private func makeNavigator(
        _ backend: ZNavigationBackend,
        staggerDelay: TimeInterval = 0.1
    ) -> (navigator: ZNavigator, resolver: NavMiniatureResolver) {
        let resolver = NavMiniatureResolver(recorder: NavProbeRecorder())
        let navigator = ZNavigator(root: Mini.home, resolver: resolver, backend: backend, staggerDelay: staggerDelay)
        return (navigator, resolver)
    }

    private let backends: [ZNavigationBackend] = [.navigationStack, .navigationView]

    func testAutomaticResolvesToAnExplicitBackend() {
        let (navigator, _) = self.makeNavigator(.automatic)
        XCTAssertNotEqual(navigator.backend, .automatic)
        XCTAssertEqual(navigator.backend, ZNavigationBackend.automatic.resolved)
    }

    func testPushAppendsOneLevel() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            XCTAssertEqual(navigator.current, Mini.home)
            XCTAssertTrue(navigator.push("A"))
            XCTAssertEqual(navigator.stack, [Mini.routeA], "\(backend)")
            XCTAssertEqual(navigator.current, Mini.routeA)
            XCTAssertEqual(navigator.path, [">", "home", "A"])
            XCTAssertEqual(navigator.depth, 1)
            XCTAssertTrue(navigator.push(Mini.routeB))
            XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB], "\(backend)")
        }
    }

    func testNavigateExpandsEveryPrefixBeyondRoot() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            XCTAssertTrue(navigator.navigate(to: [">", "home", "A", "B", "C"]))
            XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeC], "\(backend)")
            XCTAssertFalse(navigator.navigate(to: [">", "about"]))
            XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeC], "a refused navigation changes nothing")
            XCTAssertEqual(navigator.refusals.count, 1)
        }
    }

    func testPopVariants() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            navigator.navigate(to: Mini.routeC)
            XCTAssertTrue(navigator.pop())
            XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB], "\(backend)")
            XCTAssertTrue(navigator.pop(to: 2), "popping to the current depth is a no-op that succeeds")
            XCTAssertFalse(navigator.pop(to: 3), "popping to a depth beyond the stack is refused")
            XCTAssertFalse(navigator.pop(to: -1))
            XCTAssertTrue(navigator.popToRoot())
            XCTAssertEqual(navigator.stack, [], "\(backend)")
            XCTAssertEqual(navigator.current, Mini.home)
            XCTAssertTrue(navigator.pop(), "popping an empty stack is a no-op that succeeds")
        }
    }

    func testReplaceLastKeepsDepth() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            navigator.navigate(to: Mini.routeC)
            XCTAssertTrue(navigator.replaceLast(with: Mini.routeD))
            XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD], "\(backend)")
            XCTAssertFalse(navigator.replaceLast(with: Mini.routeX))
            XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD])

            let (empty, _) = self.makeNavigator(backend)
            XCTAssertTrue(empty.replaceLast(with: Mini.routeA), "on an empty stack replaceLast behaves like push")
            XCTAssertEqual(empty.stack, [Mini.routeA])
        }
    }

    func testSetStackRefusesUnknownRoutesAndRecordsTheReason() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            navigator.push("A")
            XCTAssertFalse(navigator.setStack([Mini.routeA, Mini.routeX]))
            XCTAssertEqual(navigator.stack, [Mini.routeA], "\(backend)")
            XCTAssertEqual(navigator.refusals.count, 1)
            XCTAssertTrue(navigator.refusals[0].contains("does not resolve"), navigator.refusals[0])
            XCTAssertFalse(navigator.push("X"))
            XCTAssertFalse(navigator.canRoute(Mini.routeX))
        }
    }

    func testSetStackRefusesRoutesNotBelowRoot() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            XCTAssertFalse(navigator.setStack([[">", "about"]]))
            XCTAssertFalse(navigator.setStack([Mini.home]), "the root itself is never a stack entry")
            XCTAssertEqual(navigator.stack, [], "\(backend)")
            XCTAssertEqual(navigator.refusals.count, 2)
            XCTAssertFalse(navigator.canRoute(Mini.home))
            XCTAssertTrue(navigator.canRoute(Mini.routeA))
        }
    }

    func testCarriedModelsFollowTheirRouteAndArePrunedOnPop() {
        final class Carried: ObservableObject {}
        for backend in self.backends {
            let (navigator, resolver) = self.makeNavigator(backend)
            resolver.asyncRoutes = [Mini.routeA, Mini.routeB]
            XCTAssertNil(navigator.models(for: Mini.routeA), "nothing carried and nothing cached: go async")

            let carried = Carried()
            navigator.push("A", carrying: ZRouteModels(carried))
            XCTAssertTrue(navigator.models(for: Mini.routeA)?.object(of: Carried.self) === carried, "\(backend)")

            navigator.navigate(to: Mini.routeC, carrying: [Mini.routeB: ZRouteModels(Carried())])
            XCTAssertNotNil(navigator.models(for: Mini.routeB))
            XCTAssertNotNil(navigator.models(for: Mini.routeA), "A is still on the stack, so its models are kept")

            navigator.pop(to: 1)
            XCTAssertNil(navigator.models(for: Mini.routeB), "B was popped: its carried models are pruned")
            XCTAssertNotNil(navigator.models(for: Mini.routeA))

            resolver.asyncRoutes.insert(Mini.routeX)
            resolver.asyncRoutes.insert(Mini.routeX)
            XCTAssertFalse(navigator.push(Mini.routeX, carrying: ZRouteModels(Carried())))
            XCTAssertNil(navigator.models(for: Mini.routeX), "a refused push keeps nothing")
        }
    }

    func testNavigationStackBackendMaterialisesPushesAndPopsImmediately() {
        let (navigator, _) = self.makeNavigator(.navigationStack)
        navigator.navigate(to: Mini.routeC)
        XCTAssertEqual(navigator.materialised, navigator.stack)
        XCTAssertTrue(navigator.isSettled)
        XCTAssertEqual(navigator.applied, 3)
        navigator.pop()
        XCTAssertTrue(navigator.isSettled)
        navigator.popToRoot()
        XCTAssertTrue(navigator.isSettled)
    }

    func testNavigationStackBackendReplacesAnEntryAsPopThenPush() {
        let (navigator, _) = self.makeNavigator(.navigationStack, staggerDelay: 0.1)
        navigator.navigate(to: Mini.routeC)
        navigator.replaceLast(with: Mini.routeD)
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD], "the model changes once, immediately")
        XCTAssertEqual(navigator.materialised, [Mini.routeA, Mini.routeB], "the screen pops first")
        XCTAssertFalse(navigator.isSettled)

        // The container writing back what it shows is not a user pop.
        navigator.stackBinding.wrappedValue = [Mini.routeA, Mini.routeB]
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD])

        XCTAssertTrue(NavPump.pump(until: { navigator.isSettled }, timeout: 2))
        XCTAssertEqual(navigator.materialised, [Mini.routeA, Mini.routeB, Mini.routeD])

        // Jumping to another branch is the same two-step change; a newer change cancels the pending push.
        navigator.navigate(to: Mini.routeE)
        XCTAssertEqual(navigator.materialised, [Mini.routeA])
        navigator.popToRoot()
        NavPump.pump(0.3)
        XCTAssertEqual(navigator.stack, [])
        XCTAssertEqual(navigator.materialised, [], "a cancelled push never materialises a stale target")
    }

    func testLegacyBackendPopsAtOnceAndStaggersPushes() {
        let (navigator, _) = self.makeNavigator(.navigationView, staggerDelay: 0.1)
        navigator.navigate(to: Mini.routeC)
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeC], "the model changes once, immediately")
        XCTAssertEqual(navigator.materialised, [Mini.routeA], "the first level activates synchronously")
        XCTAssertFalse(navigator.isSettled)

        XCTAssertTrue(NavPump.pump(until: { navigator.materialised.count == 2 }, timeout: 2))
        XCTAssertEqual(navigator.materialised, [Mini.routeA, Mini.routeB])
        XCTAssertTrue(NavPump.pump(until: { navigator.isSettled }, timeout: 2))
        XCTAssertEqual(navigator.materialised, navigator.stack)

        // Pop two levels at once: materialised follows in one step.
        navigator.pop(to: 1)
        XCTAssertEqual(navigator.materialised, [Mini.routeA])
        XCTAssertTrue(navigator.isSettled)

        // Pop-then-push (replaceLast): the pop is immediate, the push waits for the stagger delay.
        navigator.push("B")
        XCTAssertTrue(NavPump.pump(until: { navigator.isSettled }, timeout: 2))
        navigator.replaceLast(with: Mini.routeE.appending("nope"))
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB], "refused: unchanged")
        navigator.pop()
        navigator.push("E")
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeE])
        XCTAssertTrue(NavPump.pump(until: { navigator.isSettled }, timeout: 2))
        XCTAssertEqual(navigator.materialised, [Mini.routeA, Mini.routeE])
    }

    func testLegacyBackendCancelsPendingPushesWhenTheTargetChanges() {
        let (navigator, _) = self.makeNavigator(.navigationView, staggerDelay: 0.1)
        navigator.navigate(to: Mini.routeC)
        navigator.popToRoot()
        XCTAssertEqual(navigator.stack, [])
        XCTAssertEqual(navigator.materialised, [])
        NavPump.pump(0.35)
        XCTAssertEqual(navigator.materialised, [], "cancelled pushes never materialise a level of a stale target")
        XCTAssertTrue(navigator.isSettled)
    }

    func testLegacyLinkDeactivationPopsTheModel() {
        let (navigator, _) = self.makeNavigator(.navigationView, staggerDelay: 0.05)
        navigator.navigate(to: Mini.routeC)
        NavPump.pump(until: { navigator.isSettled }, timeout: 2)

        // The system popped B (and C above it): the level-1 link reports it is no longer active.
        navigator.legacyLinkDeactivated(at: 1)
        XCTAssertEqual(navigator.stack, [Mini.routeA])
        XCTAssertEqual(navigator.materialised, [Mini.routeA])
        XCTAssertTrue(navigator.isSettled)

        // A deactivation at or beyond the current depth is a no-op.
        navigator.legacyLinkDeactivated(at: 1)
        navigator.legacyLinkDeactivated(at: 5)
        XCTAssertEqual(navigator.stack, [Mini.routeA])
    }

    func testLegacyLinkDeactivationEchoOfAProgrammaticPopIsIgnored() {
        let (navigator, _) = self.makeNavigator(.navigationView, staggerDelay: 0.05)
        navigator.navigate(to: Mini.routeC)
        NavPump.pump(until: { navigator.isSettled }, timeout: 2)

        // replaceLast pops C (materialised drops to [A, B]) and schedules the push of D.
        navigator.replaceLast(with: Mini.routeD)
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD])
        XCTAssertEqual(navigator.materialised, [Mini.routeA, Mini.routeB])

        // The system confirms the pop of level 2 one run-loop turn later: that is not a user pop.
        navigator.legacyLinkDeactivated(at: 2)
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD], "the echo must not pop D")
        XCTAssertTrue(NavPump.pump(until: { navigator.isSettled }, timeout: 2))
        XCTAssertEqual(navigator.materialised, [Mini.routeA, Mini.routeB, Mini.routeD])

        // A genuine user pop at an active level still works.
        navigator.legacyLinkDeactivated(at: 1)
        XCTAssertEqual(navigator.stack, [Mini.routeA])
    }

    func testStackBindingRoutesThroughSetStack() {
        let (navigator, _) = self.makeNavigator(.navigationStack)
        navigator.navigate(to: Mini.routeC)
        let binding = navigator.stackBinding
        XCTAssertEqual(binding.wrappedValue, [Mini.routeA, Mini.routeB, Mini.routeC], "the binding shows what is materialised")

        binding.wrappedValue = [Mini.routeA]
        XCTAssertEqual(navigator.stack, [Mini.routeA], "a system pop is a model change like any other")

        binding.wrappedValue = [Mini.routeA, Mini.routeX]
        XCTAssertEqual(navigator.stack, [Mini.routeA], "a refused value leaves the authoritative stack")
        XCTAssertEqual(navigator.refusals.count, 1)
    }

    func testPageViewReporterEmitsOncePerPathChange() {
        for backend in self.backends {
            let (navigator, _) = self.makeNavigator(backend)
            var emitted: [String] = []
            let reporter = ZPageViewReporter(navigator: navigator) { emitted.append($0) }
            navigator.navigate(to: Mini.routeC)
            navigator.setStack([Mini.routeA, Mini.routeB, Mini.routeC])
            navigator.pop()
            navigator.popToRoot()
            navigator.popToRoot()
            XCTAssertEqual(reporter.pages, [">/home", ">/home/A/B/C", ">/home/A/B", ">/home"], "\(backend)")
            XCTAssertEqual(emitted, reporter.pages)
            XCTAssertEqual(reporter.current, ">/home")
        }
    }

    func testNavigateToKeyAsksTheModelResolver() async {
        let (navigator, _) = self.makeNavigator(.navigationStack)
        let found = await navigator.navigate(toKey: "C")
        XCTAssertTrue(found)
        XCTAssertEqual(navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeC])
        let missing = await navigator.navigate(toKey: "nope")
        XCTAssertFalse(missing)
        XCTAssertEqual(navigator.refusals.count, 1)
    }

    func testScopeIsBuiltOncePerDestination() {
        let (navigator, resolver) = self.makeNavigator(.navigationStack)
        navigator.push("A")
        _ = ZDestinationState(route: Mini.routeA, navigator: navigator)
        XCTAssertEqual(resolver.scopesBuilt, [Mini.routeA])
    }

    func testDestinationStateResolvesCarriedModelsSynchronously() {
        let (navigator, resolver) = self.makeNavigator(.navigationStack)
        navigator.push("A")
        let ready = ZDestinationState(route: Mini.routeA, navigator: navigator)
        guard case .ready = ready.phase else { return XCTFail("cached models must render in the first frame") }
        XCTAssertEqual(resolver.recorder.resolveCounts["A"], 1, "the registered closure is invoked exactly once")

        resolver.asyncRoutes = [Mini.routeB]
        navigator.push("B")
        let loading = ZDestinationState(route: Mini.routeB, navigator: navigator)
        guard case .loading = loading.phase else { return XCTFail("no models yet: loading") }
        XCTAssertNil(resolver.recorder.resolveCounts["B"], "the closure is not invoked before the models exist")

        let failed = ZDestinationState(route: Mini.routeX, navigator: navigator)
        guard case .failed = failed.phase else { return XCTFail("an unregistered route never crashes") }
    }

    func testHubRegistersNavigatorsAndRoutesDeepLinks() async {
        let hub = ZNavigationHub()
        let (home, _) = self.makeNavigator(.navigationStack)
        let aboutResolver = NavMiniatureResolver(recorder: NavProbeRecorder())
        let about = ZNavigator(root: [">", "about"], resolver: aboutResolver, backend: .navigationStack)

        hub.register(home)
        hub.register(about)
        hub.register(home)
        XCTAssertEqual(hub.navigators.count, 2, "registering twice is a no-op")
        XCTAssertTrue(hub.navigator(for: Mini.home) === home)
        XCTAssertTrue(hub.navigator(owning: Mini.routeC) === home)
        XCTAssertNil(hub.navigator(owning: [">", "settings"]))

        XCTAssertTrue(hub.navigate(to: [">", "home", "A", "B"]) === home)
        XCTAssertEqual(home.stack, [Mini.routeA, Mini.routeB])
        XCTAssertNil(hub.navigate(to: [">", "home", "X"]), "a refused navigation returns nil and keeps nothing pending")

        let byKey = await hub.navigate(toKey: "C")
        XCTAssertTrue(byKey === home)
        XCTAssertEqual(home.stack, [Mini.routeA, Mini.routeB, Mini.routeC])

        hub.unregister(about)
        XCTAssertEqual(hub.navigators.count, 1)
    }

    func testHubReplaysAPendingNavigationWhenItsNavigatorRegisters() {
        let hub = ZNavigationHub()
        XCTAssertNil(hub.navigate(to: Mini.routeB), "nobody owns >/home yet: kept for later")
        let (home, _) = self.makeNavigator(.navigationStack)
        hub.register(home)
        XCTAssertEqual(home.stack, [Mini.routeA, Mini.routeB], "replayed on registration")
    }

    func testHubHoldsNavigatorsWeakly() {
        let hub = ZNavigationHub()
        var navigator: ZNavigator? = self.makeNavigator(.navigationStack).navigator
        hub.register(navigator!)
        XCTAssertEqual(hub.navigators.count, 1)
        navigator = nil
        XCTAssertEqual(hub.navigators.count, 0, "a navigator lives exactly as long as its tab's view")
    }
}
