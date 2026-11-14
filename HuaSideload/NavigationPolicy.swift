import Foundation

struct TurnAlertPolicy {
    private var alerted: [Int: Set<Int>] = [:]
    private var lastAlert = -Double.infinity

    mutating func pattern(maneuver: Int, turn: PineNavigationWire.Turn, distance: Double,
                          elapsed: Double, eligible: Bool) -> String? {
        guard eligible, distance.isFinite, distance >= 0, elapsed >= 8, elapsed-lastAlert >= 4,
              turn != .destination else { return nil }
        let stage = distance <= 50 ? 50 : (distance <= 200 ? 200 : 0)
        guard stage != 0, !(alerted[maneuver] ?? []).contains(stage) else { return nil }
        alerted[maneuver, default: []].insert(stage)
        if stage == 50 { alerted[maneuver, default: []].insert(200) }
        lastAlert = elapsed
        switch turn {
        case .left: return "L"
        case .right: return "R"
        default: return "S"
        }
    }
}

struct ReroutePolicy {
    private var outsideSince: Double?
    private var samples = 0
    private var nextAttempt = -Double.infinity
    private(set) var failures = 0
    var needsManualRetry: Bool { failures >= 3 }

    mutating func observe(offRoute: Bool, accuracy: Double, now: Double) -> Bool {
        guard offRoute, accuracy >= 0, accuracy <= 35 else { resetObservation(); return false }
        if outsideSince == nil { outsideSince = now }
        samples += 1
        guard !needsManualRetry, samples >= 3, now-(outsideSince ?? now) >= 8, now >= nextAttempt else { return false }
        nextAttempt = now+30
        resetObservation()
        return true
    }
    mutating func resetObservation() { outsideSince = nil; samples = 0 }
    mutating func succeeded(now: Double) { failures = 0; nextAttempt = now+30; resetObservation() }
    mutating func failed(now: Double) { failures += 1; nextAttempt = now+min(180,Double(failures)*60); resetObservation() }
    mutating func manualRetry(now: Double) { failures = 0; nextAttempt = now; resetObservation() }
}

// Alerts survive ordinary distance refreshes while waiting for the previous BLE
// acknowledgement. Stop discards both kinds of queued guidance.
struct NavigationOutbox {
    private var latest: [UInt8]?
    private var alert: [UInt8]?
    private var stopping = false
    var hasPending: Bool { stopping || latest != nil || alert != nil }
    mutating func enqueue(_ data: [UInt8], isAlert: Bool) {
        stopping = false
        if isAlert { alert = data; latest = nil } else { latest = data }
    }
    mutating func stop() { latest = nil; alert = nil; stopping = true }
    mutating func clear() { latest = nil; alert = nil; stopping = false }
    mutating func next() -> (data: [UInt8], isStop: Bool)? {
        if stopping { stopping = false; return (PineNavigationWire.stop,true) }
        if let data = alert { alert = nil; return (data,false) }
        if let data = latest { latest = nil; return (data,false) }
        return nil
    }
}
