import Foundation

// Independent reader for Google Maps URLs. Viewport/Street View coordinates
// are deliberately never treated as a destination pin.
enum MapPlaceLink {
    struct Coordinate: Equatable {
        let latitude: Double
        let longitude: Double
    }
    enum Target: Equatable {
        case coordinate(Coordinate,name: String?)
        case search(String)
    }
    enum LinkError: LocalizedError {
        case invalidLink,invalidCoordinate,unresolved,network,tooManyRedirects
        var errorDescription: String? {
            switch self {
            case .invalidLink: return "Dán một liên kết địa điểm Google Maps hợp lệ."
            case .invalidCoordinate: return "Liên kết chứa tọa độ không hợp lệ. Kiểm tra lại ghim trong Google Maps."
            case .unresolved: return "Chưa đọc được địa điểm từ link này. Thử sao chép lại liên kết của một ghim hoặc tìm bằng tên/địa chỉ."
            case .network: return "Chưa mở được liên kết. Kiểm tra mạng rồi thử lại."
            case .tooManyRedirects: return "Liên kết chuyển tiếp quá nhiều lần. Thử sao chép lại link địa điểm."
            }
        }
    }

    static func url(from text: String) throws -> URL {
        guard text.utf8.count <= 16_384 else { throw LinkError.invalidLink }
        let detector = try NSDataDetector(types:NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector.matches(in:text,range:NSRange(text.startIndex...,in:text))
        guard matches.count == 1,let url = matches.first?.url else { throw LinkError.invalidLink }
        return try validated(url)
    }

    static func validated(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url:url,resolvingAgainstBaseURL:false),
              ["http","https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil,parts.password == nil,parts.port == nil,
              let host = parts.host?.lowercased(),url.absoluteString.utf8.count <= 8192 else { throw LinkError.invalidLink }
        let path = parts.path
        let isShort = (host == "maps.app.goo.gl" && path.count > 1)
            || (host == "goo.gl" && path.hasPrefix("/maps/"))
        let domains = ["google.com","google.com.vn","google.co.uk","google.com.au","google.ca",
                       "google.de","google.fr","google.co.jp","google.co.in","google.com.sg"]
        let isGoogle = domains.contains { host == $0 || host == "www."+$0 || host == "maps."+$0 }
        let isMapsPath = path == "/maps" || path.hasPrefix("/maps/")
            || (host.hasPrefix("maps.") && (path.isEmpty || path == "/"))
        guard isShort || (isGoogle && isMapsPath) else { throw LinkError.invalidLink }
        parts.scheme = "https"; parts.host = host; parts.fragment = nil
        guard let safe = parts.url else { throw LinkError.invalidLink }
        return safe
    }

    static func target(from url: URL) throws -> Target? {
        let safe = try validated(url)
        let parts = URLComponents(url:safe,resolvingAgainstBaseURL:false)!
        if parts.host == "maps.app.goo.gl" || parts.host == "goo.gl" { return nil }
        let items = parts.queryItems ?? []
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value?.replacingOccurrences(of:"+",with:" ") }
        let path = parts.path
        if value("map_action") != nil || path.contains("/streetview") { return nil }
        // A directions URL's explicit endpoint outranks origin, viewport and
        // arbitrary coordinate pairs inside its route data.
        for key in ["destination","daddr"] {
            if let raw = value(key),!raw.isEmpty { return try queryTarget(raw) }
        }
        let routePath = path.hasPrefix("/maps/dir/")
        if routePath {
            let segments = path.components(separatedBy:"/").dropFirst(3)
                .prefix { !$0.hasPrefix("@") && !$0.hasPrefix("data=") }
                .filter { !$0.isEmpty }
            guard segments.count >= 2,let end = segments.last else { return nil }
            return try queryTarget(end.replacingOccurrences(of:"+",with:" "))
        }
        // Explicit query coordinates are pins; @lat,lon and ll/center are views.
        for key in ["query","q"] {
            if let raw = value(key),let point = try coordinate(raw) {
                return .coordinate(point,name:nil)
            }
        }
        let decoded = safe.absoluteString.removingPercentEncoding ?? safe.absoluteString
        let pattern = #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)(?=[!/?&#]|$)"#
        let regex = try NSRegularExpression(pattern:pattern)
        let matches = regex.matches(in:decoded,range:NSRange(decoded.startIndex...,in:decoded))
        var pins: [Coordinate] = []
        for match in matches {
            guard let a = Range(match.range(at:1),in:decoded),let b = Range(match.range(at:2),in:decoded),
                  let point = try coordinate(String(decoded[a])+","+String(decoded[b])) else { continue }
            if !pins.contains(point) { pins.append(point) }
        }
        if pins.count > 1 { throw LinkError.unresolved }
        if let pin = pins.first { return .coordinate(pin,name:placeName(path)) }
        for key in ["query","q"] {
            if let raw = value(key),let target = try queryTarget(raw) { return target }
        }
        if let name = placeName(path) { return try queryTarget(name) }
        return nil
    }

    private static func queryTarget(_ text: String) throws -> Target? {
        let raw = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if let point = try coordinate(raw) { return .coordinate(point,name:nil) }
        guard !raw.isEmpty,raw.count <= 300,
              !raw.lowercased().hasPrefix("place_id:"),!raw.lowercased().hasPrefix("cid:"),
              !raw.lowercased().hasPrefix("http"),!raw.contains("!"),
              raw.rangeOfCharacter(from:.controlCharacters) == nil else { return nil }
        return .search(raw)
    }

    private static func coordinate(_ text: String) throws -> Coordinate? {
        let pattern = #"^\s*(?:loc:)?\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)\s*(?:\([^\n]*\))?\s*$"#
        let regex = try NSRegularExpression(pattern:pattern,options:.caseInsensitive)
        guard let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),
              let a = Range(match.range(at:1),in:text),let b = Range(match.range(at:2),in:text),
              let latitude = Double(text[a]),let longitude = Double(text[b]) else { return nil }
        guard latitude.isFinite,longitude.isFinite,abs(latitude) <= 90,abs(longitude) <= 180 else { throw LinkError.invalidCoordinate }
        return Coordinate(latitude:latitude,longitude:longitude)
    }

    private static func placeName(_ path: String) -> String? {
        for prefix in ["/maps/place/","/maps/search/"] where path.hasPrefix(prefix) {
            let name = String(path.dropFirst(prefix.count).prefix { $0 != "/" }).replacingOccurrences(of:"+",with:" ")
            if !name.isEmpty { return name }
        }
        return nil
    }

    // Read only explicit canonical/og:url metadata, never arbitrary links or
    // unrelated coordinate numbers in a page. No JavaScript or cookies needed.
    static func target(inHTML html: String) throws -> Target? {
        let tags = try NSRegularExpression(pattern:#"<(?:meta|link)\b[^>]*>"#,options:.caseInsensitive)
        let attributes = try NSRegularExpression(pattern:#"([\w:-]+)\s*=\s*["']([^"']*)["']"#)
        var candidates: [Target] = []
        for tag in tags.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
            guard let range = Range(tag.range,in:html) else { continue }
            let element = String(html[range]); var values: [String:String] = [:]
            for attribute in attributes.matches(in:element,range:NSRange(element.startIndex...,in:element)) {
                if let key = Range(attribute.range(at:1),in:element),let value = Range(attribute.range(at:2),in:element) {
                    values[String(element[key]).lowercased()] = String(element[value]).replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&#39;",with:"'").replacingOccurrences(of:"&quot;",with:"\"")
                }
            }
            let raw: String?
            if values["property"]?.lowercased() == "og:url" { raw = values["content"] }
            else if values["rel"]?.lowercased() == "canonical" { raw = values["href"] }
            else { raw = nil }
            if let raw,let url = URL(string:raw),let target = try? target(from:url),!candidates.contains(target) {
                candidates.append(target)
            }
        }
        let pins = candidates.filter { if case .coordinate = $0 { return true }; return false }
        var points: [Coordinate] = []
        for case let .coordinate(point,_) in pins where !points.contains(point) { points.append(point) }
        if points.count == 1 { return pins[0] }
        if points.count > 1 { throw LinkError.unresolved }
        return candidates.count == 1 ? candidates.first : nil
    }
}

struct MapPlaceLinkResolver {
    struct Page {
        let status: Int
        var location: String? = nil
        var html: String? = nil
    }
    typealias Fetch = (URL) async throws -> Page
    private let fetch: Fetch
    init() { self.fetch = Self.fetchPage }
    init(fetch: @escaping Fetch) { self.fetch = fetch }

    func resolve(_ text: String) async throws -> MapPlaceLink.Target {
        try await withThrowingTaskGroup(of:MapPlaceLink.Target.self) { group in
            group.addTask { try await self.resolveLink(text) }
            group.addTask {
                try await Task.sleep(for:.seconds(25))
                throw MapPlaceLink.LinkError.network
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw MapPlaceLink.LinkError.network }
            return result
        }
    }
    private func resolveLink(_ text: String) async throws -> MapPlaceLink.Target {
        var url = try MapPlaceLink.url(from:text)
        var visited = Set<String>()
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard visited.insert(url.absoluteString).inserted else { throw MapPlaceLink.LinkError.tooManyRedirects }
            if let target = try MapPlaceLink.target(from:url) { return target }
            let page: Page
            do { page = try await fetch(url) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation(); throw MapPlaceLink.LinkError.network }
            try Task.checkCancellation()
            if [301,302,303,307,308].contains(page.status),let location = page.location,
               let next = URL(string:location,relativeTo:url)?.absoluteURL {
                url = try MapPlaceLink.validated(next)
                continue
            }
            guard page.status == 200 else { throw MapPlaceLink.LinkError.network }
            if let html = page.html,let target = try MapPlaceLink.target(inHTML:html) { return target }
            throw MapPlaceLink.LinkError.unresolved
        }
        throw MapPlaceLink.LinkError.tooManyRedirects
    }

    private final class NoRedirect: NSObject,URLSessionTaskDelegate {
        func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static func fetchPage(_ url: URL) async throws -> Page {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.urlCache = nil; config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 12
        let session = URLSession(configuration:config,delegate:NoRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:10)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile Safari/604.1",forHTTPHeaderField:"User-Agent")
        let (bytes,response) = try await session.bytes(for:request)
        guard let response = response as? HTTPURLResponse else { throw MapPlaceLink.LinkError.network }
        if (300..<400).contains(response.statusCode) { return Page(status:response.statusCode,location:response.value(forHTTPHeaderField:"Location")) }
        guard response.statusCode == 200 else { return Page(status:response.statusCode) }
        let type = response.mimeType?.lowercased() ?? ""
        guard type == "text/html" || type == "application/xhtml+xml" else { throw MapPlaceLink.LinkError.unresolved }
        var data = Data(); data.reserveCapacity(64*1024)
        for try await byte in bytes {
            if data.count >= 512*1024 { break }
            data.append(byte)
        }
        return Page(status:200,html:String(decoding:data,as:UTF8.self))
    }
}
