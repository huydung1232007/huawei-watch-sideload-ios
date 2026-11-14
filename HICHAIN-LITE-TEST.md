# GT 2 Pro HiChain Lite experiment — NOT YET BUILT OR DEVICE TESTED

Prepared 2026-11-14 against HuaSideload commit `7b725da37daf9dc0c009578bfb9d62d47a283518`.
The original release 1.1 installed successfully, but the user's watch reports
`Auth 1, support type 2, AES-CBC` and stops at the unimplemented HiChain Lite branch.
The security-negotiation auth-type number and auth-algorithm number are not yet known.

## Scope

This experiment implements the Gadgetbridge Auth-1 HiChain Lite flow only when
security negotiation returns type 1 or 2, the link reports support type 2, CBC,
and algorithm 0 (HMAC) or 1 (PBKDF2). All other Lite combinations remain unsupported.
It does not implement Mobiteka Navigation or decode its application messages.
Minimum iOS remains 17; use the newer iPhone, not the iPhone 7 Plus.

The app reads the server nonce, obtains/uses the PIN, verifies the watch's challenge
response, requests bonding parameters, and sends an AES-CBC-wrapped, app-owned key.
It checks the battery query before reporting successful pairing. It implements the
counter-derived CBC IV and saves new Lite credentials in Keychain before transmitting
the bonding key, so a lost acknowledgement does not lose the candidate key.
Malformed nonce/key lengths and unknown authentication types fail closed.

The protocol phone identity is a stable, generated locally administered address
derived from the app-owned random device ID. Gadgetbridge also generates an address;
this is not the actual iPhone Bluetooth hardware address. Compatibility is untested.

Pairing writes bonding state and may interrupt Huawei Health. It is not a read-only
probe. Never accept a factory-reset prompt. `Send setup after pairing` is ignored
for the Lite path even if enabled, and automatic notification-icon registration is
skipped. Do not change Huawei accounts or reset the watch to work around errors.

## Validation status

- Independent reference challenge/response/wrapping-key vectors generated with Python
  `hashlib` / `hmac`, following Gadgetbridge's uppercase ASCII hex and PBKDF2 semantics.
- Eight Swift XCTest cases cover both crypto variants, response verification, invalid
  inputs, protocol gating, nonce extraction, IV wrapping, phone identity and bonding.
- `git diff --check` performed locally.
- Swift tests have NOT been run: no Swift/Xcode toolchain is installed on this Windows PC.
- iOS compilation and physical-watch validation have NOT been performed.
- Do not describe the source patch as a working IPA or a Navigation fix.

## Build without a local Mac

Use a separate fork of the upstream repository. Do not change unrelated repositories.
Apply the supplied patch or upload the prepared source on branch `hichain-lite-test`.
The workflow `.github/workflows/build-ipa.yml` runs on that branch, executes `swift test`,
and builds an unsigned iPhone IPA. It also remains manually runnable through Actions.
The default experimental bundle ID is `com.example.huasideload.lite`.
No Apple signing credentials are needed for the build. Sideload the resulting IPA
using your own Apple ID only after the build/tests succeed and before a supervised test.

Before installing, check that CI succeeded and that the artifact belongs to the exact
source commit. The IPA's display name is `HuaSideload Lite Test`, version 1.1.1 build 3.
Retain build/test logs and IPA SHA-256 alongside the artifact.

## Provenance and license

HuaSideload and this derivative retain the upstream AGPL-3.0 license in `LICENSE`.
HiChain Lite is ported from Gadgetbridge (AGPL-3.0-or-later), copyright (C) 2024
Damien Gaignon and Martin.JM as credited in the original files.

References inspected:
- https://github.com/Freeyourgadget/Gadgetbridge/blob/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/huawei/HuaweiCrypto.java
- https://github.com/Freeyourgadget/Gadgetbridge/blob/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/huawei/packets/DeviceConfig.java
- https://github.com/Freeyourgadget/Gadgetbridge/blob/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/huawei/requests/GetAuthRequest.java
- https://github.com/Freeyourgadget/Gadgetbridge/blob/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/huawei/requests/GetBondRequest.java
- https://github.com/Freeyourgadget/Gadgetbridge/blob/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/huawei/HuaweiSupportProvider.java
