import Foundation

// Uses GPS COURSE (direction of travel), never phone/watch orientation. Evidence
// consists of fresh, distinct moving fixes with net displacement. No timer or
// settings refresh can manufacture samples. This is a presentation warning,
// never an instruction to perform a new road maneuver or a reroute request.
struct RouteDirectionPolicy {
    enum State: Equatable { case unavailable,checking,following,opposite }
    struct Fix {
        let timestamp: Double
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let speed: Double
        let course: Double
        let courseAccuracy: Double
        func distance(to other: Fix) -> Double {
            let r = Double.pi/180
            let a = latitude*r,b = other.latitude*r
            let dlat = (other.latitude-latitude)*r,dlon = (other.longitude-longitude)*r
            let h = pow(sin(dlat/2),2)+cos(a)*cos(b)*pow(sin(dlon/2),2)
            return 6_371_000*2*asin(sqrt(min(1,max(0,h))))
        }
    }
    private struct Evidence {
        let first: Fix
        var samples: Int
        func meets(_ fix: Fix,seconds: Double,meters: Double) -> Bool {
            samples >= 3 && fix.timestamp-first.timestamp >= seconds && first.distance(to:fix) >= meters
        }
    }
    private(set) var state: State = .unavailable
    private var previousTimestamp: Double?
    private var oppositeEvidence: Evidence?
    private var forwardEvidence: Evidence?
    mutating func reset() { self = RouteDirectionPolicy() }

    static func angularDifference(_ a: Double,_ b: Double) -> Double {
        let difference = abs(a-b).truncatingRemainder(dividingBy:360)
        return min(difference,360-difference)
    }
    mutating func observe(_ fix: Fix,now: Double,routeBearing: Double?,walking: Bool,contextAllowed: Bool) -> State {
        guard contextAllowed,NavigationFixFreshness.isFresh(timestamp:fix.timestamp,now:now),
              let bearing = routeBearing,bearing.isFinite,(0..<360).contains(bearing),
              fix.latitude.isFinite,fix.longitude.isFinite,abs(fix.latitude) <= 90,abs(fix.longitude) <= 180,
              fix.accuracy.isFinite,(0...25).contains(fix.accuracy),
              fix.course.isFinite,(0..<360).contains(fix.course),
              fix.courseAccuracy.isFinite,(0...35).contains(fix.courseAccuracy),
              fix.speed.isFinite,fix.speed >= (walking ? 0.8 : 2),fix.speed <= 80 else {
            reset(); return state
        }
        if let previousTimestamp {
            guard fix.timestamp > previousTimestamp else { return state }
            if fix.timestamp-previousTimestamp > 3 { reset() }
        }
        previousTimestamp = fix.timestamp
        let difference = Self.angularDifference(fix.course,bearing)
        if difference >= 140 {
            forwardEvidence = nil
            if oppositeEvidence == nil { oppositeEvidence = Evidence(first:fix,samples:0) }
            oppositeEvidence!.samples += 1
            if oppositeEvidence!.meets(fix,seconds:4,meters:walking ? 4 : 8) { state = .opposite }
            else if state != .opposite { state = .checking }
        } else if difference <= 60 {
            oppositeEvidence = nil
            if state == .following { return state }
            if forwardEvidence == nil { forwardEvidence = Evidence(first:fix,samples:0) }
            forwardEvidence!.samples += 1
            let recovering = state == .opposite
            if forwardEvidence!.meets(fix,seconds:recovering ? 2 : 1,meters:walking ? 2 : 4) { state = .following }
            else if !recovering { state = .checking }
        } else {
            oppositeEvidence = nil; forwardEvidence = nil
            if state != .opposite { state = .checking }
        }
        return state
    }
}
