import SwiftUI

struct GoogleMapsSection: View {
    @ObservedObject var reader: MapsScreenReader
    @ObservedObject var link: WatchLink
    var body: some View {
        Section {
            Text(reader.status).font(.callout)
            if !reader.preview.isEmpty { Text(reader.preview).font(.headline) }
            if reader.isReading {
                LabeledContent("Lần gửi chỉ dẫn", value: String(reader.samples))
                Text(link.navigationStatus).font(.caption).foregroundStyle(.secondary)
                Button("Dừng đọc Google Maps", role: .destructive) { reader.stop() }
            } else if #available(iOS 27, *) {
                Button("Đọc màn hình Google Maps") { link.startGoogleMapsCapture() }
                    .disabled(link.commandsLocked || !link.isPaired)
            } else {
                Text("Đọc màn hình trong bản này cần iOS 27 trở lên.").font(.footnote)
            }
        } header: {
            Text("Google Maps — giữ màn hình mở")
        } footer: {
            Text("Trong Google Maps, chọn Xe máy và bắt đầu chuyến đi. Quay lại đây, bấm Đọc màn hình và xác nhận chia sẻ toàn màn hình với iOS; app sẽ mở lại Google Maps. Giữ máy sáng, đặt dọc và giữ chỉ đường Google Maps hiển thị. Nhận dạng chữ/mũi tên là thử nghiệm; đối chiếu trước khi dùng. Không thu âm, lưu ảnh hoặc gửi ảnh lên máy chủ.")
        }
    }
}
