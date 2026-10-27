<p align="center">
<img src="https://design.vapor.codes/images/vapor-routingkit.svg" height="96" alt="RoutingKit">
<br>
<br>
<a href="https://docs.vapor.codes/4.0/"><img src="https://design.vapor.codes/images/readthedocs.svg" alt="Documentation"></a>
<a href="https://discord.gg/vapor"><img src="https://design.vapor.codes/images/discordchat.svg" alt="Team Chat"></a>
<a href="LICENSE"><img src="https://design.vapor.codes/images/mitlicense.svg" alt="MIT License"></a>
<a href="https://github.com/vapor/routing-kit/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/vapor/routing-kit/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc" alt="Continuous Integration"></a>
<a href="https://codecov.io/github/vapor/routing-kit"><img src="https://img.shields.io/codecov/c/github/vapor/routing-kit?style=plastic&logo=codecov&label=codecov" alt="Code Coverage></a>
<a href="https://swift.org"><img src="https://design.vapor.codes/images/swift61up.svg" alt="Swift 6.1+"></a>
</p>

<br>

RoutingKit is a high-performance, trie-node router to route HTTP requests to the correct route handler. It allows for dynamic path parameters to make building web frameworks easy.

## Differences from upstream RoutingKit

This fork tracks [vapor/routing-kit](https://github.com/vapor/routing-kit) (last synced with 5.0.0-beta.3) and stays a
drop-in replacement for it: the module is `RoutingKit`, both the upstream product name `RoutingKit` and
`ZTronRoutingKit` are exported, and Vapor's `vapor4` branch builds against it unchanged (the `upstream-check` job).
What differs:

- **Both APIs.** `TrieRouter` keeps the mutable routing-kit 4 API (`TrieRouter(Output.self, options:)` and
  `register(_:at:)`) and also offers the routing-kit 5 one: `TrieRouterBuilder` with `build()`, `RouterBuilder`,
  `TrieRouter.Configuration`, partial parameters such as `":user-{id}.json"`, and a root catch-all that matches the
  empty path. `Output` is not required to be `Sendable`; `TrieRouter` and `TrieRouterBuilder` are `Sendable` when it is.
- **Matching backtracks.** Constants are tried first at every node; when the rest of the path cannot be matched below a
  constant, the search falls back to the parameter child, then to the partial parameters from the least ambiguous one,
  then to the catch-all. A constant never shadows a parameter route (`users/me` resolves to `users/:id` when only
  `users/me/profile` is registered as a constant), and a path that matches nothing leaves `Parameters` untouched.
- **Traversal helpers** on the trie: `forEach`, `map`, `zip`, `merge`, neighbours, breadth-first traversal and DOT
  export, which upstream does not ship.
- **Platforms** stay at macOS 10.15, iOS 13, tvOS 13 and watchOS 6, in the Swift 5 language mode and without
  upstream's Swift 6.2-only settings or its swift-algorithms dependency; the sources need a Swift 6 compiler.
  `AnyRouter` is gone, as upstream.

## ZTronNavigationKit

The `ZTronNavigationKit` product (module `ZNavigation`) adds the owner of *where the user is* on top of the trie: a
`ZNavigator` holds one stack of `ZRoute` values, `ZNavigationStack` renders it on `NavigationStack` (iOS 16+) or on
`NavigationView` with a chain of hidden `isActive` links (iOS 15) with identical observable behaviour, and
`ZRouteLink` pushes a value instead of building a destination. Deep links reach the navigators through a
`ZNavigationHub`. The design, the ZombieTron migration plan and the parity suite are documented in
`Sources/ZNavigation/Docs.docc/UnifiedNavigationDesign.md`.

```swift
.product(name: "ZTronNavigationKit", package: "ztron-routing-kit")
```

Model-level tests run with `swift test`; the hosted parity suite needs an iOS simulator:

```sh
xcodebuild test -scheme ztron-routing-kit-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:ZNavigationTests
```
