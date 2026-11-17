import Foundation

// Mandatory stops are visited in order, with both route progress and a precise
// nearby fix. An overlapping road or later reroute must not silently skip one.
struct RouteStopProgress {
    struct Boundary: Equatable { let id: UUID; let along: Double }
    private(set) var visited = Set<UUID>()
    private var pendingStop: UUID?
    private var nearbySamples = 0
    mutating func reset() { visited.removeAll(); pendingStop = nil; nearbySamples = 0 }
    func next(in boundaries: [Boundary]) -> Boundary? { boundaries.first { !visited.contains($0.id) } }
    func projectionMaximum(_ proposed: Double, boundaries: [Boundary]) -> Double {
        guard let next = next(in: boundaries) else { return proposed }
        return min(proposed, next.along)
    }
    mutating func arrive(boundaries: [Boundary], along: Double, distance: Double, accuracy: Double) -> UUID? {
        guard let next = next(in: boundaries), along.isFinite, distance.isFinite, accuracy.isFinite,
              accuracy >= 0, distance >= 0 else {
            pendingStop = nil; nearbySamples = 0; return nil
        }
        if accuracy <= 25, distance <= 35, abs(along - next.along) <= 40 {
            visited.insert(next.id); pendingStop = nil; nearbySamples = 0
            return next.id
        }
        // Urban storefronts, gas stations or divided roads can sit 35-55 m from the
        // kerb or under light canopy. Accept 3 consecutive nearby fixes without
        // letting a single noisy sample skip a mandatory stop.
        if accuracy <= 40, distance <= 55, abs(along - next.along) <= 60 {
            if pendingStop == next.id { nearbySamples += 1 }
            else { pendingStop = next.id; nearbySamples = 1 }
            if nearbySamples >= 3 {
                visited.insert(next.id); pendingStop = nil; nearbySamples = 0
                return next.id
            }
            return nil
        }
        pendingStop = nil; nearbySamples = 0
        return nil
    }
    mutating func skipNext(in boundaries: [Boundary]) -> UUID? {
        guard let next = next(in: boundaries) else { return nil }
        visited.insert(next.id); pendingStop = nil; nearbySamples = 0
        return next.id
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
