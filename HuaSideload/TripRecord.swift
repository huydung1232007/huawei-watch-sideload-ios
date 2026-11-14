import Foundation

struct TripRecord: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable { case active, completed, stopped, interrupted }
    let id: UUID
    let startedAt: Date
    var endedAt: Date
    let destination: String
    let mode: String
    var distance: Double
    var outcome: Outcome
    var duration: Double { max(0,endedAt.timeIntervalSince(startedAt)) }
    var averageSpeed: Double { duration > 0 ? distance/duration*3.6 : 0 }
    var outcomeLabel: String {
        switch outcome {
        case .active: return "Đang đi"
        case .completed: return "Đã đến nơi"
        case .stopped: return "Đã dừng"
        case .interrupted: return "Gián đoạn"
        }
    }
}

struct TripAccumulator {
    struct Fix {
        let time: Date
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let speed: Double
    }
    private(set) var record: TripRecord
    private var last: Fix?
    private let maximumSpeed: Double

    init(startedAt: Date, destination: String, mode: String, walking: Bool) {
        record = TripRecord(id: UUID(),startedAt: startedAt,endedAt: startedAt,
                            destination: String(destination.prefix(200)),mode: mode,distance: 0,outcome: .active)
        maximumSpeed = walking ? 8 : 80
    }

    mutating func add(_ fix: Fix) {
        guard fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90, abs(fix.longitude) <= 180,
              fix.accuracy.isFinite, fix.accuracy >= 0, fix.accuracy <= 35,
              fix.time >= record.startedAt else { return }
        record.endedAt = max(record.endedAt,fix.time)
        guard let previous = last else { last = fix; return }
        let elapsed = fix.time.timeIntervalSince(previous.time)
        guard elapsed > 0 else { return }
        if elapsed > 30 || (fix.speed >= 0 && fix.speed < 0.4) { last = fix; return }
        let meters = Self.distance(previous,fix)
        if meters/elapsed > maximumSpeed { last = fix; return }
        let minimum = fix.speed < 0 ? max(6,min(40,(previous.accuracy+fix.accuracy)*0.5)) : max(4,min(12,(previous.accuracy+fix.accuracy)*0.2))
        guard (fix.speed >= 0 || elapsed >= 3), meters >= minimum else { return }
        record.distance += meters
        last = fix
    }

    func snapshot(at time: Date, outcome: TripRecord.Outcome = .active) -> TripRecord {
        var result = record
        result.endedAt = max(record.startedAt,time)
        result.outcome = outcome
        return result
    }

    private static func distance(_ a: Fix, _ b: Fix) -> Double {
        let radians = Double.pi/180
        let lat = (b.latitude-a.latitude)*radians, lon = (b.longitude-a.longitude)*radians
        let value = pow(sin(lat/2),2)+cos(a.latitude*radians)*cos(b.latitude*radians)*pow(sin(lon/2),2)
        return 6_371_000*2*atan2(sqrt(max(0,value)),sqrt(max(0,1-value)))
    }
}

struct TripHistoryFile {
    struct Contents: Codable { var version = 1; var records: [TripRecord] = []; var active: TripRecord? }
    let url: URL

    func load() throws -> Contents {
        guard FileManager.default.fileExists(atPath: url.path) else { return Contents() }
        let data = try Data(contentsOf: url)
        let result = try JSONDecoder().decode(Contents.self,from: data)
        guard result.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return result
    }
    func save(_ contents: Contents) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(contents)
        #if os(iOS)
        try data.write(to: url,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        var resourceURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
        #else
        try data.write(to: url,options: .atomic)
        #endif
    }
}
