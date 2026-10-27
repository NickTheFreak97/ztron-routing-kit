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
by the pushing screen (Spotlight, URLs, restoration). The resolver below loads them exactly the way the three screens
load them today, call for call:

| Screen | Loads with | Injects into its destination |
| --- | --- | --- |
| `ZTronHomePageModel.loadGames` | `CRUD.readAllGames(for:options: .all)` | the `SerializedGameModel` and `ZTronMapProvider(wrappedValue: nil)` |
| `ZTronMapSelection.loadMaps` | `CRUD.readAllMaps` / `readAllSubmaps(master:)`, `options: .all`, `limitToFirstLevelMasters: true`, paired with `numberOfSlaves` into `ZTronMapModel` | the game and `ZTronMapProvider(wrappedValue: map)` |
| `ZTronMapToolsPicker.loadToolsAndTabs` | `CRUD.readTabsWithToolsForMap(for:game:map:)` | the `SerializedMapModel`, the `SerializedToolModel`, plus the game and provider inherited from above |

Every destination receives the whole set its level received before, inherited objects included, because the
`NavigationStack` backend does not inherit the environment of the pushing screen. The reads run inside one
`DBMS.transaction(#function)` on a detached background task, as the screens do; the difference is that a failure is
thrown back to the kit, which shows its "unavailable" view instead of the screens' `fatalError`.

New file `Routes/Navigation/DatabaseModelResolver.swift`, complete:

```swift
import Foundation
import RoutingKit
import SQLite
import ZNavigation
import ZTronDataModel

/// Loads, for a route the trie accepts, the environment objects the screen at that route reads today. Used only
/// when the pushing screen carried nothing: Spotlight, URL schemes, state restoration.
@MainActor
public final class DatabaseModelResolver: ZRouteModelResolver {
    public let home: ZRoute
    private var cache: [ZRoute: ZRouteModels] = [:]
    private var toolRoutes: [String: ZRoute]?

    public init(home: ZRoute = [">", "home"]) {
        self.home = home
    }

    // MARK: ZRouteModelResolver

    /// Structural answer: one to four segments below home (game; map or collection; map in a collection; tool).
    public func canResolve(_ route: ZRoute) -> Bool {
        guard let depth = route.depth(below: self.home) else { return false }
        return (1...4).contains(depth)
    }

    public func cachedModels(for route: ZRoute) -> ZRouteModels? {
        self.cache[route]
    }

    public func models(for route: ZRoute) async throws -> ZRouteModels {
        if let hit = self.cache[route] { return hit }
        guard let depth = route.depth(below: self.home), depth > 0 else { return .empty }
        let segments = Array(route.segments.suffix(depth))
        let loaded = try await Task.detached(priority: .background) {
            try Loader.load(segments)
        }.value
        let models = loaded.models()
        self.cache[route] = models
        return models
    }

    /// Spotlight: the item identifier is the tool key (`SpotlightIndexableItem(id: tool.getName())`); the full
    /// route, collections included, comes from one scan of the database, cached afterwards.
    public func route(forKey key: String) async throws -> ZRoute? {
        if let routes = self.toolRoutes { return routes[key] }
        let home = self.home
        let routes = try await Task.detached(priority: .background) {
            try Loader.toolRoutes(below: home)
        }.value
        self.toolRoutes = routes
        return routes[key]
    }

    // MARK: What a level receives

    /// The pieces found for a route. All of them are `Sendable`, so they cross back to the main actor, where the
    /// environment bag is assembled.
    private struct Loaded: Sendable {
        var game: SerializedGameModel?
        /// `nil` for the game level; the map or the collection otherwise.
        var map: ZTronMapModel?
        var tool: SerializedToolModel?

        /// Home injects the game and an empty provider; the map selection injects the game and the provider of the
        /// map or collection; the tools picker adds the serialised map and the tool.
        @MainActor
        func models() -> ZRouteModels {
            var models = ZRouteModels()
            if let game = self.game {
                models.insert(game)
            }
            models.insert(ZTronMapProvider(wrappedValue: self.map))
            if let map = self.map {
                models.insert(map.getSerializedMapModel())
            }
            if let tool = self.tool {
                models.insert(tool)
            }
            return models
        }
    }

    // MARK: Database reads, as the screens do them

    private enum Loader {
        /// `segments` are the route's segments below home: `[game]`, `[game, map]`, `[game, collection, map]`,
        /// `[game, map, tool]` or `[game, collection, map, tool]`. Whatever is not found is left out, never thrown:
        /// a constant route such as `nazi zombies outfits` is not a map, yet its screen must still open.
        static func load(_ segments: [String]) throws -> Loaded {
            var loaded = Loaded()
            var failure: Error?

            try DBMS.transaction(#function) { dbConnection in
                do {
                    // As ZTronHomePageModel.loadGames.
                    let gamesResult = try CRUD.readAllGames(for: dbConnection, options: .all)
                    guard let games = gamesResult[ReadGamesOption.games] as? [SerializedGameModel],
                        let game = games.first(where: { $0.getName() == segments[0] })
                    else { return TransactionResult.commit }
                    loaded.game = game
                    guard segments.count > 1 else { return TransactionResult.commit }

                    // As ZTronMapSelection.loadMaps with no master: the second segment is a map or a collection.
                    let topLevel = try maps(dbConnection, game: game.getName(), master: nil)
                    guard let second = topLevel.first(where: { $0.getSerializedMapModel().getName() == segments[1] })
                    else { return TransactionResult.commit }
                    loaded.map = second
                    guard segments.count > 2 else { return TransactionResult.commit }

                    if second.getSubmapsCount() > 0 {
                        // >/home/:game/<collection>/:map(/:tool): as loadMaps with the collection as master.
                        let submaps = try maps(dbConnection, game: game.getName(), master: second.getSerializedMapModel().getName())
                        guard let sub = submaps.first(where: { $0.getSerializedMapModel().getName() == segments[2] })
                        else { return TransactionResult.commit }
                        loaded.map = sub
                        if segments.count > 3 {
                            loaded.tool = try tool(dbConnection, game: game.getName(), map: segments[2], named: segments[3])
                        }
                    } else {
                        // >/home/:game/:map/:tool
                        loaded.tool = try tool(dbConnection, game: game.getName(), map: segments[1], named: segments[2])
                    }
                    return TransactionResult.commit
                } catch {
                    failure = error
                    return TransactionResult.rollback
                }
            }

            if let failure = failure { throw failure }
            return loaded
        }

        /// As `ZTronMapSelection.loadMaps`: `readAllMaps` for the game, `readAllSubmaps` below a master, both with
        /// `options: .all` and `limitToFirstLevelMasters: true`, each map paired with its number of submaps.
        static func maps(_ dbConnection: Connection, game: String, master: String?) throws -> [ZTronMapModel] {
            let result: [ReadMapOptions: [(any ReadMapOptional)?]]
            if let master = master {
                result = try CRUD.readAllSubmaps(
                    for: dbConnection,
                    master: master,
                    game: game,
                    options: .all,
                    limitToFirstLevelMasters: true
                )
            } else {
                result = try CRUD.readAllMaps(
                    for: dbConnection,
                    game: game,
                    options: .all,
                    limitToFirstLevelMasters: true
                )
            }
            guard let maps = result[ReadMapOptions.maps] as? [SerializedMapModel],
                let slaves = result[ReadMapOptions.numberOfSlaves] as? [Int],
                maps.count == slaves.count
            else {
                throw SQLQueryError.genericError(reason: "maps and submap counts missing or misaligned for \(game)")
            }
            return maps.enumerated().map { i, map in
                ZTronMapModel(map: map, numberOfSubmaps: slaves[i])
            }
        }

        /// As `ZTronMapToolsPicker.loadToolsAndTabs`: the tabs with their tools, then the tool by name.
        static func tool(_ dbConnection: Connection, game: String, map: String, named name: String) throws -> SerializedToolModel? {
            for tab in try CRUD.readTabsWithToolsForMap(for: dbConnection, game: game, map: map) {
                if let tool = tab.getTools().first(where: { $0.getName() == name }) {
                    return tool
                }
            }
            return nil
        }

        /// Every tool key to its full route below `home`, walking games, first-level maps, the submaps of the
        /// collections and their tabs with the same reads as above.
        static func toolRoutes(below home: ZRoute) throws -> [String: ZRoute] {
            var routes: [String: ZRoute] = [:]
            var failure: Error?

            try DBMS.transaction(#function) { dbConnection in
                do {
                    let gamesResult = try CRUD.readAllGames(for: dbConnection, options: .all)
                    let games = (gamesResult[ReadGamesOption.games] as? [SerializedGameModel]) ?? []
                    for game in games {
                        let gameName = game.getName()
                        for map in try maps(dbConnection, game: gameName, master: nil) {
                            let mapName = map.getSerializedMapModel().getName()
                            if map.getSubmapsCount() > 0 {
                                for sub in try maps(dbConnection, game: gameName, master: mapName) {
                                    let subName = sub.getSerializedMapModel().getName()
                                    for tab in try CRUD.readTabsWithToolsForMap(for: dbConnection, game: gameName, map: subName) {
                                        for tool in tab.getTools() where routes[tool.getName()] == nil {
                                            routes[tool.getName()] = home.appending(contentsOf: [gameName, mapName, subName, tool.getName()])
                                        }
                                    }
                                }
                            } else {
                                for tab in try CRUD.readTabsWithToolsForMap(for: dbConnection, game: gameName, map: mapName) {
                                    for tool in tab.getTools() where routes[tool.getName()] == nil {
                                        routes[tool.getName()] = home.appending(contentsOf: [gameName, mapName, tool.getName()])
                                    }
                                }
                            }
                        }
                    }
                    return TransactionResult.commit
                } catch {
                    failure = error
                    return TransactionResult.rollback
                }
            }

            if let failure = failure { throw failure }
            return routes
        }
    }
}
```

Two things the screens do that the resolver deliberately does not. `loadGames` also derives the "active" flag from
`ReadGamesOption.numberOfMaps`; that is Home's own state and stays there. The screens call `fatalError` on a database
error (with the iOS 15 EXC_BAD_ACCESS workaround from the SQLite.swift issue); the resolver throws instead, so a broken
deep link shows the kit's unavailable view rather than crashing. `SerializedToolModel.getGame()`, `getMap()` and
`getTab()` are available if a later `ZTronDataModel` gains a read-by-name for tools; until then `route(forKey:)` scans
once and caches.

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

There is exactly one route table: `appDelegate.routingService.router`, filled once by `makeNavigationRouter` in
`didFinishLaunching`. The kit never copies it and never registers into it: ``ZTrieRouteResolver`` keeps a reference
to the trie it is handed, a ``ZNavigator`` and the ``ZNavigationHub`` hold no routes, and `canRoute` is a lookup in
that same trie. The resolver belongs next to the router, built lazily on first use so that registration has already
happened. File `Routes/RoutingServiceProvider.swift`:

```swift
import Foundation
import RoutingKit
import SwiftUI
import ZNavigation

public final class RoutingServiceProvider: ObservableObject {
    internal let router: TrieRouter<(Parameters) -> any View> = .init()

    /// The one resolver over the one route table, shared by every tab: one trie, one database cache, one
    /// Spotlight table. Built on first use, after `makeNavigationRouter` has registered every route.
    @MainActor
    internal lazy var navigationResolver: any ZRouteResolver = ZTrieRouteResolver(
        router: self.router,
        models: DatabaseModelResolver(),
        scope: { ZRouteModels(ZNavigationPath.compat($0)) }
    )
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
        return ZNavigationScope(root: self.root, resolver: { routing.navigationResolver }) {
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
backends, and every pushed screen already gets the compatibility breadcrumb from the scope. The navigator is the only
per-tab object; the resolver, the trie behind it and the database cache are the shared ones from step 3.

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
