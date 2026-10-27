import Combine

/// The authoritative page-view signal: one page name per path change, emitted from the navigator's stack
/// publisher, identical on both backends. No `onAppear` double counting, no throttling.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public final class ZPageViewReporter {
    /// Every page name emitted so far, oldest first. The first entry is the root (the landing page).
    public private(set) var pages: [String] = []

    /// The page currently on screen, as last emitted.
    public var current: String? { self.pages.last }

    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - navigator: The stack to observe.
    ///   - emit: Called once per path change with the page name (``ZRoute/id`` of the route on top).
    public init(navigator: ZNavigator, emit: @escaping (String) -> Void = { _ in }) {
        let root = navigator.root
        self.cancellable = navigator.$stack
            // `$stack` publishes the new value (willSet), so derive the page from it.
            .map { ($0.last ?? root).id }
            .removeDuplicates()
            .sink { [weak self] page in
                self?.pages.append(page)
                emit(page)
            }
    }
}
