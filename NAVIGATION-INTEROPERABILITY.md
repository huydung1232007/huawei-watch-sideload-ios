# Navigation Watch interoperability experiment

The GT 2 Pro user reported successful HiChain Lite pairing and installed package
`com.pineapps.navigation.watch`, with a P2P ping addressed to `com.pineapps.navigation`.
The actual companion is Navigation Watch by Prog Apps/PineApps:
https://play.google.com/store/apps/details?id=com.pineapps.navigation

The available Android device could not be connected. The public 1.80 APK was inspected
locally, without running the Android app or uploading its code/assets to this repository.
APK SHA-256: `9874dcd8381f8e2a4fe1709dc81ac917beafee5645ac60793abfb1ee6165f2f4`.
Certificate SHA-1 matches the mirror's published signing identity:
`c9347171cbd48b90a457611ad3759b0a461cbb83`.
This does not independently prove the mirror copy matches the user's installed Android APK.

## Observed interface facts

- Phone peer package: `com.pineapps.navigation`.
- Watch peer package: `com.pineapps.navigation.watch`.
- Phone fingerprint: uppercase SHA-256 of the Android signing certificate.
- Watch fingerprint: package + public developer-key identifier.
- Watch control strings: `ping`, `init`, `exitwatch` (UTF-8).
- Phone activation message: `start` (UTF-8).
- Guidance: UTF-8 JSON; compact values are strings. `i` is instruction, `d` distance,
  `p` icon filename, `e` arrival information, `s` speed, `f` 24-hour preference,
  `v` vibration pattern, `o` display setting, and `*c` fields are decimal RGB colors.
- Stop message: JSON field `r` with string value `1`.

Version 1.1.3 build 5 implements a small independent encoder and a clearly marked
DEMO display test in the Features tab. It sends activation and one sample instruction,
checks P2P acknowledgements, and can send the stop command. It does not yet calculate
routes or read Google Maps notifications on iOS. ACK success alone does not establish
that the watch rendered the instruction; physical confirmation is still required.

No subscription, payment, entitlement or licensing mechanism is modified by this test.
No proprietary app source or image assets are redistributed. Only interface identifiers
and message field meanings are used by the independent implementation.
