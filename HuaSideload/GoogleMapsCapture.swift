import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import UIKit
import Vision

@available(iOS 27, *)
@MainActor
final class GoogleMapsCapture: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    private weak var owner: MapsScreenReader?
    private var stream: SCStream?
    private var output: MapsFrameProcessor?
    private var stopped = false
    private let queue = DispatchQueue(label: "NavigationScreenRecognition", qos: .userInitiated)

    init(owner: MapsScreenReader) { self.owner = owner }

    func present() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        let existing = stream; stream = nil; output = nil
        Task { try? await existing?.stopCapture() }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in self?.owner?.stop(reason: "Bạn đã hủy chia sẻ màn hình.") }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in self?.owner?.stop(reason: "Không mở được chia sẻ màn hình: \(error.localizedDescription)") }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in await self?.begin(filter) }
    }

    private func begin(_ filter: SCContentFilter) async {
        guard !stopped, stream == nil else { return }
        do {
            let configuration = SCStreamConfiguration()
            let bounds = UIScreen.main.bounds
            configuration.width = 1080
            configuration.height = Int(1080 * bounds.height / bounds.width)
            configuration.capturesAudio = false
            let processor = MapsFrameProcessor { [weak self] reading in
                Task { @MainActor [weak self] in
                    guard let self, !self.stopped else { return }
                    self.owner?.received(reading)
                }
            }
            let created = SCStream(filter: filter, configuration: configuration, delegate: self)
            try created.addStreamOutput(processor, type: .screen, sampleHandlerQueue: queue)
            output = processor; stream = created
            try await created.startCapture()
            guard !stopped else { return }
            owner?.captureStarted()
        } catch { owner?.stop(reason: "Không bắt đầu được đọc màn hình: \(error.localizedDescription)") }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            self.owner?.stop(reason: "Chia sẻ màn hình đã dừng: \(error.localizedDescription)")
        }
    }

    nonisolated func streamDidBecomeInactive(_ stream: SCStream) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            self.owner?.stop(reason: "Màn hình chia sẻ tạm dừng. Mở khóa iPhone và bắt đầu đọc lại.")
        }
    }
}

@available(iOS 27, *)
private final class MapsFrameProcessor: NSObject, SCStreamOutput {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let receive: (ScreenNavigation.Reading?) -> Void
    private var lastFrame = Date.distantPast
    private var languages: [String]?
    init(receive: @escaping (ScreenNavigation.Reading?) -> Void) { self.receive = receive }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
              Date().timeIntervalSince(lastFrame) >= 0.8,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date()
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()), cgImage.height > cgImage.width else { receive(nil); return }
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                if languages == nil {
                    let supported = try request.supportedRecognitionLanguages()
                    languages = ["vi-VN", "en-US"].filter { supported.contains($0) }
                }
                request.recognitionLanguages = languages ?? ["en-US"]
                try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                let lines: [ScreenNavigation.Line] = (request.results ?? []).compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.4 else { return nil }
                    let box = observation.boundingBox
                    return .init(text: candidate.string, x: box.minX, y: 1-box.maxY, width: box.width, height: box.height)
                }
                guard let initial = ScreenNavigation.parse(lines) else { receive(nil); return }
                let arrow = Self.arrow(cgImage, near: initial.distanceLine)
                receive(ScreenNavigation.parse(lines, arrow: arrow))
            } catch { receive(nil) }
        }
    }

    private static func arrow(_ image: CGImage, near line: ScreenNavigation.Line) -> PineNavigationWire.Turn? {
        guard image.bitsPerPixel == 32, image.bitsPerComponent == 8,
              let data = image.dataProvider?.data, let source = CFDataGetBytePtr(data) else { return nil }
        let frameWidth = image.width, frameHeight = image.height
        let bytesPerRow = image.bytesPerRow
        let x0 = Int(Double(frameWidth)*0.02), x1 = Int(Double(frameWidth)*min(0.20,line.x-0.015))
        let y0 = Int(Double(frameHeight)*max(0.035,line.y-0.045))
        let y1 = Int(Double(frameHeight)*min(0.33,line.y+max(0.09,line.height*3)))
        guard x1 > x0+12, y1 > y0+12, x1 <= frameWidth, y1 <= frameHeight else { return nil }
        let width = x1-x0, height = y1-y0
        var mask = [Bool](repeating: false, count: width*height)
        for y in 0..<height { for x in 0..<width {
            let index = (y+y0)*bytesPerRow + (x+x0)*4
            mask[y*width+x] = source[index] > 180 && source[index+1] > 180 && source[index+2] > 180
        } }
        var best: NavigationArrow.Match?
        for seed in mask.indices where mask[seed] {
            var pixels: [Int] = [seed], cursor = 0
            mask[seed] = false
            var minX = width, minY = height, maxX = 0, maxY = 0
            while cursor < pixels.count {
                let position = pixels[cursor]; cursor += 1
                let x = position%width, y = position/width
                minX=min(minX,x); maxX=max(maxX,x); minY=min(minY,y); maxY=max(maxY,y)
                let neighbours = [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]
                for (nx,ny) in neighbours where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let next = ny*width+nx
                    if mask[next] { mask[next]=false; pixels.append(next) }
                }
            }
            let w=maxX-minX+1, h=maxY-minY+1
            guard pixels.count > 50, w > 10, h > 10, Double(pixels.count)/Double(w*h) < 0.80 else { continue }
            var normalized = [Bool](repeating: false, count: 32*32)
            for position in pixels {
                let x = 2+(position%width-minX)*27/max(1,w-1)
                let y = 2+(position/width-minY)*27/max(1,h-1)
                normalized[y*32+x] = true
            }
            if let match = NavigationArrow.classify(normalized), match.confidence > (best?.confidence ?? 0) { best=match }
        }
        return best?.turn
    }
}
