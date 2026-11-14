import XCTest
@testable import HuaSideloadParsing

final class NavigationPolicyTests: XCTestCase {
    func testOrdinaryDistanceRefreshNoLongerWaitsThreeSeconds() {
        var policy = GuidanceRefreshPolicy()
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 100,now: 0,force: false))
        XCTAssertFalse(policy.shouldSend(key: "left",distance: 95,now: 0.4,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 88,now: 1,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 76,now: 2,force: false))
    }
    func testNearTurnCrossingCanRefreshBeforeOneSecond() {
        var policy = GuidanceRefreshPolicy()
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 55,now: 0,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 49,now: 0.3,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 19,now: 0.6,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 9,now: 0.9,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 0,now: 1.2,force: false))
    }
    func testChangedManeuverAndGPSStateAreNotHeldForOrdinaryCadence() {
        var policy = GuidanceRefreshPolicy()
        _ = policy.shouldSend(key: "left",distance: 0,now: 0,force: false)
        XCTAssertTrue(policy.shouldSend(key: "right",distance: 80,now: 0.3,force: false))
        XCTAssertTrue(policy.shouldSend(key: "gps-stale",distance: nil,now: 0.6,force: false))
    }
    func testThresholdUpdatesAreBoundedAndForceStillPasses() {
        var policy = GuidanceRefreshPolicy()
        _ = policy.shouldSend(key: "left",distance: 55,now: 0,force: false)
        XCTAssertFalse(policy.shouldSend(key: "left",distance: 49,now: 0.1,force: false))
        XCTAssertTrue(policy.shouldSend(key: "left",distance: 48,now: 0.3,force: false))
        XCTAssertFalse(policy.shouldSend(key: "left",distance: 47,now: 0.4,force: false))
        XCTAssertTrue(policy.shouldSend(key: "arrival",distance: 0,now: 0.41,force: true))
    }
    func testOldOrFutureGPSCannotLookFresh() {
        XCTAssertTrue(NavigationFixFreshness.isFresh(timestamp: 100,now: 106))
        XCTAssertFalse(NavigationFixFreshness.isFresh(timestamp: 100,now: 106.01))
        XCTAssertFalse(NavigationFixFreshness.isFresh(timestamp: 100,now: 97))
        XCTAssertFalse(NavigationFixFreshness.isFresh(timestamp: .nan,now: 100))
    }
    func testBatchedLocationsCannotRollProgressBackToOlderFix() {
        XCTAssertTrue(NavigationFixFreshness.accepts(timestamp: 100,now: 101,previous: 99))
        XCTAssertFalse(NavigationFixFreshness.accepts(timestamp: 99,now: 101,previous: 100))
        XCTAssertFalse(NavigationFixFreshness.accepts(timestamp: 100,now: 101,previous: 100))
        XCTAssertFalse(NavigationFixFreshness.accepts(timestamp: 70,now: 101,previous: nil))
        XCTAssertFalse(NavigationFixFreshness.accepts(timestamp: 105,now: 101,previous: nil))
    }
    func testFortyKmhSimulationUsesLatestFixEverySecond() {
        var policy = GuidanceRefreshPolicy()
        var shown = 100.0
        for second in 0...6 {
            let actual = max(0,100-Double(second)*40/3.6)
            if policy.shouldSend(key: "left",distance: actual,now: Double(second),force: false) { shown = actual }
            XCTAssertEqual(shown,actual,accuracy: 0.01)
        }
    }
    func testQueuedAlertUsesLatestDistanceWhileWaitingForBLE() throws {
        var box = NavigationOutbox()
        box.enqueue(try PineNavigationWire.guidance(instruction: "Rẽ trái",distance: "190 m",turn: .left,vibration: "L"),isAlert: true)
        box.enqueue(try PineNavigationWire.guidance(instruction: "Rẽ trái",distance: "30 m",turn: .left),isAlert: false)
        let packet = try XCTUnwrap(box.next())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(packet.data)) as? [String: String])
        XCTAssertEqual(fields["d"],"30 m")
        XCTAssertEqual(fields["v"],"L")
        XCTAssertNil(box.next())
    }
    func testQueuedOldTurnAlertIsDiscardedWhenManeuverChanges() throws {
        var box = NavigationOutbox()
        box.enqueue(try PineNavigationWire.guidance(instruction: "Rẽ trái",distance: "45 m",turn: .left,vibration: "L"),isAlert: true)
        box.enqueue(try PineNavigationWire.guidance(instruction: "Rẽ phải",distance: "80 m",turn: .right),isAlert: false)
        let packet = try XCTUnwrap(box.next())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(packet.data)) as? [String: String])
        XCTAssertEqual(fields["i"],"Rẽ phải")
        XCTAssertEqual(fields["v"],"")
        XCTAssertNil(box.next())
    }
    func testAlertsAtBothThresholdsWithoutRepeating() {
        var policy = TurnAlertPolicy()
        XCTAssertNil(policy.pattern(maneuver: 1,turn: .left,distance: 250,elapsed: 10,eligible: true))
        XCTAssertEqual(policy.pattern(maneuver: 1,turn: .left,distance: 190,elapsed: 11,eligible: true),"L")
        XCTAssertNil(policy.pattern(maneuver: 1,turn: .left,distance: 160,elapsed: 22,eligible: true))
        XCTAssertEqual(policy.pattern(maneuver: 1,turn: .left,distance: 45,elapsed: 30,eligible: true),"L")
        XCTAssertNil(policy.pattern(maneuver: 1,turn: .left,distance: 20,elapsed: 40,eligible: true))
    }
    func testJumpIntoNearZoneDoesNotSendBothAlerts() {
        var policy = TurnAlertPolicy()
        XCTAssertEqual(policy.pattern(maneuver: 2,turn: .right,distance: 40,elapsed: 12,eligible: true),"R")
        XCTAssertNil(policy.pattern(maneuver: 2,turn: .right,distance: 100,elapsed: 30,eligible: true))
    }
    func testNoStartupDestinationOrIneligibleAlert() {
        var policy = TurnAlertPolicy()
        XCTAssertNil(policy.pattern(maneuver: 1,turn: .left,distance: 40,elapsed: 2,eligible: true))
        XCTAssertNil(policy.pattern(maneuver: 1,turn: .destination,distance: 40,elapsed: 10,eligible: true))
        XCTAssertNil(policy.pattern(maneuver: 0,turn: .straight,distance: 0,elapsed: 20,eligible: false))
    }
    func testRerouteNeedsGoodGPSAndSustainedDeviation() {
        var policy = ReroutePolicy()
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 10,now: 0))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 10,now: 4))
        XCTAssertTrue(policy.observe(offRoute: true,accuracy: 10,now: 8))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 10,now: 9))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 10,now: 15))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 10,now: 20))
    }
    func testBadGPSOrReturningToRouteResetsConfirmation() {
        var policy = ReroutePolicy()
        _ = policy.observe(offRoute: true,accuracy: 5,now: 0)
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 70,now: 10))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 12))
        XCTAssertFalse(policy.observe(offRoute: false,accuracy: 5,now: 20))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 21))
    }
    func testBackoffAndThreeFailuresRequireManualRetry() {
        var policy = ReroutePolicy()
        policy.failed(now: 0); policy.failed(now: 60); policy.failed(now: 180)
        XCTAssertTrue(policy.needsManualRetry)
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 1000))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 1010))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 1020))
        policy.manualRetry(now: 1030)
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 1030))
        XCTAssertFalse(policy.observe(offRoute: true,accuracy: 5,now: 1034))
        XCTAssertTrue(policy.observe(offRoute: true,accuracy: 5,now: 1038))
    }
    func testOutboxPreservesAlertAheadOfNewDistanceRefresh() {
        var box = NavigationOutbox()
        box.enqueue([1],isAlert: false)
        box.enqueue([2],isAlert: true)
        box.enqueue([3],isAlert: false)
        XCTAssertEqual(box.next()?.data,[2])
        XCTAssertEqual(box.next()?.data,[3])
        XCTAssertNil(box.next())
    }
    func testStopAndRerouteDiscardOldPendingAlerts() {
        var box = NavigationOutbox()
        box.enqueue([1],isAlert: true); box.stop()
        XCTAssertTrue(box.next()?.isStop == true)
        XCTAssertNil(box.next())
        box.enqueue([2],isAlert: true); box.clear()
        XCTAssertFalse(box.hasPending)
    }
    func testVibrationFieldUsesKnownInterfaceTokensAndClearsOnRefresh() throws {
        let alert = try PineNavigationWire.guidance(instruction: "Rẽ trái",distance: "50 m",turn: .left,vibration: "L")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(alert)) as? [String: String])
        XCTAssertEqual(json["v"],"L")
        let plain = try PineNavigationWire.guidance(instruction: "Rẽ trái",distance: "40 m",turn: .left)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(plain)) as? [String: String])?["v"],"")
        XCTAssertThrowsError(try PineNavigationWire.guidance(instruction: "x",distance: "",turn: .left,vibration: "invalid"))
    }
    func testAutomaticMotorcycleRequestDoesNotAskForAlternatives() throws {
        let request = try MotorcycleRoute.request(origin: .init(latitude: 10,longitude: 106),destination: .init(latitude: 11,longitude: 106),alternatives: false)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: request) as? [String: Any])?["alternates"] as? Int,0)
    }
}
