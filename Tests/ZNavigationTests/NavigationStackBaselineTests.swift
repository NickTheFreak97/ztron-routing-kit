#if canImport(UIKit) && !os(watchOS)
    import Combine
    import Foundation
    import SwiftUI
    import UIKit
    import XCTest

    @testable import ZNavigation

    /// Plain `NavigationStack(path:)` with `navigationDestination(for:)` and no ZNavigation code: records what SwiftUI
    /// itself does on this simulator, so that a difference seen in the parity suite can be attributed to SwiftUI or to
    /// the kit. Prints `BASELINE` lines; asserts only the model.
    @MainActor
    final class NavigationStackBaselineTests: XCTestCase {
        @MainActor
        final class PathModel: ObservableObject {
            @Published var path: [String] = []
        }

        struct Root: View {
            @ObservedObject var model: PathModel
            let recorder: NavProbeRecorder
            var destination: @MainActor (String, NavProbeRecorder) -> AnyView = {
                AnyView(NavProbeScreen(tag: $0, recorder: $1))
            }

            var body: some View {
                if #available(iOS 16.0, *) {
                    NavigationStack(path: self.$model.path) {
                        Text("root")
                            .navigationDestination(for: String.self) { tag in
                                self.destination(tag, self.recorder)
                            }
                    }
                } else {
                    Text("NavigationStack unavailable")
                }
            }
        }

        /// Mimics `ZRouteDestinationView`: the screen built once into a `@StateObject`, shown as `AnyView`, with the
        /// explicit identity and the task modifier switchable.
        @MainActor
        final class BoxState: ObservableObject {
            let view: AnyView

            init(tag: String, recorder: NavProbeRecorder) {
                self.view = AnyView(NavProbeScreen(tag: tag, recorder: recorder))
            }
        }

        struct BoxedDestination: View {
            let tag: String
            let useID: Bool
            let useTask: Bool
            @StateObject private var state: BoxState

            init(tag: String, recorder: NavProbeRecorder, useID: Bool, useTask: Bool) {
                self.tag = tag
                self.useID = useID
                self.useTask = useTask
                self._state = StateObject(wrappedValue: BoxState(tag: tag, recorder: recorder))
            }

            var body: some View {
                self.identified
                    .task(id: self.useTask ? self.tag : "") {}
            }

            @ViewBuilder
            private var identified: some View {
                if self.useID {
                    self.state.view.id(self.tag)
                } else {
                    self.state.view
                }
            }
        }

        /// One hosted plain `NavigationStack`.
        @MainActor
        final class Host {
            let recorder = NavProbeRecorder()
            let model = PathModel()
            let window: UIWindow

            init(destination: (@MainActor (String, NavProbeRecorder) -> AnyView)? = nil) {
                var root = Root(model: self.model, recorder: self.recorder)
                if let destination = destination {
                    root.destination = destination
                }
                self.window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                self.window.rootViewController = UIHostingController(rootView: root)
                self.window.makeKeyAndVisible()
            }

            /// Pumps until no lifecycle event has been recorded for a while.
            func quiet() {
                var seen = self.recorder.events.count
                var since = Date()
                NavPump.pump(
                    until: {
                        if self.recorder.events.count != seen {
                            seen = self.recorder.events.count
                            since = Date()
                        }
                        return Date().timeIntervalSince(since) > 0.6
                    },
                    timeout: 6
                )
            }

            func push(_ tag: String) {
                self.model.path.append(tag)
                NavPump.pump(until: { self.recorder.mounted[tag] != nil }, timeout: 5)
                self.quiet()
            }

            func tearDown() {
                self.window.isHidden = true
                self.window.rootViewController = nil
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

        func testSequentialPushesThenSameDepthReplacement() {
            guard #available(iOS 16.0, *) else { return }
            let host = Host()
            defer { host.tearDown() }
            host.quiet()
            for tag in ["A", "B", "C"] {
                host.push(tag)
            }
            print("BASELINE pushes: inits \(host.recorder.initCounts) events \(host.recorder.events)")

            host.model.path[2] = "D"
            let dAppeared = NavPump.pump(until: { host.recorder.mounted["D"] != nil }, timeout: 5)
            host.quiet()
            print(
                "BASELINE replace: dAppeared=\(dAppeared) path=\(host.model.path) inits \(host.recorder.initCounts) "
                    + "events \(host.recorder.events)"
            )
            XCTAssertEqual(host.model.path, ["A", "B", "D"])

            host.model.path = ["A"]
            NavPump.pump(until: { host.recorder.mounted["A"] != nil }, timeout: 5)
            host.quiet()
            print("BASELINE pop two: path=\(host.model.path) mounted \(host.recorder.mounted) events \(host.recorder.events)")
            XCTAssertEqual(host.model.path, ["A"])
        }

        /// Three sequential pushes through destination wrappers of increasing resemblance to `ZRouteDestinationView`,
        /// to attribute a re-created `@StateObject` to one of the wrapper's parts.
        func testSequentialPushesThroughWrappedDestinations() {
            guard #available(iOS 16.0, *) else { return }
            let variants: [(String, @MainActor (String, NavProbeRecorder) -> AnyView)] = [
                ("boxed", { AnyView(BoxedDestination(tag: $0, recorder: $1, useID: false, useTask: false)) }),
                ("boxed+id", { AnyView(BoxedDestination(tag: $0, recorder: $1, useID: true, useTask: false)) }),
                ("boxed+task", { AnyView(BoxedDestination(tag: $0, recorder: $1, useID: false, useTask: true)) }),
                ("boxed+id+task", { AnyView(BoxedDestination(tag: $0, recorder: $1, useID: true, useTask: true)) }),
            ]
            for (name, destination) in variants {
                let host = Host(destination: destination)
                host.quiet()
                for tag in ["A", "B", "C"] {
                    host.push(tag)
                }
                print("BASELINE variant=\(name) inits \(host.recorder.initCounts) events \(host.recorder.events)")
                host.tearDown()
                NavPump.pump(0.1)
            }
        }
    }
#endif
