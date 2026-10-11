# Headset installation — 11 October 2026

Shuttle Club **1.0 (7)**, bundle identifier `com.shuttleclub.vision`, is built, signed and installed on the user's Vision Pro running visionOS 27.0.1. An independent headset app query confirms version 1.0 (7).

- All **105 native simulator tests in 12 suites** passed in **12.931 seconds**.
- Signed build 7 succeeded with the existing development team and automatic provisioning.
- Installation succeeded and an independent app query confirmed build 7.
- The update adds open→close grab, wrist-locked holding, deliberate full-open release, safe tracking-loss recovery, saved hand fits and remembered input/hand selection. Controller angle controls are clarified and alignment is upright.
- The approved Minimal/Playful menus, native 3D racket chooser and original layered icon are included.
- Open Shuttle Club manually. Launch and actual input interaction were not independently confirmed after this installation.

In **Hand tracking**, open your selected hand, then close it to grab. The faint preview becomes solid. Relaxing the fingers keeps the grip; fully opening for about 0.3 seconds releases it. Release or wrist loss pauses an active rally. Grab/recover, then choose Resume. Physical grip detection thresholds, fit, fast swings, controller tracking, audio, comfort, frame rate and launcher appearance still require device validation. Simulator tests use artificial measured poses.

Build log: `/private/tmp/shuttle-grab-device-build.log`
Test log: `/private/tmp/shuttle-grab-tests.log`
Result bundle: `/private/tmp/shuttle-vision-build/Logs/Test/Test-ShuttleClub-2026.10.11_22-21-18-+0800.xcresult`
Install result: `/private/tmp/shuttle-build7-install-result.json`
Version confirmation: `/private/tmp/shuttle-build7-app-query.json`
Signed app: `/private/tmp/shuttle-headset-install/Build/Products/Debug-xros/ShuttleClub.app`

The simulator emitted backlight-observer and audio-queue warnings during startup; all tests completed successfully. Xcode emitted its usual metadata-extraction warning for the absent AppIntents dependency. These warnings do not establish headset audio quality.

This is development provisioning, not App Store distribution. The previous embedded development profile expires on 18 October 2026 at 11:24:07 UTC (19:24 Singapore time); check the current signature/profile when redistributing or reinstalling after expiry.
