#if canImport(UIKit) && !os(watchOS)
    import Combine
    import Foundation
    import SwiftUI
    import UIKit
    import XCTest

    @testable import ZNavigation

    /// Each scenario of the parity plan runs twice, once per explicit backend, in a `UIWindow` + `UIHostingController`
    /// with the run loop pumped between steps, against the miniature resolver.
    ///
    /// Always asserted equal across backends: the final stack and the probe identifier of the top screen. Init counts,
    /// resolve counts and the sequence of appearances are asserted equal where the plan requires it; multi-level jumps
    /// are allowed to instantiate and animate the intermediate levels differently, and every scenario prints its report
    /// so the differences are documented from data.
    @MainActor
    final class NavigationParityTests: XCTestCase {
        private typealias Mini = NavMiniatureResolver

        struct Report: Equatable {
            var stack: [ZRoute]
            var topProbe: String?
            var initCounts: [String: Int]
            var resolveCounts: [String: Int]
            var lifecycle: [String]

            /// Only the `appear:` events: when a screen is removed is delivered at different moments by the two backends.
            var appearances: [String] { self.lifecycle.filter { $0.hasPrefix("appear:") } }
        }

        enum Field: CaseIterable {
            case initCounts
            case resolveCounts
            case appearances
        }

        /// One hosted run: window + navigator + recorder.
        @MainActor
        final class Host {
            let backend: ZNavigationBackend
            let recorder = NavProbeRecorder()
            let driver = NavProbeDriver()
            let resolver: NavMiniatureResolver
            let navigator: ZNavigator
            let window: UIWindow

            init(backend: ZNavigationBackend, tabs: Bool, staggerDelay: TimeInterval) {
                self.backend = backend
                let recorder = self.recorder
                let driver = self.driver
                self.resolver = NavMiniatureResolver(recorder: recorder)
                self.navigator = ZNavigator(root: Mini.home, resolver: self.resolver, backend: backend, staggerDelay: staggerDelay)
                let navigator = self.navigator
                let shell = NavProbeShell(driver: driver) {
                    ZNavigationStack(navigator: navigator) { NavProbeRoot(recorder: recorder, driver: driver) }
                }
                let content: AnyView = tabs ? AnyView(NavProbeTabs(driver: driver) { shell }) : AnyView(shell)
                self.window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                self.window.rootViewController = UIHostingController(rootView: content)
                self.window.makeKeyAndVisible()
            }

            var label: String { "\(self.backend)" }

            /// The tag of the screen the navigator says is on top.
            var topTag: String {
                self.navigator.stack.last.flatMap { self.resolver.tag(for: $0) } ?? "root"
            }

            /// Pumps until the navigator is settled and the top screen has appeared, then until the lifecycle has been
            /// quiet for a while, so that covered screens have had a chance to report their disappearance. Animations are disabled
            /// by `setUp`. The hostless runner reports disappearances late, which is why only appearances are compared.
            @discardableResult
            func settle(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> Bool {
                let settled = NavPump.pump(
                    until: { self.navigator.isSettled && self.recorder.mounted[self.topTag] != nil },
                    timeout: timeout
                )
                XCTAssertTrue(
                    settled,
                    "\(self.label): did not settle on \(self.topTag); mounted \(self.recorder.mounted); events \(self.recorder.events)",
                    file: file,
                    line: line
                )
                // Then wait for the transition to finish: no lifecycle event for a while.
                var seen = self.recorder.events.count
                var quietSince = Date()
                NavPump.pump(
                    until: {
                        if self.recorder.events.count != seen {
                            seen = self.recorder.events.count
                            quietSince = Date()
                        }
                        return Date().timeIntervalSince(quietSince) > 0.6
                    },
                    timeout: 6
                )
                return settled
            }

            func report(since mark: Int) -> Report {
                Report(
                    stack: self.navigator.stack,
                    topProbe: self.recorder.mounted[self.topTag],
                    initCounts: self.recorder.initCounts,
                    resolveCounts: self.recorder.resolveCounts,
                    lifecycle: self.recorder.lifecycle(since: mark)
                )
            }

            /// The UIKit navigation controller both backends are built on.
            var navigationController: UINavigationController? {
                func find(_ controller: UIViewController?) -> UINavigationController? {
                    guard let controller = controller else { return nil }
                    if let navigation = controller as? UINavigationController {
                        return navigation
                    }
                    for child in controller.children {
                        if let found = find(child) {
                            return found
                        }
                    }
                    return find(controller.presentedViewController)
                }
                return find(self.window.rootViewController)
            }

            func tearDown() {
                self.window.isHidden = true
                self.window.rootViewController = nil
            }
        }

        /// Simulates the app shell: re-rendering it re-creates the container value, like `ZTronAppShield` does today.
        struct NavProbeShell<Content: View>: View {
            @ObservedObject var driver: NavProbeDriver
            let content: () -> Content

            init(driver: NavProbeDriver, @ViewBuilder content: @escaping () -> Content) {
                self.driver = driver
                self.content = content
            }

            var body: some View {
                VStack(spacing: 0) {
                    Text("shell \(self.driver.shellTick)").font(.caption2)
                    self.content()
                }
            }
        }

        struct NavProbeTabs<Content: View>: View {
            @ObservedObject var driver: NavProbeDriver
            let content: () -> Content

            init(driver: NavProbeDriver, @ViewBuilder content: @escaping () -> Content) {
                self.driver = driver
                self.content = content
            }

            var body: some View {
                TabView(selection: self.$driver.tab) {
                    self.content().tabItem { Text("home") }.tag(0)
                    Text("about").tabItem { Text("about") }.tag(1)
                }
            }
        }

        private var animationsWereEnabled = true

        override func setUp() {
            super.setUp()
            self.animationsWereEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
        }

        override func tearDown() {
            UIView.setAnimationsEnabled(self.animationsWereEnabled)
            super.tearDown()
        }

        // MARK: - Runner

        private func onBothBackends(
            _ name: String,
            tabs: Bool = false,
            staggerDelay: TimeInterval = 0.65,
            _ scenario: (Host) -> Report
        ) -> [ZNavigationBackend: Report] {
            var reports: [ZNavigationBackend: Report] = [:]
            for backend in [ZNavigationBackend.navigationStack, .navigationView] {
                let host = Host(backend: backend, tabs: tabs, staggerDelay: staggerDelay)
                host.settle()
                let report = scenario(host)
                reports[backend] = report
                print("PARITY \(name) \(backend): \(report)")
                host.tearDown()
                NavPump.pump(0.1)
            }
            return reports
        }

        private func assertParity(
            _ reports: [ZNavigationBackend: Report],
            comparing fields: Set<Field> = Set(Field.allCases),
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            guard let stack = reports[.navigationStack], let legacy = reports[.navigationView] else {
                return XCTFail("both backends must report", file: file, line: line)
            }
            XCTAssertEqual(stack.stack, legacy.stack, "final stack differs", file: file, line: line)
            XCTAssertEqual(stack.topProbe, legacy.topProbe, "top screen identity differs", file: file, line: line)
            if fields.contains(.initCounts) {
                XCTAssertEqual(stack.initCounts, legacy.initCounts, "init counts differ", file: file, line: line)
            }
            if fields.contains(.resolveCounts) {
                XCTAssertEqual(stack.resolveCounts, legacy.resolveCounts, "resolve counts differ", file: file, line: line)
            }
            if fields.contains(.appearances) {
                XCTAssertEqual(stack.appearances, legacy.appearances, "appear sequence differs", file: file, line: line)
            }
        }

        // MARK: - Scenarios

        // 1. push one level: stack [A], A appeared once.
        func testPushOneLevel() {
            let reports = self.onBothBackends("pushOneLevel") { host in
                let mark = host.recorder.mark()
                host.navigator.push("A")
                host.settle()
                XCTAssertEqual(host.navigator.stack, [Mini.routeA], host.label)
                XCTAssertEqual(host.recorder.count("appear:A", since: mark), 1, host.label)
                XCTAssertEqual(host.recorder.mounted["A"], "A#1", host.label)
                XCTAssertEqual(host.recorder.resolveCounts["A"], 1, "\(host.label): destination resolved once")
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 2. push three levels via navigate(to:): stack [A, B, C], C appeared once; back once: [A, B].
        func testNavigateThreeLevelsThenBack() {
            let reports = self.onBothBackends("navigateThreeLevels") { host in
                let mark = host.recorder.mark()
                host.navigator.navigate(to: [">", "home", "A", "B", "C"])
                host.settle()
                XCTAssertEqual(host.navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeC], host.label)
                XCTAssertEqual(host.recorder.count("appear:C", since: mark), 1, host.label)
                XCTAssertEqual(host.recorder.resolveCounts["C"], 1, host.label)
                XCTAssertEqual(host.recorder.mounted["C"], "C#1", host.label)

                host.navigator.pop()
                host.settle()
                XCTAssertEqual(host.navigator.stack, [Mini.routeA, Mini.routeB], host.label)
                XCTAssertEqual(host.recorder.mounted["B"], "B#1", host.label)
                return host.report(since: mark)
            }
            // Intermediate levels of a multi-level jump may be instantiated at different moments.
            self.assertParity(reports, comparing: [])
        }

        // 3. popToRoot from depth 3: stack [], same root instance.
        func testPopToRootFromDepthThree() {
            let reports = self.onBothBackends("popToRoot") { host in
                host.navigator.navigate(to: Mini.routeC)
                host.settle()
                let mark = host.recorder.mark()
                host.navigator.popToRoot()
                host.settle()
                XCTAssertEqual(host.navigator.stack, [], host.label)
                XCTAssertEqual(host.recorder.mounted["root"], "root#1", "\(host.label): the root's state survives")
                return host.report(since: mark)
            }
            self.assertParity(reports, comparing: [.appearances])
        }

        // 4. interactive back: UINavigationController.popViewController on the hosted controller updates the navigator.
        func testInteractiveBackWritesIntoTheNavigator() {
            let reports = self.onBothBackends("interactiveBack") { host in
                host.navigator.push("A")
                host.settle()
                host.navigator.push("B")
                host.settle()
                let mark = host.recorder.mark()

                guard let navigation = host.navigationController else {
                    XCTFail("\(host.label): no UINavigationController in the hosted hierarchy")
                    return host.report(since: mark)
                }
                navigation.popViewController(animated: false)
                let popped = NavPump.pump(until: { host.navigator.stack == [Mini.routeA] }, timeout: 5)
                XCTAssertTrue(popped, "\(host.label): the model never saw the system pop; stack \(host.navigator.stack)")
                host.settle()
                XCTAssertEqual(host.recorder.mounted["A"], "A#1", "\(host.label): A's state survived being covered")
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 5. replaceLast: depth unchanged, new top appeared, lower levels intact.
        func testReplaceLastKeepsDepthAndLowerLevels() {
            let reports = self.onBothBackends("replaceLast") { host in
                host.navigator.push("A")
                host.settle()
                host.navigator.push("B")
                host.settle()
                host.navigator.push("C")
                host.settle()
                let mark = host.recorder.mark()
                let initsBefore = host.recorder.initCounts

                host.navigator.replaceLast(with: Mini.routeD)
                host.settle()
                XCTAssertEqual(host.navigator.stack, [Mini.routeA, Mini.routeB, Mini.routeD], host.label)
                XCTAssertEqual(host.recorder.count("appear:D", since: mark), 1, host.label)
                XCTAssertEqual(host.recorder.mounted["D"], "D#1", host.label)
                XCTAssertEqual(host.recorder.initCounts["A"], initsBefore["A"], "\(host.label): A not re-created")
                XCTAssertEqual(host.recorder.initCounts["B"], initsBefore["B"], "\(host.label): B not re-created")
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 6. shell re-render churn: with [A, B] pushed, re-render the shell 10 times: zero extra inits, zero resolves,
        //    zero appear/disappear events.
        func testShellReRenderChurnLeavesDestinationsAlone() {
            let reports = self.onBothBackends("shellChurn") { host in
                host.navigator.push("A")
                host.settle()
                host.navigator.push("B")
                host.settle()
                let mark = host.recorder.mark()
                let initsBefore = host.recorder.initCounts
                let resolvesBefore = host.recorder.resolveCounts
                let bodiesBefore = host.recorder.bodyCounts

                for _ in 0..<10 {
                    host.driver.shellTick += 1
                    host.driver.rootTick += 1
                    NavPump.pump(0.05)
                }
                NavPump.pump(0.2)

                XCTAssertEqual(host.recorder.initCounts, initsBefore, "\(host.label): shell churn re-created a screen")
                XCTAssertEqual(host.recorder.resolveCounts, resolvesBefore, "\(host.label): shell churn re-resolved a route")
                XCTAssertEqual(host.recorder.lifecycle(since: mark), [], host.label)
                XCTAssertEqual(host.recorder.mounted["B"], "B#1", host.label)
                print("PARITY shellChurn \(host.backend) bodies before \(bodiesBefore) after \(host.recorder.bodyCounts)")
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 7. tab switch and back with [A, B] pushed: stack preserved, no re-inits.
        func testTabSwitchPreservesTheStack() {
            let reports = self.onBothBackends("tabSwitch", tabs: true) { host in
                host.navigator.push("A")
                host.settle()
                host.navigator.push("B")
                host.settle()
                let mark = host.recorder.mark()
                let initsBefore = host.recorder.initCounts

                host.driver.tab = 1
                NavPump.pump(0.4)
                host.driver.tab = 0
                host.settle()

                XCTAssertEqual(host.navigator.stack, [Mini.routeA, Mini.routeB], host.label)
                XCTAssertEqual(host.recorder.initCounts, initsBefore, "\(host.label): a tab switch re-created a screen")
                XCTAssertEqual(host.recorder.mounted["B"], "B#1", host.label)
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 8. unresolvable route: setStack refused, stack unchanged, no crash, nothing on screen changes.
        func testUnresolvableRouteIsRefusedWithoutChangingTheScreen() {
            let reports = self.onBothBackends("unresolvable") { host in
                host.navigator.push("A")
                host.settle()
                let mark = host.recorder.mark()

                XCTAssertFalse(host.navigator.setStack([Mini.routeX]), host.label)
                XCTAssertFalse(host.navigator.navigate(to: Mini.routeX), host.label)
                XCTAssertFalse(host.navigator.push("X"), host.label)
                XCTAssertFalse(host.navigator.canRoute(Mini.routeX), host.label)
                NavPump.pump(0.3)

                XCTAssertEqual(host.navigator.stack, [Mini.routeA], host.label)
                XCTAssertEqual(host.recorder.lifecycle(since: mark), [], host.label)
                XCTAssertEqual(host.navigator.refusals.count, 3, host.label)
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 9. identity is the path: popping and pushing the same route again gives a fresh screen, on both backends.
        func testIdentityIsThePathOnBothBackends() {
            let reports = self.onBothBackends("identity") { host in
                let mark = host.recorder.mark()
                host.navigator.push("A")
                host.settle()
                XCTAssertEqual(host.recorder.mounted["A"], "A#1", host.label)
                host.navigator.pop()
                host.settle()
                host.navigator.push("A")
                host.settle()
                XCTAssertEqual(host.recorder.mounted["A"], "A#2", "\(host.label): a new push is a new screen instance")
                XCTAssertEqual(host.recorder.initCounts["A"], 2, host.label)
                XCTAssertEqual(host.recorder.resolveCounts["A"], 2, host.label)
                return host.report(since: mark)
            }
            self.assertParity(reports)
        }

        // 10. deep link whose models arrive asynchronously: loading first, then the screen, resolved once.
        func testAsyncModelsShowLoadingThenTheScreenOnce() {
            let reports = self.onBothBackends("asyncModels") { host in
                host.resolver.asyncRoutes = [Mini.routeB]
                host.resolver.asyncDelay = 0.2
                let mark = host.recorder.mark()
                host.navigator.navigate(to: Mini.routeB)
                host.settle()
                XCTAssertEqual(host.navigator.stack, [Mini.routeA, Mini.routeB], host.label)
                XCTAssertEqual(host.recorder.resolveCounts["B"], 1, "\(host.label): the closure runs once the models exist")
                XCTAssertEqual(host.recorder.mounted["B"], "B#1", host.label)
                return host.report(since: mark)
            }
            self.assertParity(reports, comparing: [.resolveCounts])
        }
    }
#endif
