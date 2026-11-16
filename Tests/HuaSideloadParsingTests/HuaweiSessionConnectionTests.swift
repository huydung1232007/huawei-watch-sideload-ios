import XCTest
@testable import HuaSideloadParsing

@MainActor
final class HuaweiSessionConnectionTests: XCTestCase {
    private final class MemorySecrets: SecretBackend {
        var values: [String: String] = [:]
        func read(_ key: String) -> String? { values[key] }
        func write(_ value: String, for key: String) -> Bool { values[key] = value; return true }
        func delete(_ key: String) { values[key] = nil }
    }

    // A deterministic watch simulator exercises the actual handshake, not just
    // the crypto helper. No Bluetooth, actual identities or keychain are used.
    @MainActor private final class WatchHarness {
        let secrets = MemorySecrets()
        let defaults: UserDefaults
        let suite = "HuaweiSessionConnectionTests." + UUID().uuidString
        let oldPIN = [UInt8](repeating: 0x11, count: 16)
        let newPIN = [UInt8](repeating: 0x22, count: 16)
        let oldKey = [UInt8](repeating: 0x33, count: 16)
        let nonce = [UInt8](repeating: 0x44, count: 16)
        var session: HuaweiSession!
        var commands: [UInt8] = []
        var stages: [PairingStage] = []
        var acceptAuth = false
        var answerAuth = true
        var freshPINIssued = false
        var negotiationIdentity: [UInt8]?

        init() {
            defaults = UserDefaults(suiteName: suite)!
            secrets.values["lite.pin.watch"] = oldPIN.hexCompact
            secrets.values["lite.secret.watch"] = oldKey.hexCompact
            let store = WatchStore(defaults: defaults, credentials: CredentialStore(secure: secrets, legacy: defaults))
            session = HuaweiSession(writeFrame: { [weak self] frame in self?.receive(frame) },
                                    maxWriteLength: { 182 }, log: { _, _ in }, store: store,
                                    requestTimeout: { _, _ in 0.05 })
            session.onPairingStage = { [weak self] in self?.stages.append($0) }
        }

        func receive(_ frame: [UInt8]) {
            guard let result = HuaweiPacketParser().feed(frame).first,
                  case .success(let packet) = result else { return }
            commands.append(packet.commandId)
            var tlv = HuaweiTLV()
            switch packet.commandId {
            case 0x01:
                tlv = tlv.with(0x05, [0, 1] + nonce).with(0x07, [2]).with(0x08, [0])
            case 0x33:
                tlv = tlv.with(0x02, [1])
                if let negotiationIdentity { tlv = tlv.with(0x05, negotiationIdentity) }
            case 0x2C:
                freshPINIssued = true
                let iv = [UInt8](repeating: 0x55, count: 16)
                let encrypted = try! HCrypto.cbcEncrypt(newPIN, key: PinCode.digestSecret(authVersion: 1), iv: iv)
                tlv = tlv.with(0x01, encrypted).with(0x02, iv)
            case 0x13:
                guard answerAuth else { return }
                if acceptAuth, let client = packet.tlv?.value(0x02) {
                    let auth = try! HiChainLite.authentication(pin: freshPINIssued ? newPIN : oldPIN,
                        serverNonce: nonce, clientNonce: Array(client.dropFirst(2)), authAlgo: 0)
                    tlv = tlv.with(0x01, auth.expectedResponse)
                } else { tlv = tlv.with(0x01, [UInt8](repeating: 0, count: 32)) }
            case 0x0F:
                // Intentionally stop before bonding: a valid auth must reach
                // BondParams; stale/invalid auth must never reach it.
                tlv = tlv.with(0x01, [0xFF])
            default: return
            }
            _ = session.receive(HuaweiPacket(serviceId: packet.serviceId, commandId: packet.commandId, body: tlv.serialize()))
        }

        func cleanup() { session.reset(); defaults.removePersistentDomain(forName: suite) }
    }

    func testStaleSavedPINStopsBeforeBondingAndPreservesCredentials() async {
        let watch = WatchHarness(); defer { watch.cleanup() }
        do { try await watch.session.pair(watch: "watch"); XCTFail("Invalid authentication accepted") } catch {}
        XCTAssertTrue(watch.session.liteAuthenticationFailedWithSavedPIN)
        XCTAssertEqual(watch.commands, [0x01, 0x33, 0x13])
        XCTAssertEqual(watch.secrets.values["lite.pin.watch"], watch.oldPIN.hexCompact)
        XCTAssertEqual(watch.secrets.values["lite.secret.watch"], watch.oldKey.hexCompact)
        XCTAssertFalse(watch.session.isPaired)
        XCTAssertTrue(watch.stages.contains(.liteAuthenticating))
    }

    func testDisconnectClearsAnIdentityFromThePreviousSession() async {
        let watch = WatchHarness(); defer { watch.cleanup() }
        watch.negotiationIdentity = Array(String(repeating: "0123456789ABCDEF", count: 4).utf8)
        do { try await watch.session.pair(watch: "watch") } catch {}
        XCTAssertNotNil(watch.session.watchUDID)
        XCTAssertEqual(watch.session.identityEvidence.identityState, .recognized)
        watch.session.reset()
        XCTAssertNil(watch.session.watchUDID)
        XCTAssertEqual(watch.session.identityEvidence.identityState, .notRead)
        watch.negotiationIdentity = nil
        do { try await watch.session.pair(watch: "watch") } catch {}
        XCTAssertNil(watch.session.watchUDID)
        XCTAssertEqual(watch.session.identityEvidence.identityState, .missing)
    }

    func testSavedPINTimeoutOffersRecoveryAndDoesNotBond() async {
        let watch = WatchHarness(); defer { watch.cleanup() }
        watch.answerAuth = false
        do { try await watch.session.pair(watch: "watch"); XCTFail("Missing response accepted") }
        catch { XCTAssertTrue(String(describing: error).contains("Lite 2/4")) }
        XCTAssertTrue(watch.session.liteAuthenticationFailedWithSavedPIN)
        XCTAssertEqual(watch.commands, [0x01, 0x33, 0x13])
        XCTAssertEqual(watch.secrets.values["lite.pin.watch"], watch.oldPIN.hexCompact)
    }

    func testExplicitFreshPINIgnoresCacheAndAuthenticatesBeforeBondParams() async {
        let watch = WatchHarness(); defer { watch.cleanup() }
        watch.acceptAuth = true
        do { try await watch.session.pair(watch: "watch", refreshLitePIN: true); XCTFail("Malformed BondParams accepted") } catch {}
        XCTAssertEqual(watch.commands, [0x01, 0x33, 0x2C, 0x13, 0x0F])
        XCTAssertFalse(watch.session.liteAuthenticationFailedWithSavedPIN)
        XCTAssertTrue(watch.stages.contains(.liteBonding))
        // An unsuccessful later stage still must not overwrite the old set.
        XCTAssertEqual(watch.secrets.values["lite.pin.watch"], watch.oldPIN.hexCompact)
        XCTAssertEqual(watch.secrets.values["lite.secret.watch"], watch.oldKey.hexCompact)
    }

    func testFreshPINRejectedDoesNotErasePreviousCredentialsOrBond() async {
        let watch = WatchHarness(); defer { watch.cleanup() }
        do { try await watch.session.pair(watch: "watch", refreshLitePIN: true); XCTFail("Invalid authentication accepted") } catch {}
        XCTAssertEqual(watch.commands, [0x01, 0x33, 0x2C, 0x13])
        XCTAssertFalse(watch.session.liteAuthenticationFailedWithSavedPIN)
        XCTAssertEqual(watch.secrets.values["lite.pin.watch"], watch.oldPIN.hexCompact)
    }

    func testCancellingPendingRequestReleasesWaiterAndCannotConsumeNewResponse() async throws {
        var sent = 0
        let session = HuaweiSession(writeFrame: { _ in sent += 1 }, maxWriteLength: { 182 }, log: { _, _ in })
        let first = Task { try await session.request(1, 0x33, HuaweiTLV(), label: "cancelled", encrypted: false) }
        for _ in 0..<200 where sent < 1 { await Task.yield() }
        XCTAssertEqual(sent, 1)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled request succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let second = Task { try await session.request(1, 0x33, HuaweiTLV(), label: "current", encrypted: false) }
        for _ in 0..<200 where sent < 2 { await Task.yield() }
        XCTAssertEqual(sent, 2)
        _ = session.receive(HuaweiPacket(serviceId: 1, commandId: 0x33, body: HuaweiTLV().with(2, [1]).serialize()))
        let response = try await second.value
        XCTAssertEqual(response.commandId, 0x33)
        session.reset()
    }

    func testDisconnectResumesPendingHandshakeInsteadOfWaitingForTimeout() async {
        var sent = false
        let session = HuaweiSession(writeFrame: { _ in sent = true }, maxWriteLength: { 182 }, log: { _, _ in })
        let pending = Task { try await session.request(1, 0x33, HuaweiTLV(), label: "disconnect", encrypted: false) }
        for _ in 0..<200 where !sent { await Task.yield() }
        XCTAssertTrue(sent)
        session.reset()
        do { _ = try await pending.value; XCTFail("Disconnected request succeeded") }
        catch { XCTAssertTrue(String(describing: error).contains("Connection lost")) }
    }
}
