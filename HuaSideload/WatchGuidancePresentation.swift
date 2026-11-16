import Foundation

// Formatting only: never advances route progress, changes the turn icon or
// manufactures a maneuver. A follow-up describes the immediate next maneuver.
enum WatchGuidancePresentation {
    private struct AdjacentTurn {
        let turn: PineNavigationWire.Turn
        let meters: Int
    }
    private static func isTurn(_ turn: PineNavigationWire.Turn) -> Bool {
        turn == .left || turn == .right || turn == .uTurn
    }
    private static func adjacentTurn(current: PineNavigationWire.Turn,remaining: Double,
                                     next: PineNavigationWire.Turn?,gap: Double?) -> AdjacentTurn? {
        guard isTurn(current),remaining.isFinite,(0...150).contains(remaining),
              let next,isTurn(next),let gap,gap.isFinite,(10...100).contains(gap) else { return nil }
        return AdjacentTurn(turn:next,meters:max(5,Int((gap/5).rounded())*5))
    }
    static func followUp(current: PineNavigationWire.Turn,remaining: Double,
                         next: PineNavigationWire.Turn?,gap: Double?) -> String {
        guard let following = adjacentTurn(current:current,remaining:remaining,next:next,gap:gap) else { return "" }
        return "Sau đó \(following.turn.title.lowercased()) sau \(following.meters) m"
    }
    // The speed field has value;unit slots. Show the FOLLOWING maneuver, never
    // the primary arrow. A straight step uses its segment length, not the gap
    // to that step; a turn uses the distance after the current turn to that turn.
    // Rendering these arrow glyphs still needs confirmation on Navigation Watch.
    static func speedField(metersPerSecond: Double,next: PineNavigationWire.Turn?,gap: Double?,
                           straightLength: Double?,showFollowing: Bool,showSpeed: Bool = true) -> String {
        if showFollowing,let next,let gap,gap.isFinite,gap >= 0,(next == .straight || gap > 0),
           let distance = next == .straight ? straightLength : gap,
           distance.isFinite,(1...20_000_000).contains(distance) {
            let symbol: String
            switch next {
            case .straight: symbol = "↑"
            case .left: symbol = "←"
            case .right: symbol = "→"
            case .uTurn: symbol = "↶"
            case .destination: symbol = showSpeed ? "" : "•"
            default: symbol = ""
            }
            if !symbol.isEmpty { return symbol+";"+followingDistance(distance) }
        }
        guard showSpeed else { return "" }
        guard metersPerSecond.isFinite,metersPerSecond >= 0 else { return "" }
        let kmh = metersPerSecond*3.6
        guard kmh.isFinite else { return "" }
        return String(format:"%.0f;km/h",locale:Locale(identifier:"en_US_POSIX"),kmh)
    }
    private static func followingDistance(_ meters: Double) -> String {
        if meters < 1000 {
            let rounded = max(5,Int((meters/5).rounded())*5)
            return rounded >= 1000 ? "1km" : "\(rounded)m"
        }
        let km = (meters/100).rounded()/10
        if km < 10 {
            return km == km.rounded() ? "\(Int(km))km" : String(format:"%.1fkm",locale:Locale(identifier:"en_US_POSIX"),km)
        }
        return km <= 999 ? "\(Int(km.rounded()))km" : ">999km"
    }
    static func instruction(_ primary: String,followUp: String) -> String {
        guard !followUp.isEmpty else { return String(primary.prefix(180)) }
        let suffix = "; " + String(followUp.prefix(65))
        let limit = 180-suffix.count
        let first = primary.count > limit ? String(primary.prefix(limit-1))+"…" : primary
        return first+suffix
    }
    static func summary(meters: Double,seconds: Double) -> String? {
        guard meters.isFinite,(0...20_000_000).contains(meters),seconds.isFinite,
              seconds > 0,seconds <= 604_800 else { return nil }
        let distance = meters >= 1000 ? String(format:"%.1fkm",locale:Locale(identifier:"en_US_POSIX"),meters/1000)
            : "\(max(0,Int((meters/5).rounded())*5))m"
        return "\(distance) · \(max(1,Int(ceil(seconds/60))))ph"
    }
    static func arrivalField(clock: String,meters: Double,seconds: Double,expanded: Bool,displayDuration: Bool = false) -> String {
        let time = String(clock.filter { $0 != ";" && !$0.isNewline }.prefix(12))
        guard expanded,summary(meters:meters,seconds:seconds) != nil else { return time+";ETA;;" }
        // Hardware feedback: the third slot is visible but long combined text
        // clips, while the second caption slot is ignored on this GT 2 Pro.
        // Alternate short values in the confirmed visible third slot.
        let minutes = max(1,Int(ceil(seconds/60)))
        let duration: String
        if minutes < 60 { duration = "\(minutes)p" }
        else if minutes % 60 == 0 { duration = "\(minutes/60)h" }
        else { duration = String(format:"%dh%02d",minutes/60,minutes%60) }
        let roundedKm = (meters/100).rounded()/10
        let distance: String
        if meters < 1000 { distance = "\(max(0,Int((meters/5).rounded())*5))m" }
        else if roundedKm < 10 { distance = String(format:"%.1fkm",locale:Locale(identifier:"en_US_POSIX"),roundedKm) }
        else if roundedKm <= 999 { distance = "\(Int(roundedKm.rounded()))km" }
        else { distance = ">999km" }
        return time+";;"+(displayDuration ? duration : distance)+";"
    }
}

// Latch below 100 m so GPS jitter cannot flip back to speed before this
// maneuver is passed. RouteNavigator owns maneuver advancement and all resets.
struct FollowingManeuverPolicy {
    private var activeManeuver: Int?
    mutating func reset() { activeManeuver = nil }
    mutating func shouldShow(maneuver: Int,current: PineNavigationWire.Turn,remaining: Double,enabled: Bool,always: Bool = false) -> Bool {
        if always {
            reset()
            return remaining.isFinite && remaining >= 0
        }
        guard enabled,remaining.isFinite,remaining >= 0,
              current == .left || current == .right || current == .uTurn else {
            reset(); return false
        }
        if activeManeuver != maneuver { reset() }
        if remaining < 100 { activeManeuver = maneuver }
        return activeManeuver == maneuver
    }
}
