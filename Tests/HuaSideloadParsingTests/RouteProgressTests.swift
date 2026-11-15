import XCTest
import MapKit
@testable import HuaSideloadParsing

final class RouteProgressTests: XCTestCase {
    func testRealMapKitCoordinatesKeepNorthBearingConvention() throws {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude:10.77645,longitude:106.70092))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude:10.77745,longitude:106.70092))
        let path = try XCTUnwrap(RouteProgress(points:[.init(x:a.x,y:a.y),.init(x:b.x,y:b.y)],lengths:[a.distance(to:b)]))
        XCTAssertEqual(try XCTUnwrap(path.stableForwardBearing(at:20)),0,accuracy:0.001)
    }
    func testForwardBearingUsesMapKitNorthEastSouthWestAxes() throws {
        for (x,y,bearing) in [(0.0,-100.0,0.0),(100,0,90),(0,100,180),(-100,0,270)] {
            let path = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:x,y:y)],lengths:[100]))
            XCTAssertEqual(try XCTUnwrap(path.stableForwardBearing(at:0)),bearing,accuracy:0.001)
            XCTAssertEqual(try XCTUnwrap(path.stableForwardBearing(at:50)),bearing,accuracy:0.001)
        }
    }
    func testBearingIsIndependentOfMapPointMeterScale() throws {
        let path = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:1000,y:0)],lengths:[100]))
        XCTAssertEqual(try XCTUnwrap(path.stableForwardBearing(at:50)),90,accuracy:0.001)
    }
    func testCornersAndHairpinsAreNotDirectionReferences() throws {
        let corner = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:0,y:-100),.init(x:100,y:-100)],lengths:[100,100]))
        XCTAssertNotNil(corner.stableForwardBearing(at:50))
        XCTAssertNil(corner.stableForwardBearing(at:95))
        XCTAssertNil(corner.stableForwardBearing(at:100))
        let hairpin = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:0,y:-100),.init(x:0,y:0)],lengths:[100,100]))
        XCTAssertNil(hairpin.stableForwardBearing(at:100))
        XCTAssertEqual(try XCTUnwrap(hairpin.stableForwardBearing(at:150)),180,accuracy:0.001)
    }
    func testHeadingSkipsDuplicatePointsAndRejectsInvalidOrTinyWindows() throws {
        let path = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:0,y:0),.init(x:100,y:0)],lengths:[0,100]))
        XCTAssertEqual(try XCTUnwrap(path.stableForwardBearing(at:0)),90,accuracy:0.001)
        for value in [-1.0,101,.nan,.infinity] { XCTAssertNil(path.stableForwardBearing(at:value)) }
        let tiny = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:2,y:0)],lengths:[2]))
        XCTAssertNil(tiny.stableForwardBearing(at:0))
    }
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
