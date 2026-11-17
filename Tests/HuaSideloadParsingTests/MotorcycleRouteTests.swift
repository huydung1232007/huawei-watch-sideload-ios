import XCTest
@testable import HuaSideloadParsing

final class MotorcycleRouteTests: XCTestCase {
    private func shape(_ coordinates: [(Int,Int)]) -> String {
        var previous = (0,0), bytes = [UInt8]()
        func append(_ delta: Int) {
            var value = delta < 0 ? (-delta*2-1) : delta*2
            while value >= 32 { bytes.append(UInt8((value & 31) | 32)+63); value >>= 5 }
            bytes.append(UInt8(value)+63)
        }
        for point in coordinates { append(point.0-previous.0); append(point.1-previous.1); previous = point }
        return String(bytes:bytes,encoding:.utf8)!
    }
    private func twoLegs() -> [String:Any] {
        func leg(_ points: [(Int,Int)]) -> [String:Any] {
            ["shape":shape(points),"summary":["has_highway":false],"maneuvers":[
                ["travel_type":"motorcycle","begin_shape_index":0,"type":1,"instruction":"Start"],
                ["travel_type":"motorcycle","begin_shape_index":1,"type":4,"instruction":"Arrive"]]]
        }
        return ["trip":["status":0,"units":"kilometers","summary":["time":100.0,"length":2.0,"has_highway":false],
            "legs":[leg([(10_000_000,106_000_000),(10_001_000,106_000_000)]),
                    leg([(10_001_000,106_000_000),(10_002_000,106_000_000)])]]]
    }
    func testRequestKeepsStopOrderAndUsesBreaksWithoutAlternates() throws {
        let stops = [MotorcycleRoute.Coordinate(latitude:10.1,longitude:106),.init(latitude:10.2,longitude:106)]
        let data = try MotorcycleRoute.request(origin:.init(latitude:10,longitude:106),destination:.init(latitude:10.3,longitude:106),stops:stops)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        let locations = try XCTUnwrap(root["locations"] as? [[String:Any]])
        XCTAssertEqual(locations.compactMap { $0["lat"] as? Double },[10,10.1,10.2,10.3])
        XCTAssertTrue(locations.allSatisfy { $0["type"] as? String == "break" })
        XCTAssertEqual(root["alternates"] as? Int,0)
        XCTAssertThrowsError(try MotorcycleRoute.request(origin:stops[0],destination:stops[1],stops:Array(repeating:stops[0],count:4)))
    }
    func testMultiLegDecodeJoinsGeometryAndOffsetsTurnsAtStopBoundary() throws {
        let route = try MotorcycleRoute.decode(encode(twoLegs()))
        XCTAssertEqual(route.coordinates.count,3)
        XCTAssertEqual(route.stopEndIndexes,[1])
        XCTAssertEqual(route.steps.map(\.index),[0,1,1,2])
        XCTAssertEqual(route.steps[1].instruction,"Đến điểm dừng 1")
        XCTAssertEqual(route.steps.last?.instruction,"Đến điểm đến")
        XCTAssertEqual(route.distance,2000)
    }
    func testInvalidLaterLegRejectsWholeItinerary() throws {
        for invalid in ["highway","mode","index","gap"] {
            var root = twoLegs(), trip = root["trip"] as! [String:Any]
            var legs = trip["legs"] as! [[String:Any]], maneuvers = legs[1]["maneuvers"] as! [[String:Any]]
            switch invalid {
            case "highway": legs[1]["summary"] = ["has_highway":true]
            case "mode": maneuvers[0]["travel_type"] = "car"
            case "index": maneuvers[1]["begin_shape_index"] = 99
            default: legs[1]["shape"] = shape([(11_000_000,106_000_000),(11_001_000,106_000_000)])
            }
            legs[1]["maneuvers"] = maneuvers; trip["legs"] = legs; root["trip"] = trip
            XCTAssertThrowsError(try MotorcycleRoute.decode(encode(root)))
        }
    }
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
        XCTAssertEqual(root["alternates"] as? Int, 2)
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

    private func alternativeFixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "motorcycle-hcmc-alternatives", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testReadsThreeDistinctPublicRoutesInProviderOrder() throws {
        let routes = try MotorcycleRoute.decodeOptions(encode(alternativeFixture()))
        XCTAssertEqual(routes.count, 3)
        XCTAssertEqual(routes[0].distance, 2312, accuracy: 1)
        XCTAssertEqual(routes[1].distance, 2315, accuracy: 1)
        XCTAssertEqual(routes[2].distance, 2796, accuracy: 1)
        XCTAssertNotEqual(routes[0].coordinates, routes[1].coordinates)
        XCTAssertTrue(routes.allSatisfy { !$0.steps.isEmpty && !$0.via.isEmpty })
    }

    func testDuplicateGeometryDoesNotCreateFakeExtraChoices() throws {
        var root = try fixture()
        root["alternates"] = [["trip": root["trip"]!], ["trip": root["trip"]!]]
        XCTAssertEqual(try MotorcycleRoute.decodeOptions(encode(root)).count, 1)
    }

    func testUnsafeAlternativeIsFilteredWithoutDroppingValidChoices() throws {
        var root = try alternativeFixture()
        var alternatives = root["alternates"] as! [[String: Any]]
        var trip = alternatives[0]["trip"] as! [String: Any]
        var summary = trip["summary"] as! [String: Any]; summary["has_highway"] = true
        trip["summary"] = summary; alternatives[0]["trip"] = trip; root["alternates"] = alternatives
        let routes = try MotorcycleRoute.decodeOptions(encode(root))
        XCTAssertEqual(routes.count, 2)
        XCTAssertEqual(routes[1].distance, 2796, accuracy: 1)
    }

    func testValidAlternateCanReplaceRejectedPrimary() throws {
        var root = try alternativeFixture(); var trip = root["trip"] as! [String: Any]
        var summary = trip["summary"] as! [String: Any]; summary["has_highway"] = true
        trip["summary"] = summary; root["trip"] = trip
        let routes = try MotorcycleRoute.decodeOptions(encode(root))
        XCTAssertEqual(routes.count, 2)
        XCTAssertEqual(routes[0].distance, 2315, accuracy: 1)
    }

    func testSingleRouteResponseStillWorksWithoutAlternates() throws {
        XCTAssertEqual(try MotorcycleRoute.decodeOptions(encode(fixture())).count, 1)
    }

    func testDetailedVietnameseManeuverTranslationsAndStepDurations() throws {
        let route = try MotorcycleRoute.decode(encode(fixture()))
        XCTAssertEqual(route.steps.first?.duration ?? 0, 80.883, accuracy: 0.01)
        XCTAssertEqual(route.steps[1].duration ?? 0, 10.216, accuracy: 0.01)
        XCTAssertEqual(MotorcycleRoute.translate(type: 9, names: "Lê Lợi", direction: .right), "Chếch phải vào Lê Lợi")
        XCTAssertEqual(MotorcycleRoute.translate(type: 16, names: "Pasteur", direction: .left), "Chếch trái vào Pasteur")
        XCTAssertEqual(MotorcycleRoute.translate(type: 11, names: "Nguyễn Huệ", direction: .right), "Ngoặt gấp phải vào Nguyễn Huệ")
        XCTAssertEqual(MotorcycleRoute.translate(type: 23, names: "Võ Văn Kiệt", direction: .right), "Giữ bên phải vào Võ Văn Kiệt")
        XCTAssertEqual(MotorcycleRoute.translate(type: 28, names: "Cát Lái", direction: .unspecified), "Lên phà Cát Lái")
        XCTAssertEqual(MotorcycleRoute.translate(type: 999, names: "Trần Hưng Đạo", direction: .unspecified), "Đi theo Trần Hưng Đạo")
    }

}
