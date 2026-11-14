import Foundation

// Independent reader for the documented Valhalla route JSON and polyline6 format.
struct MotorcycleRoute {
    struct Coordinate: Equatable { let latitude: Double; let longitude: Double }
    struct Step { let index: Int; let instruction: String; let turn: PineNavigationWire.Turn }
    let coordinates: [Coordinate]
    let steps: [Step]
    let duration: Double
    let distance: Double

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

    static func request(origin: Coordinate, destination: Coordinate) throws -> Data {
        guard [origin, destination].allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else { throw RouteError.invalid }
        return try JSONSerialization.data(withJSONObject: [
            "locations": [["lat": origin.latitude, "lon": origin.longitude], ["lat": destination.latitude, "lon": destination.longitude]],
            "costing": "motorcycle", "costing_options": ["motorcycle": ["use_highways": 0, "use_tolls": 0, "use_trails": 0]],
            "units": "kilometers", "language": "en-US"
        ])
    }

    static func decode(_ data: Data) throws -> MotorcycleRoute {
        guard data.count < 4_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RouteError.invalid }
        if let error = root["error"] as? String { throw RouteError.provider(error) }
        guard let trip = root["trip"] as? [String: Any], trip["status"] as? Int == 0,
              trip["units"] as? String == "kilometers", let summary = trip["summary"] as? [String: Any],
              let legs = trip["legs"] as? [[String: Any]], legs.count == 1,
              let shape = legs[0]["shape"] as? String,
              let maneuvers = legs[0]["maneuvers"] as? [[String: Any]], !maneuvers.isEmpty,
              let duration = summary["time"] as? Double, duration.isFinite, duration > 0,
              let length = summary["length"] as? Double, length.isFinite, length > 0 else { throw RouteError.invalid }
        // use_highways is a preference, not an exclusion. Independently reject a
        // returned highway route, including highway endpoints; never fall back to auto.
        guard summary["has_highway"] as? Bool == false,
              !maneuvers.contains(where: { $0["highway"] as? Bool == true }) else { throw RouteError.highway }
        let coordinates = try decodeShape(shape)
        var steps: [Step] = []
        var lastIndex = 0
        for maneuver in maneuvers {
            guard maneuver["travel_type"] as? String == "motorcycle" else { throw RouteError.wrongMode }
            guard let index = maneuver["begin_shape_index"] as? Int, index >= lastIndex, index < coordinates.count,
                  let type = maneuver["type"] as? Int, let text = maneuver["instruction"] as? String,
                  !text.isEmpty, text.utf8.count < 4096 else { throw RouteError.invalid }
            let names = (maneuver["street_names"] as? [String])?.prefix(2).joined(separator: " / ") ?? ""
            let direction = turn(type)
            let translated: String
            switch type {
            case 1...3: translated = "Khởi hành" + (names.isEmpty ? " theo tuyến" : " theo " + names)
            case 4...6: translated = "Đến điểm đến"
            case 25: translated = "Nhập làn" + (names.isEmpty ? "" : " vào " + names)
            case 26: translated = "Vào vòng xuyến; ra lối số \(maneuver["roundabout_exit_count"] as? Int ?? 0)"
            case 27: translated = "Ra khỏi vòng xuyến" + (names.isEmpty ? "" : " vào " + names)
            default: translated = direction == .unspecified ? text : direction.title + (names.isEmpty ? "" : " vào " + names)
            }
            steps.append(Step(index: index, instruction: translated, turn: direction))
            lastIndex = index
        }
        return MotorcycleRoute(coordinates: coordinates, steps: steps, duration: duration, distance: length * 1000)
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
