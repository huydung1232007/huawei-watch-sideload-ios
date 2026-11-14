import XCTest
@testable import HuaSideloadParsing

final class RouteProgressTests: XCTestCase {
    func testDistanceFollowsPolylineRatherThanStraightLine() throws {
        let path = try XCTUnwrap(RouteProgress(points: [.init(x: 0, y: 0), .init(x: 100, y: 0), .init(x: 100, y: 100)], lengths: [100, 100]))
        let projection = try XCTUnwrap(path.project(.init(x: 40, y: 10)))
        XCTAssertEqual(projection.along, 40, accuracy: 0.001)
        XCTAssertEqual(projection.crossTrack, 10, accuracy: 0.001)
        XCTAssertEqual(path.totalLength - projection.along, 160, accuracy: 0.001)
    }

    func testMapCoordinateScaleIsConvertedToMeters() throws {
        let path = try XCTUnwrap(RouteProgress(points: [.init(x: 0, y: 0), .init(x: 1000, y: 0)], lengths: [100]))
        let projection = try XCTUnwrap(path.project(.init(x: 500, y: 100)))
        XCTAssertEqual(projection.along, 50, accuracy: 0.001)
        XCTAssertEqual(projection.crossTrack, 10, accuracy: 0.001)
    }

    func testProgressWindowDoesNotJumpToLaterRoute() throws {
        let path = try XCTUnwrap(RouteProgress(points: [.init(x: 0, y: 0), .init(x: 1000, y: 0)], lengths: [1000]))
        let projection = try XCTUnwrap(path.project(.init(x: 800, y: 0), minimum: 0, maximum: 100))
        XCTAssertEqual(projection.along, 100, accuracy: 0.001)
        XCTAssertEqual(projection.crossTrack, 700, accuracy: 0.001)
    }

    func testSkipsDuplicatePointsAndRejectsInvalidRoute() throws {
        let path = try XCTUnwrap(RouteProgress(points: [.init(x: 0, y: 0), .init(x: 0, y: 0), .init(x: 10, y: 0)], lengths: [0, 10]))
        XCTAssertEqual(try XCTUnwrap(path.project(.init(x: 5, y: 0))).along, 5, accuracy: 0.001)
        XCTAssertNil(RouteProgress(points: [.init(x: 0, y: 0)], lengths: []))
        XCTAssertNil(RouteProgress(points: [.init(x: 0, y: 0), .init(x: .nan, y: 0)], lengths: [1]))
        XCTAssertNil(path.project(.init(x: .infinity, y: 0)))
    }

    func testProjectionClampsAtRouteEnds() throws {
        let path = try XCTUnwrap(RouteProgress(points: [.init(x: 0, y: 0), .init(x: 100, y: 0)], lengths: [100]))
        XCTAssertEqual(try XCTUnwrap(path.project(.init(x: -10, y: 0))).along, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(path.project(.init(x: 120, y: 0))).along, 100, accuracy: 0.001)
    }
}
