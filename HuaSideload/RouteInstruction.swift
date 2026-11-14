import Foundation

enum RouteInstruction {
    // Inspect maneuver wording before a road name, rather than interpreting
    // street names such as "Left Bank Road" as a left turn.
    static func turn(for text: String) -> PineNavigationWire.Turn {
        let value = text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                 locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("roundabout") || value.contains("vong xuyen") || value.contains("bung binh") { return .unspecified }
        if value.hasPrefix("make a u-turn") || value.hasPrefix("u-turn") || value.hasPrefix("quay dau") { return .uTurn }
        let maneuver = value.components(separatedBy: " onto ").first?
            .components(separatedBy: " into ").first?
            .components(separatedBy: " vao ").first ?? value
        if ["turn left", "keep left", "bear left", "re trai", "giu ben trai"].contains(where: maneuver.hasPrefix) { return .left }
        if ["turn right", "keep right", "bear right", "re phai", "giu ben phai"].contains(where: maneuver.hasPrefix) { return .right }
        if ["arrive", "your destination", "den noi", "da den"].contains(where: value.hasPrefix) { return .destination }
        if ["continue", "head ", "go straight", "di thang", "tiep tuc"].contains(where: value.hasPrefix) { return .straight }
        return .unspecified
    }
}
