import Logging

/// A single node of the ``TrieRouter``s trie tree of routes.
///
/// Nodes are mutable: ``TrieRouter/register(_:at:)`` grows the tree in place, which is what this fork's consumers rely
/// on. ``TrieRouterBuilder`` copies the tree when it builds a router, so a built router never changes afterwards.
final class TrieRouterNode<Output>: CustomStringConvertible {
    /// Describes a node that has matched a parameter or anything
    final class Wildcard {
        private(set) var parameter: String?
        private(set) var explicitlyIncludesAnything = false

        let node: TrieRouterNode

        private init(node: TrieRouterNode) {
            self.node = node
        }

        static func anything(_ node: TrieRouterNode) -> Wildcard {
            let wildcard = Wildcard(node: node)
            wildcard.explicitlyIncludesAnything = true
            return wildcard
        }

        static func parameter(_ node: TrieRouterNode, named name: String) -> Wildcard {
            let wildcard = Wildcard(node: node)
            wildcard.setParameterName(name)
            return wildcard
        }

        /// Update the wildcard to match a new parameter name
        func setParameterName(_ name: String) {
            self.parameter = name
        }

        /// Explicitly mark an anything token
        func explicitlyIncludeAnything() {
            self.explicitlyIncludesAnything = true
        }
    }

    /// A child that matches one segment against a template with embedded parameters, such as `:user-{id}-details`.
    ///
    /// `components` are the literal parts with an empty entry where a parameter goes; `parameters` are the parameter
    /// names in order.
    struct PartialMatch {
        let template: String
        let components: [Substring]
        let parameters: [Substring]
        let node: TrieRouterNode

        /// More parameters, more ambiguous: `file.{ext}` is tried before `{name}.{ext}`.
        var ambiguity: Int { self.parameters.count }
    }

    /// All constant child nodes.
    var constants: [String: TrieRouterNode]

    /// Wildcard child node that may be a named parameter or an anything
    var wildcard: Wildcard?

    /// Partial-match child nodes, least ambiguous first.
    var partials: [PartialMatch]

    /// Catchall node, if one exists.
    /// This node should not have any child nodes.
    var catchall: TrieRouterNode?

    /// This node's output
    var output: Output?

    /// Creates a new node.
    init(output: Output? = nil) {
        self.output = output
        self.constants = [:]
        self.partials = []
    }

    /// Registers `output` at `path` below this node, creating the nodes along the way.
    func insert(_ output: Output, at path: [PathComponent], isCaseInsensitive: Bool, logger: Logger) {
        assert(!path.isEmpty, "Cannot register a route with an empty path.")

        // for each dynamic path in the route get the appropriate child, generate a new one if necessary
        var current = self
        for (index, component) in path.enumerated() {
            switch component {
            case .catchall:
                precondition(index == path.count - 1, "Catchall ('\(component)') must be the last component in a path.")
                fallthrough
            default:
                current = current.buildOrFetchChild(for: component, isCaseInsensitive: isCaseInsensitive)
            }
        }

        // if this node already has output, we are overriding a route
        if current.output != nil {
            logger.info("[Routing] Overriding duplicate route for \(path[0]) \(path.dropFirst().string)")
        }

        // after iterating over all path components, we can set the output on the current node
        current.output = output
    }

    /// Fetches the child node for the supplied path component, or builds a new segment onto the tree if necessary.
    func buildOrFetchChild(for component: PathComponent, isCaseInsensitive: Bool) -> TrieRouterNode {
        switch component {
        case .constant(let string):
            // We're going to be comparing this path against an incoming lowercased path later
            // so it's more efficient to lowercase it up front
            let string = isCaseInsensitive ? string.lowercased() : string

            // search for existing constant
            if let node = self.constants[string] {
                return node
            }

            // none found, add a new node
            let node = TrieRouterNode()
            self.constants[string] = node
            return node
        case .parameter(let name):
            let node: TrieRouterNode

            if let wildcard = self.wildcard {
                if let existingName = self.wildcard?.parameter {
                    precondition(
                        existingName == name,
                        "It is not possible to have two routes with the same prefix but different parameter names, even if the trailing path components differ (tried to add route with \(name) that collides with \(existingName))."
                    )
                } else {
                    wildcard.setParameterName(name)
                }
                node = wildcard.node
            } else {
                node = TrieRouterNode()
                self.wildcard = .parameter(node, named: name)
            }
            return node
        case .partialParameter(let template, let components, let parameters):
            precondition(
                parameters.count == Set(parameters).count,
                #"Partial ":\#(template)" contains multiple parameters with the same name"#
            )
            if let existing = self.partials.first(where: { $0.template == template }) {
                return existing.node
            }
            let node = TrieRouterNode()
            self.partials.append(PartialMatch(template: template, components: components, parameters: parameters, node: node))
            // The more specific partials are queried first: with `{a}.{ext}` and `file.{ext}`, `file.txt` matches the
            // second one even though it matches both.
            self.partials.sort { $0.ambiguity < $1.ambiguity }
            return node
        case .catchall:
            let node: TrieRouterNode
            if let fallback = self.catchall {
                node = fallback
            } else {
                node = TrieRouterNode()
                self.catchall = node
            }
            return node
        case .anything:
            let node: TrieRouterNode
            if let wildcard = self.wildcard {
                wildcard.explicitlyIncludeAnything()
                node = wildcard.node
            } else {
                node = TrieRouterNode()
                self.wildcard = .anything(node)
            }
            return node
        }
    }

    /// A deep copy of this subtree. Outputs are copied as values, so reference outputs stay shared.
    func copy() -> TrieRouterNode {
        let clone = TrieRouterNode(output: self.output)
        clone.constants = self.constants.mapValues { $0.copy() }
        if let wildcard = self.wildcard {
            let node = wildcard.node.copy()
            let cloned: Wildcard
            if let name = wildcard.parameter {
                cloned = .parameter(node, named: name)
                if wildcard.explicitlyIncludesAnything {
                    cloned.explicitlyIncludeAnything()
                }
            } else {
                cloned = .anything(node)
            }
            clone.wildcard = cloned
        }
        clone.partials = self.partials.map {
            PartialMatch(template: $0.template, components: $0.components, parameters: $0.parameters, node: $0.node.copy())
        }
        clone.catchall = self.catchall?.copy()
        return clone
    }

    var description: String {
        self.subpathDescriptions.joined(separator: "\n")
    }

    var subpathDescriptions: [String] {
        var desc: [String] = []
        for (name, constant) in self.constants {
            desc.append("→ \(name)")
            desc += constant.subpathDescriptions.indented()
        }

        if let wildcard = self.wildcard {
            if let name = wildcard.parameter {
                desc.append("→ :\(name)")
                desc += wildcard.node.subpathDescriptions.indented()
            }

            if wildcard.explicitlyIncludesAnything {
                desc.append("→ *")
                desc += wildcard.node.subpathDescriptions.indented()
            }
        }

        for partial in self.partials {
            desc.append("→ \(partial.template)")
            desc += partial.node.subpathDescriptions.indented()
        }

        if self.catchall != nil {
            desc.append("→ **")
        }
        return desc
    }
}

extension Array where Element == String {
    fileprivate func indented() -> [String] {
        self.map { "  " + $0 }
    }
}
