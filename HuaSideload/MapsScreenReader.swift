import Combine
import Foundation
import UIKit

@MainActor
final class MapsScreenReader: ObservableObject {
    @Published private(set) var isReading = false
    @Published private(set) var status = "Chọn xe máy và bắt đầu chuyến đi trong Google Maps trước."
    @Published private(set) var preview = ""
    @Published private(set) var samples = 0
    var onGuidance: (([UInt8]) -> Void)?
    var onStop: (() -> Void)?
    private var driver: AnyObject?
    private var lastValid = Date()
    private var lastSent = Date.distantPast
    private var lastText = ""
    private var cleared = false

    func start() {
        guard !isReading else { return }
        if #available(iOS 27, *) {
            isReading = true; samples = 0; preview = ""; lastText = ""
            lastValid = Date(); lastSent = .distantPast; cleared = false
            status = "Chọn chia sẻ toàn màn hình trong hộp thoại iOS."
            let capture = GoogleMapsCapture(owner: self)
            driver = capture
            capture.present()
        } else {
            status = "Bản đọc màn hình này cần iOS 27 trở lên. Điều hướng chạy nền vẫn dùng được."
        }
    }

    func stop(reason: String = "Đã dừng đọc Google Maps.", notifyWatch: Bool = true) {
        let wasReading = isReading
        isReading = false; status = reason
        if #available(iOS 27, *), let capture = driver as? GoogleMapsCapture { capture.stop() }
        driver = nil
        if wasReading && notifyWatch { onStop?() }
    }

    func deliveryFailed(_ text: String) {
        guard isReading else { return }
        stop(reason: "Đã dừng vì gửi tới đồng hồ thất bại: " + text, notifyWatch: false)
    }

    func captureStarted() {
        guard isReading else { return }
        status = "Đang chờ màn hình chỉ đường Google Maps."
        UIApplication.shared.open(URL(string: "comgooglemaps://")!)
    }

    func received(_ reading: ScreenNavigation.Reading?) {
        guard isReading else { return }
        guard let reading else {
            if Date().timeIntervalSince(lastValid) > 8 {
                status = "Chưa thấy chỉ đường Google Maps. Giữ Google Maps mở, chuyến đi đang chạy và máy ở chiều dọc."
                if !cleared { cleared = true; onStop?() }
            }
            return
        }
        lastValid = Date(); cleared = false
        let text = reading.instruction + " · " + reading.distance
        preview = text
        status = reading.turn == .unspecified ? "Đã đọc chữ; chưa xác định được mũi tên. Đối chiếu trên Google Maps." : "Đang đọc Google Maps trên iPhone."
        guard text != lastText || Date().timeIntervalSince(lastSent) >= 3 else { return }
        do {
            let bytes = try PineNavigationWire.guidance(instruction: reading.instruction, distance: reading.distance, turn: reading.turn)
            lastText = text; lastSent = Date(); samples += 1
            onGuidance?(bytes)
        } catch { stop(reason: "Không tạo được chỉ dẫn: \(error)") }
    }
}
