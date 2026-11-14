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


## Apple-map route selection (1.1.7 build 9)

The user reported the Apple-map route mode working on the phone; this does not
separately establish how long screen-locked updates were tested. Google navigation
was not producing a visible arrow/distance yet. The user then explicitly requested
removing Google Maps and adding route selection to the Apple-map view. Accordingly,
the Google UI, screen capture driver, OCR/arrow code/tests, URL scheme and capture
background/usage declarations are removed. Current app code has no Google mode.
The build can again use the existing iOS 17 target and macOS 15 Intel CI toolchain.

Route calculation requests alternate routes from both providers. Motorcycle requests
ask for two alternates, yielding at most three displayed choices. Each motorcycle
candidate undergoes the same mode/highway/geometry checks; invalid alternatives are
filtered, identical geometry is deduplicated, and no extra routes are synthesized.
MapKit walking/automobile routes use requestsAlternateRoutes. A provider may return
only one reasonable route. Each row shows a route number, distance, duration and
road summary; the selected route is blue and other routes gray. Selecting a row
atomically replaces the route geometry, origin and maneuver list used by guidance.
Changing selection is disabled while navigating; stop first to choose another route.

A single public-landmark HCMC probe returned three motorcycle routes of 2.312 km,
2.315 km and 2.796 km. The response is retained as a bounded parser test fixture,
without any user location. This confirms the live API response format, not physical
route selection/navigation behavior on the user's watch. The new selection flow
requires a device-side check after installing the updated IPA.

References:
- https://developer.apple.com/documentation/mapkit/mkdirections/request/requestsalternateroutes
- https://valhalla.github.io/valhalla/api/route/api-reference/

The user also requested removing the Navigation Watch display-test block. The DEMO
section, sample send/stop methods and demonstration payload helper are removed in
this build. Its dedicated demo-only test is removed; real guidance/protocol tests
remain. Navigation is now entered through the Apple-map route-selection section.


## Navigation companion redesign (1.1.8 build 10)

User requested features 1/2/5: turn haptics, automatic rerouting and trip history,
then asked for a more attractive/convenient app. Navigation is now the first tab,
with an Apple map, connected-watch/battery pill, destination sheet, mode selector,
route cards and a large Start button. During navigation the bottom card shows the
next instruction/distance, live trip statistics, Recalculate and End. History has
its own tab; pairing and advanced tools/logs remain accessible separately.

Turn alerts use independently implemented interface tokens observed in the local
Android companion: v = L/R/S (confirmation/nudge are also known values). No private
Android code/assets are redistributed. Alerts fire once per maneuver near 200 m
and 50 m, skip departure/destination and the first eight seconds, and have a four-
second minimum gap. A near-zone first observation consumes the earlier alert too.
Ordinary BLE distance updates cannot overwrite a queued alert; stop/reroute clears
old queued instructions. The settings sheet contains an on/off toggle and left/
right haptic checks. Physical vibration behavior on the user's GT 2 Pro is still
unverified; a P2P acknowledgement is not evidence of felt vibration.

Automatic rerouting needs accurate GPS (<=35 m), multiple out-of-route fixes over
at least eight seconds, and only one request at a time. Motorcycle mode remains
motorcycle, requests one new route and applies the existing highway/mode checks.
Success has a 30-second cooldown. Failures back off 60/120/180 seconds; after three
failures the user must explicitly retry. Stop/disconnect invalidates in-flight
route responses so late responses cannot restart a trip. Rerouting changes route
geometry/maneuvers while preserving the same trip's statistics. GPS remains active
in the already authorized location background mode; device behavior needs testing.

Trip history records destination name, mode, start/end, estimated GPS distance,
elapsed time, average speed and completion state. It stores NO GPS track/coordinates.
Low-quality points, implausible jumps, stationary fixes and long GPS gaps are not
joined into mileage. Statistics are estimates. A checkpoint is saved about every
30 seconds; an unfinished checkpoint becomes an interrupted record at next launch.
Local JSON is written atomically in the app sandbox with iOS protection usable
after first unlock, and excluded from backup. No history is uploaded to GitHub or
routing servers. Routing requests still send their required endpoints to providers.
Existing unreadable history is not overwritten; delete actions are explicit UI actions.

CI additionally builds a simulator DEBUG app with synthetic public-landmark preview
data to capture Navigation/History screenshots for visual review. Preview data is
excluded from device Release builds and does not access any user watch/location.
The original Google capture and display-demo functionality remain removed.

The final CI run uses the previously verified ARM Xcode-27 image for simulator
rendering; the first Intel run passed the logic suite and device Release build but
was slow in simulator rendering. Boot and UI-render steps are bounded. New route
responses also recheck GPS freshness, GPS loss resets deviation confirmation, and
history read access is retried after the app becomes active/unlocked.
