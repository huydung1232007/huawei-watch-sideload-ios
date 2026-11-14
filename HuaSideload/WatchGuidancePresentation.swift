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
        guard expanded,let summary = summary(meters:meters,seconds:seconds) else { return time+";ETA;;" }
        // Observed phone protocol: arrival ; label ; trip detail ; reserved.
        // Keep the four slots and existing arrival/speed fields intact.
        return time+";;"+summary+";"
    }
}
