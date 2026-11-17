import Combine
import Foundation
import SwiftUI

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
            places = try file.load().places
            canSave = true; storageMessage = nil
        } catch {
            canSave = false
            storageMessage = "Chưa đọc được địa điểm yêu thích. Tệp cũ được giữ nguyên; tạm thời không ghi đè."
        }
    }
    @discardableResult func save(_ value: FavoritePlace) -> Bool {
        do {
            var place = try value.validated(); place.updatedAt = Date()
            var next = places
            if let index = next.firstIndex(where: { $0.id == place.id }) {
                next[index] = place
            } else {
                next.insert(place, at: 0)
            }
            return persist(next)
        } catch { storageMessage = error.localizedDescription; return false }
    }
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = places
        next.move(fromOffsets: source, toOffset: destination)
        guard next != places else { return }
        _ = persist(next)
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
