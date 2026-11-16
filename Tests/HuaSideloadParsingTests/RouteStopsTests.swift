import XCTest
@testable import HuaSideloadParsing

final class RouteStopsTests: XCTestCase {
    func testStopsRequireOrderedNearbyAccurateFixesAndSurviveRerouting() {
        let a = UUID(), b = UUID()
        let boundaries = [RouteStopProgress.Boundary(id:a,along:100),.init(id:b,along:300)]
        var state = RouteStopProgress()
        XCTAssertEqual(state.projectionMaximum(500,boundaries:boundaries),100)
        XCTAssertNil(state.arrive(boundaries:boundaries,along:300,distance:0,accuracy:5))
        XCTAssertNil(state.arrive(boundaries:boundaries,along:100,distance:36,accuracy:5))
        XCTAssertNil(state.arrive(boundaries:boundaries,along:100,distance:10,accuracy:26))
        XCTAssertEqual(state.arrive(boundaries:boundaries,along:95,distance:10,accuracy:5),a)
        XCTAssertEqual(state.next(in:boundaries)?.id,b)
        // A new route contains only unvisited stops, with new along distances.
        let rerouted = [RouteStopProgress.Boundary(id:b,along:80)]
        XCTAssertEqual(state.projectionMaximum(500,boundaries:rerouted),80)
        XCTAssertEqual(state.arrive(boundaries:rerouted,along:80,distance:5,accuracy:5),b)
        XCTAssertEqual(state.visited,Set([a,b]))
        XCTAssertEqual(state.projectionMaximum(500,boundaries:rerouted),500)
        state.reset(); XCTAssertTrue(state.visited.isEmpty)
    }
    func testInvalidFixesCannotVisitStop() {
        let boundaries = [RouteStopProgress.Boundary(id:UUID(),along:100)]
        for invalid in [Double.nan,Double.infinity,-1] {
            var state = RouteStopProgress()
            XCTAssertNil(state.arrive(boundaries:boundaries,along:100,distance:invalid,accuracy:5))
            XCTAssertNil(state.arrive(boundaries:boundaries,along:100,distance:5,accuracy:invalid))
        }
    }
    func testJoinedLegsPreserveDistancesAndBoundaryIndexes() throws {
        let first = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:100,y:0)],lengths:[100]))
        let second = try XCTUnwrap(RouteProgress(points:[.init(x:105,y:0),.init(x:205,y:0)],lengths:[100]))
        let joined = try XCTUnwrap(RouteLegJoiner.join([.init(path:first,gap:0),.init(path:second,gap:5)]))
        XCTAssertEqual(joined.starts,[0,105]); XCTAssertEqual(joined.ends,[1,3])
        XCTAssertEqual(joined.path.totalLength,205)
        XCTAssertEqual(joined.path.cumulative[joined.ends[0]],100)
        XCTAssertEqual(joined.path.project(.init(x:150,y:0))?.along,150)
        XCTAssertNil(RouteLegJoiner.join([.init(path:first,gap:0),.init(path:second,gap:21)]))
        XCTAssertNil(RouteLegJoiner.join([]))
        XCTAssertNil(RouteLegJoiner.join(Array(repeating:.init(path:first,gap:0),count:5)))
    }
}
