import SwiftUI
import UIKit
import PhotosUI

@MainActor
final class PCRemoteFeature: ObservableObject, WatchFeature {
    @Published private(set) var configuration: PCRemoteConfiguration?
    @Published private(set) var enabled = false
    @Published private(set) var verified = false
    @Published private(set) var checking = false
    @Published private(set) var status = "Mở PC Remote trên Windows, rồi quét mã QR để kết nối."
    @Published private(set) var failed = false
    private weak var host: WatchFeatureHost?
    private let secrets = KeychainBackend(service: "HuaSideload.PCRemote")
    private let transport = PCRemoteTransport()
    private let enabledKey = "PCRemoteEnabledV1"
    private let configKey = "configuration.v1"
    private var generation = UUID()
    private var draining: UUID?
    private var buttons = PCRemoteButtons()
    private var playingEstimate = false
    private var lastButton: (PCRemoteCommand, Double)?
    private struct Job { let command: PCRemoteCommand; let time: Double }
    private var pending = [Job]()

    init() {
        if let text = secrets.read(configKey), let saved = try? PCRemoteConfiguration(text: text) {
            configuration = saved
            enabled = UserDefaults.standard.bool(forKey: enabledKey)
            status = "Đã lưu PC. Bấm Kiểm tra kết nối để sử dụng."
        }
    }
    var watchPackages: [String] { [] }
    var ownsMusicScreen: Bool { enabled && configuration != nil }
    var watchConnected: Bool { host?.isPaired == true }
    func attach(to host: WatchFeatureHost) { self.host = host }
    func handle(_ message: [String: Any], from package: String) async -> Bool { false }
    func sections() -> AnyView { AnyView(PCRemoteSummarySection(feature: self)) }

    func importConfiguration(_ text: String) {
        do {
            let candidate = try PCRemoteConfiguration(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            let normalized = String(decoding: try JSONEncoder().encode(candidate), as: UTF8.self)
            guard secrets.write(normalized, for: configKey) else {
                status = "Chưa lưu được mã kết nối vào Keychain. Thử lại khi iPhone đã mở khóa."; failed = true; return
            }
            setEnabled(false)
            configuration = candidate; verified = false; failed = false
            checkConnection()
        } catch { status = error.localizedDescription; failed = true }
    }
    func forgetPC() {
        setEnabled(false); secrets.delete(configKey)
        configuration = nil; verified = false
        status = "Đã bỏ PC đã lưu. Quét QR để thêm lại."; failed = false
    }
    func reportQRImageError() {
        failed = true
        status = "Không tìm thấy mã PC Remote trong ảnh. Chọn ảnh chụp rõ toàn bộ QR trên PC."
    }
    func setEnabled(_ value: Bool) {
        guard !value || (configuration != nil && verified) else { return }
        enabled = value; UserDefaults.standard.set(value, forKey: enabledKey)
        invalidate()
        if value {
            buttons.reset(); playingEstimate = false
            status = watchConnected ? "Đã bật. Mở Nhạc trên đồng hồ và chọn điều khiển điện thoại." : "Đã bật điều khiển PC. Có thể thử bằng các nút trên iPhone."
            failed = false; showOnWatch("Play / pause")
        } else {
            status = "Điều khiển PC đang tắt."; failed = false
        }
    }
    func checkConnection() {
        guard configuration != nil, !checking, pending.count < 4 else { return }
        checking = true; failed = false; status = "Đang kiểm tra PC…"
        enqueue(.ping)
    }
    func watchPaired() {
        buttons.reset()
        if enabled { checkConnection() }
    }
    func connectionLost() {
        invalidate(); buttons.reset()
        if enabled { status = "Đồng hồ mất kết nối. Chờ kết nối lại." }
    }
    func musicScreenOpened() {
        guard enabled else { return }
        buttons.reset()
        showOnWatch("Play / pause")
    }
    func musicButton(_ button: MusicControl.Button?, volume: Int?) {
        guard enabled, let command = buttons.command(button: button, volume: volume) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastButton, previous.0 == command, now - previous.1 < 0.15 { return }
        lastButton = (command, now)
        enqueue(command)
    }
    func sendFromPhone(_ command: PCRemoteCommand) {
        guard command != .ping, enabled else { return }
        enqueue(command)
    }
    private func invalidate() {
        generation = UUID(); draining = nil; pending.removeAll()
        checking = false; lastButton = nil
        transport.cancel()
    }
    private func enqueue(_ command: PCRemoteCommand) {
        guard configuration != nil, command == .ping || enabled, pending.count < 4 else { return }
        pending.append(Job(command: command, time: ProcessInfo.processInfo.systemUptime))
        guard draining == nil else { return }
        let token = generation; draining = token
        host?.inBackground("PC media remote") { [weak self] in await self?.drain(token) }
    }
    private func drain(_ token: UUID) async {
        defer { if draining == token { draining = nil; checking = false } }
        while generation == token, !pending.isEmpty, !Task.isCancelled {
            let job = pending.removeFirst()
            // Old queued button presses must not fire after a stalled network.
            guard job.command == .ping || ProcessInfo.processInfo.systemUptime - job.time < 2 else { continue }
            guard let configuration else { return }
            do {
                try await transport.send(job.command, configuration: configuration)
                guard generation == token, !Task.isCancelled else { return }
                verified = true; failed = false
                if job.command == .ping {
                    status = enabled ? "PC sẵn sàng. Mở Nhạc trên đồng hồ để điều khiển." : "PC đã trả lời. Bật Điều khiển từ đồng hồ để sử dụng."
                    if enabled { showOnWatch("PC ready") }
                } else {
                    if job.command == .playPause { playingEstimate.toggle() }
                    status = "Đã gửi tới Windows: " + job.command.title
                    showOnWatch(job.command.title)
                    host?.log(.success, "PC Remote: " + job.command.rawValue + " acknowledged")
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                verified = false; pending.removeAll(); enabled = false
                UserDefaults.standard.set(false, forKey: enabledKey)
                failed = true; status = error.localizedDescription
                host?.log(.error, "PC Remote: request failed; control disabled")
                return
            }
        }
    }
    private func showOnWatch(_ text: String) {
        guard enabled else { return }
        // Volume/state are UI estimates, not measurements of the Windows player.
        host?.showOnMusicScreen(top: "PC Remote", main: text, playing: playingEstimate,
                               volumePercent: buttons.volume * 100 / 15)
    }
}

private struct PCRemoteSummarySection: View {
    @ObservedObject var feature: PCRemoteFeature
    var body: some View {
        Section {
            NavigationLink { PCRemoteView(feature: feature) } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Điều khiển PC").font(.headline)
                        Text(feature.enabled ? "Đang bật · Nhạc và video" : "Kết nối Windows bằng mã QR")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "desktopcomputer").foregroundStyle(.blue) }
            }
        }
    }
}

struct PCRemoteView: View {
    @ObservedObject var feature: PCRemoteFeature
    @State private var scanning = false
    @State private var enteringCode = false
    @State private var code = ""
    @State private var qrPhoto: PhotosPickerItem?
    @State private var readingPhoto = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PC Remote").font(.title2.bold())
                        Text("Nhạc và video trên Windows").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Label(feature.status, systemImage: feature.failed ? "exclamationmark.circle" : "antenna.radiowaves.left.and.right")
                    .font(.callout).foregroundStyle(feature.failed ? Color.orange : Color.secondary)
            }
            Section {
                if let configuration = feature.configuration {
                    LabeledContent("Địa chỉ", value: "\(configuration.host):\(configuration.port)")
                }
                Button { scanning = true } label: { Label("Quét mã QR trên PC", systemImage: "qrcode.viewfinder") }
                PhotosPicker(selection: $qrPhoto, matching: .images, photoLibrary: .shared()) {
                    Label(readingPhoto ? "Đang đọc mã QR…" : "Chọn ảnh mã QR", systemImage: "photo")
                }.disabled(readingPhoto)
                Button("Dán mã kết nối") {
                    if let text = UIPasteboard.general.string { feature.importConfiguration(text) }
                    else { enteringCode = true }
                }
                Button { feature.checkConnection() } label: {
                    HStack { Text("Kiểm tra kết nối"); if feature.checking { Spacer(); ProgressView() } }
                }.disabled(feature.configuration == nil || feature.checking)
            } header: { Text("Kết nối PC") } footer: {
                Text("Mở PC Remote trên Windows. iPhone và PC cần cùng mạng Wi-Fi/LAN. Cho phép Mạng cục bộ khi iPhone hỏi.")
            }
            Section {
                Toggle("Điều khiển từ đồng hồ", isOn: Binding(get: { feature.enabled }, set: { feature.setEnabled($0) }))
                    .disabled(!feature.enabled && !feature.verified)
                Text("Trên đồng hồ: mở Nhạc → chọn điều khiển nhạc điện thoại. Dùng ▶/❚❚, bài trước/sau và âm lượng.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !feature.watchConnected {
                    Label("Kết nối đồng hồ ở tab Đồng hồ để dùng các nút Nhạc. Nút trên iPhone vẫn dùng được.", systemImage: "watch.analog")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PCRemoteCommand.allCases.filter { $0 != .ping }, id: \.rawValue) { command in
                        Button { feature.sendFromPhone(command) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: command.icon).font(.title2)
                                Text(command.title).font(.caption)
                            }.frame(maxWidth: .infinity, minHeight: 70)
                        }.buttonStyle(.bordered).disabled(!feature.enabled)
                    }
                }.padding(.vertical, 6)
            } header: { Text("Thử điều khiển ngay trên iPhone") } footer: {
                Text("PC gửi phím media của Windows. Ứng dụng đang phát nhạc/video quyết định cách xử lý. Trạng thái phát và thanh âm lượng trên đồng hồ là ước lượng, không phải số đo của PC.")
            }
            if feature.configuration != nil {
                Section { Button("Bỏ PC đã lưu", role: .destructive) { feature.forgetPC() } }
            }
        }
        .navigationTitle("Điều khiển PC").navigationBarTitleDisplayMode(.inline)
        .onChange(of: qrPhoto) { _, item in
            guard let item else { return }
            readingPhoto = true
            Task {
                defer { readingPhoto = false; qrPhoto = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw PCRemoteError.configuration }
                    let text = try await Task.detached(priority: .userInitiated) { try PCRemoteQRImage.decode(data) }.value
                    feature.importConfiguration(text)
                } catch { feature.reportQRImageError() }
            }
        }
        .sheet(isPresented: $scanning) {
            PCRemoteQRScanner { text in scanning = false; feature.importConfiguration(text) }
        }
        .sheet(isPresented: $enteringCode) {
            NavigationStack {
                Form {
                    Section("Mã kết nối từ PC") {
                        TextEditor(text: $code).frame(minHeight: 130).font(.caption.monospaced())
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    Button("Lưu và kiểm tra") { feature.importConfiguration(code); code = ""; enteringCode = false }
                }.navigationTitle("Nhập mã kết nối")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { code = ""; enteringCode = false } } }
            }
        }
    }
}
