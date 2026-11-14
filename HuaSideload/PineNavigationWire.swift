import Foundation

// Independently implemented interoperability encoder. Field meanings and public
// peer identifiers were observed in the signed Navigation Watch Android 1.80 APK.
// No Android implementation or app assets are included in this project.
enum PineNavigationWire {
    static let watchPackage = "com.pineapps.navigation.watch"
    static let phonePackage = "com.pineapps.navigation"
    // Public certificate fingerprint and public watch app ID; these are not secrets.
    static let phoneFingerprint = "375B477B9A7BA9EDC7509C86E412F7BE2E3DFE40F874A941AF17AC61104AAE48"
    static let watchFingerprint = "com.pineapps.navigation.watch_BJcan6UJzVPTB/tyzfEtHGZsja3l1llwtrOG3sJm4xtA+fY00Jwl6oeZ4ofLOomZC9MVSlToTlVVZd/R+HE/ur8="

    struct PeerIdentity {
        let phoneFingerprint: String
        let watchFingerprint: String
    }

    // Incoming watch->phone data carries the watch's own identifier in tag 05
    // and the phone identifier expected by that installed app in tag 06.
    // A Play-distributed phone APK can have a different certificate from the
    // phone build configured in an older AppGallery watch app.
    static func peerIdentity(from message: P2P.Message) -> PeerIdentity? {
        guard message.kind == P2P.Kind.data, message.source == watchPackage,
              message.destination == phonePackage,
              let phone = message.destinationFingerprint, phone.utf8.count == 64,
              phone.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let watch = message.sourceFingerprint, watch.hasPrefix(watchPackage + "_"),
              let key = Data(base64Encoded: String(watch.dropFirst(watchPackage.count + 1))),
              key.count == 65, key.first == 0x04 else { return nil }
        return PeerIdentity(phoneFingerprint: phone, watchFingerprint: watch)
    }

    enum Control: String { case ping, initialize = "init", exit = "exitwatch" }

    static func control(_ data: [UInt8]) -> Control? {
        guard let text = String(bytes: data, encoding: .utf8) else { return nil }
        return Control(rawValue: text)
    }

    static let start = Array("start".utf8)
    static let stop = Array(#"{"r":"1"}"#.utf8)

    enum Turn: String, CaseIterable, Identifiable {
        case straight, left, right, uTurn, destination, unspecified
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .straight: return "continue_16.png"
            case .left: return "normal_left_16.png"
            case .right: return "normal_right_16.png"
            case .destination: return "destination_16.png"
            case .uTurn: return "uturn_left_16.png"
            case .unspecified: return "head_towards_16.png"
            }
        }
        var title: String {
            switch self {
            case .straight: return "Đi thẳng"
            case .left: return "Rẽ trái"
            case .right: return "Rẽ phải"
            case .destination: return "Đến nơi"
            case .uTurn: return "Quay đầu"
            case .unspecified: return "Xem chỉ dẫn"
            }
        }
    }

    static func guidance(instruction: String, distance: String, turn: Turn,
                         eta: String = "", speed: String = "") throws -> [UInt8] {
        // Huawei's phone companion stringifies all compact-field values.
        let fields: [String: String] = [
            "i": String(instruction.prefix(180)), "d": String(distance.prefix(40)), "p": turn.icon,
            "e": String(eta.prefix(80)), "s": String(speed.prefix(40)),
            "f": "1", "o": "1", "v": "",
            "ic": "16777215", "dc": "16777215", "ec": "16777215",
            "sc": "16777215", "cc": "16777215", "pc": "16777215", "bc": "0"
        ]
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard data.count <= 1000 else { throw HuaweiAuthError.unexpected("Navigation message exceeds 1000 bytes") }
        return Array(data)
    }
}
