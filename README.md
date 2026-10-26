<p align="center">
<img src="https://design.vapor.codes/images/vapor-routingkit.svg" height="96" alt="RoutingKit">
<br>
<br>
<a href="https://docs.vapor.codes/4.0/"><img src="https://design.vapor.codes/images/readthedocs.svg" alt="Documentation"></a>
<a href="https://discord.gg/vapor"><img src="https://design.vapor.codes/images/discordchat.svg" alt="Team Chat"></a>
<a href="LICENSE"><img src="https://design.vapor.codes/images/mitlicense.svg" alt="MIT License"></a>
<a href="https://github.com/vapor/routing-kit/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/vapor/routing-kit/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc" alt="Continuous Integration"></a>
<a href="https://codecov.io/github/vapor/routing-kit"><img src="https://img.shields.io/codecov/c/github/vapor/routing-kit?style=plastic&logo=codecov&label=codecov"></a>
<a href="https://swift.org"><img src="https://design.vapor.codes/images/swift510up.svg" alt="Swift 5.10+"></a>
</p>

<br>

RoutingKit is a high-performance, trie-node router to route HTTP requests to the correct route handler. It allows for dynamic path parameters to make building web frameworks easy.

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
