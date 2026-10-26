import RoutingKit
import XCTest

/// Constants are tried before parameters at every node, and the search backtracks to the parameter branch when the
/// constant branch cannot match the rest of the path, so a constant never shadows a parameter route. Catch-alls come
/// last.
final class ConstantPrecedenceTests: XCTestCase {
    private let tool = "iw.ss.easter.egg.rat.king.eye.tool.name"

    private func route(_ path: [String], in router: TrieRouter<String>) -> (output: String?, parameters: Parameters) {
        var parameters = Parameters()
        let output = router.route(path: path, parameters: &parameters)
        return (output, parameters)
    }

    /// The two registrations of the question, in either order.
    private func makeRouter(constantFirst: Bool) -> TrieRouter<String> {
        let router = TrieRouter<String>()
        let generic: [PathComponent] = [">", "home", .parameter("game"), .parameter("map"), .constant(self.tool)]
        let specific: [PathComponent] = [">", "home", "infinite warfare", "shaolin shuffle", .constant(self.tool)]
        if constantFirst {
            router.register("View2", at: specific)
            router.register("View1", at: generic)
        } else {
            router.register("View1", at: generic)
            router.register("View2", at: specific)
        }
        return router
    }

    func testTheConstantRouteWinsForItsOwnPathWhateverTheRegistrationOrder() {
        for constantFirst in [false, true] {
            let router = self.makeRouter(constantFirst: constantFirst)
            let result = self.route([">", "home", "infinite warfare", "shaolin shuffle", self.tool], in: router)
            XCTAssertEqual(result.output, "View2", "constantFirst: \(constantFirst)")
            XCTAssertNil(result.parameters.get("game"), "the constant branch captures no parameters")
            XCTAssertNil(result.parameters.get("map"))
        }
    }

    func testOtherGamesReachTheParameterRoute() {
        let router = self.makeRouter(constantFirst: false)
        let result = self.route([">", "home", "black ops 3", "shadows of evil", self.tool], in: router)
        XCTAssertEqual(result.output, "View1")
        XCTAssertEqual(result.parameters.get("game"), "black ops 3")
        XCTAssertEqual(result.parameters.get("map"), "shadows of evil")
    }

    func testOtherMapsOfTheConstantGameBacktrackToTheParameterRoute() {
        let router = self.makeRouter(constantFirst: false)
        // "infinite warfare" is taken as a constant, "spaceland" is not below it, so the search backtracks to :game.
        let result = self.route([">", "home", "infinite warfare", "spaceland", self.tool], in: router)
        XCTAssertEqual(result.output, "View1")
        XCTAssertEqual(result.parameters.get("game"), "infinite warfare")
        XCTAssertEqual(result.parameters.get("map"), "spaceland")
    }

    func testIntermediateScreensOfTheConstantGameStayReachable() {
        let router = self.makeRouter(constantFirst: false)
        router.register("MapSelection", at: [">", "home", .parameter("game")])
        router.register("ToolsPicker", at: [">", "home", .parameter("game"), .parameter("map")])

        let selection = self.route([">", "home", "infinite warfare"], in: router)
        XCTAssertEqual(selection.output, "MapSelection", "the constant node has no output: back to :game")
        XCTAssertEqual(selection.parameters.get("game"), "infinite warfare")

        let picker = self.route([">", "home", "infinite warfare", "shaolin shuffle"], in: router)
        XCTAssertEqual(picker.output, "ToolsPicker")
        XCTAssertEqual(picker.parameters.get("map"), "shaolin shuffle")

        XCTAssertEqual(self.route([">", "home", "infinite warfare", "spaceland"], in: router).output, "ToolsPicker")
        XCTAssertEqual(self.route([">", "home", "black ops 3"], in: router).output, "MapSelection")
    }

    func testOtherToolsOfTheConstantMapStayReachable() {
        let router = self.makeRouter(constantFirst: false)
        router.register("Other", at: [">", "home", .parameter("game"), .parameter("map"), "iw.ss.other.tool"])
        let result = self.route([">", "home", "infinite warfare", "shaolin shuffle", "iw.ss.other.tool"], in: router)
        XCTAssertEqual(result.output, "Other")
        XCTAssertEqual(result.parameters.get("game"), "infinite warfare")
        XCTAssertEqual(result.parameters.get("map"), "shaolin shuffle")
    }

    func testUsersMeResolvesToTheParameterRoute() {
        let router = TrieRouter<String>()
        router.register("profile", at: ["users", "me", "profile"])
        router.register("user", at: ["users", .parameter("id")])

        var parameters = Parameters()
        XCTAssertEqual(router.route(path: ["users", "me"], parameters: &parameters), "user")
        XCTAssertEqual(parameters.get("id"), "me")
        XCTAssertEqual(router.route(path: ["users", "me", "profile"], parameters: &parameters), "profile")
        XCTAssertEqual(router.route(path: ["users", "42"], parameters: &parameters), "user")
        XCTAssertEqual(parameters.get("id"), "42")
    }

    func testAFailedBranchLeavesNoParametersBehind() {
        let router = TrieRouter<String>()
        router.register("constant", at: ["a", "b", "d"])
        router.register("parameter", at: ["a", .parameter("x"), "c"])

        // a/b/c: the constant "b" dead-ends at "c", the search backtracks and :x captures "b".
        var matched = Parameters()
        XCTAssertEqual(router.route(path: ["a", "b", "c"], parameters: &matched), "parameter")
        XCTAssertEqual(matched.get("x"), "b")

        // a/b/zzz matches nothing and captures nothing.
        var unmatched = Parameters()
        XCTAssertNil(router.route(path: ["a", "b", "zzz"], parameters: &unmatched))
        XCTAssertNil(unmatched.get("x"))
        XCTAssertTrue(unmatched.getCatchall().isEmpty)
    }

    func testBacktrackingRestoresAParameterCapturedByAnOuterBranch() {
        let router = TrieRouter<String>()
        router.register("deep", at: ["a", .parameter("x"), "c"])
        router.register("shallow", at: [.parameter("x"), "b", "d"])

        // a/b/d: the constant "a" branch captures x = "b" and dead-ends at "d"; the search backtracks to the root's
        // :x, which captures "a", and the stale "b" must not survive.
        var matched = Parameters()
        XCTAssertEqual(router.route(path: ["a", "b", "d"], parameters: &matched), "shallow")
        XCTAssertEqual(matched.get("x"), "a")

        var unmatched = Parameters()
        XCTAssertNil(router.route(path: ["a", "b", "zzz"], parameters: &unmatched))
        XCTAssertNil(unmatched.get("x"))
    }

    func testCatchallsComeLastAndTheDeepestOneWins() {
        let router = TrieRouter<String>()
        router.register("root catchall", at: [.catchall])
        router.register("a catchall", at: ["a", .catchall])
        router.register("a x", at: ["a", .parameter("x")])
        router.register("a b c", at: ["a", "b", "c"])

        var exact = Parameters()
        XCTAssertEqual(router.route(path: ["a", "b", "c"], parameters: &exact), "a b c")
        XCTAssertTrue(exact.getCatchall().isEmpty)

        var parameter = Parameters()
        XCTAssertEqual(router.route(path: ["a", "b"], parameters: &parameter), "a x", "the parameter beats the catch-all")
        XCTAssertEqual(parameter.get("x"), "b")

        var deep = Parameters()
        XCTAssertEqual(router.route(path: ["a", "b", "zzz"], parameters: &deep), "a catchall", "nothing more specific matches")
        XCTAssertEqual(deep.getCatchall(), ["b", "zzz"])
        XCTAssertNil(deep.get("x"), "the parameter captured on the failed branch is not kept")

        var root = Parameters()
        XCTAssertEqual(router.route(path: ["q", "r"], parameters: &root), "root catchall")
        XCTAssertEqual(root.getCatchall(), ["q", "r"])
    }

    func testBacktrackingHonoursCaseInsensitivity() {
        let router = TrieRouter<String>(options: [.caseInsensitive])
        router.register("profile", at: ["users", "me", "profile"])
        router.register("user", at: ["users", .parameter("id")])

        var parameters = Parameters()
        XCTAssertEqual(router.route(path: ["USERS", "Me"], parameters: &parameters), "user")
        XCTAssertEqual(parameters.get("id"), "Me", "the captured value keeps its original case")
        XCTAssertEqual(router.route(path: ["Users", "ME", "Profile"], parameters: &parameters), "profile")
    }

    func testReplicatingTheSubtreeUnderTheConstantStillWorks() {
        let router = self.makeRouter(constantFirst: false)
        router.register("ToolsPicker", at: [">", "home", "infinite warfare", .parameter("map")])
        router.register("View1", at: [">", "home", "infinite warfare", .parameter("map"), .constant(self.tool)])

        XCTAssertEqual(self.route([">", "home", "infinite warfare", "spaceland"], in: router).output, "ToolsPicker")
        XCTAssertEqual(self.route([">", "home", "infinite warfare", "spaceland", self.tool], in: router).output, "View1")
        XCTAssertEqual(self.route([">", "home", "infinite warfare", "shaolin shuffle", self.tool], in: router).output, "View2")
    }

    func testBranchingInsideTheHandlerStillWorks() {
        let router = TrieRouter<(Parameters) -> String>()
        router.register(
            { parameters in
                parameters.get("game") == "infinite warfare" && parameters.get("map") == "shaolin shuffle" ? "View2" : "View1"
            },
            at: [">", "home", .parameter("game"), .parameter("map"), .constant(self.tool)]
        )

        var shaolin = Parameters()
        let shaolinOutput = router.route(path: [">", "home", "infinite warfare", "shaolin shuffle", self.tool], parameters: &shaolin)
        XCTAssertEqual(shaolinOutput?(shaolin), "View2")

        var spaceland = Parameters()
        let spacelandOutput = router.route(path: [">", "home", "infinite warfare", "spaceland", self.tool], parameters: &spaceland)
        XCTAssertEqual(spacelandOutput?(spaceland), "View1")
    }
}
