import Foundation

// Mandatory stops are visited in order, with both route progress and a precise
// nearby fix. An overlapping road or later reroute must not silently skip one.
struct RouteStopProgress {
    struct Boundary: Equatable { let id: UUID; let along: Double }
    private(set) var visited = Set<UUID>()
    mutating func reset() { visited.removeAll() }
    func next(in boundaries: [Boundary]) -> Boundary? { boundaries.first { !visited.contains($0.id) } }
    func projectionMaximum(_ proposed: Double, boundaries: [Boundary]) -> Double {
        guard let next = next(in: boundaries) else { return proposed }
        return min(proposed, next.along)
    }
    mutating func arrive(boundaries: [Boundary], along: Double, distance: Double, accuracy: Double) -> UUID? {
        guard let next = next(in: boundaries), along.isFinite, distance.isFinite, accuracy.isFinite,
              (0...25).contains(accuracy), (0...35).contains(distance), abs(along-next.along) <= 40 else { return nil }
        visited.insert(next.id); return next.id
    }
}

enum RouteLegJoiner {
    struct Leg { let path: RouteProgress; let gap: Double }
    struct Joined { let path: RouteProgress; let starts: [Double]; let ends: [Int] }
    static func join(_ legs: [Leg]) -> Joined? {
        guard (1...4).contains(legs.count) else { return nil }
        var points = [RouteProgress.Point](), lengths = [Double](), starts = [Double](), ends = [Int]()
        var total = 0.0
        for (index, leg) in legs.enumerated() {
            guard leg.gap.isFinite, (0...20).contains(leg.gap) else { return nil }
            if index > 0 { lengths.append(leg.gap); total += leg.gap }
            starts.append(total)
            points.append(contentsOf: leg.path.points); lengths.append(contentsOf: leg.path.lengths)
            total += leg.path.totalLength; ends.append(points.count-1)
        }
        guard let path = RouteProgress(points: points,lengths: lengths) else { return nil }
        return Joined(path: path,starts: starts,ends: ends)
    }
}
