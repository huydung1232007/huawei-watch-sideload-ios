import Foundation
import Vision

enum PCRemoteQRImage {
    static func decode(_ data: Data) throws -> String {
        guard !data.isEmpty, data.count <= 15 * 1024 * 1024 else { throw PCRemoteError.configuration }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(data: data, options: [:]).perform([request])
        for item in request.results ?? [] {
            if let text = item.payloadStringValue, (try? PCRemoteConfiguration(text: text)) != nil { return text }
        }
        throw PCRemoteError.configuration
    }
}
