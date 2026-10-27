import Combine
import SwiftUI

/// The environment objects a destination injects into its subtree, keyed by type.
///
/// Today every pushed screen of ZombieTron depends on environment objects that only its pushing parent can supply
/// (the game, the map provider, the tool). The bag is type-erased so that ``ZNavigator`` is generic over nothing:
/// the app decides what a screen needs, the pushing screen carries it, and ``ZRouteDestinationView`` injects it.
///
/// Inserting an object replaces a previously inserted object of the same dynamic type. Insertion order is kept and
/// later objects are injected outermost, so on a type conflict within a merge the later bag wins.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct ZRouteModels {
    private var objects: [any ObservableObject] = []

    public init() {}

    public init(_ objects: any ObservableObject...) {
        for object in objects {
            self.insert(object)
        }
    }

    /// "This destination needs nothing beyond app-level objects".
    public static var empty: ZRouteModels { ZRouteModels() }

    public var isEmpty: Bool { self.objects.isEmpty }

    public var count: Int { self.objects.count }

    /// Adds `object`, replacing a previously inserted object of the same dynamic type.
    public mutating func insert(_ object: any ObservableObject) {
        let key = ObjectIdentifier(type(of: object))
        self.objects.removeAll { ObjectIdentifier(type(of: $0)) == key }
        self.objects.append(object)
    }

    /// A copy with `object` inserted.
    public func inserting(_ object: any ObservableObject) -> ZRouteModels {
        var copy = self
        copy.insert(object)
        return copy
    }

    /// The first inserted object that is an `Object`.
    public func object<Object: ObservableObject>(of type: Object.Type = Object.self) -> Object? {
        for object in self.objects {
            if let match = object as? Object {
                return match
            }
        }
        return nil
    }

    /// A copy with every object of `other` inserted; `other` wins on a type conflict.
    public func merging(_ other: ZRouteModels) -> ZRouteModels {
        var copy = self
        for object in other.objects {
            copy.insert(object)
        }
        return copy
    }

    /// Injects every object as an environment object of `view`, in insertion order (later objects outermost).
    @MainActor
    func inject(into view: AnyView) -> AnyView {
        var result = view
        for object in self.objects {
            result = Self.inject(object, into: result)
        }
        return result
    }

    @MainActor
    private static func inject<Object: ObservableObject>(_ object: Object, into view: AnyView) -> AnyView {
        AnyView(view.environmentObject(object))
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension View {
    /// Injects every object of `models` as an environment object of this view.
    @MainActor
    public func environmentObjects(_ models: ZRouteModels) -> AnyView {
        models.inject(into: AnyView(self))
    }
}
