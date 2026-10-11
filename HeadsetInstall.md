# Headset installation — 11 October 2026

Shuttle Club **1.0 (8)**, bundle identifier `com.shuttleclub.vision`, is built and signed for the paired Vision Pro. Installation is pending: the headset could not fulfill required device usage assertions (CoreDevice error 4016). The last independently confirmed installed version is **1.0 (7)**; no build 8 install or launch is claimed.

- All **132 native simulator tests in 14 suites** passed in **14.216 seconds**; all **16 shared-physics tests** also passed.
- Signed build 8 succeeded with the existing development team and automatic provisioning.
- Backgrounding keeps an acquired hand mount while interrupting unfinished gestures; foreground readiness requires a fresh measured sample.
- Missing-palm feedback, saved hand-fit reset, controller sample ordering, motion validation and connection recovery are improved.
- Rotating string contacts use the visible world-space surface and actual contact-point velocity. Milo's footwork continues between points.
- Tracking setup now has contrasting selected controls, one clear status card, Align angle/Reset, and collapsed secondary options.
- Approved home/racket menus, original audio and the layered icon remain included.

Wake and unlock the headset, then install the signed update. Open Shuttle Club manually after installation. Physical holding comfort, fast swings, controller tracking, audio, frame rate and launcher appearance still require device validation; simulator tests use artificial measured poses.

For hands, show your open palm and knuckles, then close to grab. The faint preview becomes solid. Relaxed fingers keep the locked grip. Fully opening for about 0.3 seconds releases it. Release or wrist loss pauses an active rally. Bring the wrist back or grab again, then choose Resume. Hold a comfortable ready pose and use **Align angle**; **Reset hand fit** restores that hand’s default alignment.

Build log: `/private/tmp/shuttle-build 8-device-build.log`
Test log: `/private/tmp/shuttle-build 8-tests.log`
Core log: `/private/tmp/shuttle-polish-core-tests.log`
Result bundle: `/private/tmp/shuttle-vision-build/Logs/Test/Test-ShuttleClub-2026.10.11_22-43-00-+0800.xcresult`
Install attempt: `/private/tmp/shuttle-build 8-install-result.json`
Signed app: `/private/tmp/shuttle-headset-install/Build/Products/Debug-xros/ShuttleClub.app`

Native setup captures: [home setup](Preview/Build8-Home-Tracking.png) and [court setup](Preview/Build8-Court-Tracking.png).

The simulator emitted backlight-observer/audio-queue warnings during startup and Xcode reported absent AppIntents metadata. All tests completed successfully. These logs do not establish headset audio quality.

This is development provisioning, not App Store distribution. The previously inspected development profile expires on 18 October 2026 at 11:24:07 UTC (19:24 Singapore time); check the current signature/profile when redistributing or reinstalling after expiry.
