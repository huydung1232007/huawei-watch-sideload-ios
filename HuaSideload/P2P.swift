import Foundation

// Messaging between the phone and apps on the watch (Gadgetbridge: packets/P2P.java, p2p/HuaweiBaseP2PService.java)
enum P2P {
    static let serviceId: UInt8 = 0x34
    static let commandId: UInt8 = 0x01

    enum Kind {
        static let ping: UInt8 = 1
        static let data: UInt8 = 2
        static let ack: UInt8 = 3
    }

    // Raw acknowledgements: 0xCF = communication success, 0xCD = incoming-ping reply.
    // 0xCE/206 is a communication failure; it does not prove the watch app is closed.
    enum Code {
        static let ok = 0xCF
        static let pingReply = 0xCD
    }

    struct Message {
        let kind: UInt8
        let sequence: UInt16
        let source: String
        let destination: String
        let sourceFingerprint: String?
        let destinationFingerprint: String?
        let data: [UInt8]?
        let code: Int?
    }

    static func request(kind: UInt8, sequence: UInt16, source: String, destination: String,
                        sourceFingerprint: String? = nil, destinationFingerprint: String? = nil,
                        data: [UInt8]? = nil, code: Int = 0) -> HuaweiTLV {
        var tlv = HuaweiTLV()
            .with(0x01, [kind])
            .with(0x02, .bigEndian(sequence))
            .with(0x03, Array(source.utf8))
            .with(0x04, Array(destination.utf8))
        if kind == Kind.data {
            if let sourceFingerprint { tlv = tlv.with(0x05, Array(sourceFingerprint.utf8)) }
            if let destinationFingerprint { tlv = tlv.with(0x06, Array(destinationFingerprint.utf8)) }
        }
        if let data, !data.isEmpty { tlv = tlv.with(0x07, data) }
        if kind == Kind.ack { tlv = tlv.with(0x08, .bigEndian(UInt32(truncatingIfNeeded: code))) }
        return tlv
    }

    static func parse(_ tlv: HuaweiTLV) -> Message? {
        guard let kind = tlv.value(0x01)?.first, let sequence = tlv.int(0x02) else { return nil }
        func text(_ tag: UInt8) -> String { tlv.value(tag).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        return Message(kind: kind, sequence: UInt16(truncatingIfNeeded: sequence), source: text(0x03), destination: text(0x04),
                       sourceFingerprint: tlv.value(0x05).flatMap { String(bytes: $0, encoding: .utf8) },
                       destinationFingerprint: tlv.value(0x06).flatMap { String(bytes: $0, encoding: .utf8) },
                       data: tlv.value(0x07), code: tlv.int(0x08))
    }
}
