import XCTest
@testable import HuaSideloadParsing

final class WatchGuidancePresentationTests: XCTestCase {
    func testWarnsAboutImmediateAdjacentTurnWhileApproaching() {
        XCTAssertEqual(WatchGuidancePresentation.followUp(current:.left,remaining:120,next:.right,gap:60),"Sau đó rẽ phải sau 60 m")
        XCTAssertEqual(WatchGuidancePresentation.followUp(current:.right,remaining:50,next:.uTurn,gap:25),"Sau đó quay đầu sau 25 m")
    }
    func testDoesNotWarnForDistantDuplicateOrAlreadyPassedTurns() {
        for (remaining,gap) in [(151.0,60.0),(50,101),(50,0),(50,9),(-1,60),(Double.nan,60),(50,Double.infinity)] {
            XCTAssertEqual(WatchGuidancePresentation.followUp(current:.left,remaining:remaining,next:.right,gap:gap),"")
        }
    }
    func testDepartureStraightUnknownAndArrivalCannotInventSecondTurn() {
        for turn in [PineNavigationWire.Turn.straight,.unspecified,.destination] {
            XCTAssertEqual(WatchGuidancePresentation.followUp(current:turn,remaining:30,next:.left,gap:40),"")
            XCTAssertEqual(WatchGuidancePresentation.followUp(current:.left,remaining:30,next:turn,gap:40),"")
        }
        XCTAssertEqual(WatchGuidancePresentation.followUp(current:.left,remaining:30,next:nil,gap:nil),"")
    }
    func testLongStreetNameStillLeavesSpaceForFollowUp() {
        let followUp = "Sau đó rẽ phải sau 60 m"
        let text = WatchGuidancePresentation.instruction("Rẽ trái vào "+String(repeating:"Nguyễn ",count:40),followUp:followUp)
        XCTAssertTrue(text.hasPrefix("Rẽ trái vào")); XCTAssertTrue(text.hasSuffix(followUp))
        XCTAssertLessThanOrEqual(text.count,180)
    }
    func testExpandedArrivalUsesObservedFourSlotLayout() {
        let field = WatchGuidancePresentation.arrivalField(clock:"18:45",meters:3200,seconds:540,expanded:true)
        XCTAssertEqual(field,"18:45;;3.2km · 9ph;")
        XCTAssertEqual(field.components(separatedBy:";").count,4)
    }
    func testCompactSettingRestoresExistingArrivalPayload() {
        XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"18:45",meters:3200,seconds:540,expanded:false),"18:45;ETA;;")
    }
    func testInvalidRouteEstimatesCannotOverflowOrLeakNaN() {
        for (meters,seconds) in [(Double.nan,60.0),(10,Double.infinity),(-1,60),(10,-1),(10,0),(Double.greatestFiniteMagnitude,60),(10,Double.greatestFiniteMagnitude)] {
            XCTAssertNil(WatchGuidancePresentation.summary(meters:meters,seconds:seconds))
            XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"18:45",meters:meters,seconds:seconds,expanded:true),"18:45;ETA;;")
        }
    }
    func testSubMinuteTripStillHasUsefulCompactSummary() {
        XCTAssertEqual(WatchGuidancePresentation.summary(meters:80,seconds:20),"80m · 1ph")
    }
    func testEnrichedPacketPreservesPrimaryTurnDistanceSpeedAndVibration() throws {
        let followUp = WatchGuidancePresentation.followUp(current:.left,remaining:50,next:.right,gap:60)
        let bytes = try PineNavigationWire.guidance(instruction:WatchGuidancePresentation.instruction("Rẽ trái vào Nguyễn Trãi",followUp:followUp),
            distance:"50 m",turn:.left,eta:WatchGuidancePresentation.arrivalField(clock:"18:45",meters:3200,seconds:540,expanded:true),speed:"32;km/h",vibration:"L")
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(bytes)) as? [String:String])
        XCTAssertEqual(packet["d"],"50 m"); XCTAssertEqual(packet["p"],"normal_left_16.png")
        XCTAssertEqual(packet["s"],"32;km/h"); XCTAssertEqual(packet["v"],"L")
        XCTAssertEqual(packet["e"],"18:45;;3.2km · 9ph;")
        XCTAssertTrue(packet["i"]?.contains("Sau đó rẽ phải sau 60 m") == true)
        XCTAssertLessThan(bytes.count,1000)
    }
}
