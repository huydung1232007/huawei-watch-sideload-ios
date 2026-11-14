import XCTest
@testable import HuaSideloadParsing

final class MotorcycleRouteTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "motorcycle-hcmc-public", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func encode(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root) }

    func testPublicHCMCResponseContainsMotorcycleGeometryAndTurns() throws {
        let route = try MotorcycleRoute.decode(encode(fixture()))
        XCTAssertGreaterThan(route.coordinates.count, 20)
        XCTAssertEqual(route.distance, 482, accuracy: 1)
        XCTAssertEqual(route.steps[1].turn, .left)
        XCTAssertEqual(route.steps.last?.turn, .destination)
        XCTAssertTrue(route.steps[1].instruction.hasPrefix("Rẽ trái"))
        XCTAssertEqual(route.steps[1].index, 19)
    }

    func testRejectsHighwayEvenIfServerIgnoredAvoidancePreference() throws {
        var root = try fixture(); var trip = root["trip"] as! [String: Any]
        var summary = trip["summary"] as! [String: Any]; summary["has_highway"] = true
        trip["summary"] = summary; root["trip"] = trip
        XCTAssertThrowsError(try MotorcycleRoute.decode(encode(root)))
        summary.removeValue(forKey: "has_highway"); trip["summary"] = summary; root["trip"] = trip
        XCTAssertThrowsError(try MotorcycleRoute.decode(encode(root)))
    }

    func testRejectsAutoFallbackAndOutOfBoundsManeuver() throws {
        for field in ["travel_type", "begin_shape_index"] {
            var root = try fixture(); var trip = root["trip"] as! [String: Any]
            var legs = trip["legs"] as! [[String: Any]]; var maneuvers = legs[0]["maneuvers"] as! [[String: Any]]
            if field == "travel_type" { maneuvers[0][field] = "car" } else { maneuvers[0][field] = 100_000 }
            legs[0]["maneuvers"] = maneuvers; trip["legs"] = legs; root["trip"] = trip
            XCTAssertThrowsError(try MotorcycleRoute.decode(encode(root)))
        }
    }

    func testRequestUsesMotorcycleWithoutIgnoringAccessRules() throws {
        let data = try MotorcycleRoute.request(origin: .init(latitude: 10, longitude: 106), destination: .init(latitude: 11, longitude: 106))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["costing"] as? String, "motorcycle")
        XCTAssertNil(root["ignore_access"])
        XCTAssertThrowsError(try MotorcycleRoute.request(origin: .init(latitude: 91, longitude: 106), destination: .init(latitude: 11, longitude: 106)))
    }

    func testRejectsTruncatedAndInvalidPolyline() {
        for text in ["", "_", "~~~~~~~", "\u{0001}"] { XCTAssertThrowsError(try MotorcycleRoute.decodeShape(text)) }
    }

    func testDocumentedManeuverTypesIncludeBothUTurnsAndRoundabouts() {
        XCTAssertEqual(MotorcycleRoute.turn(9), .right)
        XCTAssertEqual(MotorcycleRoute.turn(16), .left)
        XCTAssertEqual(MotorcycleRoute.turn(12), .uTurn)
        XCTAssertEqual(MotorcycleRoute.turn(13), .uTurn)
        XCTAssertEqual(MotorcycleRoute.turn(26), .unspecified)
    }
}
