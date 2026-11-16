import Foundation

// Only the documented security-reply tag is treated as a UDID. In particular,
// a serial, an arbitrary 32-byte challenge, or a service list is never hashed or
// converted into a purported device identifier. Reports contain lengths and
// numeric protocol capabilities, never raw TLV values, PINs, keys or identities.
struct WatchIdentityEvidence {
    enum IdentityState: Equatable {
        case notRead, missing, unsupported, recognized
        var label: String {
            switch self {
            case .notRead: return "Chưa đọc phản hồi từ đồng hồ."
            case .missing: return "Đồng hồ chưa gửi UDID trong phản hồi hiện tại."
            case .unsupported: return "Có trường nhận dạng nhưng chưa đọc được định dạng."
            case .recognized: return "Đã nhận mã UDID đúng định dạng."
            }
        }
    }

    private(set) var identityState: IdentityState = .notRead
    private(set) var authVersion: Int?
    private(set) var supportType: Int?
    private(set) var encryptMethod: Int?
    private(set) var securityLayout = "not received"
    private(set) var identityBytes: Int?
    private(set) var platformLayout = "not queried"
    private(set) var platformAPI: Int?
    private(set) var platformType: Int?
    private(set) var platformWidth: Int?
    private(set) var platformHeight: Int?
    private(set) var platformCode: Int?
    var installPhase = "not attempted"
    var installStatus: Int?

    mutating func recordLink(_ link: LinkInfo) {
        authVersion = link.authVersion
        supportType = link.deviceSupportType
        encryptMethod = link.encryptMethod
    }

    static func layout(_ tlv: HuaweiTLV) -> String {
        let fields = tlv.items.prefix(32).map { String(format: "%02X:%dB", $0.tag, $0.value.count) }
        return fields.isEmpty ? "empty" : fields.joined(separator: " ")
    }

    // Return the actual identity only to the existing masked on-device display;
    // keep no copy of it in the diagnostic report model.
    mutating func recordSecurity(_ tlv: HuaweiTLV) -> String? {
        securityLayout = Self.layout(tlv)
        let fields = tlv.items.filter { $0.tag == 0x05 }
        identityBytes = fields.first?.value.count
        guard !fields.isEmpty else { identityState = .missing; return nil }
        guard fields.count == 1 else { identityState = .unsupported; return nil }
        var bytes = fields[0].value
        let padding: Set<UInt8> = [0, 9, 10, 13, 32]
        while let first = bytes.first, padding.contains(first) { bytes.removeFirst() }
        while let last = bytes.last, padding.contains(last) { bytes.removeLast() }
        guard bytes.count == 64,
              bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              !bytes.allSatisfy({ $0 == 48 }), !bytes.allSatisfy({ $0 == 70 || $0 == 102 }) else {
            identityState = .unsupported
            return nil
        }
        identityState = .recognized
        return String(decoding: bytes, as: UTF8.self).uppercased()
    }

    mutating func recordPlatform(_ tlv: HuaweiTLV) {
        platformAPI = nil; platformType = nil; platformWidth = nil; platformHeight = nil
        platformCode = tlv.int(0x7F)
        platformLayout = Self.layout(tlv)
        guard let outer = tlv.value(0x81), let groups = try? HuaweiTLV.parse(outer),
              let inner = groups.items.first(where: { $0.tag == 0x82 }),
              let params = try? HuaweiTLV.parse(inner.value) else { return }
        platformLayout += " / " + Self.layout(params)
        platformType = params.int(0x03)
        platformAPI = params.int(0x04)
        platformWidth = params.int(0x07)
        platformHeight = params.int(0x08)
    }

    mutating func platformUnavailable() {
        platformAPI = nil; platformType = nil; platformWidth = nil; platformHeight = nil
        platformCode = nil
        platformLayout = "no usable response"
    }

    func report() -> String {
        func number(_ value: Int?) -> String { value.map(String.init) ?? "unknown" }
        return """
        HN-IDENTITY-1
        Auth version: \(number(authVersion)); support: \(number(supportType)); encryption: \(number(encryptMethod))
        Security reply tags: \(securityLayout)
        Identity field bytes: \(number(identityBytes)); recognized: \(identityState == .recognized ? "yes" : "no")
        App platform tags: \(platformLayout)
        App platform result: \(number(platformCode))
        App API: \(number(platformAPI)); type: \(number(platformType)); screen: \(number(platformWidth))x\(number(platformHeight))
        Install phase: \(installPhase); watch status: \(number(installStatus))
        """
    }
}
