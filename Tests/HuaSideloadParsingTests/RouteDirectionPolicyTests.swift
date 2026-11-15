import XCTest
@testable import HuaSideloadParsing

final class RouteDirectionPolicyTests: XCTestCase {
    private func fix(_ t: Double,meters: Double,course: Double = 180,speed: Double = 3,
                     accuracy: Double = 5,courseAccuracy: Double = 5,latitude: Double? = nil) -> RouteDirectionPolicy.Fix {
        .init(timestamp:100+t,latitude:latitude ?? (10+meters/111_195),longitude:106,
              accuracy:accuracy,speed:speed,course:course,courseAccuracy:courseAccuracy)
    }
    private func observe(_ policy: inout RouteDirectionPolicy,_ point: RouteDirectionPolicy.Fix,
                         bearing: Double? = 0,walking: Bool = false,allowed: Bool = true,age: Double = 0) -> RouteDirectionPolicy.State {
        policy.observe(point,now:point.timestamp+age,routeBearing:bearing,walking:walking,contextAllowed:allowed)
    }
    private func wrong(_ policy: inout RouteDirectionPolicy) {
        for t in 0...4 { _ = observe(&policy,fix(Double(t),meters:-3*Double(t))) }
        XCTAssertEqual(policy.state,.opposite)
    }
    func testDepartureBehindRouteIsDetectedDespiteProjectionClampingAtZero() throws {
        let route = try XCTUnwrap(RouteProgress(points:[.init(x:0,y:0),.init(x:0,y:-100)],lengths:[100]))
        var policy = RouteDirectionPolicy()
        for t in 0...4 {
            let projection = try XCTUnwrap(route.project(.init(x:0,y:3*Double(t))))
            XCTAssertEqual(projection.along,0)
            let state = observe(&policy,fix(Double(t),meters:-3*Double(t)),bearing:route.stableForwardBearing(at:projection.along))
            XCTAssertEqual(state,t == 4 ? .opposite : .checking)
        }
    }
    func testAlignedCourseNeedsRealSamplesAndMovement() {
        var policy = RouteDirectionPolicy()
        XCTAssertEqual(observe(&policy,fix(0,meters:0,course:0)),.checking)
        XCTAssertEqual(observe(&policy,fix(1,meters:3,course:0)),.checking)
        XCTAssertEqual(observe(&policy,fix(2,meters:6,course:0)),.following)
        XCTAssertEqual(observe(&policy,fix(3,meters:9,course:0)),.following)
    }
    func testPhoneFacingDoesNotEnterPolicyAndNorthWrapIsAligned() {
        XCTAssertEqual(RouteDirectionPolicy.angularDifference(355,5),10)
        var policy = RouteDirectionPolicy()
        for t in 0...2 { _ = observe(&policy,fix(Double(t),meters:3*Double(t),course:355),bearing:5) }
        XCTAssertEqual(policy.state,.following)
    }
    func testSingleOppositeSpikeDoesNotProduceWarning() {
        var policy = RouteDirectionPolicy()
        _ = observe(&policy,fix(0,meters:0))
        for t in 1...3 { _ = observe(&policy,fix(Double(t),meters:3*Double(t),course:0)) }
        XCTAssertEqual(policy.state,.following)
    }
    func testStationaryAndJitterWithoutNetMovementCannotConfirmWrongWay() {
        var policy = RouteDirectionPolicy()
        for t in 0...15 {
            XCTAssertNotEqual(observe(&policy,fix(Double(t),meters:t.isMultiple(of:2) ? 1 : -1)),.opposite)
        }
        XCTAssertEqual(observe(&policy,fix(16,meters:0,speed:0)),.unavailable)
    }
    func testSlowWalkingHasItsOwnMovementThreshold() {
        var policy = RouteDirectionPolicy()
        for t in 0...4 {
            XCTAssertNotEqual(observe(&policy,fix(Double(t),meters:-0.9*Double(t),speed:0.9),walking:true),.opposite)
        }
        XCTAssertEqual(observe(&policy,fix(5,meters:-4.5,speed:0.9),walking:true),.opposite)
        XCTAssertEqual(observe(&policy,fix(6,meters:-5,speed:0.79),walking:true),.unavailable)
    }
    func testPoorGPSUnknownCourseAndInvalidCoordinatesClearWarning() {
        let bad = [fix(5,meters:-15,accuracy:26),fix(5,meters:-15,accuracy:-1),
                   fix(5,meters:-15,courseAccuracy:-1),fix(5,meters:-15,courseAccuracy:36),
                   fix(5,meters:-15,course:-1),fix(5,meters:-15,course:.nan),
                   fix(5,meters:-15,speed:1.9),fix(5,meters:-15,speed:.infinity),
                   fix(5,meters:-15,latitude:.nan),fix(5,meters:-15,latitude:91)]
        for point in bad {
            var policy = RouteDirectionPolicy(); wrong(&policy)
            XCTAssertEqual(observe(&policy,point),.unavailable)
        }
    }
    func testStaleFutureAndLongGapCannotCarryEvidence() {
        var policy = RouteDirectionPolicy(); wrong(&policy)
        XCTAssertEqual(observe(&policy,fix(5,meters:-15),age:7),.unavailable)
        XCTAssertEqual(observe(&policy,fix(6,meters:-18),age:-3),.unavailable)
        for t in 7...9 { _ = observe(&policy,fix(Double(t),meters:-3*Double(t))) }
        XCTAssertEqual(observe(&policy,fix(13,meters:-39)),.checking)
        for t in 14...16 { XCTAssertNotEqual(observe(&policy,fix(Double(t),meters:-3*Double(t))),.opposite) }
        XCTAssertEqual(observe(&policy,fix(17,meters:-51)),.opposite)
    }
    func testRepeatedAndOutOfOrderFixesCannotManufactureSamples() {
        var policy = RouteDirectionPolicy()
        let first = fix(0,meters:0)
        for _ in 0..<10 { XCTAssertEqual(observe(&policy,first),.checking) }
        _ = observe(&policy,fix(1,meters:-3))
        let old = fix(0.5,meters:-1)
        XCTAssertEqual(policy.observe(old,now:102,routeBearing:0,walking:false,contextAllowed:true),.checking)
        XCTAssertNotEqual(observe(&policy,fix(2,meters:-6)),.opposite)
        XCTAssertNotEqual(observe(&policy,fix(3,meters:-9)),.opposite)
        XCTAssertEqual(observe(&policy,fix(4,meters:-12)),.opposite)
    }
    func testCorrectingCourseNeedsSustainedForwardMovement() {
        var policy = RouteDirectionPolicy(); wrong(&policy)
        XCTAssertEqual(observe(&policy,fix(5,meters:-9,course:0)),.opposite)
        XCTAssertEqual(observe(&policy,fix(6,meters:-6,course:0)),.opposite)
        XCTAssertEqual(observe(&policy,fix(7,meters:-3,course:0)),.following)
    }
    func testIntermediateAnglesDoNotFlickerAConfirmedWarning() {
        var policy = RouteDirectionPolicy(); wrong(&policy)
        XCTAssertEqual(observe(&policy,fix(5,meters:-15,course:100)),.opposite)
        XCTAssertEqual(observe(&policy,fix(6,meters:-18,course:139)),.opposite)
        policy.reset()
        for t in 0...6 { XCTAssertEqual(observe(&policy,fix(Double(t),meters:3*Double(t),course:100)),.checking) }
    }
    func testTurnRerouteArrivalAndResetDiscardOldEvidence() {
        var policy = RouteDirectionPolicy(); wrong(&policy)
        XCTAssertEqual(observe(&policy,fix(5,meters:-15),allowed:false),.unavailable)
        XCTAssertEqual(observe(&policy,fix(6,meters:-18)),.checking)
        policy.reset()
        XCTAssertEqual(policy.state,.unavailable)
        XCTAssertEqual(observe(&policy,fix(7,meters:-21)),.checking)
        XCTAssertEqual(observe(&policy,fix(8,meters:-24),bearing:nil),.unavailable)
    }
}
