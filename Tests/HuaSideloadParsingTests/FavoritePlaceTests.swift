import XCTest
@testable import HuaSideloadParsing

final class FavoritePlaceTests: XCTestCase {
    private func place(_ name: String = "Nhà") -> FavoritePlace {
        FavoritePlace(name:name,latitude:10.77645,longitude:106.70092,createdAt:Date(timeIntervalSince1970:1_700_000_000))
    }
    private func file() -> FavoritePlacesFile {
        FavoritePlacesFile(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("places.json"))
    }
    func testVietnameseNameIsTrimmedWithoutChangingCoordinatesOrIdentity() throws {
        let original = place("  Nhà của tôi \n")
        let normalized = try original.validated()
        XCTAssertEqual(normalized.name,"Nhà của tôi")
        XCTAssertEqual(normalized.id,original.id)
        XCTAssertEqual(normalized.latitude,original.latitude)
        XCTAssertEqual(normalized.longitude,original.longitude)
        XCTAssertThrowsError(try place(" \n ").validated())
        XCTAssertThrowsError(try place(String(repeating:"á",count:61)).validated())
    }
    func testInvalidCoordinatesAreRejected() {
        for coordinate in [(Double.nan,106.0),(10.0,Double.infinity),(91.0,106.0),(10.0,-181.0)] {
            XCTAssertThrowsError(try FavoritePlace(name:"A",latitude:coordinate.0,longitude:coordinate.1).validated())
        }
        XCTAssertNoThrow(try FavoritePlace(name:"Gốc",latitude:0,longitude:0).validated())
    }
    func testCoordinatesNamesAndIdsSurviveFileRoundTrip() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
        let original = FavoritePlacesFile.Contents(places:[place(),place("Công ty")])
        try file.save(original)
        XCTAssertEqual(try file.load(),original)
    }
    func testRenameAndDeletionDoNotChangeOtherSavedPosition() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
        let first = place(), second = place("Công ty")
        try file.save(.init(places:[first,second]))
        var contents = try file.load(); contents.places[0].name = "Nhà mới"
        try file.save(contents)
        let renamed = try file.load().places[0]
        XCTAssertEqual(renamed.id,first.id)
        XCTAssertEqual(renamed.createdAt,first.createdAt)
        XCTAssertEqual(renamed.latitude,first.latitude)
        contents.places.removeAll { $0.id == first.id }; try file.save(contents)
        XCTAssertEqual(try file.load().places,[second])
    }
    func testBrokenFileIsNotModifiedByLoading() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at:file.url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let broken = Data("broken favorite data".utf8); try broken.write(to:file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf:file.url),broken)
    }
    func testUnsupportedFileVersionIsRejectedWithoutRewriting() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at:file.url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let bytes = Data(#"{"version":2,"places":[]}"#.utf8); try bytes.write(to:file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf:file.url),bytes)
    }
    func testDuplicateIdsCannotReplaceValidFile() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
        let original = place(); try file.save(.init(places:[original]))
        let bytes = try Data(contentsOf:file.url)
        XCTAssertThrowsError(try file.save(.init(places:[original,original])))
        XCTAssertEqual(try Data(contentsOf:file.url),bytes)
    }
    func testInvalidDraftCannotOverwriteSavedFavorites() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
        let original = place(); try file.save(.init(places:[original]))
        XCTAssertThrowsError(try file.save(.init(places:[place("")])))
        XCTAssertEqual(try file.load().places,[original])
    }
    func testGPSCaptureRequiresRecentAccurateFix() {
        XCTAssertTrue(FavoriteGPSFix.usable(timestamp:100,now:105,accuracy:35))
        XCTAssertFalse(FavoriteGPSFix.usable(timestamp:100,now:105.01,accuracy:5))
        XCTAssertFalse(FavoriteGPSFix.usable(timestamp:100,now:101,accuracy:36))
        XCTAssertFalse(FavoriteGPSFix.usable(timestamp:100,now:101,accuracy:-1))
        XCTAssertFalse(FavoriteGPSFix.usable(timestamp:100,now:97,accuracy:5))
        XCTAssertFalse(FavoriteGPSFix.usable(timestamp:100,now:101,accuracy:.nan))
    }
}
