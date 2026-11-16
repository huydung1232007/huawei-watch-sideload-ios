import XCTest
@testable import HuaSideloadParsing

final class WatchGuidancePresentationTests: XCTestCase {
    func testSpeedOffAlwaysShowsFollowingEvenKilometersAwayWithoutLatchingSpeedOn() {
        var policy = FollowingManeuverPolicy()
        let show = policy.shouldShow(maneuver:2,current:.straight,remaining:8000,enabled:false,always:true)
        XCTAssertTrue(show)
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:2400,straightLength:nil,showFollowing:show,showSpeed:false),"←;2.4km")
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.straight,gap:0,straightLength:4000,showFollowing:show,showSpeed:false),"↑;4km")
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:8000,enabled:true))
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:.nan,enabled:true,always:true))
    }
    func testSpeedOffCannotFallBackToKmhOrInventUnknownFollowingStep() {
        for next in [nil,.unspecified,.straight] as [PineNavigationWire.Turn?] {
            XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:next,gap:60,straightLength:nil,showFollowing:true,showSpeed:false),"")
        }
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.destination,gap:5000,straightLength:nil,showFollowing:true,showSpeed:false),"•;5km")
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:.nan,straightLength:nil,showFollowing:true,showSpeed:false),"")
    }
    func testFollowingTurnUsesDirectionAfterPrimaryAndDistanceAfterIt() {
        var policy = FollowingManeuverPolicy()
        let show = policy.shouldShow(maneuver:2,current:.right,remaining:30,enabled:true)
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:60,straightLength:nil,showFollowing:show),"←;60m")
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.right,gap:2400,straightLength:nil,showFollowing:show),"→;2.4km")
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.uTurn,gap:25,straightLength:nil,showFollowing:show),"↶;25m")
    }
    func testFollowingStraightUsesItsSegmentLengthNotGapToItsStart() {
        for gap in [0.0,10,60] {
            XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.straight,gap:gap,straightLength:2000,showFollowing:true),"↑;2km")
        }
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.straight,gap:10,straightLength:nil,showFollowing:true),"36;km/h")
    }
    func testFollowingDistanceLabelsFitCompactSpeedField() {
        for (meters,label) in [(1.0,"5m"),(62,"60m"),(999,"1km"),(1000,"1km"),(1200,"1.2km"),(9999,"10km"),(36000,"36km"),(1_000_000,">999km")] {
            let value = WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:meters,straightLength:nil,showFollowing:true)
            XCTAssertEqual(value,"←;"+label)
            XCTAssertLessThanOrEqual(value.components(separatedBy:";")[1].count,6)
        }
    }
    func testNoInventedHintForUnknownArrivalDuplicateOrInvalidGap() {
        for turn in [nil,.unspecified,.destination] as [PineNavigationWire.Turn?] {
            XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:turn,gap:60,straightLength:nil,showFollowing:true),"36;km/h")
        }
        for gap in [nil,0,-1,.nan,.infinity,20_000_001] as [Double?] {
            XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:gap,straightLength:nil,showFollowing:true),"36;km/h")
        }
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:60,straightLength:nil,showFollowing:false),"36;km/h")
    }
    func testFollowingHintDoesNotDependOnValidGpsSpeed() {
        for speed in [-1.0,Double.nan,Double.infinity] {
            XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:speed,next:.left,gap:60,straightLength:nil,showFollowing:true),"←;60m")
            XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:speed,next:nil,gap:nil,straightLength:nil,showFollowing:false),"")
        }
    }
    func testHintActivatesStrictlyBelow100MetersAndLatchesThroughJitter() {
        var policy = FollowingManeuverPolicy()
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.right,remaining:150,enabled:true))
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.right,remaining:100,enabled:true))
        XCTAssertTrue(policy.shouldShow(maneuver:2,current:.right,remaining:99.9,enabled:true))
        XCTAssertTrue(policy.shouldShow(maneuver:2,current:.right,remaining:105,enabled:true))
        XCTAssertTrue(policy.shouldShow(maneuver:2,current:.right,remaining:0,enabled:true))
    }
    func testAdvancingManeuverRestoresSpeedUntilNextApproach() {
        var policy = FollowingManeuverPolicy()
        XCTAssertTrue(policy.shouldShow(maneuver:2,current:.right,remaining:30,enabled:true))
        let show = policy.shouldShow(maneuver:3,current:.left,remaining:2000,enabled:true)
        XCTAssertFalse(show)
        XCTAssertEqual(WatchGuidancePresentation.speedField(metersPerSecond:10,next:.right,gap:60,straightLength:nil,showFollowing:show),"36;km/h")
        XCTAssertTrue(policy.shouldShow(maneuver:3,current:.left,remaining:90,enabled:true))
    }
    func testHintDisableResetAndInvalidStateCannotLeakLatchedStep() {
        var policy = FollowingManeuverPolicy()
        for turn in [PineNavigationWire.Turn.straight,.unspecified,.destination] {
            XCTAssertTrue(policy.shouldShow(maneuver:2,current:.left,remaining:30,enabled:true))
            XCTAssertFalse(policy.shouldShow(maneuver:2,current:turn,remaining:30,enabled:true))
            XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:120,enabled:true))
        }
        for distance in [-1.0,Double.nan,Double.infinity] {
            XCTAssertTrue(policy.shouldShow(maneuver:2,current:.left,remaining:30,enabled:true))
            XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:distance,enabled:true))
        }
        XCTAssertTrue(policy.shouldShow(maneuver:2,current:.left,remaining:30,enabled:true))
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:30,enabled:false))
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:120,enabled:true))
        XCTAssertTrue(policy.shouldShow(maneuver:2,current:.left,remaining:30,enabled:true))
        policy.reset()
        XCTAssertFalse(policy.shouldShow(maneuver:2,current:.left,remaining:120,enabled:true))
    }
    func testSecondaryHintPacketPreservesPrimaryArrowDistanceEtaAndHaptic() throws {
        let speed = WatchGuidancePresentation.speedField(metersPerSecond:10,next:.left,gap:60,straightLength:nil,showFollowing:true)
        let data = try PineNavigationWire.guidance(instruction:"Rẽ phải vào Nguyễn Trãi",distance:"30 m",turn:.right,eta:"03:38;;1h21;",speed:speed,vibration:"R")
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(data)) as? [String:String])
        XCTAssertEqual(packet["s"],"←;60m")
        XCTAssertEqual(packet["p"],"normal_right_16.png")
        XCTAssertEqual(packet["d"],"30 m")
        XCTAssertEqual(packet["i"],"Rẽ phải vào Nguyễn Trãi")
        XCTAssertEqual(packet["e"],"03:38;;1h21;")
        XCTAssertEqual(packet["v"],"R")
        XCTAssertLessThan(data.count,1000)
    }
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
        XCTAssertEqual(field,"18:45;;3.2km;")
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
        XCTAssertEqual(packet["e"],"18:45;;3.2km;")
        XCTAssertTrue(packet["i"]?.contains("Sau đó rẽ phải sau 60 m") == true)
        XCTAssertLessThan(bytes.count,1000)
    }
    func testThirtySixKmWatchRegressionUsesSeparateShortLabels() {
        XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"03:26",meters:36_000,seconds:82*60,expanded:true),"03:26;;36km;")
        XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"03:26",meters:36_000,seconds:82*60,expanded:true,displayDuration:true),"03:26;;1h22;")
        XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"03:26",meters:36_000,seconds:120*60,expanded:true,displayDuration:true),"03:26;;2h;")
        XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"03:26",meters:36_000,seconds:142*60,expanded:true,displayDuration:true),"03:26;;2h22;")
    }
    func testWatchDetailNeverContainsWrappedCombinedSummary() {
        for meters in [80.0,995,3200,9999,36_000,100_000,1_000_000] {
            for seconds in [60.0,6000,86_400,604_800] {
                for duration in [false,true] {
                    let fields = WatchGuidancePresentation.arrivalField(clock:"18:45",meters:meters,seconds:seconds,expanded:true,displayDuration:duration).components(separatedBy:";")
                    XCTAssertEqual(fields.count,4)
                    XCTAssertEqual(fields[1],"")
                    XCTAssertLessThanOrEqual(fields[2].count,6)
                    XCTAssertFalse(fields[2].contains("·")); XCTAssertFalse(fields[2].contains(" "))
                }
            }
        }
    }
    func testRotationKeepsArrivalClockAndUsesTheVisibleSlotOnly() {
        let distance = WatchGuidancePresentation.arrivalField(clock:"03:38",meters:36_000,seconds:81*60,expanded:true)
        let time = WatchGuidancePresentation.arrivalField(clock:"03:38",meters:36_000,seconds:81*60,expanded:true,displayDuration:true)
        XCTAssertEqual(distance,"03:38;;36km;")
        XCTAssertEqual(time,"03:38;;1h21;")
        XCTAssertEqual(WatchGuidancePresentation.arrivalField(clock:"03:38",meters:36_000,seconds:81*60,expanded:false,displayDuration:true),"03:38;ETA;;")
    }
}
