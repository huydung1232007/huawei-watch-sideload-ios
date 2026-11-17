import Foundation

// Send fresh GPS guidance roughly once a second, with bounded extra updates at
// critical turn thresholds. The rate limit never delays the phone's own UI.
struct GuidanceRefreshPolicy {
    private var sentAt = -Double.infinity
    private var sentKey: String?
    private var sentDistance: Double?

    mutating func shouldSend(key: String, distance: Double?, now: Double, force: Bool) -> Bool {
        let elapsed = now - sentAt
        let crossedThreshold: Bool
        if let old = sentDistance, let distance, old.isFinite, distance.isFinite {
            crossedThreshold = [50.0, 20, 10, 0].contains { old > $0 && distance <= $0 }
        } else { crossedThreshold = false }
        guard force || elapsed >= 0.9 || (elapsed >= 0.25 && (key != sentKey || crossedThreshold)) else { return false }
        sentAt = now; sentKey = key; sentDistance = distance
        return true
    }
}

enum NavigationFixFreshness {
    static func isFresh(timestamp: Double, now: Double) -> Bool {
        let age = now - timestamp
        return age.isFinite && age >= -2 && age <= 6
    }
    static func accepts(timestamp: Double, now: Double, previous: Double?) -> Bool {
        let age = now - timestamp
        return age.isFinite && age >= -2 && age < 30 && (previous == nil || timestamp > previous!)
    }
}

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
        if isAlert { alert = data; latest = nil; return }
        // While the current BLE request is awaiting its acknowledgement, update
        // a queued alert's distance too. Do not replay an old "190 m" alert ahead
        // of a new "30 m" fix, or vibrate for a turn that is no longer current.
        if let pending = alert,
           let old = try? JSONSerialization.jsonObject(with: Data(pending)) as? [String: String],
           var fresh = try? JSONSerialization.jsonObject(with: Data(data)) as? [String: String],
           let pattern = old["v"], !pattern.isEmpty {
            if old["i"] == fresh["i"], old["p"] == fresh["p"] {
                fresh["v"] = pattern
                if let merged = try? JSONSerialization.data(withJSONObject: fresh,options: [.sortedKeys]) {
                    alert = Array(merged); latest = nil; return
                }
            } else { alert = nil }
        }
        latest = data
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

// Keeps phone GPS navigation alive across transient BLE drops, P2P timeouts or
// closing and reopening Navigation Watch on the wrist.
struct WatchDeliveryPolicy {
    private(set) var watchAppClosed = false
    private(set) var consecutiveFailures = 0
    private var retryAfter = -Double.infinity

    mutating func reset() {
        watchAppClosed = false
        consecutiveFailures = 0
        retryAfter = -Double.infinity
    }
    mutating func watchOpened() { reset() }
    mutating func watchExited() {
        watchAppClosed = true
        consecutiveFailures = 0
        retryAfter = -Double.infinity
    }
    mutating func connectionLost() { reset() }
    func canAttempt(isPaired: Bool, now: Double) -> Bool {
        guard isPaired, !watchAppClosed, now.isFinite else { return false }
        return now >= retryAfter
    }
    mutating func succeeded() {
        consecutiveFailures = 0
        retryAfter = -Double.infinity
    }
    mutating func failed(now: Double) {
        consecutiveFailures += 1
        let delay = min(10.0, Double(consecutiveFailures) * 3.0)
        retryAfter = (now.isFinite ? now : 0) + delay
    }
}

// Interpolates remaining time from per-maneuver/per-leg cumulative durations
// when available, falling back cleanly to distance-proportional scaling.
enum RouteRemainingTime {
    struct Milestone: Equatable {
        let along: Double
        let elapsed: Double
    }
    static func seconds(progress: Double, totalLength: Double, expectedTravelTime: Double, milestones: [Milestone]) -> Double {
        guard totalLength.isFinite, totalLength > 0, expectedTravelTime.isFinite, expectedTravelTime >= 0 else { return 0 }
        let clamped = min(totalLength, max(0, progress.isFinite ? progress : 0))
        let linear = expectedTravelTime * max(0, totalLength - clamped) / totalLength
        guard milestones.count >= 2,
              let first = milestones.first, let last = milestones.last,
              abs(first.along) <= 0.5, abs(first.elapsed) <= 0.5,
              abs(last.along - totalLength) <= 1.0, last.elapsed > 0,
              zip(milestones, milestones.dropFirst()).allSatisfy({
                  $0.0.along.isFinite && $0.1.along.isFinite && $0.0.elapsed.isFinite && $0.1.elapsed.isFinite
                      && $0.1.along >= $0.0.along && $0.1.elapsed >= $0.0.elapsed
              }) else { return linear }
        let scale = expectedTravelTime / last.elapsed
        for (a, b) in zip(milestones, milestones.dropFirst()) where clamped <= b.along {
            let span = b.along - a.along
            let ratio = span > 0.001 ? min(1, max(0, (clamped - a.along) / span)) : 1
            let elapsed = (a.elapsed + (b.elapsed - a.elapsed) * ratio) * scale
            return max(0, expectedTravelTime - elapsed)
        }
        return 0
    }
}

struct RecentSearchQueries {
    static let limit = 6
    static func record(_ raw: String, into existing: [String]) -> [String] {
        let cleaned = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard cleaned.count >= 2 else { return Array(existing.prefix(limit)) }
        let key = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
        let filtered = existing.filter {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) != key
        }
        return Array(([cleaned] + filtered).prefix(limit))
    }
}
