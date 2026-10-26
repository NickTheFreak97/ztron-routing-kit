/// One entry of a navigation stack: the full absolute path up to that level.
///
/// SwiftUI's `navigationDestination(for:)` receives the pushed value alone, without its index in the stack, so the
/// value has to carry everything needed to resolve it. A route is therefore the absolute path, not a single segment.
/// Hashing on the full path gives the identity rule for free: the same path is always the same screen identity, and
/// two different paths never share one.
///
/// The routes ZombieTron registers in its `TrieRouter` start with the root symbol `">"`, but ``ZRoute`` itself
/// attaches no meaning to any segment.
public struct ZRoute: Hashable, Codable, Sendable, CustomStringConvertible, Identifiable {
    /// The path segments, root first.
    public let segments: [String]

    public init(_ segments: [String]) {
        self.segments = segments
    }

    /// The route one level below this one.
    public func appending(_ segment: String) -> ZRoute {
        ZRoute(self.segments + [segment])
    }

    /// The route `segments.count` levels below this one.
    public func appending(contentsOf segments: [String]) -> ZRoute {
        ZRoute(self.segments + segments)
    }

    /// The route one level above this one, `nil` for a route of a single segment.
    public var parent: ZRoute? {
        self.segments.count > 1 ? ZRoute(Array(self.segments.dropLast())) : nil
    }

    /// Levels below a two-segment root: `[">", "home"]` is depth 0, `[">", "home", "black ops 7"]` is depth 1.
    public var depth: Int { self.segments.count - 2 }

    /// Levels below `root`, or `nil` when `root` is not a prefix of this route.
    public func depth(below root: ZRoute) -> Int? {
        self.hasPrefix(root) ? self.segments.count - root.segments.count : nil
    }

    /// The last segment; `">"` for an empty route.
    public var last: String { self.segments.last ?? ">" }

    /// Stable identity key, also the analytics page name: the segments joined by `/`.
    public var id: String { self.segments.joined(separator: "/") }

    public var description: String { self.id }

    /// `true` when `other` is a (non-strict) prefix of this route.
    public func hasPrefix(_ other: ZRoute) -> Bool {
        guard self.segments.count >= other.segments.count else { return false }
        return Array(self.segments.prefix(other.segments.count)) == other.segments
    }

    /// Every prefix of this route strictly longer than `root`, shortest first: what a navigator pushes so that Back
    /// walks down one level at a time.
    ///
    /// Returns `nil` when `root` is not a prefix of this route and `[]` when the route *is* the root.
    public func prefixes(beyond root: ZRoute) -> [ZRoute]? {
        guard self.hasPrefix(root) else { return nil }
        guard self.segments.count > root.segments.count else { return [] }
        return ((root.segments.count + 1)...self.segments.count).map { ZRoute(Array(self.segments.prefix($0))) }
    }
}

extension ZRoute: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(elements)
    }
}
