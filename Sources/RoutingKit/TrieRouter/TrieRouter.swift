import Logging

/// Generic ``TrieRouter`` built using the "trie" tree algorithm.
///
/// Use ``register(_:at:)`` to register routes into the router, or accumulate them in a ``TrieRouterBuilder`` and call
/// its ``TrieRouterBuilder/build()`` for an independent copy. Use ``route(path:parameters:)`` to then fetch a matching
/// route's output.
///
/// See https://en.wikipedia.org/wiki/Trie for more information.
public final class TrieRouter<Output>: Router, CustomStringConvertible {
    typealias Node = TrieRouterNode<Output>

    /// Available ``TrieRouter`` customization options.
    public enum ConfigurationOption: Sendable {
        /// If set, this will cause the router's route matching to be case-insensitive.
        ///
        /// > Note: Case-insensitive routing may be less performant than case-sensitive routing.
        case caseInsensitive
    }

    /// The options as one value, in the shape routing-kit 5 uses.
    public struct Configuration: Sendable {
        public let isCaseInsensitive: Bool

        public init(isCaseInsensitive: Bool = false) {
            self.isCaseInsensitive = isCaseInsensitive
        }

        public static var caseInsensitive: Self { .init(isCaseInsensitive: true) }
    }

    /// Configured options such as case-sensitivity.
    public var options: Set<ConfigurationOption>

    /// ``options`` as a ``Configuration``.
    public var config: Configuration {
        Configuration(isCaseInsensitive: self.options.contains(.caseInsensitive))
    }

    /// The root node.
    internal let root: Node

    /// Configured logger.
    public let logger: Logger

    /// Create a new ``TrieRouter``.
    ///
    /// - Parameters:
    ///   - type: The output type for the router.
    ///   - options: Configured options such as case-sensitivity.
    public init(_ type: Output.Type = Output.self, options: Set<ConfigurationOption> = []) {
        self.root = Node()
        self.options = options
        self.logger = .init(label: "codes.vapor.routingkit")
    }

    /// Create a new ``TrieRouter``.
    ///
    /// - Parameters:
    ///   - type: The output type for the router.
    ///   - options: Configured options such as case-sensitivity.
    ///   - logger: A logger for the router to use.
    public init(_ type: Output.Type = Output.self, options: Set<ConfigurationOption> = [], logger: Logger) {
        self.root = Node()
        self.options = options
        self.logger = logger
    }

    /// Create a new ``TrieRouter`` from a ``Configuration``, the routing-kit 5 spelling of the options.
    public convenience init(
        _ type: Output.Type = Output.self,
        config: Configuration,
        logger: Logger = .init(label: "codes.vapor.routingkit")
    ) {
        self.init(type, options: config.isCaseInsensitive ? [.caseInsensitive] : [], logger: logger)
    }

    /// Adopts an already built tree; used by ``TrieRouterBuilder/build()``.
    init(root: Node, options: Set<ConfigurationOption>, logger: Logger) {
        self.root = root
        self.options = options
        self.logger = logger
    }

    /// Registers a new route to this router at a given path.
    ///
    ///     let route = Route(...)
    ///     let router = TrieRouter<Route>()
    ///     router.register(route, at: [.constant("users"), User.parameter])
    ///
    /// - Parameters:
    ///   - output: Output to register.
    ///   - path: Path to register output at.
    public func register(_ output: Output, at path: [PathComponent]) {
        self.root.insert(output, at: path, isCaseInsensitive: self.options.contains(.caseInsensitive), logger: self.logger)
    }

    /// Routes a path, returning the best-matching output and collecting any dynamic parameters.
    ///
    ///     var params = Parameters()
    ///     router.route(path: ["users", "Vapor"], parameters: &params)
    ///
    /// At every node the constant child is tried first. If the rest of the path cannot be matched below it, the
    /// search backtracks and tries the parameter (or anything) child, then the partial-parameter children from the
    /// least ambiguous one, so a constant that shares a prefix with a parameter never shadows it: with `users/:id`
    /// and `users/me/profile` registered, `users/me` resolves to `users/:id`. Catch-alls have the lowest precedence
    /// and are consulted only when nothing more specific below their node matches; the deepest one on the matched
    /// prefix wins, and a root catch-all also matches the empty path.
    ///
    /// `parameters` receives only the values captured on the matching branch; a path that matches nothing leaves it
    /// untouched.
    ///
    /// - Parameters:
    ///   - path: Raw path segments.
    ///   - parameters: Will collect dynamic parameter values.
    /// - Returns: Output of matching route, if found.
    public func route(path: [String], parameters: inout Parameters) -> Output? {
        let caseInsensitive = self.options.contains(.caseInsensitive)
        if path.isEmpty, let catchall = self.root.catchall, let output = catchall.output {
            parameters.setCatchall(matched: [])
            return output
        }
        guard let match = self.match(path, from: 0, at: self.root, caseInsensitive: caseInsensitive, parameters: &parameters) else {
            return nil
        }
        if let start = match.catchallStart {
            parameters.setCatchall(matched: [String](path.dropFirst(start)))
        }
        return match.output
    }

    /// Matches `path[startIndex...]` below `startNode`: the constant child first, then the wildcard child, then the
    /// partial children, each with the rest of the path matched recursively so that a dead end backtracks, then the
    /// node's own catch-all. A chain of constants with no alternative beside them is walked in a loop, so the common
    /// case recurses only at real decision points. A parameter captured on a branch that fails is restored to its
    /// previous value, so `parameters` only ever reflects the match.
    ///
    /// - Returns: The output and, for a catch-all match, the index of the first segment it swallowed.
    private func match(
        _ path: [String],
        from startIndex: Int,
        at startNode: Node,
        caseInsensitive: Bool,
        parameters: inout Parameters
    ) -> (output: Output, catchallStart: Int?)? {
        var node = startNode
        var index = startIndex

        while index < path.count {
            let slice = path[index]
            let constant = node.constants[caseInsensitive ? slice.lowercased() : slice]

            // No decision to make at this node: follow the constant without recursing.
            if let constant = constant, node.wildcard == nil, node.partials.isEmpty, node.catchall == nil {
                node = constant
                index += 1
                continue
            }

            if let constant = constant,
                let match = self.match(path, from: index + 1, at: constant, caseInsensitive: caseInsensitive, parameters: &parameters)
            {
                return match
            }

            if let wildcard = node.wildcard {
                if let name = wildcard.parameter {
                    let previous = parameters.get(name)
                    parameters.set(name, to: slice)
                    if let match = self.match(
                        path, from: index + 1, at: wildcard.node, caseInsensitive: caseInsensitive, parameters: &parameters)
                    {
                        return match
                    }
                    parameters.restore(name, to: previous)
                } else if let match = self.match(
                    path, from: index + 1, at: wildcard.node, caseInsensitive: caseInsensitive, parameters: &parameters)
                {
                    return match
                }
            }

            for partial in node.partials {
                guard let captures = self.captures(of: partial, in: slice) else { continue }
                var previous: [(name: String, value: String?)] = []
                previous.reserveCapacity(captures.count)
                for (name, value) in captures {
                    let name = String(name)
                    previous.append((name: name, value: parameters.get(name)))
                    parameters.set(name, to: String(value))
                }
                if let match = self.match(
                    path, from: index + 1, at: partial.node, caseInsensitive: caseInsensitive, parameters: &parameters)
                {
                    return match
                }
                for (name, value) in previous.reversed() {
                    parameters.restore(name, to: value)
                }
            }

            if let catchall = node.catchall, let output = catchall.output {
                return (output, index)
            }
            return nil
        }

        // The whole path is consumed: only an output on this very node is a match. A catch-all needs at least one
        // segment, so this node's catch-all does not apply; the caller falls back to its own.
        return node.output.map { ($0, nil) }
    }

    /// Matches one path segment against a partial template, literal parts verbatim and each parameter greedily up to
    /// the last occurrence of the literal that follows it. Returns the captured values by parameter name, or `nil`.
    func captures(of partial: Node.PartialMatch, in segment: String) -> [Substring: Substring]? {
        var result: [Substring: Substring] = [:]
        var index = segment.startIndex

        var componentIndex = partial.components.startIndex
        let lastComponentIndex = partial.components.index(before: partial.components.endIndex)

        while componentIndex <= lastComponentIndex {
            if index >= segment.endIndex {
                // At the end of the segment with literal components left: no match.
                if componentIndex < lastComponentIndex { return nil }
                break
            }

            let element = partial.components[componentIndex]

            if element.isEmpty {
                let endIndex: String.Index
                if componentIndex < lastComponentIndex {
                    let nextElement = partial.components[partial.components.index(after: componentIndex)]
                    // greedy matching
                    guard let range = segment.range(of: nextElement, backwardsIn: index..<segment.endIndex) else { return nil }
                    endIndex = range.lowerBound
                } else {
                    endIndex = segment.endIndex
                }
                result[partial.parameters[result.count]] = segment[index..<endIndex]
                index = endIndex
            } else {
                // Verify the literal matches at current position
                let substring = segment[index...].prefix(element.count)
                guard substring == element else { return nil }
                index = substring.endIndex
            }

            partial.components.formIndex(after: &componentIndex)
        }

        return result
    }

    // See `CustomStringConvertible.description`.
    public var description: String {
        self.root.description
    }
}

extension TrieRouter {
    public final class OutputWithPath {
        private let output: Output
        private let absolutePath: [String]

        init(output: Output, absolutePath: [String]) {
            self.output = output
            self.absolutePath = absolutePath
        }

        public func getOutput() -> Output {
            return self.output
        }

        public func getAbsolutePath() -> [String] {
            return self.absolutePath
        }
    }

    public final class NullableOutputWithPath {
        private let output: Output?
        private let absolutePath: [String]

        init(output: Output?, absolutePath: [String]) {
            self.output = output
            self.absolutePath = absolutePath
        }

        public func getOutput() -> Output? {
            return self.output
        }

        public func getAbsolutePath() -> [String] {
            return self.absolutePath
        }
    }
}

/// A router whose outputs are `Sendable` may be shared once registration is over. Registration is not synchronised:
/// register before sharing, as ``TrieRouterBuilder`` does, and never while another thread routes.
extension TrieRouter: @unchecked Sendable where Output: Sendable {}
