import Combine
import Foundation
import RoutingKit
import SwiftUI

@testable import ZNavigation

// Test doubles shared by the model-level and the hosted parity tests: a run-loop pump, a recorder, probe screens
// and a three-level miniature resolver. Nothing here renders a real app screen.

// MARK: - Run loop pumping

enum NavPump {
    /// Pumps the main run loop for `seconds`, in short slices.
    @MainActor
    static func pump(_ seconds: TimeInterval) {
        let end = Date(timeIntervalSinceNow: seconds)
        while Date() < end {
            RunLoop.main.run(until: min(end, Date(timeIntervalSinceNow: 0.02)))
        }
    }

    /// Pumps until `condition` holds or `timeout` elapses. Returns the final value of the condition.
    @MainActor
    @discardableResult
    static func pump(until condition: () -> Bool, timeout: TimeInterval = 8) -> Bool {
        let end = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }
}

// MARK: - Recorder

/// Main-thread-only recorder shared by every probe screen of one scenario.
@MainActor
final class NavProbeRecorder {
    /// "init:A", "appear:A", "disappear:A" in order of occurrence (bodies are counted, not sequenced).
    private(set) var events: [String] = []
    private(set) var initCounts: [String: Int] = [:]
    private(set) var bodyCounts: [String: Int] = [:]
    /// How many times the registered closure of a tag was invoked (== destination resolutions).
    private(set) var resolveCounts: [String: Int] = [:]
    /// tag -> probe identifier of the instance currently on screen (set on appear, cleared on disappear).
    private(set) var mounted: [String: String] = [:]

    /// Returns a deterministic probe identifier: "<tag>#<n-th init of that tag>".
    func noteInit(_ tag: String) -> String {
        self.initCounts[tag, default: 0] += 1
        self.events.append("init:\(tag)")
        return "\(tag)#\(self.initCounts[tag] ?? 0)"
    }

    func noteBody(_ tag: String) {
        self.bodyCounts[tag, default: 0] += 1
    }

    func noteResolve(_ tag: String) {
        self.resolveCounts[tag, default: 0] += 1
    }

    func noteAppear(_ tag: String, _ probe: String) {
        self.events.append("appear:\(tag)")
        self.mounted[tag] = probe
    }

    func noteDisappear(_ tag: String, _ probe: String) {
        self.events.append("disappear:\(tag)")
        if self.mounted[tag] == probe {
            self.mounted[tag] = nil
        }
    }

    func mark() -> Int { self.events.count }

    var lifecycle: [String] {
        self.events.filter { $0.hasPrefix("appear:") || $0.hasPrefix("disappear:") }
    }

    func lifecycle(since mark: Int) -> [String] {
        self.events.dropFirst(mark).filter { $0.hasPrefix("appear:") || $0.hasPrefix("disappear:") }
    }

    func count(_ event: String, since mark: Int = 0) -> Int {
        self.events.dropFirst(mark).filter { $0 == event }.count
    }
}

/// Counts `@StateObject` initialisations per screen; its `id` is the probe identifier.
@MainActor
final class NavProbeModel: ObservableObject {
    let id: String

    init(tag: String, recorder: NavProbeRecorder) {
        self.id = recorder.noteInit(tag)
    }
}

/// Test-only mutable inputs driven from the test (root state churn, tab selection).
@MainActor
final class NavProbeDriver: ObservableObject {
    @Published var rootTick = 0
    @Published var shellTick = 0
    @Published var tab = 0
}

// MARK: - Probe screens

/// A pushed screen: records init / body / appear / disappear and exposes its probe identifier.
@MainActor
struct NavProbeScreen: View {
    let tag: String
    let recorder: NavProbeRecorder
    @StateObject private var probe: NavProbeModel

    init(tag: String, recorder: NavProbeRecorder) {
        self.tag = tag
        self.recorder = recorder
        self._probe = StateObject(wrappedValue: NavProbeModel(tag: tag, recorder: recorder))
    }

    var body: some View {
        self.recorder.noteBody(self.tag)
        return VStack(spacing: 4) {
            Text("screen \(self.tag)").font(.headline)
            Text(self.probe.id).font(.caption.monospaced()).accessibilityIdentifier("probe.\(self.tag)")
        }
        .navigationTitle(self.tag)
        .onAppear { self.recorder.noteAppear(self.tag, self.probe.id) }
        .onDisappear { self.recorder.noteDisappear(self.tag, self.probe.id) }
    }
}

/// The root screen: owns `@State` that the test mutates through the driver (scenario 6) and a `ZRouteLink`.
@MainActor
struct NavProbeRoot: View {
    let recorder: NavProbeRecorder
    @ObservedObject var driver: NavProbeDriver
    @State private var localTick = 0
    @StateObject private var probe: NavProbeModel

    init(recorder: NavProbeRecorder, driver: NavProbeDriver) {
        self.recorder = recorder
        self.driver = driver
        self._probe = StateObject(wrappedValue: NavProbeModel(tag: "root", recorder: recorder))
    }

    var body: some View {
        self.recorder.noteBody("root")
        return VStack(spacing: 4) {
            Text("root \(self.probe.id)").font(.headline)
            Text("local \(self.localTick) driver \(self.driver.rootTick)").font(.caption)
            ZRouteLink("A") { Text("go to A") }
        }
        .navigationTitle("root")
        .onReceive(self.driver.$rootTick.dropFirst()) { _ in self.localTick += 1 }
        .onAppear { self.recorder.noteAppear("root", self.probe.id) }
        .onDisappear { self.recorder.noteDisappear("root", self.probe.id) }
    }
}

// MARK: - Miniature resolver

/// Three levels below `>/home`: A, A/B, A/B/C (+ A/B/D for replaceLast, A/E for a sibling), nothing else.
@MainActor
final class NavMiniatureResolver: ZRouteResolver, ZRouteModelResolver {
    static let home: ZRoute = [">", "home"]
    static let routeA = home.appending("A")
    static let routeB = routeA.appending("B")
    static let routeC = routeB.appending("C")
    static let routeD = routeB.appending("D")
    static let routeE = routeA.appending("E")
    /// Never registered.
    static let routeX = home.appending("X")

    let recorder: NavProbeRecorder
    private(set) var table: [ZRoute: String] = [routeA: "A", routeB: "B", routeC: "C", routeD: "D", routeE: "E"]
    /// Routes whose models are delivered asynchronously (exercises the loading phase).
    var asyncRoutes: Set<ZRoute> = []
    var asyncDelay: TimeInterval = 0.05
    /// Routes created once per destination by `scope(for:)`, recorded for the tests.
    private(set) var scopesBuilt: [ZRoute] = []

    init(recorder: NavProbeRecorder) {
        self.recorder = recorder
    }

    func tag(for route: ZRoute) -> String? { self.table[route] }

    // ZRouteResolver

    func canResolve(_ route: ZRoute) -> Bool { self.table[route] != nil }

    func screen(for route: ZRoute) -> ZResolvedScreen? {
        guard let tag = self.table[route] else { return nil }
        let recorder = self.recorder
        return ZResolvedScreen(parameters: Parameters()) { _ in
            recorder.noteResolve(tag)
            return NavProbeScreen(tag: tag, recorder: recorder)
        }
    }

    var models: any ZRouteModelResolver { self }

    func scope(for route: ZRoute) -> ZRouteModels {
        self.scopesBuilt.append(route)
        return ZRouteModels.empty
    }

    // ZRouteModelResolver

    func cachedModels(for route: ZRoute) -> ZRouteModels? {
        self.asyncRoutes.contains(route) ? nil : ZRouteModels.empty
    }

    func models(for route: ZRoute) async throws -> ZRouteModels {
        try await Task.sleep(nanoseconds: UInt64(self.asyncDelay * 1_000_000_000))
        return ZRouteModels.empty
    }

    func route(forKey key: String) async throws -> ZRoute? {
        self.table.first { $0.value == key }?.key
    }
}
