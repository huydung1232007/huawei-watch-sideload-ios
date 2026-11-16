import XCTest
@testable import HuaSideloadParsing

final class MapShareEnvelopeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970:1_000_000)
    private let link = "https://www.google.com/maps/search/?api=1&query=10.779783,106.699018"
    func testSharedLinkRoundTripsWithoutChangingLocation() throws {
        let value = try MapShareEnvelope(text:"Bưu điện \n"+link,now:now)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try MapShareEnvelope.decode(data,now:now),value)
        XCTAssertEqual(try MapShareEnvelope.decode(data,now:now.addingTimeInterval(600)),value)
        XCTAssertThrowsError(try MapShareEnvelope.decode(data,now:now.addingTimeInterval(601)))
        XCTAssertThrowsError(try MapShareEnvelope.decode(data,now:now.addingTimeInterval(-31)))
    }
    func testUnsafeTamperedOrOversizedHandoffIsRejected() throws {
        let data = try JSONEncoder().encode(MapShareEnvelope(text:link,now:now))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for (key,value) in [("link","https://evil.example/maps" as Any),("version",2 as Any),("link","file:///private/data" as Any)] {
            var changed = original; changed[key] = value
            XCTAssertThrowsError(try MapShareEnvelope.decode(JSONSerialization.data(withJSONObject:changed),now:now))
        }
        XCTAssertThrowsError(try MapShareEnvelope.decode(Data(repeating:32,count:16_385),now:now))
    }
    func testAppURLHasOneExplicitGoogleMapsLink() throws {
        var parts = URLComponents(); parts.scheme = "huasideload"; parts.host = "maps"
        parts.queryItems = [.init(name:"url",value:link)]
        XCTAssertEqual(try MapShareEnvelope.fromAppURL(XCTUnwrap(parts.url),now:now).link,link)
        parts.queryItems?.append(.init(name:"url",value:link))
        XCTAssertThrowsError(try MapShareEnvelope.fromAppURL(XCTUnwrap(parts.url),now:now))
        parts.queryItems = [.init(name:"url",value:"https://example.com/maps")]
        XCTAssertThrowsError(try MapShareEnvelope.fromAppURL(XCTUnwrap(parts.url),now:now))
    }
}
