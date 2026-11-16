import Foundation
import CryptoKit

enum PCRemoteError: LocalizedError {
    case configuration, invalidReply, authentication, unavailable, timeout, rejected(String)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Mã kết nối PC không hợp lệ. Hãy quét lại QR trong chương trình Windows."
        case .invalidReply: return "PC trả về dữ liệu không hợp lệ."
        case .authentication: return "Mã kết nối không khớp. Hãy quét lại QR của PC."
        case .unavailable: return "Chưa kết nối được PC. Kiểm tra cùng Wi-Fi, chương trình Windows và quyền Mạng cục bộ."
        case .timeout: return "PC chưa trả lời. Kiểm tra mạng Wi-Fi và quyền Mạng cục bộ của app."
        case .rejected(let code):
            switch code {
            case "paused": return "PC đang tạm dừng nhận điều khiển. Bật lại trong chương trình Windows."
            case "stale": return "Giờ iPhone và PC lệch nhau. Bật ngày giờ tự động trên hai máy."
            case "input_failed": return "Windows chưa nhận được phím điều khiển."
            default: return "PC từ chối lệnh. Thử kiểm tra kết nối hoặc quét lại QR."
            }
        }
    }
}

struct PCRemoteConfiguration: Codable, Equatable {
    let v: Int
    let host: String
    let port: Int
    let key: String

    init(text: String) throws {
        guard text.utf8.count <= 1024, let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else {
            throw PCRemoteError.configuration
        }
        self = value
    }
    var isValid: Bool {
        v == 1 && Self.isLANAddress(host) && (1024...65535).contains(port) && keyBytes?.count == 32
    }
    var keyBytes: Data? { PCRemoteWire.hexData(key) }
    static func isLANAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let values = parts.compactMap { UInt8($0) }
        guard values.count == 4, zip(parts, values).allSatisfy({ String($0.1) == String($0.0) }) else { return false }
        return values[0] == 10 || (values[0] == 172 && (16...31).contains(values[1])) ||
            (values[0] == 192 && values[1] == 168)
    }
}

enum PCRemoteCommand: String, Codable, CaseIterable {
    case ping, playPause = "play_pause", previous, next, volumeUp = "volume_up", volumeDown = "volume_down", mute
    var title: String {
        switch self {
        case .ping: return "Kiểm tra PC"
        case .playPause: return "Phát / tạm dừng"
        case .previous: return "Bài trước"
        case .next: return "Bài tiếp"
        case .volumeUp: return "Tăng âm lượng"
        case .volumeDown: return "Giảm âm lượng"
        case .mute: return "Bật / tắt tiếng"
        }
    }
    var icon: String {
        switch self {
        case .ping: return "network"
        case .playPause: return "playpause.fill"
        case .previous: return "backward.end.fill"
        case .next: return "forward.end.fill"
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        case .mute: return "speaker.slash.fill"
        }
    }
}

enum PCRemoteWire {
    static let maximumFrameSize = 2048
    struct Request: Codable {
        let v: Int
        let id: String
        let ts: Int64
        let command: PCRemoteCommand
        let signature: String
    }
    struct Reply: Codable {
        let v: Int
        let id: String
        let ok: Bool
        let code: String
        let signature: String
    }
    static func hexData(_ text: String) -> Data? {
        guard text.utf8.count == 64, text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        let chars = Array(text.utf8)
        var bytes = [UInt8]()
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(decoding: chars[index...index+1], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }
    static func signature(_ message: String, key: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
            .map { String(format: "%02x", $0) }.joined()
    }
    static func request(_ command: PCRemoteCommand, configuration: PCRemoteConfiguration,
                        id: String = UUID().uuidString.lowercased(), time: Date = Date()) throws -> Request {
        guard configuration.isValid, let key = configuration.keyBytes else { throw PCRemoteError.configuration }
        let ts = Int64(time.timeIntervalSince1970)
        let message = "HN-PC-1\n\(id)\n\(ts)\n\(command.rawValue)"
        return Request(v: 1, id: id, ts: ts, command: command, signature: signature(message, key: key))
    }
    static func frame(_ request: Request) throws -> Data {
        let payload = try JSONEncoder().encode(request)
        guard payload.count <= maximumFrameSize else { throw PCRemoteError.invalidReply }
        var length = UInt32(payload.count).bigEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(payload)
        return result
    }
    static func frameLength(_ header: Data) throws -> Int {
        guard header.count == 4 else { throw PCRemoteError.invalidReply }
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...maximumFrameSize).contains(count) else { throw PCRemoteError.invalidReply }
        return count
    }
    static func verifyReply(_ data: Data, requestID: String, key: Data) throws -> Reply {
        guard data.count <= maximumFrameSize, let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.v == 1, reply.id == requestID, reply.code.utf8.count <= 40,
              let mac = hexData(reply.signature) else { throw PCRemoteError.invalidReply }
        let message = "HN-PC-1-REPLY\n\(reply.id)\n\(reply.ok ? 1 : 0)\n\(reply.code)"
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(message.utf8), using: SymmetricKey(data: key)) else {
            throw PCRemoteError.authentication
        }
        guard reply.ok && reply.code == "ok" else { throw PCRemoteError.rejected(reply.code) }
        return reply
    }
}

// One received packet may contain both a button and a volume value. It must
// produce at most one action; metadata echoes with the same volume do nothing.
struct PCRemoteButtons {
    private(set) var volume = 8
    mutating func reset() { volume = 8 }
    mutating func command(button: MusicControl.Button?, volume received: Int?) -> PCRemoteCommand? {
        let previousVolume = volume
        if let received, (0...15).contains(received) { volume = received }
        if let button {
            switch button {
            case .play, .pause: return .playPause
            case .previous: return .previous
            case .next: return .next
            case .volumeUp: return .volumeUp
            case .volumeDown: return .volumeDown
            }
        }
        guard let received, (0...15).contains(received), received != previousVolume else { return nil }
        return received > previousVolume ? .volumeUp : .volumeDown
    }
}
