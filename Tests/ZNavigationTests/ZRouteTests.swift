import Foundation
import XCTest

@testable import ZNavigation

final class ZRouteTests: XCTestCase {
    private let home: ZRoute = [">", "home"]

    func testAppendingAndParent() {
        let game = self.home.appending("black ops 7")
        XCTAssertEqual(game.segments, [">", "home", "black ops 7"])
        XCTAssertEqual(game.parent, self.home)
        XCTAssertEqual(game.appending(contentsOf: ["kowakujo", "tool"]).segments.count, 5)
        XCTAssertNil(ZRoute([">"]).parent)
    }

    func testDepthAndLast() {
        XCTAssertEqual(self.home.depth, 0)
        XCTAssertEqual(self.home.appending("black ops 7").depth, 1)
        XCTAssertEqual(self.home.appending("black ops 7").depth(below: self.home), 1)
        XCTAssertNil(ZRoute([">", "about"]).depth(below: self.home))
        XCTAssertEqual(self.home.last, "home")
        XCTAssertEqual(ZRoute([]).last, ">")
    }

    func testIdentityIsThePath() {
        let a = self.home.appending("A")
        let again = ZRoute([">", "home", "A"])
        XCTAssertEqual(a, again)
        XCTAssertEqual(a.hashValue, again.hashValue)
        XCTAssertEqual(a.id, ">/home/A")
        XCTAssertEqual(a.description, a.id)
        XCTAssertNotEqual(a, self.home.appending("B"))
        XCTAssertEqual(Set([a, again, self.home.appending("B")]).count, 2)
    }

    func testHasPrefix() {
        let c = self.home.appending("A").appending("B").appending("C")
        XCTAssertTrue(c.hasPrefix(self.home))
        XCTAssertTrue(c.hasPrefix(c))
        XCTAssertFalse(self.home.hasPrefix(c))
        XCTAssertFalse(c.hasPrefix([">", "about"]))
    }

    func testPrefixesBeyondRoot() {
        let c = self.home.appending("A").appending("B").appending("C")
        XCTAssertEqual(
            c.prefixes(beyond: self.home),
            [self.home.appending("A"), self.home.appending("A").appending("B"), c]
        )
        XCTAssertEqual(self.home.prefixes(beyond: self.home), [])
        XCTAssertNil(ZRoute([">", "about", "credits"]).prefixes(beyond: self.home))
    }

    func testCodableRoundTrip() throws {
        let route = self.home.appending("black ops 7").appending("bo7.kowakujo.easter.egg.maneni.neko.tool.name")
        let data = try JSONEncoder().encode([route])
        let decoded = try JSONDecoder().decode([ZRoute].self, from: data)
        XCTAssertEqual(decoded, [route])
    }

    func testSegmentsAreStoredVerbatim() {
        let route: ZRoute = [">", "home", "Black Ops 7", "kowakujo", "bo7.kowakujo.easter.egg.maneni.neko.tool.name"]
        XCTAssertEqual(route.segments, [">", "home", "Black Ops 7", "kowakujo", "bo7.kowakujo.easter.egg.maneni.neko.tool.name"])
    }
}
