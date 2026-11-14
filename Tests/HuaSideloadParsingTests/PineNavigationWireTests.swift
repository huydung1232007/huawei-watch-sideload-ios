import XCTest
@testable import HuaSideloadParsing

final class PineNavigationWireTests: XCTestCase {
    func testObservedStartupCommands() {
        XCTAssertEqual(PineNavigationWire.control(Array("ping".utf8)), .ping)
        XCTAssertEqual(PineNavigationWire.control(Array("init".utf8)), .initialize)
        XCTAssertEqual(PineNavigationWire.control(Array("exitwatch".utf8)), .exit)
        XCTAssertNil(PineNavigationWire.control([0xFF]))
        XCTAssertNil(PineNavigationWire.control(Array("unrelated".utf8)))
    }

    func testGuidanceUsesCompanionStringFieldsAndVietnameseUTF8() throws {
        let bytes = try PineNavigationWire.guidance(instruction: "Rẽ trái vào đường A", distance: "100 m", turn: .left)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes)) as? [String: String])
        XCTAssertEqual(object["i"], "Rẽ trái vào đường A")
        XCTAssertEqual(object["d"], "100 m")
        XCTAssertEqual(object["p"], "normal_left_16.png")
        XCTAssertEqual(object["f"], "1")
        XCTAssertNil(object["r"])
        XCTAssertLessThanOrEqual(bytes.count, 1000)
    }

    func testDemoCannotBeMistakenForRealGuidance() throws {
        for turn in PineNavigationWire.Turn.allCases {
            let bytes = try PineNavigationWire.demonstration(turn)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes)) as? [String: String])
            XCTAssertTrue(try XCTUnwrap(object["i"]).hasPrefix("DEMO - "))
            XCTAssertEqual(object["p"], turn.icon)
        }
    }

    func testStartAndStopAreDifferentProtocolMessages() throws {
        XCTAssertEqual(String(decoding: PineNavigationWire.start, as: UTF8.self), "start")
        let stop = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(PineNavigationWire.stop)) as? [String: String])
        XCTAssertEqual(stop, ["r": "1"])
    }

    func testByteLimitAppliesAfterUTF8Encoding() {
        XCTAssertThrowsError(try PineNavigationWire.guidance(
            instruction: String(repeating: "🚶", count: 180), distance: String(repeating: "🚶", count: 40),
            turn: .straight, eta: String(repeating: "🚶", count: 80), speed: String(repeating: "🚶", count: 40)))
    }
}
