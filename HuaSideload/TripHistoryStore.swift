import Combine
import Foundation

@MainActor
final class TripHistoryStore: ObservableObject {
    @Published private(set) var records: [TripRecord] = []
    @Published private(set) var storageMessage: String?
    private let file: TripHistoryFile
    private var contents = TripHistoryFile.Contents()
    private var canSave = true

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
        file = TripHistoryFile(url: directory.appendingPathComponent("TripHistory/trips.json"))
        do {
            contents = try file.load()
            if var active = contents.active {
                active.outcome = .interrupted
                contents.records.removeAll { $0.id == active.id }
                contents.records.insert(active,at: 0); contents.active = nil
                try file.save(contents)
            }
            records = contents.records.sorted { $0.startedAt > $1.startedAt }
        } catch {
            canSave = false
            storageMessage = "Chưa đọc được lịch sử đã lưu. Dữ liệu cũ được giữ nguyên; tạm thời không ghi đè."
        }
    }

    func checkpoint(_ record: TripRecord) { contents.active = record; persist() }
    func finish(_ record: TripRecord) {
        contents.active = nil
        contents.records.removeAll { $0.id == record.id }
        contents.records.insert(record,at: 0)
        records = contents.records.sorted { $0.startedAt > $1.startedAt }
        persist()
    }
    func delete(_ id: UUID) {
        contents.records.removeAll { $0.id == id }; records.removeAll { $0.id == id }; persist()
    }
    func clear() { contents.records = []; records = []; persist() }
    private func persist() {
        guard canSave else { return }
        do { try file.save(contents); storageMessage = nil }
        catch { storageMessage = "Chưa lưu được lịch sử. Điều hướng vẫn tiếp tục; mở lại app để kiểm tra." }
    }
}

#if DEBUG && targetEnvironment(simulator)
extension TripHistoryStore {
    func prepareVisualPreview() {
        records = [
            TripRecord(id:UUID(),startedAt:Date().addingTimeInterval(-7200),endedAt:Date().addingTimeInterval(-6600),
                destination:"Nhà văn hóa Thanh niên",mode:"Xe máy",distance:2312,outcome:.completed),
            TripRecord(id:UUID(),startedAt:Date().addingTimeInterval(-85000),endedAt:Date().addingTimeInterval(-84000),
                destination:"Công viên Tao Đàn",mode:"Xe máy",distance:4600,outcome:.stopped)
        ]
    }
}
#endif
