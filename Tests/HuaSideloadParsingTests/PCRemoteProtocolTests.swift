import XCTest
@testable import HuaSideloadParsing

final class PCRemoteProtocolTests: XCTestCase {
    private struct Fixture: Decodable {
        let key_hex: String
        let configuration: PCRemoteConfiguration
        let request: PCRemoteWire.Request
        let reply: PCRemoteWire.Reply
    }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pc-remote-v1", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    func testSignedRequestMatchesPythonGoldenVector() throws {
        let fixture = try fixture()
        let request = try PCRemoteWire.request(.playPause, configuration: fixture.configuration,
            id: fixture.request.id, time: Date(timeIntervalSince1970: Double(fixture.request.ts)))
        XCTAssertEqual(request.signature, fixture.request.signature)
        XCTAssertEqual(request.command, .playPause)
        let frame = try PCRemoteWire.frame(request)
        XCTAssertEqual(try PCRemoteWire.frameLength(Data(frame.prefix(4))), frame.count - 4)
        let decoded = try JSONDecoder().decode(PCRemoteWire.Request.self, from: Data(frame.dropFirst(4)))
        XCTAssertEqual(decoded.signature, fixture.request.signature)
    }
    func testPythonReplySignatureAndCorrelationAreChecked() throws {
        let fixture = try fixture(); let data = try JSONEncoder().encode(fixture.reply)
        let key = try XCTUnwrap(PCRemoteWire.hexData(fixture.key_hex))
        XCTAssertTrue(try PCRemoteWire.verifyReply(data, requestID: fixture.request.id, key: key).ok)
        XCTAssertThrowsError(try PCRemoteWire.verifyReply(data, requestID: UUID().uuidString, key: key))
        XCTAssertThrowsError(try PCRemoteWire.verifyReply(data, requestID: fixture.request.id, key: Data(repeating: 255, count: 32)))
        var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        changed["ok"] = false
        XCTAssertThrowsError(try PCRemoteWire.verifyReply(JSONSerialization.data(withJSONObject: changed), requestID: fixture.request.id, key: key))
    }
    func testOnlyPrivateIPv4EndpointsAndFullKeysAreAccepted() throws {
        let fixture = try fixture()
        let encoded = try JSONEncoder().encode(fixture.configuration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for host in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "192.168.01.2", "localhost", "example.com", "::1", "192.168.1.1/route"] {
            object["host"] = host
            XCTAssertThrowsError(try PCRemoteConfiguration(text: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)))
        }
        for host in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.20"] { XCTAssertTrue(PCRemoteConfiguration.isLANAddress(host)) }
        object["host"] = "192.168.1.20"; object["key"] = "short"
        XCTAssertThrowsError(try PCRemoteConfiguration(text: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)))
        object["key"] = fixture.key_hex; object["port"] = 65536
        XCTAssertThrowsError(try PCRemoteConfiguration(text: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)))
    }
    func testFrameBoundsRejectEmptyOversizedAndMalformedHeaders() {
        for header in [Data(), Data([0, 0, 0, 0]), Data([0, 0, 8, 1]), Data([255, 255, 255, 255]), Data([0, 0, 1])] {
            XCTAssertThrowsError(try PCRemoteWire.frameLength(header))
        }
    }
    func testButtonAndVolumeInOnePacketCauseOneAction() {
        var state = PCRemoteButtons()
        XCTAssertEqual(state.command(button: .next, volume: 9), .next)
        XCTAssertNil(state.command(button: nil, volume: 9))
        XCTAssertEqual(state.command(button: .volumeDown, volume: 8), .volumeDown)
        XCTAssertNil(state.command(button: nil, volume: 8))
        XCTAssertEqual(state.command(button: .play, volume: nil), .playPause)
        XCTAssertEqual(state.command(button: .pause, volume: nil), .playPause)
    }
    func testVolumeOnlyPacketsIgnoreEchoesAndMalformedValues() {
        var state = PCRemoteButtons()
        XCTAssertNil(state.command(button: nil, volume: 8))
        XCTAssertEqual(state.command(button: nil, volume: 9), .volumeUp)
        XCTAssertEqual(state.command(button: nil, volume: 7), .volumeDown)
        XCTAssertNil(state.command(button: nil, volume: 100))
        XCTAssertEqual(state.volume, 7)
        state.reset(); XCTAssertEqual(state.volume, 8)
        XCTAssertNil(state.command(button: nil, volume: nil))
    }
    func testReadsPairingConfigurationFromQRPhotoFixture() throws {
        let fixture = try fixture()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pc-remote-qr-fixture", withExtension: "png"))
        let text = try PCRemoteQRImage.decode(Data(contentsOf: url))
        XCTAssertEqual(try PCRemoteConfiguration(text: text), fixture.configuration)
    }
    func testQRPhotoRejectsEmptyAndInvalidImageData() {
        XCTAssertThrowsError(try PCRemoteQRImage.decode(Data()))
        XCTAssertThrowsError(try PCRemoteQRImage.decode(Data("not an image".utf8)))
    }
}
