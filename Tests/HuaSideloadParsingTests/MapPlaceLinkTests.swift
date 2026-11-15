import XCTest
@testable import HuaSideloadParsing

final class MapPlaceLinkTests: XCTestCase {
    private let pin = MapPlaceLink.Coordinate(latitude:10.779783,longitude:106.699018)
    private let direct = "https://www.google.com/maps/search/?api=1&query=10.779783%2C106.699018"
    private func target(_ text: String) throws -> MapPlaceLink.Target? {
        try MapPlaceLink.target(from:MapPlaceLink.url(from:text))
    }
    func testOfficialCoordinateQueryAndSharedText() throws {
        XCTAssertEqual(try target(direct),.coordinate(pin,name:nil))
        XCTAssertEqual(try target("Bưu điện Trung tâm Sài Gòn\n"+direct),.coordinate(pin,name:nil))
        XCTAssertEqual(try target("https://maps.google.com/?q=loc:10.779783,106.699018"),.coordinate(pin,name:nil))
    }
    func testCoordinatePinOutranksViewport() throws {
        let url = "https://www.google.com/maps/place/Central+Post+Office/@11,107,16z/data=!4m2!3d10.779783!4d106.699018"
        XCTAssertEqual(try target(url),.coordinate(pin,name:"Central Post Office"))
        XCTAssertEqual(try target("https://www.google.com/maps?ll=11,107&q=10.779783,106.699018"),.coordinate(pin,name:nil))
    }
    func testExplicitDestinationWinsOverOriginAndRouteData() throws {
        let url = "https://www.google.com/maps/dir/?api=1&origin=11,107&destination=10.779783,106.699018&data=!3d12!4d108"
        XCTAssertEqual(try target(url),.coordinate(pin,name:nil))
        XCTAssertEqual(try target("https://maps.google.com/?saddr=11,107&daddr=10.779783,106.699018"),.coordinate(pin,name:nil))
    }
    func testPathDirectionsUseLastDestinationNotViewport() throws {
        XCTAssertEqual(try target("https://www.google.com/maps/dir/11,107/10.779783,106.699018/@12,108,10z"),.coordinate(pin,name:nil))
        XCTAssertEqual(try target("https://www.google.com/maps/dir/Start/Central+Post+Office/@12,108,10z"),.search("Central Post Office"))
    }
    func testNameAndAddressRequireExplicitSearchSelection() throws {
        XCTAssertEqual(try target("https://www.google.com/maps/search/?api=1&query=Central+Post+Office+Ho+Chi+Minh+City"),.search("Central Post Office Ho Chi Minh City"))
        XCTAssertEqual(try target("https://www.google.com/maps/place/B%C6%B0u+%C4%91i%E1%BB%87n+Trung+t%C3%A2m/"),.search("Bưu điện Trung tâm"))
    }
    func testViewportStreetViewAndPlaceIdAreNotGuessedPins() throws {
        for url in ["https://www.google.com/maps/@11,107,16z", "https://maps.google.com/?ll=11,107", "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=11,107", "https://www.google.com/maps/search/?api=1&query=place_id:ChIJabc"] {
            XCTAssertNil(try target(url))
        }
    }
    func testInvalidCoordinatesAreRejected() {
        for query in ["91,106","10,181","-91,-181"] {
            XCTAssertThrowsError(try target("https://maps.google.com/?q="+query))
        }
        XCTAssertThrowsError(try target("https://www.google.com/maps/place/X/data=!3d91!4d106"))
    }
    func testAmbiguousMultiplePinsAreRejected() {
        XCTAssertThrowsError(try target("https://www.google.com/maps/place/X/data=!3d10!4d106!3d11!4d107"))
    }
    func testOnlySupportedGoogleMapsHostsAndPathsCanBeRequested() {
        for url in ["https://maps.app.goo.gl.evil.example/token", "https://evil.example/?q=10,106", "https://google.com@evil.example/maps?q=10,106", "https://www.google.com:8443/maps?q=10,106", "https://www.google.com/search?q=10,106", "https://goo.gl/other/token", "file:///tmp/test", "http://127.0.0.1/maps", "https://consent.google.com/maps", "https://www.google.com/maps?q=10,106 https://maps.google.com/?q=11,107"] {
            XCTAssertThrowsError(try MapPlaceLink.url(from:url),url)
        }
        XCTAssertThrowsError(try MapPlaceLink.url(from:String(repeating:"a",count:17_000)))
    }
    func testHttpIsUpgradedAndCountryDomainSupported() throws {
        let url = try MapPlaceLink.url(from:"http://www.google.com.vn/maps?q=10.779783,106.699018#fragment")
        XCTAssertEqual(url.scheme,"https"); XCTAssertNil(url.fragment)
        XCTAssertEqual(try MapPlaceLink.target(from:url),.coordinate(pin,name:nil))
    }
    func testCanonicalHtmlMetadataRecoversPinAndIgnoresArbitraryLinks() throws {
        let html = "<html><a href='https://maps.google.com/?q=11,107'>Other</a><meta property='og:url' content='https://maps.google.com/?q=10.779783,106.699018&amp;entry=test'></html>"
        XCTAssertEqual(try MapPlaceLink.target(inHTML:html),.coordinate(pin,name:nil))
        XCTAssertNil(try MapPlaceLink.target(inHTML:"<a href='https://maps.google.com/?q=11,107'>Other</a>"))
        XCTAssertNil(try MapPlaceLink.target(inHTML:"<meta property='og:url' content='https://evil.example/?q=11,107'>"))
    }
    func testHtmlConflictingPinsRejectedAndSamePinDeduplicated() throws {
        let meta = "<meta property='og:url' content='https://maps.google.com/?q=10.779783,106.699018'>"
        let same = "<link rel='canonical' href='https://www.google.com/maps/place/Post+Office/data=!3d10.779783!4d106.699018'>"
        XCTAssertNotNil(try MapPlaceLink.target(inHTML:meta+same))
        XCTAssertThrowsError(try MapPlaceLink.target(inHTML:meta+"<link rel='canonical' href='https://maps.google.com/?q=11,107'>"))
    }
    func testDirectPinWorksWithoutNetwork() async throws {
        let resolver = MapPlaceLinkResolver { _ in XCTFail("Direct coordinates must not need network"); throw URLError(.notConnectedToInternet) }
        let value = try await resolver.resolve(direct)
        XCTAssertEqual(value,.coordinate(pin,name:nil))
    }
    func testShortLinkRedirectResolvesPin() async throws {
        let resolver = MapPlaceLinkResolver { url in
            XCTAssertEqual(url.host,"maps.app.goo.gl")
            return .init(status:302,location:"https://www.google.com/maps/place/Post+Office/@11,107,16z/data=!3d10.779783!4d106.699018")
        }
        let value = try await resolver.resolve("https://maps.app.goo.gl/testToken")
        XCTAssertEqual(value,.coordinate(pin,name:"Post Office"))
    }
    func testShortLinkCanResolveNameWithoutChoosingSearchResult() async throws {
        let resolver = MapPlaceLinkResolver { _ in .init(status:302,location:"https://www.google.com/maps/place/Post+Office/") }
        let value = try await resolver.resolve("https://goo.gl/maps/testToken")
        XCTAssertEqual(value,.search("Post Office"))
        // Same query/ftid shape as the real sample, using only a public landmark
        // and a synthetic identifier; no user link/address is published.
        let query = MapPlaceLinkResolver { _ in .init(status:302,location:"https://maps.google.com?q=B%C6%B0u+%C4%91i%E1%BB%87n+Trung+t%C3%A2m,+H%E1%BB%93+Ch%C3%AD+Minh&ftid=0x1:0x2&g_st=ic") }
        let address = try await query.resolve("https://maps.app.goo.gl/testToken?g_st=ic")
        XCTAssertEqual(address,.search("Bưu điện Trung tâm, Hồ Chí Minh"))
    }
    func testRedirectToUnapprovedHostCannotBeFetched() async {
        let resolver = MapPlaceLinkResolver { url in
            XCTAssertEqual(url.host,"maps.app.goo.gl")
            return .init(status:302,location:"https://evil.example/maps?q=10,106")
        }
        do { _ = try await resolver.resolve("https://maps.app.goo.gl/testToken"); XCTFail("Must reject redirect") }
        catch { XCTAssertTrue(error is MapPlaceLink.LinkError) }
    }
    func testRedirectLoopAndMissingLocationFail() async {
        let loop = MapPlaceLinkResolver { _ in .init(status:302,location:"https://maps.app.goo.gl/testToken") }
        let broken = MapPlaceLinkResolver { _ in .init(status:302) }
        for resolver in [loop,broken] {
            do { _ = try await resolver.resolve("https://maps.app.goo.gl/testToken"); XCTFail("Must fail") }
            catch { XCTAssertTrue(error is MapPlaceLink.LinkError) }
        }
    }
    func testShortLinkHtmlFallbackAndOfflineError() async throws {
        let html = MapPlaceLinkResolver { _ in .init(status:200,html:"<link rel='canonical' href='https://maps.google.com/?q=10.779783,106.699018'>") }
        let value = try await html.resolve("https://maps.app.goo.gl/testToken")
        XCTAssertEqual(value,.coordinate(pin,name:nil))
        let offline = MapPlaceLinkResolver { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await offline.resolve("https://maps.app.goo.gl/testToken"); XCTFail("Must fail offline") }
        catch { XCTAssertTrue(error is MapPlaceLink.LinkError) }
    }
    func testCancellationStopsResolution() async {
        let resolver = MapPlaceLinkResolver { _ in try await Task.sleep(for:.seconds(30)); return .init(status:200) }
        let task = Task { try await resolver.resolve("https://maps.app.goo.gl/testToken") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
