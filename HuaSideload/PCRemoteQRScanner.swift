import SwiftUI
import AVFoundation
import UIKit

struct PCRemoteQRScanner: View {
    let scanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PCRemoteCamera(scanned: scanned)
                .frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea(edges: .bottom)
                .navigationTitle("Quét mã trên PC").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } } }
        }
    }
}

private struct PCRemoteCamera: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    func makeUIViewController(context: Context) -> PCRemoteCameraController { PCRemoteCameraController(scanned: scanned) }
    func updateUIViewController(_ controller: PCRemoteCameraController, context: Context) {}
}

private final class PCRemoteCameraController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "HuaSideload.PCRemote.Camera")
    private let scanned: (String) -> Void
    private var preview: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var delivered = false
    private var visible = false
    private let message = UILabel()
    private var observers = [NSObjectProtocol]()
    init(scanned: @escaping (String) -> Void) { self.scanned = scanned; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        // Attach the preview synchronously, before configuring/starting capture.
        // The old async attachment could race startRunning and sheet layout.
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds
        view.layer.addSublayer(layer); preview = layer
        message.text = "Đang mở camera…"
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        message.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(message)
        NSLayoutConstraint.activate([message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                                     message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                                     message.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28)])
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
            object: session, queue: .main) { [weak self] _ in
                self?.message.text = "Camera chưa hoạt động. Bấm Hủy rồi dùng Chọn ảnh mã QR ở màn hình trước."
            })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
            object: session, queue: .main) { [weak self] _ in self?.message.text = "Camera đang bị gián đoạn. Đóng ứng dụng khác đang dùng camera rồi thử lại." })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); visible = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: beginCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.visible else { return }
                    if allowed { self.beginCapture() } else { self.denied() }
                }
            }
        default: denied()
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); visible = false
        captureQueue.async { self.session.stopRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    private func denied() { message.text = "Cho phép Camera trong Cài đặt → HuaSideload, hoặc dùng Dán mã kết nối." }
    private func beginCapture() {
        captureQueue.async {
            do {
                if !self.configured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video) else { throw PCRemoteError.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureMetadataOutput()
                    self.session.beginConfiguration()
                    if self.session.canSetSessionPreset(.high) { self.session.sessionPreset = .high }
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration(); throw PCRemoteError.unavailable
                    }
                    self.session.addInput(input)
                    guard self.session.canAddOutput(output) else {
                        self.session.removeInput(input); self.session.commitConfiguration(); throw PCRemoteError.unavailable
                    }
                    self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                    self.session.commitConfiguration(); self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.preview?.frame = self.view.bounds
                    self.message.text = running ? "Đưa mã QR trong PC Remote vào khung hình." : "Chưa mở được camera. Bấm Hủy rồi dùng Chọn ảnh mã QR."
                }
            } catch { DispatchQueue.main.async { self.message.text = "Không mở được camera. Bạn có thể dùng Dán mã kết nối." } }
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible, !delivered, let text = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        delivered = true; captureQueue.async { self.session.stopRunning() }; scanned(text)
    }
}
