import Foundation

// Formatting only: never advances route progress, changes the turn icon or
// manufactures a maneuver. A follow-up describes the immediate next maneuver.
enum WatchGuidancePresentation {
    private static func isTurn(_ turn: PineNavigationWire.Turn) -> Bool {
        turn == .left || turn == .right || turn == .uTurn
    }
    static func followUp(current: PineNavigationWire.Turn,remaining: Double,
                         next: PineNavigationWire.Turn?,gap: Double?) -> String {
        guard isTurn(current),remaining.isFinite,(0...150).contains(remaining),
              let next,isTurn(next),let gap,gap.isFinite,(10...100).contains(gap) else { return "" }
        let meters = max(5,Int((gap/5).rounded())*5)
        return "Sau đó \(next.title.lowercased()) sau \(meters) m"
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
    static func arrivalField(clock: String,meters: Double,seconds: Double,expanded: Bool) -> String {
        let time = String(clock.filter { $0 != ";" && !$0.isNewline }.prefix(12))
        guard expanded,summary(meters:meters,seconds:seconds) != nil else { return time+";ETA;;" }
        // GT 2 Pro has a narrow fixed-height trip area. The 1.3.0 combined
        // "36.0km · 82ph" wrapped and was clipped on the user's watch. Use
        // separate short caption/detail slots, never a combined sentence.
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
        return time+";"+duration+";"+distance+";"
    }
}
