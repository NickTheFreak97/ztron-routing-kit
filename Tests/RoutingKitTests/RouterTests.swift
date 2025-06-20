@testable import RoutingKit
import XCTest

final class RouterTests: XCTestCase {
    func testRouter() throws {
        let router = TrieRouter(Int.self)
        router.register(42, at: ["foo", "bar", "baz", ":user"])
        var params = Parameters()
        XCTAssertEqual(router.route(path: ["foo", "bar", "baz", "Tanner"], parameters: &params), 42)
        XCTAssertEqual(params.get("user"), "Tanner")
    }
    
    func testCaseSensitiveRouting() throws {
        let router = TrieRouter<Int>()
        router.register(42, at: [.constant("path"), .constant("TO"), .constant("fOo")])
        var params = Parameters()
        XCTAssertNil(router.route(path: ["PATH", "tO", "FOo"], parameters: &params))
        XCTAssertEqual(router.route(path: ["path", "TO", "fOo"], parameters: &params), 42)
    }
    
    func testCaseInsensitiveRouting() throws {
        let router = TrieRouter<Int>(options: [.caseInsensitive])
        router.register(42, at: [.constant("path"), .constant("TO"), .constant("fOo")])
        var params = Parameters()
        XCTAssertEqual(router.route(path: ["PATH", "tO", "FOo"], parameters: &params), 42)
    }

    func testAnyRouting() throws {
        let router = TrieRouter<Int>()
        router.register(0, at: [.constant("a"), .anything])
        router.register(1, at: [.constant("b"), .parameter("1"), .anything])
        router.register(2, at: [.constant("c"), .parameter("1"), .parameter("2"), .anything])
        router.register(3, at: [.constant("d"), .parameter("1"), .parameter("2")])
        router.register(4, at: [.constant("e"), .parameter("1"), .catchall])
        router.register(5, at: [.anything, .constant("e"), .parameter("1")])

        var params = Parameters()
        XCTAssertEqual(router.route(path: ["a", "b"], parameters: &params), 0)
        XCTAssertNil(router.route(path: ["a"], parameters: &params))
        XCTAssertEqual(router.route(path: ["a", "a"], parameters: &params), 0)
        XCTAssertEqual(router.route(path: ["b", "a", "c"], parameters: &params), 1)
        XCTAssertNil(router.route(path: ["b"], parameters: &params))
        XCTAssertNil(router.route(path: ["b", "a"], parameters: &params))
        XCTAssertEqual(router.route(path: ["b", "a", "c"], parameters: &params), 1)
        XCTAssertNil(router.route(path: ["c"], parameters: &params))
        XCTAssertNil(router.route(path: ["c", "a"], parameters: &params))
        XCTAssertNil(router.route(path: ["c", "b"], parameters: &params))
        XCTAssertEqual(router.route(path: ["d", "a", "b"], parameters: &params), 3)
        XCTAssertNil(router.route(path: ["d", "a", "b", "c"], parameters: &params))
        XCTAssertNil(router.route(path: ["d", "a"], parameters: &params))
        XCTAssertEqual(router.route(path: ["e", "1", "b", "a"], parameters: &params), 4)
        XCTAssertEqual(router.route(path: ["f", "e", "1"], parameters: &params), 5)
        XCTAssertEqual(router.route(path: ["g", "e", "1"], parameters: &params), 5)
        XCTAssertEqual(router.route(path: ["g", "e", "1"], parameters: &params), 5)
    }

    func testWildcardRoutingHasNoPrecedence() throws {
        let router1 = TrieRouter<Int>()
        router1.register(0, at: [.constant("a"), .parameter("1"), .constant("a")])
        router1.register(1, at: [.constant("a"), .anything, .constant("b")])

        let router2 = TrieRouter<Int>()
        router2.register(0, at: [.constant("a"), .anything, .constant("a")])
        router2.register(1, at: [.constant("a"), .anything, .constant("b")])

        var params1 = Parameters()
        var params2 = Parameters()
        let path = ["a", "1", "b"]

        XCTAssertEqual(router1.route(path: path, parameters: &params1), 1)
        XCTAssertEqual(router2.route(path: path, parameters: &params2), 1)
    }

    func testRouterSuffixes() throws {
        let router = TrieRouter<Int>(options: [.caseInsensitive])
        router.register(1, at: [.constant("a")])
        router.register(2, at: [.constant("aa")])

        var params = Parameters()
        XCTAssertEqual(router.route(path: ["a"], parameters: &params), 1)
        XCTAssertEqual(router.route(path: ["aa"], parameters: &params), 2)
    }


    func testDocBlock() throws {
        let router = TrieRouter<Int>()
        router.register(42, at: ["users", ":user"])

        var params = Parameters()
        XCTAssertEqual(router.route(path: ["users", "Tanner"], parameters: &params), 42)
        XCTAssertEqual(params.get("user"), "Tanner")
    }

    func testDocs() throws {
        let router = TrieRouter(Double.self)
        router.register(42, at: ["fun", "meaning_of_universe"])
        router.register(1337, at: ["fun", "leet"])
        router.register(3.14, at: ["math", "pi"])
        var params = Parameters()
        XCTAssertEqual(router.route(path: ["fun", "meaning_of_universe"], parameters: &params), 42)
    }
    
    // https://github.com/vapor/routing/issues/64
    func testParameterPercentDecoding() throws {
        let router = TrieRouter(String.self)
        router.register("c", at: [.constant("a"), .parameter("b")])
        var params = Parameters()
        XCTAssertEqual(router.route(path: ["a", "te%20st"], parameters: &params), "c")
        XCTAssertEqual(params.get("b"), "te st")
    }

    // https://github.com/vapor/routing-kit/issues/74
    func testCatchallNested() throws {
        let router = TrieRouter(String.self)
        router.register("/**", at: [.catchall])
        router.register("/a/**", at: ["a", .catchall])
        router.register("/a/b/**", at: ["a", "b", .catchall])
        router.register("/a/b", at: ["a", "b"])
        var params = Parameters()
        XCTAssertEqual(router.route(path: ["a"], parameters: &params), "/**")
        XCTAssertEqual(router.route(path: ["a", "b"], parameters: &params), "/a/b")
        XCTAssertEqual(router.route(path: ["a", "b", "c"], parameters: &params), "/a/b/**")
        XCTAssertEqual(router.route(path: ["a", "c"], parameters: &params), "/a/**")
        XCTAssertEqual(router.route(path: ["b"], parameters: &params), "/**")
        XCTAssertEqual(router.route(path: ["b", "c", "d", "e"], parameters: &params), "/**")
    }

    func testCatchallPrecedence() throws {
        let router = TrieRouter(String.self)
        router.register("a", at: ["v1", "test"])
        router.register("b", at: ["v1", .catchall])
        router.register("c", at: ["v1", .anything])
        var params = Parameters()
        XCTAssertEqual(router.route(path: ["v1", "test"], parameters: &params), "a")
        XCTAssertEqual(router.route(path: ["v1", "test", "foo"], parameters: &params), "b")
        XCTAssertEqual(router.route(path: ["v1", "foo"], parameters: &params), "c")
    }
    
    func testCatchallValue() throws {
        let router = TrieRouter<Int>()
        router.register(42, at: ["users", ":user", "**"])
        router.register(24, at: ["users", "**"])

        var params = Parameters()
        XCTAssertNil(router.route(path: ["users"], parameters: &params))
        XCTAssertEqual(params.getCatchall().count, 0)
        XCTAssertEqual(router.route(path: ["users", "stevapple"], parameters: &params), 24)
        XCTAssertEqual(params.getCatchall(), ["stevapple"])
        XCTAssertEqual(router.route(path: ["users", "stevapple", "posts", "2"], parameters: &params), 42)
        XCTAssertEqual(params.getCatchall(), ["posts", "2"])
    }
    
    func testRouterDescription() throws {
        // Use simple routing to eliminate the impact of registration order
        let constA: PathComponent = "a"
        let constOne: PathComponent = "1"
        let paramOne: PathComponent = .parameter("1")
        let anything: PathComponent = .anything
        let catchall: PathComponent = .catchall
        let router = TrieRouter<Int>()
        router.register(0, at: [constA, anything])
        router.register(1, at: [constA, constOne, catchall])
        router.register(2, at: [constA, constOne, anything])
        router.register(3, at: [anything, constA, paramOne])
        router.register(4, at: [catchall])
        // Manually build description
        let desc = """
        → \(constA)
          → \(constOne)
            → \(anything)
            → \(catchall)
          → \(anything)
        → \(anything)
          → \(constA)
            → \(paramOne)
        → \(catchall)
        """
        XCTAssertEqual(router.description, desc)
    }
    
    func testPathComponentDescription() throws {
        let paths = [
            "aaaaa/bbbb/ccc/dd",
            "123/:45/6/789",
            "123/**",
            "*/*/*/**",
            ":12/12/*"
        ]
        for path in paths {
            XCTAssertEqual(path.pathComponents.string, path)
            XCTAssertEqual(("/" + path).pathComponents.string, path)
        }
    }
    
    func testPathComponentInterpolation() throws {
        do {
            let pathComponentLiteral: PathComponent = "path"
            switch pathComponentLiteral {
            case .constant(let value):
                XCTAssertEqual(value, "path")
            default:
                XCTFail("pathComponentLiteral \(pathComponentLiteral) is not .constant(\"path\")")
            }
        }
        do {
            let pathComponentLiteral: PathComponent = ":path"
            switch pathComponentLiteral {
            case .parameter(let value):
                XCTAssertEqual(value, "path")
            default:
                XCTFail("pathComponentLiteral \(pathComponentLiteral) is not .parameter(\"path\")")
            }
        }
        do {
            let pathComponentLiteral: PathComponent = "*"
            switch pathComponentLiteral {
            case .anything:
                break
            default:
                XCTFail("pathComponentLiteral \(pathComponentLiteral) is not .anything")
            }
        }
        do {
            let pathComponentLiteral: PathComponent = "**"
            switch pathComponentLiteral {
            case .catchall:
                break
            default:
                XCTFail("pathComponentLiteral \(pathComponentLiteral) is not .catchall")
            }
        }
        do {
            let constant = "foo"
            let pathComponentInterpolation: PathComponent = "\(constant)"
            switch pathComponentInterpolation {
            case .constant(let value):
                XCTAssertEqual(value, "foo")
            default:
                XCTFail("pathComponentInterpolation \(pathComponentInterpolation) is not .constant(\"foo\")")
            }
        }
        do {
            let parameter = "foo"
            let pathComponentInterpolation: PathComponent = ":\(parameter)"
            switch pathComponentInterpolation {
            case .parameter(let value):
                XCTAssertEqual(value, "foo")
            default:
                XCTFail("pathComponentInterpolation \(pathComponentInterpolation) is not .parameter(\"foo\")")
            }
        }
        do {
            let anything = "*"
            let pathComponentInterpolation: PathComponent = "\(anything)"
            switch pathComponentInterpolation {
            case .anything:
                break
            default:
                XCTFail("pathComponentInterpolation \(pathComponentInterpolation) is not .anything")
            }
        }
        do {
            let catchall = "**"
            let pathComponentInterpolation: PathComponent = "\(catchall)"
            switch pathComponentInterpolation {
            case .catchall:
                break
            default:
                XCTFail("pathComponentInterpolation \(pathComponentInterpolation) is not .catchall")
            }
        }
    }

    func testParameterNamesFetch() throws {
        let router = TrieRouter<Int>()
        router.register(42, at: ["foo", ":bar", ":baz", ":bam"])
        router.register(24, at: ["bar", ":bar", "**"])

        var params1 = Parameters()
        XCTAssertNil(router.route(path: ["foo"], parameters: &params1))
        XCTAssertTrue(params1.getCatchall().isEmpty)

        var params2 = Parameters()
        XCTAssertEqual(router.route(path: ["foo", "a", "b", "c"], parameters: &params2), 42)
        XCTAssertEqual(Set(params2.allNames), ["bar", "baz", "bam"]) // Set will compare equal regardless of ordering
        XCTAssertTrue(params2.getCatchall().isEmpty)

        var params3 = Parameters()
        XCTAssertEqual(router.route(path: ["bar", "baz", "bam"], parameters: &params3), 24)
        XCTAssertEqual(Set(params3.allNames), ["bar"])
        XCTAssertEqual(params3.getCatchall(), ["bam"])
    }
    
    func testConstantNeighboursFetch() throws {
        let router = TrieRouter<Int>()
        router.register(42, at: ["foo", "bar", "yoo"])
        router.register(24, at: ["bar", "bar"])
        router.register(12, at: ["bar", "man"])
        router.register(6, at: ["bar", "man", ":yoo"])
        router.register(12, at: ["bar", "man", "joe"])

        let neighbours = router.neighbours(path: ["bar"])
        
        XCTAssertNotNil(neighbours)
        XCTAssertNotNil(neighbours?.firstIndex(where: { node in
            return node.getOutput() == 24
        }))
        XCTAssertNotNil(neighbours?.firstIndex(where: { node in
            return node.getOutput() == 12
        }))
        XCTAssertNil(neighbours?.firstIndex(where: { node in
            return node.getOutput() == 6
        }))
        XCTAssertEqual(neighbours?.count, 2)
        
        let emptyRouter = TrieRouter<Int>()
        let emptyNeighbours = emptyRouter.neighbours(path: [])
        
        XCTAssertEqual(emptyNeighbours?.count, 0)
        
        let level1LeavesRouter = TrieRouter<Int>()
        level1LeavesRouter.register(12, at: ["foo"])
        level1LeavesRouter.register(6, at: ["bar"])
        
        let rootNeighbours = level1LeavesRouter.neighbours(path: [])
        
        XCTAssertNotNil(rootNeighbours)
        XCTAssertEqual(rootNeighbours?.count, 2)
        XCTAssertTrue(rootNeighbours?.firstIndex(where: { node in
            return node.getOutput() == 12
        }) != nil)
        XCTAssertTrue(rootNeighbours?.firstIndex(where: { node in
            return node.getOutput() == 6
        }) != nil)
        XCTAssertFalse(rootNeighbours?.firstIndex(where: { node in
            return node.getOutput() == 3
        }) != nil)

    }
    
    func testMap() throws {
        let router = TrieRouter<Int>()
        router.register(0, at: [">", "Police", "zoom"])
        router.register(1, at: [">", "Police"])
        router.register(2, at: [">", "Depot"])
        router.register(3, at: [">", "Shutters"])
        router.register(4, at: [">", "Cakes"])
        router.register(5, at: [">", "SpacelandSign", "zoom"])
        router.register(6, at: [">", "SpacelandSign"])

        router.map { absolutePath, output in
            return absolutePath
        }.forEach { path in
            print(path)
        }
    }
    
    func testForEachBFS() throws {
        let router = TrieRouter<(String, Int)>()
        router.register(("PoliceZoom", 0), at: [">", "Police", "zoom"])
        router.register(("Police", 0), at: [">", "Police"])
        router.register(("Depot", 1), at: [">", "Depot"])
        router.register(("Shutters", 2), at: [">", "Shutters"])
        router.register(("Cakes", 3), at: [">", "Cakes"])
        router.register(("SpacelandSignZoom", 0), at: [">", "SpacelandSign", "zoom"])
        router.register(("SpacelandSign", 4), at: [">", "SpacelandSign"])
        router.register(("SpacelandSignZoomRaveZoom", 0), at: [">", "SpacelandSign", "zoom", "rave", "zoom"])

        print(router.toDOT{ absolutePath, output in
            if let output = output {
                return output.0
            } else {
                return absolutePath.last!
            }
        })
        
        router.forEachBFS { neighbours in
            return neighbours.sorted { lhs, rhs in
                guard let lhsOut = lhs.getOutput(), let rhsOut = rhs.getOutput() else { return false }
                return lhsOut.1 < rhsOut.1
            }
        } shouldVisitNeighbours: { nodeInfo in
            return nodeInfo.getAbsolutePath().count <= 1
        } _: { path, output in
            print(path, output)
        }
    }
    
    /// Tests successful, now `<`, `<=`, `sharesRoutes` became `internal` and therefore the ability to run this test is missing.
    /*
    func testArrayLessThanOperator() throws {
        XCTAssertEqual([">", "police", "zoom"] < [">", "police"], false)
        XCTAssertEqual([">", "police", "zoom"] < [">", "police", "zoom"], false)
        XCTAssertEqual([">", "police", "zoom"] <= [">", "police", "zoom"], true)
        XCTAssertEqual([">", "police"] < [">", "police", "zoom"], true)
        XCTAssertEqual([] < [], false)
        XCTAssertEqual([] <= [], true)
    }
    
    func testSharesRoutes() throws {
        let lhs = TrieRouter<(String, Int)>()
        let rhs = TrieRouter<(String, Double)>()

        XCTAssertEqual(lhs.sharesRoutes(with: rhs), true)
        XCTAssertEqual(rhs.sharesRoutes(with: lhs), true)
        
        lhs.register(("PoliceZoom", 0), at: [">", "Police", "zoom"])
        lhs.register(("Police", 0), at: [">", "Police"])
        lhs.register(("Depot", 1), at: [">", "Depot"])
        lhs.register(("Shutters", 2), at: [">", "Shutters"])
        lhs.register(("Cakes", 3), at: [">", "Cakes"])
        lhs.register(("SpacelandSignZoom", 0), at: [">", "SpacelandSign", "zoom"])
        lhs.register(("SpacelandSign", 4), at: [">", "SpacelandSign"])
        
        rhs.register(("SpacelandSignZoom", 0), at: [">", "SpacelandSign", "zoom"])
        rhs.register(("SpacelandSign", 4), at: [">", "SpacelandSign"])
        rhs.register(("Police", 0), at: [">", "Police"])
        rhs.register(("PoliceZoom", 0), at: [">", "Police", "zoom"])
        rhs.register(("Shutters", 2), at: [">", "Shutters"])
        rhs.register(("Depot", 1), at: [">", "Depot"])
        rhs.register(("Cakes", 3), at: [">", "Cakes"])

        XCTAssertEqual(lhs.sharesRoutes(with: rhs), true)
        XCTAssertEqual(rhs.sharesRoutes(with: lhs), true)
        
        lhs.register(("SpacelandSignZoomRaveZoom", 0), at: [">", "SpacelandSign", "zoom", "rave", "zoom"])
        
        XCTAssertEqual(lhs.sharesRoutes(with: rhs), false)
        XCTAssertEqual(rhs.sharesRoutes(with: lhs), false)
    }
     */
    
    func testZipRouters() throws {
        let lhs = TrieRouter<(String, Int)>()
        let rhs = TrieRouter<(String, Double)>()
        
        lhs.register(("PoliceZoom", 0), at: [">", "Police", "zoom"])
        lhs.register(("Police", 0), at: [">", "Police"])
        lhs.register(("Depot", 1), at: [">", "Depot"])
        lhs.register(("Shutters", 2), at: [">", "Shutters"])
        lhs.register(("Cakes", 3), at: [">", "Cakes"])
        lhs.register(("SpacelandSignZoom", 0), at: [">", "SpacelandSign", "zoom"])
        lhs.register(("SpacelandSign", 4), at: [">", "SpacelandSign"])
        
        rhs.register(("SpacelandSignZoom", 0), at: [">", "SpacelandSign", "zoom"])
        rhs.register(("SpacelandSign", 4), at: [">", "SpacelandSign"])
        rhs.register(("Police", 0), at: [">", "Police"])
        rhs.register(("PoliceZoom", 0), at: [">", "Police", "zoom"])
        rhs.register(("Shutters", 2), at: [">", "Shutters"])
        rhs.register(("Depot", 1), at: [">", "Depot"])
        rhs.register(("Cakes", 3), at: [">", "Cakes"])
        
        let zip = lhs.zip(to: rhs) { absolutePath, lhsOutput, rhsOutput in
            return (lhsOutput, rhsOutput)
        }
        
        XCTAssertNotNil(zip)
        
        zip?.forEach{ absolutePath, output in
            XCTAssertEqual(output.0.0, output.1.0)
        }
        
        lhs.register(("SpacelandSignZoomRaveZoom", 0), at: [">", "SpacelandSign", "zoom", "rave", "zoom"])

        let second = lhs.zip(to: rhs) { absolutePath, lhsOutput, rhsOutput in
            return (lhsOutput, rhsOutput)
        }
        
        XCTAssertNil(second)
    }
    
    func testHasSlice() throws {
        let lhs = TrieRouter<(String, Int)>()
        
        lhs.register(("PoliceZoom", 0), at: [">", "Police", "zoom"])
        lhs.register(("Police", 0), at: [">", "Police"])
        lhs.register(("Depot", 1), at: [">", "Depot"])
        lhs.register(("Shutters", 2), at: [">", "Shutters"])
        lhs.register(("Cakes", 3), at: [">", "Cakes"])
        lhs.register(("SpacelandSignZoom", 0), at: [">", "SpacelandSign", "zoom"])
        lhs.register(("SpacelandSign", 4), at: [">", "SpacelandSign"])
        
        XCTAssertTrue(lhs.hasSlice(named: ">"))
        XCTAssertTrue(lhs.hasSlice(named: "Depot"))
        XCTAssertTrue(lhs.hasSlice(named: "zoom"))
        XCTAssertFalse(lhs.hasSlice(named: "zoom", rootPath: [">", "Cakes"]))
    }
    
    func testIsSuperSet() throws {
        let lhs = TrieRouter<Int>()
        lhs.register(0, at: [">", "Police", "zoom"])
        lhs.register(0, at: [">", "Police"])
        lhs.register(1, at: [">", "Depot"])
        lhs.register(2, at: [">", "Shutters"])
        lhs.register(3, at: [">", "Cakes"])
        lhs.register(0, at: [">", "SpacelandSign", "zoom"])
        lhs.register(4, at: [">", "SpacelandSign"])

        XCTAssertTrue(lhs.isSuperSet(of: lhs))
        
        let rhs = TrieRouter<Double>()
        
        XCTAssertTrue(lhs.isSuperSet(of: rhs))
        XCTAssertFalse(rhs.isSuperSet(of: lhs))
        
        rhs.register(1, at: [">", "Depot"])
        rhs.register(2, at: [">", "Shutters"])
        rhs.register(3, at: [">", "Cakes"])
        rhs.register(0, at: [">", "SpacelandSign", "zoom"])
        rhs.register(4, at: [">", "SpacelandSign"])
        
        XCTAssertTrue(lhs.isSuperSet(of: rhs))
        XCTAssertFalse(rhs.isSuperSet(of: lhs))
        
        rhs.register(4, at: [">", "SpacelandSign", "Rave"])

        rhs.forEachBFS(rootPath: [">", "Maronna"]) { absoltePath, output in
            print(absoltePath)
        }
        
        XCTAssertFalse(lhs.isSuperSet(of: rhs))
        XCTAssertFalse(rhs.isSuperSet(of: lhs))
    }
    
    func testNeighbours() throws {
        let router = TrieRouter<Int>()
        router.register(0, at: [">", "the final reich"])
        router.register(1, at: [">", "the darkest shore"])
        router.register(2, at: [">", "the shadowed throne"])
        router.register(3, at: [">", "the tortured path"])
        router.register(4, at: [">", "the frozen dawn"])
        router.register(0, at: [">", "the tortured path", "into the storm"])
        router.register(1, at: [">", "the tortured path", "across the depths"])
        router.register(2, at: [">", "the tortured path", "beneath the ice"])
        
        XCTAssertEqual(router.reduceNeighbours(parentPath: [">", "the darkest shore"], 0) { partialResult, _, _ in
            return partialResult + 1
        }, 0)
        
        XCTAssertEqual(router.reduceNeighbours(parentPath: [">", "the tortured path"], 0) { partialResult, _, _ in
            return partialResult + 1
        }, 3)
    }
    
    func testParametersPrecedence() throws {
        let router = TrieRouter<Int>()
        
        router.register(
            0,
            at: [.constant("home"), .parameter("game"), .parameter("map")]
        )
        
        router.register(
            1,
            at: [.constant("home"), .constant("black ops 6"), .parameter("spaceland")]
        )
        
        var params: Parameters = .init()
        let result = router.route(path: ["home", "infinite warfare", "spaceland"] , parameters: &params)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result, 0)
    }
}
