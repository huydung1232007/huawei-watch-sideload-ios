import CoreFoundation
import Foundation

// Independent reader of the public Google Maps web embed's JSON bootstrap.
// This web format is not a stable API. Accept only a point descriptor whose
// full feature ID and decimal CID agree with the requested place; never camera
// coordinates, a static-map center or a similarly named search result.
struct GooglePlaceIdentity: Equatable {
    private let high: UInt64?
    private let low: UInt64
    var decimalCID: String { String(low) }
    var embedURL: URL {
        var parts = URLComponents(string:"https://www.google.com/maps")!
        parts.queryItems = [.init(name:"cid",value:decimalCID),.init(name:"output",value:"embed"),.init(name:"hl",value:"vi")]
        return parts.url!
    }
    init?(ftid: String) {
        let pair = ftid.lowercased().components(separatedBy:":")
        guard pair.count == 2,pair.allSatisfy({ $0.hasPrefix("0x") }),
              let high = UInt64(pair[0].dropFirst(2),radix:16),
              let low = UInt64(pair[1].dropFirst(2),radix:16),low > 0 else { return nil }
        self.high = high; self.low = low
    }
    init?(cid: String) {
        guard !cid.isEmpty,cid.utf8.allSatisfy({ (48...57).contains($0) }),let low = UInt64(cid),low > 0 else { return nil }
        high = nil; self.low = low
    }
    static func from(_ url: URL) throws -> GooglePlaceIdentity? {
        let parts = URLComponents(url:url,resolvingAgainstBaseURL:false)!
        let items = parts.queryItems ?? []
        // These IDs belong to a place link, not an arbitrary endpoint in a
        // multi-stop directions URL. Explicit destination handling stays intact.
        if parts.path.hasPrefix("/maps/dir") || items.contains(where:{ ["destination","daddr"].contains($0.name) }) { return nil }
        let ftids = Set(items.filter { $0.name == "ftid" }.compactMap(\.value).filter { !$0.isEmpty })
        let cids = Set(items.filter { $0.name == "cid" }.compactMap(\.value).filter { !$0.isEmpty })
        guard ftids.count <= 1,cids.count <= 1 else { throw MapPlaceLink.LinkError.exactPinUnavailable }
        if let text = ftids.first {
            guard let id = GooglePlaceIdentity(ftid:text) else { throw MapPlaceLink.LinkError.exactPinUnavailable }
            if let cid = cids.first,GooglePlaceIdentity(cid:cid)?.low != id.low { throw MapPlaceLink.LinkError.exactPinUnavailable }
            return id
        }
        if let cid = cids.first {
            guard let id = GooglePlaceIdentity(cid:cid) else { throw MapPlaceLink.LinkError.exactPinUnavailable }
            return id
        }
        return nil
    }

    func pin(inHTML html: String) throws -> MapPlaceLink.Target? {
        guard html.utf8.count <= 512*1024 else { return nil }
        let regex = try NSRegularExpression(pattern:#"initEmbed\s*\(\s*(?=\[)"#)
        var found: [(MapPlaceLink.Coordinate,String?)] = []
        var nodes = 0
        func visit(_ value: Any,depth: Int) throws {
            nodes += 1
            guard depth <= 32,nodes <= 20_000 else { throw MapPlaceLink.LinkError.exactPinUnavailable }
            guard let array = value as? [Any] else { return }
            if array.count >= 4,let ftid = array[0] as? String,
               let rendered = GooglePlaceIdentity(ftid:ftid),rendered.low == low,
               high == nil || rendered.high == high,
               let cid = array[3] as? String,GooglePlaceIdentity(cid:cid)?.low == low,
               let pair = array[2] as? [Any],pair.count == 2,
               let a = pair[0] as? NSNumber,let b = pair[1] as? NSNumber,
               CFGetTypeID(a) != CFBooleanGetTypeID(),CFGetTypeID(b) != CFBooleanGetTypeID() {
                let latitude = a.doubleValue,longitude = b.doubleValue
                guard latitude.isFinite,longitude.isFinite,abs(latitude) <= 90,abs(longitude) <= 180 else {
                    throw MapPlaceLink.LinkError.invalidCoordinate
                }
                let point = MapPlaceLink.Coordinate(latitude:latitude,longitude:longitude)
                let rawName = (array[1] as? String)?.components(separatedBy:.whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator:" ")
                let name = rawName.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
                if !found.contains(where:{ $0.0 == point }) { found.append((point,name)) }
            }
            for child in array where child is [Any] { try visit(child,depth:depth+1) }
        }
        for match in regex.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
            guard let range = Range(match.range,in:html) else { continue }
            let bytes = Array(html[range.upperBound...].utf8)
            guard let data = Self.jsonArrayPrefix(bytes),let root = try? JSONSerialization.jsonObject(with:data) else { continue }
            try visit(root,depth:0)
        }
        guard found.count <= 1 else { throw MapPlaceLink.LinkError.exactPinUnavailable }
        return found.first.map { .coordinate($0.0,name:$0.1) }
    }
    private static func jsonArrayPrefix(_ bytes: [UInt8]) -> Data? {
        guard bytes.first == 91 else { return nil }
        var depth = 0,inString = false,escaped = false
        for (i,byte) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else {
                if byte == 34 { inString = true }
                else if byte == 91 || byte == 123 { depth += 1 }
                else if byte == 93 || byte == 125 {
                    depth -= 1
                    if depth == 0 { return Data(bytes[...i]) }
                    if depth < 0 { return nil }
                }
            }
        }
        return nil
    }
}
