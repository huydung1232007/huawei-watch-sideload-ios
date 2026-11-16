import XCTest
@testable import HuaSideloadParsing

final class WatchIdentityEvidenceTests: XCTestCase {
    private let sample = String(repeating: "0123456789abcdef", count: 4)

    func testKnownReplyFieldAccepts64HexAndNormalizesCase() {
        var evidence = WatchIdentityEvidence()
        XCTAssertEqual(evidence.recordSecurity(HuaweiTLV().with(5, Array(sample.utf8))), sample.uppercased())
        XCTAssertEqual(evidence.identityState, .recognized)
        XCTAssertEqual(evidence.identityBytes, 64)
    }

    func testNullAndWhitespacePaddingDoNotHideAValidIdentity() {
        var evidence = WatchIdentityEvidence()
        let data: [UInt8] = [32, 9] + Array(sample.utf8) + [0, 13, 10]
        XCTAssertEqual(evidence.recordSecurity(HuaweiTLV().with(5, data)), sample.uppercased())
    }

    func testBinary32BytesAreNotInventedIntoAUdid() {
        var evidence = WatchIdentityEvidence()
        XCTAssertNil(evidence.recordSecurity(HuaweiTLV().with(5, Array(UInt8(0)...UInt8(31)))))
        XCTAssertEqual(evidence.identityState, .unsupported)
        XCTAssertEqual(evidence.identityBytes, 32)
        XCTAssertTrue(evidence.report().contains("05:32B"))
    }

    func testSerialOrMatchingLengthInAnotherFieldDoesNotBecomeIdentity() {
        var evidence = WatchIdentityEvidence()
        let tlv = HuaweiTLV().with(9, Array("SERIAL-EXAMPLE-PRIVATE".utf8)).with(3, Array(sample.utf8))
        XCTAssertNil(evidence.recordSecurity(tlv))
        XCTAssertEqual(evidence.identityState, .missing)
        XCTAssertFalse(evidence.report().contains("SERIAL-EXAMPLE-PRIVATE"))
        XCTAssertFalse(evidence.report().lowercased().contains(sample))
    }

    func testInvalidCharactersAndPlaceholderIdsAreRejected() {
        for value in [String(repeating: "Z", count: 64), String(repeating: "0", count: 64),
                      String(repeating: "F", count: 64), String(repeating: "a", count: 63),
                      String(repeating: "é", count: 32)] {
            var evidence = WatchIdentityEvidence()
            XCTAssertNil(evidence.recordSecurity(HuaweiTLV().with(5, Array(value.utf8))))
            XCTAssertEqual(evidence.identityState, .unsupported)
        }
    }

    func testConflictingOrDuplicateIdentityFieldsAreNotSilentlyChosen() {
        var evidence = WatchIdentityEvidence()
        let tlv = HuaweiTLV().with(5, Array(sample.utf8)).with(5, Array(sample.uppercased().utf8))
        XCTAssertNil(evidence.recordSecurity(tlv))
        XCTAssertEqual(evidence.identityState, .unsupported)
    }

    func testReportContainsMetadataButNoRawUdidPinNonceOrPlatformText() {
        var evidence = WatchIdentityEvidence()
        _ = evidence.recordSecurity(HuaweiTLV().with(5, Array(sample.utf8)).with(1, Array("PIN-DO-NOT-EXPORT".utf8)))
        let params = HuaweiTLV().with(3, [38]).with(4, [6]).with(7, .bigEndian(UInt32(454)))
            .with(8, .bigEndian(UInt32(454))).with(5, Array("PRIVATE-PLATFORM-TEXT".utf8))
        evidence.recordPlatform(HuaweiTLV().with(0x81, HuaweiTLV().with(0x82, params.serialize()).serialize()))
        let report = evidence.report()
        XCTAssertTrue(report.contains("App API: 6; type: 38; screen: 454x454"))
        for privateText in [sample, sample.uppercased(), "PIN-DO-NOT-EXPORT", "PRIVATE-PLATFORM-TEXT"] {
            XCTAssertFalse(report.contains(privateText))
        }
    }

    func testUnavailablePlatformClearsOldCapabilitiesAndReportsNumericRejection() {
        var evidence = WatchIdentityEvidence()
        evidence.recordPlatform(HuaweiTLV().with(0x7F, .bigEndian(UInt32(123))))
        XCTAssertTrue(evidence.report().contains("App platform result: 123"))
        evidence.platformUnavailable()
        XCTAssertNil(evidence.platformCode)
        XCTAssertNil(evidence.platformAPI)
        XCTAssertTrue(evidence.report().contains("no usable response"))
    }
}
