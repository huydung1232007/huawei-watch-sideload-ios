import XCTest
@testable import HuaSideloadParsing

final class NavMiniWireTests: XCTestCase {
    func testReplyContainsExplicitSampleFlagAndMatchingRequest() throws {
        let reply = try XCTUnwrap(NavMiniWire.reply(to:["t":"navmini.hello","v":1,"n":42],at:Date()))
        XCTAssertEqual(reply["t"] as? String,"navmini.status")
        XCTAssertEqual(reply["n"] as? Int,42)
        XCTAssertEqual(reply["demo"] as? Bool,true)
        XCTAssertEqual(reply["distance"] as? String,"120 m")
        XCTAssertEqual(reply["remaining"] as? String,"3.2 km")
        XCTAssertLessThan(try JSONSerialization.data(withJSONObject:reply).count,1000)
    }
    func testForeignTypeOrUnsupportedProtocolIsRejected() {
        XCTAssertNil(NavMiniWire.reply(to:["t":"hello","v":1,"n":1],at:Date()))
        XCTAssertNil(NavMiniWire.reply(to:["t":"navmini.hello","v":2,"n":1],at:Date()))
    }
    func testBooleanFractionAndOutOfRangeNoncesAreRejected() {
        let values: [Any] = [true,0,-1,1.5,1_000_000_000,"1"]
        for value in values {
            XCTAssertNil(NavMiniWire.reply(to:["t":"navmini.hello","v":1,"n":value],at:Date()))
        }
    }
    func testMissingFieldsAndOversizeRequestsAreRejected() {
        XCTAssertNil(NavMiniWire.reply(to:["t":"navmini.hello","n":1],at:Date()))
        XCTAssertNil(NavMiniWire.reply(to:["t":"navmini.hello","v":1,"n":1,"pad":String(repeating:"x",count:1100)],at:Date()))
    }
    func testRenderAcknowledgementUsesSeparateType() {
        let message: [String: Any] = ["t":"navmini.rendered","v":1,"n":123]
        XCTAssertEqual(NavMiniWire.nonce(in:message,type:"navmini.rendered"),123)
        XCTAssertNil(NavMiniWire.reply(to:message,at:Date()))
    }
    func testStableOwnPeerAddressesDifferFromNavigationWatch() {
        XCTAssertEqual(NavMiniWire.watchPackage,"com.huydung1232007.navmini")
        XCTAssertEqual(NavMiniWire.phonePackage,"com.huydung1232007.navmini.phone")
        XCTAssertNotEqual(NavMiniWire.watchPackage,PineNavigationWire.watchPackage)
    }
}
