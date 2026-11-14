import Combine
import Foundation

@MainActor
final class FavoritePlacesStore: ObservableObject {
    @Published private(set) var places: [FavoritePlace] = []
    @Published private(set) var storageMessage: String?
    private let file: FavoritePlacesFile
    private var canSave = false

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
        file = FavoritePlacesFile(url: directory.appendingPathComponent("Favorites/places.json"))
        loadExisting()
    }
    func retryLoadingIfNeeded() { if !canSave { loadExisting() } }
    private func loadExisting() {
        do {
            places = try file.load().places.sorted { $0.updatedAt > $1.updatedAt }
            canSave = true; storageMessage = nil
        } catch {
            canSave = false
            storageMessage = "Chưa đọc được địa điểm yêu thích. Tệp cũ được giữ nguyên; tạm thời không ghi đè."
        }
    }
    @discardableResult func save(_ value: FavoritePlace) -> Bool {
        do {
            var place = try value.validated(); place.updatedAt = Date()
            var next = places.filter { $0.id != place.id }; next.insert(place,at: 0)
            return persist(next)
        } catch { storageMessage = error.localizedDescription; return false }
    }
    @discardableResult func delete(_ id: UUID) -> Bool { persist(places.filter { $0.id != id }) }
    private func persist(_ next: [FavoritePlace]) -> Bool {
        guard canSave else { return false }
        do {
            try file.save(.init(places: next))
            places = next; storageMessage = nil; return true
        } catch { storageMessage = "Chưa lưu được địa điểm. Thử lại khi iPhone đã mở khóa."; return false }
    }
}

#if DEBUG && targetEnvironment(simulator)
extension FavoritePlacesStore {
    func prepareVisualPreview() {
        places = [
            FavoritePlace(name:"Nhà văn hóa Thanh niên",latitude:10.7828,longitude:106.6959),
            FavoritePlace(name:"Công viên Tao Đàn",latitude:10.7765,longitude:106.6866)
        ]
    }
}
#endif
