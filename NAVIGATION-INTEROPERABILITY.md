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

The user reported code 206 while the watch still emitted init/ping. Huawei documents
206 as a general communication failure, including possible peer identity mismatch;
it must not be labelled only as "app not running".
https://developer.huawei.com/consumer/en/doc/connectivity-guides/faq-0000001050818031/

Version 1.1.4 build 6 preserves P2P fingerprint tags 05/06 previously discarded by
the parser, and learns the watch's source fingerprint and expected phone destination
fingerprint from packets belonging to the exact Navigation peer pair. It validates
the public-identifier formats, keeps them only for the connection, and logs only
whether the phone identifier differs from the APK. Actual values are not published.
When init/ping established that the app is open, it sends guidance directly instead
of first sending the optional activation command. Outcomes log the failing stage.
The user subsequently reported that the watch displayed the sample instruction successfully. This validates sample display on that watch, not live route tracking.


## Apple Maps route experiment (1.1.5 build 7)

The user accepted Apple Maps as an alternative and requires operation with the iPhone
screen locked. This build adds an independent MapKit route session inside HuaSideload:
local place search, walking/automobile route preview, explicit start/stop and GPS route
progress. It does not read another Maps app's active navigation session. No Google key,
Google Cloud project, billing setup, captured screen or notification extraction is used.

Core Location background activity and the location background mode keep an explicitly
started trip eligible for updates when the screen locks. The existing Bluetooth mode
and a short background task finish each serialized watch send. Only the newest pending
GPS instruction is retained; stop clears pending guidance. Disconnect, permission loss,
watch app exit or delivery failure stops the session. Route and coordinates are not
persisted or written into app-level route logs. MapKit requests necessarily send search
and route information to Apple's map service. Low/stale GPS is reported on the watch.

Limitations: device-side background behavior still needs a physical test. Force-quitting
or OS termination stops the trip; it does not automatically restore an active route.
There is no motorcycle mode or automatic off-route recalculation in this experiment.
Maneuver icons recognize only supported wording, with a generic icon for unknown text;
the original Apple instruction is preserved. ETA uses the original route duration scaled
by remaining distance, not a new live traffic estimate. Keep the Navigation watch app
open. Search and route availability depend on Apple coverage and connectivity.

References:
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- https://developer.apple.com/documentation/mapkit/mkdirections
- https://www.apple.com/ios/feature-availability/


## Dual-mode prototype (1.1.6 build 8)

The user subsequently requires motorcycles and accepts Google Maps with the screen on.
The current prototype therefore offers two mutually exclusive guidance sources:

1. An iOS 27+ ScreenCaptureKit full-display stream selected through Apple's system
   picker, with on-device Vision OCR and independent geometric arrow templates.
   The user starts motorcycle navigation in Google Maps, enables screen sharing,
   and keeps Maps visible in portrait orientation. No audio output is attached,
   screenshots are not saved, and image buffers never leave the phone. A Google
   navigation banner, remaining duration and Google/Exit context must be recognized
   before producing guidance. Unsupported/uncertain arrow shapes keep a generic icon
   and an explicit request to consult Maps. Switching away clears guidance after an
   observation timeout; stream inactivity/lock stops capture. No direct Maps API or
   cross-app notification reader is claimed. Recognition still needs physical validation.
2. A background GPS session with destination search and map display from Apple.
   The motorcycle route itself comes from Valhalla/OpenStreetMap, NOT Apple's
   automobile profile. The user is informed in the UI that route endpoints are sent
   to the FOSSGIS demo endpoint on an explicit Calculate action. Requests use the
   motorcycle profile, never ignore access restrictions and never fall back to auto.
   Highway avoidance is a preference; the decoder independently refuses returned
   highway routes or missing highway classification. Routes must explicitly report
   motorcycle travel type. The personal experiment limits requests to one per three
   seconds and destinations within 100 km; no continuous server polling/rerouting is
   performed. OSM attribution is visible. Walking/automobile remain separate modes.

A public-landmark-only 482 m HCMC motorcycle response was obtained for a bounded API
probe. It is a parser fixture; it is not a navigation safety or background-execution test.
The probe's hard-exclusion option produced warning 208 (not supported by that server).
The app does NOT request hard exclusions and does not claim they are enforced. Instead,
it refuses any response whose has_highway field is missing/true or maneuver flags
report a highway. This can conservatively refuse some valid local routes as well.

No end-user release or server service is deployed. This is a personal sideloaded trial;
public demo fair-use rules apply. A general distribution should arrange a provider or
self-host and notify the demo operator as its README requests; no such notice has been
sent by the assistant. The request header identifies this experimental fork.

References:
- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype
- https://github.com/valhalla/valhalla#demo-server
- https://valhalla.github.io/valhalla/api/route/api-reference/
