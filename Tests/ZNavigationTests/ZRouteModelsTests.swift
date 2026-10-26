import Combine
import XCTest

@testable import ZNavigation

private final class GameModel: ObservableObject {
    let name: String

    init(_ name: String) {
        self.name = name
    }
}

private final class MapModel: ObservableObject {
    let name: String

    init(_ name: String) {
        self.name = name
    }
}

@MainActor
final class ZRouteModelsTests: XCTestCase {
    func testEmptyHasNoObjects() {
        XCTAssertTrue(ZRouteModels.empty.isEmpty)
        XCTAssertEqual(ZRouteModels().count, 0)
        XCTAssertNil(ZRouteModels.empty.object(of: GameModel.self))
    }

    func testInsertReplacesAnObjectOfTheSameType() {
        var models = ZRouteModels(GameModel("bo3"))
        models.insert(MapModel("origins"))
        models.insert(GameModel("bo7"))
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.object(of: GameModel.self)?.name, "bo7")
        XCTAssertEqual(models.object(of: MapModel.self)?.name, "origins")
    }

    func testInsertingReturnsACopy() {
        let base = ZRouteModels(GameModel("bo3"))
        let extended = base.inserting(MapModel("origins"))
        XCTAssertEqual(base.count, 1)
        XCTAssertEqual(extended.count, 2)
    }

    func testMergingPrefersTheOtherBagOnConflicts() {
        let carried = ZRouteModels(GameModel("carried"), MapModel("carried map"))
        let scope = ZRouteModels(GameModel("scope"))
        let merged = carried.merging(scope)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.object(of: GameModel.self)?.name, "scope")
        XCTAssertEqual(merged.object(of: MapModel.self)?.name, "carried map")
    }
}
