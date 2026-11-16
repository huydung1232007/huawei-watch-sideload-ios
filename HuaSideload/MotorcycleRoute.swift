import Foundation

// Independent reader for the documented Valhalla route JSON and polyline6 format.
struct MotorcycleRoute {
    struct Coordinate: Equatable { let latitude: Double; let longitude: Double }
    struct Step { let index: Int; let instruction: String; let turn: PineNavigationWire.Turn }
    let coordinates: [Coordinate]
    let steps: [Step]
    let duration: Double
    let distance: Double
    let via: String
    var stopEndIndexes: [Int] = []

    enum RouteError: LocalizedError {
        case invalid, highway, wrongMode, provider(String)
        var errorDescription: String? {
            switch self {
            case .invalid: return "Dữ liệu tuyến xe máy không hợp lệ."
            case .highway: return "Tuyến trả về có cao tốc hoặc thiếu thông tin kiểm tra cao tốc. Chưa thể dùng tuyến này cho xe máy."
            case .wrongMode: return "Máy chủ không trả về tuyến xe máy."
            case .provider(let text): return "Không tính được tuyến xe máy: " + String(text.prefix(160))
            }
        }
    }

    static func request(origin: Coordinate, destination: Coordinate, alternatives: Bool = true, stops: [Coordinate] = []) throws -> Data {
        let places = [origin] + stops + [destination]
        guard stops.count <= 3, places.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else { throw RouteError.invalid }
        return try JSONSerialization.data(withJSONObject: [
            "locations": places.map { ["lat": $0.latitude, "lon": $0.longitude, "type": "break"] as [String: Any] },
            "costing": "motorcycle", "costing_options": ["motorcycle": ["use_highways": 0, "use_tolls": 0, "use_trails": 0]],
            "units": "kilometers", "language": "en-US", "alternates": alternatives && stops.isEmpty ? 2 : 0
        ])
    }

    static func decode(_ data: Data) throws -> MotorcycleRoute {
        guard data.count < 4_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RouteError.invalid }
        if let error = root["error"] as? String { throw RouteError.provider(error) }
        guard let trip = root["trip"] as? [String: Any], trip["status"] as? Int == 0,
              trip["units"] as? String == "kilometers", let summary = trip["summary"] as? [String: Any],
              let legs = trip["legs"] as? [[String: Any]], (1...4).contains(legs.count),
              let duration = summary["time"] as? Double, duration.isFinite, duration > 0,
              let length = summary["length"] as? Double, length.isFinite, length > 0 else { throw RouteError.invalid }
        // use_highways is a preference, not an exclusion. Independently reject a
        // returned highway route, including highway endpoints; never fall back to auto.
        guard summary["has_highway"] as? Bool == false else { throw RouteError.highway }
        var coordinates = [Coordinate](), stopEnds = [Int](), allManeuvers = [[String: Any]]()
        var steps: [Step] = []
        for (legIndex, leg) in legs.enumerated() {
        guard let shape = leg["shape"] as? String, let maneuvers = leg["maneuvers"] as? [[String: Any]], !maneuvers.isEmpty else { throw RouteError.invalid }
        guard !maneuvers.contains(where: { $0["highway"] as? Bool == true }),
              (leg["summary"] as? [String: Any])?["has_highway"] as? Bool != true else { throw RouteError.highway }
        let legPoints = try decodeShape(shape)
        let duplicate = coordinates.last == legPoints.first
        if let previous = coordinates.last, let first = legPoints.first {
            let lat = (first.latitude-previous.latitude)*Double.pi/180
            let lon = (first.longitude-previous.longitude)*Double.pi/180
            let value = pow(sin(lat/2),2)+cos(first.latitude*Double.pi/180)*cos(previous.latitude*Double.pi/180)*pow(sin(lon/2),2)
            guard 6_371_000*2*atan2(sqrt(max(0,value)),sqrt(max(0,1-value))) <= 20 else { throw RouteError.invalid }
        }
        let offset = duplicate ? coordinates.count-1 : coordinates.count
        coordinates.append(contentsOf: duplicate ? Array(legPoints.dropFirst()) : legPoints)
        guard coordinates.count <= 100_000 else { throw RouteError.invalid }
        var lastIndex = 0
        for maneuver in maneuvers {
            guard maneuver["travel_type"] as? String == "motorcycle" else { throw RouteError.wrongMode }
            guard let index = maneuver["begin_shape_index"] as? Int, index >= lastIndex, index < legPoints.count,
                  let type = maneuver["type"] as? Int, let text = maneuver["instruction"] as? String,
                  !text.isEmpty, text.utf8.count < 4096 else { throw RouteError.invalid }
            let names = (maneuver["street_names"] as? [String])?.prefix(2).joined(separator: " / ") ?? ""
            let direction = turn(type)
            let translated: String
            switch type {
            case 1...3: translated = "Khởi hành" + (names.isEmpty ? " theo tuyến" : " theo " + names)
            case 4...6: translated = legIndex < legs.count-1 ? "Đến điểm dừng \(legIndex+1)" : "Đến điểm đến"
            case 25: translated = "Nhập làn" + (names.isEmpty ? "" : " vào " + names)
            case 26:
                if let count = maneuver["roundabout_exit_count"] as? Int, count > 0 { translated = "Vào vòng xuyến; ra lối số \(count)" }
                else { translated = "Vào vòng xuyến — theo tuyến" }
            case 27: translated = "Ra khỏi vòng xuyến" + (names.isEmpty ? "" : " vào " + names)
            default: translated = direction == .unspecified ? text : direction.title + (names.isEmpty ? "" : " vào " + names)
            }
            steps.append(Step(index: offset+index, instruction: translated, turn: direction))
            lastIndex = index
        }
        if legIndex < legs.count-1 { stopEnds.append(coordinates.count-1) }
        allManeuvers.append(contentsOf: maneuvers)
        }
        let namedRoads: [(String, Double)] = allManeuvers.compactMap { maneuver in
            guard let name = (maneuver["street_names"] as? [String])?.first, !name.isEmpty else { return nil }
            return (name, maneuver["length"] as? Double ?? 0)
        }.sorted { $0.1 > $1.1 }
        var roads: [String] = []
        for (name, _) in namedRoads where !roads.contains(name) {
            roads.append(name)
            if roads.count == 2 { break }
        }
        return MotorcycleRoute(coordinates: coordinates, steps: steps, duration: duration, distance: length * 1000,
                               via: String(roads.joined(separator: " · ").prefix(140)),stopEndIndexes: stopEnds)
    }

    static func decodeOptions(_ data: Data) throws -> [MotorcycleRoute] {
        guard data.count < 4_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RouteError.invalid }
        if let error = root["error"] as? String { throw RouteError.provider(error) }
        let candidates = [root] + Array(((root["alternates"] as? [[String: Any]]) ?? []).prefix(2))
        var routes: [MotorcycleRoute] = []
        var firstError: Error?
        for candidate in candidates {
            do {
                let value = try decode(JSONSerialization.data(withJSONObject: candidate))
                if !routes.contains(where: { $0.coordinates == value.coordinates }) { routes.append(value) }
            } catch { if firstError == nil { firstError = error } }
        }
        guard !routes.isEmpty else { throw firstError ?? RouteError.invalid }
        return routes
    }

    static func turn(_ type: Int) -> PineNavigationWire.Turn {
        switch type {
        case 4...6: return .destination
        case 7, 8, 17, 22: return .straight
        case 9...11, 18, 20, 23, 37: return .right
        case 12, 13: return .uTurn
        case 14...16, 19, 21, 24, 38: return .left
        default: return .unspecified
        }
    }

    static func decodeShape(_ shape: String) throws -> [Coordinate] {
        let bytes = Array(shape.utf8)
        guard bytes.count < 2_000_000 else { throw RouteError.invalid }
        var cursor = 0, latitude: Int64 = 0, longitude: Int64 = 0
        func delta() throws -> Int64 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while cursor < bytes.count, shift <= 30 {
                let byte = bytes[cursor]; cursor += 1
                guard (63...126).contains(byte) else { throw RouteError.invalid }
                let value = UInt64(byte - 63)
                result |= (value & 31) << shift
                if value < 32 { return result & 1 == 0 ? Int64(result >> 1) : -Int64(result >> 1) - 1 }
                shift += 5
            }
            throw RouteError.invalid
        }
        var points: [Coordinate] = []
        while cursor < bytes.count {
            latitude += try delta(); longitude += try delta()
            let point = Coordinate(latitude: Double(latitude) / 1e6, longitude: Double(longitude) / 1e6)
            guard abs(point.latitude) <= 90, abs(point.longitude) <= 180, points.count < 100_000 else { throw RouteError.invalid }
            points.append(point)
        }
        guard points.count >= 2 else { throw RouteError.invalid }
        return points
    }
}
