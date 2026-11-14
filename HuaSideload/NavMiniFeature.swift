import Foundation
import SwiftUI

@MainActor
final class NavMiniFeature: ObservableObject, WatchFeature {
    @Published private(set) var status = "Mở Nav Mini trên đồng hồ rồi bấm Thử kết nối."
    private weak var host: WatchFeatureHost?
    private var lastReply = -Double.infinity
    private var pendingNonce: Int?
    var watchPackages: [String] { [NavMiniWire.watchPackage] }
    func attach(to host: WatchFeatureHost) { self.host = host }
    func connectionLost() { pendingNonce = nil; status = "Chờ kết nối lại đồng hồ." }
    func handle(_ message: [String: Any],from package: String) async -> Bool {
        guard package == NavMiniWire.watchPackage else { return false }
        if let nonce = NavMiniWire.nonce(in:message,type:"navmini.rendered") {
            guard nonce == pendingNonce else { return true }
            pendingNonce = nil
            status = "Nav Mini đã báo xử lý dữ liệu từ iPhone."
            host?.log(.success,"Nav Mini: matching render acknowledgement")
            return true
        }
        guard let reply = NavMiniWire.reply(to:message,at:Date()) else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastReply >= 0.5 else { return true }
        guard let bridge = host?.bridge(for:package) else { return true }
        lastReply = now; pendingNonce = reply["n"] as? Int
        bridge.send(reply)
        status = "Đã gửi dữ liệu thử; chờ Nav Mini xác nhận."
        host?.log(.info,"Nav Mini: replied to a test request")
        return true
    }
    func sections() -> AnyView {
        guard WatchAppCatalog.app(for:NavMiniWire.watchPackage) != nil else { return AnyView(EmptyView()) }
        return AnyView(NavMiniStatusSection(feature:self))
    }
}

private struct NavMiniStatusSection: View {
    @ObservedObject var feature: NavMiniFeature
    var body: some View {
        Section {
            Text(feature.status)
            Text("Bản kiểm tra ứng dụng riêng. Các số km, phút, tốc độ và chỗ rẽ trên Nav Mini là dữ liệu minh họa.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Label("Nav Mini · thử kết nối",systemImage:"watch.analog") }
    }
}
