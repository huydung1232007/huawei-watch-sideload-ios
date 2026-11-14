import Foundation

struct FavoritePlace: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),name: String,latitude: Double,longitude: Double,createdAt: Date = Date()) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.createdAt = createdAt; updatedAt = createdAt
    }
    func validated() throws -> FavoritePlace {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.count <= 60 else { throw ValidationError.name }
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { throw ValidationError.coordinate }
        return result
    }
    enum ValidationError: LocalizedError {
        case name, coordinate
        var errorDescription: String? {
            switch self {
            case .name: return "Nhập tên địa điểm từ 1 đến 60 ký tự."
            case .coordinate: return "Tọa độ vị trí không hợp lệ."
            }
        }
    }
}

// A new store, separate from trip history and pairing keys. Saving coordinates
// is intentional here: a favorite must work as a future routing destination.
struct FavoritePlacesFile {
    struct Contents: Codable, Equatable {
        var version = 1
        var places: [FavoritePlace] = []
    }
    let url: URL
    func load() throws -> Contents {
        guard FileManager.default.fileExists(atPath: url.path) else { return Contents() }
        let contents = try JSONDecoder().decode(Contents.self,from: Data(contentsOf: url))
        try validate(contents)
        return contents
    }
    func save(_ contents: Contents) throws {
        try validate(contents)
        let data = try JSONEncoder().encode(contents)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        var resourceURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
        #else
        try data.write(to: url,options: .atomic)
        #endif
    }
    private func validate(_ contents: Contents) throws {
        guard contents.version == 1, Set(contents.places.map(\.id)).count == contents.places.count else {
            throw CocoaError(.coderReadCorrupt)
        }
        for place in contents.places { _ = try place.validated() }
    }
}

enum FavoriteGPSFix {
    static func usable(timestamp: Double,now: Double,accuracy: Double) -> Bool {
        let age = now-timestamp
        return age.isFinite && age >= -2 && age <= 5 && accuracy.isFinite && accuracy >= 0 && accuracy <= 35
    }
}
