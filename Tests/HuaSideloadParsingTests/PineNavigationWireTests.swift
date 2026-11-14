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

    func testLearnsCorrectFingerprintDirectionFromWatchPacket() throws {
        let expectedPhone = String(repeating: "AB", count: 32)
        let packet = P2P.request(kind: P2P.Kind.data, sequence: 17,
            source: PineNavigationWire.watchPackage, destination: PineNavigationWire.phonePackage,
            sourceFingerprint: PineNavigationWire.watchFingerprint, destinationFingerprint: expectedPhone,
            data: Array("init".utf8))
        let message = try XCTUnwrap(P2P.parse(packet))
        let peer = try XCTUnwrap(PineNavigationWire.peerIdentity(from: message))
        XCTAssertEqual(peer.watchFingerprint, PineNavigationWire.watchFingerprint)
        XCTAssertEqual(peer.phoneFingerprint, expectedPhone)
        XCTAssertNotEqual(peer.phoneFingerprint, PineNavigationWire.phoneFingerprint)
    }

    func testIgnoresWrongPeerOrMalformedFingerprint() throws {
        func message(source: String, phoneFingerprint: String) throws -> P2P.Message {
            try XCTUnwrap(P2P.parse(P2P.request(kind: P2P.Kind.data, sequence: 1,
                source: source, destination: PineNavigationWire.phonePackage,
                sourceFingerprint: PineNavigationWire.watchFingerprint, destinationFingerprint: phoneFingerprint,
                data: Array("ping".utf8))))
        }
        XCTAssertNil(PineNavigationWire.peerIdentity(from: try message(source: "another.watch", phoneFingerprint: PineNavigationWire.phoneFingerprint)))
        XCTAssertNil(PineNavigationWire.peerIdentity(from: try message(source: PineNavigationWire.watchPackage, phoneFingerprint: "short")))
        XCTAssertNil(PineNavigationWire.peerIdentity(from: try message(source: PineNavigationWire.watchPackage, phoneFingerprint: String(repeating: "Z", count: 64))))
    }

    func testParsesSingleByteCommunicationFailureCode() throws {
        let packet = HuaweiTLV().with(0x01, [P2P.Kind.ack]).with(0x02, [0, 1])
            .with(0x03, Array(PineNavigationWire.watchPackage.utf8))
            .with(0x04, Array(PineNavigationWire.phonePackage.utf8)).with(0x08, [0xCE])
        XCTAssertEqual(try XCTUnwrap(P2P.parse(packet)).code, 206)
    }
}
