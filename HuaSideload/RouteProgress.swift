import Foundation

// Geometry-only route projection. Coordinate units and segment meter lengths are
// supplied separately, so MapKit's map points retain their correct distance scale.
struct RouteProgress {
    struct Point { let x: Double; let y: Double }
    struct Projection { let along: Double; let crossTrack: Double }
    let points: [Point]
    let lengths: [Double]
    let cumulative: [Double]
    var totalLength: Double { cumulative.last ?? 0 }

    init?(points: [Point], lengths: [Double]) {
        guard points.count >= 2, lengths.count == points.count - 1,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              lengths.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        var sums: [Double] = [0]
        for length in lengths { sums.append(sums.last! + length) }
        guard sums.last! > 0 else { return nil }
        self.points = points; self.lengths = lengths; cumulative = sums
    }

    func project(_ position: Point, minimum: Double = 0, maximum: Double = .infinity,
                 preferred: Double = 0) -> Projection? {
        guard position.x.isFinite, position.y.isFinite, minimum <= maximum else { return nil }
        var best: Projection?
        var bestScore = Double.infinity
        for index in lengths.indices {
            let a = points[index], b = points[index + 1], meters = lengths[index]
            let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
            guard meters > 0, squared > 0,
                  cumulative[index + 1] >= minimum, cumulative[index] <= maximum else { continue }
            let low = max(0, (minimum - cumulative[index]) / meters)
            let high = min(1, (maximum - cumulative[index]) / meters)
            guard low <= high else { continue }
            let t = min(high, max(low, ((position.x - a.x) * dx + (position.y - a.y) * dy) / squared))
            let x = a.x + t * dx, y = a.y + t * dy
            let cross = hypot(position.x - x, position.y - y) * meters / sqrt(squared)
            let along = cumulative[index] + t * meters
            // At a crossing, prefer the nearby part of the route over a distant loop.
            let score = cross + abs(along - preferred) * 0.0001
            if score < bestScore { bestScore = score; best = Projection(along: along, crossTrack: cross) }
        }
        return best
    }

    // MapKit Mercator x points east and y points south. Its local angles are
    // conformal; meter lengths control the sampling window independently of
    // coordinate scale. Reject corners/hairpins rather than averaging across
    // them and mistaking a legitimate turn for opposite travel.
    func stableForwardBearing(at along: Double) -> Double? {
        guard along.isFinite,(0...totalLength).contains(along) else { return nil }
        let start = max(0,along-6),end = min(totalLength,along+6)
        guard end-start >= 4,let a = point(at:start),let b = point(at:end),
              hypot(b.x-a.x,b.y-a.y) > 0 else { return nil }
        func bearing(_ dx: Double,_ dy: Double) -> Double {
            (atan2(dx,-dy)*180/Double.pi+360).truncatingRemainder(dividingBy:360)
        }
        let heading = bearing(b.x-a.x,b.y-a.y)
        let low = max(0,along-20),high = min(totalLength,along+20)
        for i in lengths.indices where lengths[i] > 0 && cumulative[i+1] > low && cumulative[i] < high {
            let dx = points[i+1].x-points[i].x,dy = points[i+1].y-points[i].y
            guard hypot(dx,dy) > 0,RouteDirectionPolicy.angularDifference(heading,bearing(dx,dy)) <= 40 else { return nil }
        }
        return heading
    }
    private func point(at meters: Double) -> Point? {
        for i in lengths.indices where lengths[i] > 0 && meters >= cumulative[i] && meters <= cumulative[i+1] {
            let t = (meters-cumulative[i])/lengths[i]
            return Point(x:points[i].x+(points[i+1].x-points[i].x)*t,
                         y:points[i].y+(points[i+1].y-points[i].y)*t)
        }
        return nil
    }
}
