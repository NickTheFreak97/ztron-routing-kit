import Logging

/// A builder for constructing ``TrieRouter`` instances using the trie data structure.
///
/// ``TrieRouterBuilder`` provides an efficient way to build routing tables by accumulating route registrations and
/// then constructing a ``TrieRouter`` for fast lookups. It is the routing-kit 5 way of building a router; this fork
/// also keeps ``TrieRouter/register(_:at:)`` on the router itself.
///
/// ## Configuration Options
///
/// - `.caseInsensitive`: Enables case-insensitive route matching
///
/// **Note**: Route registration is cumulative - each call to ``register(_:at:)`` adds to the existing routes.
///   Registering the same path twice will override the previous output.
///
/// **Important**: The builder has value semantics, and ``build()`` returns an independent copy of the routes
///   registered so far: later registrations on this builder never change a router already built.
///
/// See [Trie on Wikipedia](https://en.wikipedia.org/wiki/Trie) for more information about the underlying data
/// structure.
public struct TrieRouterBuilder<Output>: RouterBuilder {
    public typealias Router = TrieRouter<Output>
    typealias Node = TrieRouterNode<Output>

    /// Configured options such as case-sensitivity.
    public let config: TrieRouter<Output>.Configuration

    /// Configured logger.
    let logger: Logger

    private var root: Node

    /// Creates a new ``TrieRouterBuilder``.
    ///
    /// - Parameters:
    ///   - type: The output type for the router.
    ///   - config: Configured options such as case-sensitivity.
    ///   - logger: A logger for the router to use.
    public init(
        _ type: Output.Type = Output.self,
        config: TrieRouter<Output>.Configuration = .init(),
        logger: Logger = .init(label: "codes.vapor.routingkit")
    ) {
        self.root = Node()
        self.config = config
        self.logger = logger
    }

    /// Constructs a new ``TrieRouter`` based on the routes registered to this builder.
    /// - Returns: a ``TrieRouter`` holding a copy of the routes, independent of this builder.
    public func build() -> TrieRouter<Output> {
        TrieRouter(root: self.root.copy(), options: self.config.isCaseInsensitive ? [.caseInsensitive] : [], logger: self.logger)
    }

    /// Registers a new route to this builder at a given path.
    ///
    ///     var builder = TrieRouterBuilder<Route>()
    ///     builder.register(route, at: [.constant("users"), User.parameter])
    ///     let router = builder.build()
    ///
    /// - Parameters:
    ///   - output: Output to register.
    ///   - path: Path to register output at.
    public mutating func register(_ output: Output, at path: [PathComponent]) {
        // Value semantics: a copied builder gets its own tree before it is mutated.
        if !isKnownUniquelyReferenced(&self.root) {
            self.root = self.root.copy()
        }
        self.root.insert(output, at: path, isCaseInsensitive: self.config.isCaseInsensitive, logger: self.logger)
    }
}

/// A builder whose outputs are `Sendable` may cross isolation domains between registrations; it is never shared while
/// one registration runs.
extension TrieRouterBuilder: @unchecked Sendable where Output: Sendable {}
