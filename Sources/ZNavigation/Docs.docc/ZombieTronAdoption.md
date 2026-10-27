# Adopting ZTronNavigationKit in ZombieTron

The app-side routine, step by step, with the code each step needs. Every step builds and ships on its own.

## Overview

The kit's `main` publishes the `ZTronNavigationKit` product (module `ZNavigation`). Nothing in ZombieTron changes
until the app opts in; `ZTronAppShield` is never replaced, and the 427 `registerView(path:)` registrations are never
edited. The order below is the one from <doc:UnifiedNavigationDesign> section 6, made concrete. File paths are relative
to `ZombieTron/ZombieTron/`.

What the kit already guarantees, so the app does not have to: one navigation interface with identical behaviour on
`NavigationStack` (iOS 16+) and `NavigationView` (iOS 15), destinations resolved once per push, a same-depth
replacement done as pop-then-push on both backends, deep links through a hub, and a router that backtracks so a constant
never shadows a parameter route.

## Step 0: resolve the new product

1. In Xcode, Package Dependencies, update `ztron-routing-kit` to the current `main` (it is pinned to revision
   `a9fb1a82` in `Package.resolved`). `ZTronRouter` depends on the same package and keeps compiling: the routing-kit 4
   API it uses is unchanged.
2. Add the product `ZTronNavigationKit` to the ZombieTron target, next to `ZTronRoutingKit`.
3. Build. Nothing else changes yet; the router's matching is the only behavioural difference, and it is more
   permissive (backtracking), never less.

## Step 1: the database model resolver

The kit resolves *what* to show from the trie; the app resolves the *models* a screen needs when nothing was carried
by the pushing screen (Spotlight, URLs, restoration). The prototype under `Tests/NavigationTests/Prototype/` already
has this class; move it into the app target as `Routes/Navigation/DatabaseModelResolver.swift` with these changes:

- Imports: `import ZNavigation`, `import RoutingKit`, `import ZTronDataModel`, `import SQLite`; drop
  `@testable import ZombieTron`.
- The class is `@MainActor` (the protocol is); the lock goes away.
- ``ZRouteModels`` is a type-erased bag now: insert the objects instead of filling fields.
- `route(forToolKey:)` becomes `route(forKey:)`.

```swift
import Foundation
import RoutingKit
import SQLite
import ZNavigation
import ZTronDataModel

@MainActor
public final class DatabaseModelResolver: ZRouteModelResolver {
    public let home: ZRoute
    private var cache: [ZRoute: ZRouteModels] = [:]
    private var toolTable: [String: ZRoute]?

    public init(home: ZRoute = [">", "home"]) {
        self.home = home
    }

    /// Structural answer only; the trie answers "is there a screen".
    public func canResolve(_ route: ZRoute) -> Bool {
        guard let depth = route.depth(below: self.home) else { return false }
        return (1...4).contains(depth)
    }

    public func cachedModels(for route: ZRoute) -> ZRouteModels? {
        self.cache[route]
    }

    public func models(for route: ZRoute) async throws -> ZRouteModels {
        if let hit = self.cache[route] { return hit }
        let home = self.home
        let models = try await Task.detached(priority: .userInitiated) {
            try DatabaseModelResolver.load(route, home: home)
        }.value
        self.cache[route] = models
        return models
    }

    public func route(forKey key: String) async throws -> ZRoute? {
        if let table = self.toolTable { return table[key] }
        let home = self.home
        let table = try await Task.detached(priority: .userInitiated) {
            try DatabaseModelResolver.buildToolTable(home: home)
        }.value
        self.toolTable = table
        return table[key]
    }

    // The synchronous loaders are the prototype's, unchanged except for how the result is assembled:
    //
    //     var models = ZRouteModels()
    //     models.insert(game)                                  // SerializedGameModel
    //     models.insert(ZTronMapProvider(wrappedValue: nil))   // top-level selection
    //     ...
    //     models.insert(ZTronMapProvider(wrappedValue: sub))   // a map or a collection
    //     models.insert(try tool(db, game: gameName, map: rel[2], key: rel[3]))   // SerializedToolModel
    //     return models
}
```

`DBMS.transaction`, `CRUD.readAllGames`, `readAllMaps`, `readAllSubmaps` and `readTabsWithToolsForMap` are used exactly
as in the prototype's `load(_:home:)`, `buildToolTable(home:)`, `maps(_:game:master:)` and `tool(_:game:map:key:)`.

## Step 2: the compatibility breadcrumb

`sendViewAnalytics()`, `ProTipsSheet` and the sheet header read a `ZNavigationPath` from the environment. The kit's
resolver hands every destination a stable per-push "scope" bag, so the breadcrumb keeps working without touching those
files. New file `Routes/Navigation/ZNavigationPath + compat.swift`:

```swift
import ZNavigation

extension ZNavigationPath {
    /// The read-only breadcrumb for a route, built with the class's public API only.
    static func compat(_ route: ZRoute) -> ZNavigationPath {
        let draft = ZNavigationPath().getMutableCopy()        // starts at [">"]
        for segment in route.segments.dropFirst() {
            _ = draft.appending(segment)
        }
        return draft.getImmutableCopy()
    }
}
```

## Step 3: the app's resolver

One place builds the resolver over the real route table. New file `Routes/Navigation/ZombieTronRouteResolver.swift`:

```swift
import RoutingKit
import ZNavigation

enum ZombieTronRouteResolver {
    @MainActor
    static func make(routing: RoutingServiceProvider) -> any ZRouteResolver {
        ZTrieRouteResolver(
            router: routing.router,                       // internal to the app module: fine here
            models: DatabaseModelResolver(),
            scope: { ZRouteModels(ZNavigationPath.compat($0)) }
        )
    }
}
```

`minimumSegments` keeps its default of 2, so the shell's single-segment `[.anything]` 404 route can never be mistaken
for a screen.

## Step 4: install the container where the container is created today

`withAppropriateNavigationView()` is the only place that creates a `NavigationStack` or a `NavigationView`, once per
tab from inside the shell. Rewrite its body on ``ZNavigationScope``, which owns the tab's navigator and registers it
with the hub (step 6). The iOS 15 appearance setup in the modifier's initialiser stays as it is. File
`Extensions/View Extensions/View + withAppropriateNavigationView.swift`:

```swift
import SwiftUI
import ZNavigation
import ZTronTheme

public extension View {
    func withAppropriateNavigationView(
        root: ZRoute = [">", "home"],
        theme: any ZTronTheme = ZTronThemeProvider.default()
    ) -> some View {
        self.modifier(AppropriateNavigationView(root: root, theme: theme))
    }
}

fileprivate struct AppropriateNavigationView: ViewModifier {
    private let root: ZRoute
    private let theme: any ZTronTheme
    @EnvironmentObject private var routingService: RoutingServiceProvider

    init(root: ZRoute, theme: any ZTronTheme) {
        self.root = root
        self.theme = theme
        // ... the existing `if #unavailable(iOS 16.0)` UITabBar / UINavigationBar appearance setup, unchanged
    }

    func body(content: Content) -> some View {
        let routing = self.routingService
        return ZNavigationScope(root: self.root, resolver: { ZombieTronRouteResolver.make(routing: routing) }) {
            content
                .appToolbar()
        }
    }
}
```

Two notes. The old body's `.injectNavBarHeight(self.navbarHeight)` on the iOS 15 branch injected a value that was
never set; drop it or apply it around the scope. And the About tab must get its own root, or two navigators would
share `>/home` and the hub would keep only the last one: in `ZTronAppShield` the About call becomes
`.withAppropriateNavigationView(root: [">", "about"])`. That is one argument on one line; nothing else in the shell
changes, and with no routes registered below `>/about` its links are simply disabled.

After this step the app runs unchanged: the existing `NavigationLink(destination:)` sites still work inside both
backends, and every pushed screen already gets the compatibility breadcrumb from the scope.

## Step 5: links that push a value

Replace the three `NavigationLink(destination:)` sites with ``ZRouteLink``, carrying the models the screen already
holds, so the destination renders in its first frame exactly as today.

`Commander/Home/ZTronHome.swift`, inside the grid:

```swift
ZRouteLink(game.getName(), carrying: ZRouteModels(game, ZTronMapProvider(wrappedValue: nil))) {
    // the existing ZStack with the game logo, unchanged
}
.disabled(!self.model.shouldMakeActive(game.getName()))
```

`Commander/Maps/ZTronMapSelection.swift`, inside the `ForEach`:

```swift
ZRouteLink(map.getSerializedMapModel().getName(), carrying: ZRouteModels(self.gameData, ZTronMapProvider(wrappedValue: map))) {
    // the existing banner image, unchanged
}
.id(map.getSerializedMapModel().getName())
```

`Commander/Tools/ZTronMapToolsPicker.swift`, inside the tools grid:

```swift
ZRouteLink(tool.getName(), carrying: ZRouteModels(self.map, tool)) {
    self.ToolViewWithContext(for: tool)
}
```

`ZRouteLink` disables itself when the route does not resolve, so `routeAvailabilityCache`, `computeToolAvailability`
and the `allowsHitTesting(self.isToolAvailable(tool))` modifier can go; if the availability is still needed elsewhere,
read it from the navigator in the environment: `@EnvironmentObject var navigator: ZNavigator` and
`navigator.canRoute(navigator.current.appending(tool.getName()))`. The `destinationView(for:)` builders and the
per-link `ZNavigationPath` drafts are no longer called and can be deleted.

Behaviour to know: `ZRouteLink` is a `Button` with the `.plain` style on both backends, which is also why it never
builds its destination eagerly.

## Step 6: the hub and Spotlight

Deep links need a receiver that is not the shell. `ZombieTronApp.swift` creates the hub, installs it on the shield
with a modifier (the shield itself is untouched) and handles Spotlight continuation:

```swift
import CoreSpotlight
import ZNavigation

@StateObject private var navigationHub = ZNavigationHub()

// in `body`, on ZTronAppShield(), next to the existing environmentObject calls:
.zNavigationHub(self.navigationHub)
.onContinueUserActivity(CSSearchableItemActionType) { activity in
    guard let key = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
    Task { await self.navigationHub.navigate(toKey: key) }
}
```

The item's unique identifier is the tool key; `DatabaseModelResolver.route(forKey:)` recovers game, collection and map
from the database, so the stored Spotlight metadata is not needed. A navigation that arrives before the Home tab's
navigator exists (cold start) is kept by the hub and replayed when the navigator registers. All Spotlight content lives
under `>/home`, the tab the shell shows first; switching tabs for a deep link would need the shell to observe the hub
and is out of scope.

URL schemes and state restoration use the same primitive: parse to segments, `navigationHub.navigate(to:)`; encode
`navigator.stack` (it is `Codable`) in `SceneStorage` to restore.

## Step 7: page views from the navigator

Today every return to a screen fires `onAppear` again and the throttled publisher drops events during fast navigation.
Move the signal to ``ZPageViewReporter``: one page name per path change, identical on both backends. The app reaches
each navigator through the hub, so the reporters live next to it in `ZombieTronApp.swift`:

```swift
import Mixpanel

@State private var pageViewReporters: [ZRoute: ZPageViewReporter] = [:]

// on ZTronAppShield(), after .zNavigationHub(self.navigationHub):
.onReceive(self.navigationHub.objectWillChange.receive(on: RunLoop.main)) { _ in
    for navigator in self.navigationHub.navigators where self.pageViewReporters[navigator.root] == nil {
        self.pageViewReporters[navigator.root] = ZPageViewReporter(navigator: navigator) { page in
            Mixpanel.mainInstance().track(event: "Page View", properties: ["Page Name": page])
        }
    }
}
```

Then make `SendViewAnalyticsModifier.body` return `content` unchanged, and remove `.sendViewAnalytics()` from the
route files in one mechanical pass when convenient. `ThrottleProvider` loses its only sender.

## Step 8: remove what the kit replaced

- `Tests/NavigationTests/Prototype/`: delete the library files the kit now provides (`ZRoute`, `ZNavigator`,
  `ZNavigationBackend`, `ZNavigationStack`, `ZRouteDestinationView`, `ZRouteLink`, `ZRouteResolver`,
  `PageViewReporter`, `Miniature/`). `DatabaseModelResolver.swift` moved to the app in step 1.
- Keep `NavigationPathTests`, `NavigationRouteResolutionTests` and `NavigationTestSupport`: they exercise the app's
  real route table and the breadcrumb class, both still in use.
- `docs/navigation/UNIFIED-NAVIGATION-DESIGN.md` is superseded by <doc:UnifiedNavigationDesign> in the kit.
- `initialPath` / `initialView` in the shell stay: the resolved Home view is simply the root content of the container.
  `ZNavigationPath.WritableDraft.droppingLast(_:)` has no caller left and can go.

## Step 9: verify

1. Home, game, map, tool, Back at every level; the Back button pops exactly one level each time.
2. Pro Tips sheet and header still show the right path (the compatibility breadcrumb).
3. Mixpanel receives one "Page View" per path change and none on return (reporter), not two.
4. A Spotlight result opens the tool, from a cold start and while the app is running.
5. Shell re-renders (keyboard, rotation, tab switch) no longer rebuild the pushed screens: tool state survives.
6. On an iOS 15 device, if one is available: a three-level deep link animates in three steps; nothing else differs.

What cannot be verified in the kit: iOS 15 runtime behaviour (no simulator runtime can be installed) and the
`BottomSheet`, `introspect(.tabView)` and `appToolbar()` interactions inside the new container, which must be checked
on device.
