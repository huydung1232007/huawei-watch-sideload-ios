import Foundation

// The Share extension does not require App Groups or shared Keychain access.
// Explicitly shared Google Maps URLs are handed off through a local-only,
// short-lived pasteboard item; the main app validates it again before preview.
struct MapShareEnvelope: Codable, Identifiable, Equatable {
    static let pasteboardType = "com.huasideload.map-share.v1"
    let version: Int
    let id: UUID
    let created: Double
    let link: String

    init(text: String, now: Date = Date()) throws {
        version = 1; id = UUID(); created = now.timeIntervalSince1970
        link = try MapPlaceLink.url(from:text).absoluteString
    }
    static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        guard data.count <= 16_384, let item = try? JSONDecoder().decode(Self.self,from:data),
              item.version == 1,item.created.isFinite,
              (-30...600).contains(now.timeIntervalSince1970-item.created),
              (try? MapPlaceLink.validated(URL(string:item.link) ?? URL(fileURLWithPath:"/"))) != nil else {
            throw MapPlaceLink.LinkError.invalidLink
        }
        return item
    }
    static func fromAppURL(_ url: URL, now: Date = Date()) throws -> Self {
        guard url.absoluteString.utf8.count <= 24_000,
              let parts = URLComponents(url:url,resolvingAgainstBaseURL:false),
              parts.scheme?.lowercased() == "huasideload",parts.host == "maps",
              parts.user == nil,parts.password == nil,parts.port == nil,
              parts.path.isEmpty || parts.path == "/",parts.fragment == nil,
              let items = parts.queryItems,items.count == 1,items[0].name == "url",let text = items[0].value else {
            throw MapPlaceLink.LinkError.invalidLink
        }
        return try Self(text:text,now:now)
    }
}
