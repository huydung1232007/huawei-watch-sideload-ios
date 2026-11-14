import XCTest
@testable import HuaSideloadParsing

final class TripRecordTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func fix(_ seconds: Double,longitude: Double,accuracy: Double = 5,speed: Double = 10) -> TripAccumulator.Fix {
        .init(time: start.addingTimeInterval(seconds),latitude: 0,longitude: longitude,accuracy: accuracy,speed: speed)
    }
    func testTracksDistanceDurationAndAverageSpeed() {
        var trip = TripAccumulator(startedAt: start,destination: "Điểm A",mode: "Xe máy",walking: false)
        trip.add(fix(0,longitude: 0)); trip.add(fix(10,longitude: 0.001))
        let result = trip.snapshot(at: start.addingTimeInterval(10),outcome: .completed)
        XCTAssertEqual(result.distance,111.19,accuracy: 0.1)
        XCTAssertEqual(result.duration,10)
        XCTAssertEqual(result.averageSpeed,40.03,accuracy: 0.1)
        XCTAssertEqual(result.outcome,.completed)
    }
    func testStationaryNoiseBadAccuracyAndHugeJumpsAreNotMileage() {
        var trip = TripAccumulator(startedAt: start,destination: "A",mode: "Xe máy",walking: false)
        trip.add(fix(0,longitude: 0)); trip.add(fix(1,longitude: 0.0001,speed: 0))
        trip.add(fix(2,longitude: 0.01,accuracy: 100))
        trip.add(fix(3,longitude: 1))
        XCTAssertEqual(trip.record.distance,0)
    }
    func testLongGPSGapDoesNotJoinUnknownPath() {
        var trip = TripAccumulator(startedAt: start,destination: "A",mode: "Xe máy",walking: false)
        trip.add(fix(0,longitude: 0)); trip.add(fix(100,longitude: 0.01))
        XCTAssertEqual(trip.record.distance,0)
        trip.add(fix(110,longitude: 0.011))
        XCTAssertEqual(trip.record.distance,111.19,accuracy: 0.1)
    }
    func testOutOfOrderAndInvalidLocationsDoNotChangeMileage() {
        var trip = TripAccumulator(startedAt: start,destination: "A",mode: "Đi bộ",walking: true)
        trip.add(fix(5,longitude: 0)); trip.add(fix(4,longitude: 0.001))
        trip.add(fix(6,longitude: .nan)); trip.add(fix(7,longitude: 181))
        XCTAssertEqual(trip.record.distance,0)
        XCTAssertEqual(trip.snapshot(at: start.addingTimeInterval(-1)).duration,0)
    }
    func testHistoryFileRoundTripKeepsAggregateOnlyAndActiveCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = TripHistoryFile(url: directory.appendingPathComponent("trips.json"))
        var trip = TripAccumulator(startedAt: start,destination: "Điểm A",mode: "Xe máy",walking: false)
        trip.add(fix(0,longitude: 0)); trip.add(fix(10,longitude: 0.001))
        let active = trip.snapshot(at: start.addingTimeInterval(10))
        try file.save(.init(records: [],active: active))
        XCTAssertEqual(try file.load().active,active)
        let text = try String(contentsOf: file.url,encoding: .utf8)
        XCTAssertFalse(text.contains("latitude")); XCTAssertFalse(text.contains("longitude"))
        var contents = try file.load()
        contents.active = nil; contents.records = [trip.snapshot(at: start.addingTimeInterval(20),outcome: .stopped)]
        try file.save(contents)
        XCTAssertEqual(try file.load().records.count,1)
        XCTAssertNil(try file.load().active)
    }
    func testMalformedHistoryIsNotModifiedByLoading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let file = TripHistoryFile(url: directory.appendingPathComponent("trips.json"))
        let data = Data("broken history".utf8); try data.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf: file.url),data)
    }
}
