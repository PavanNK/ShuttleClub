# Headset status — 12 October 2026

Current source and simulator version: **Shuttle Club 1.0 (11)**, `com.shuttleclub.vision`. The final unsigned Vision Pro Release compile passed. **Build 11 is not signed or installed.** The user declined physical Vision Pro access for this task; no device query, signing, install or launch was performed.

The last independently confirmed installed version is **1.0 (7)**. Build 8 was previously signed, but its installation failed with CoreDevice error 4016 because required usage assertions were unavailable. No successful build 8 install or launch is claimed.

## Current build 11

All **209 native tests in 22 suites passed in 28.430 seconds**, with the final unsigned Release compile also successful. Shared physics is unchanged from its last direct 16-test run in build 9. [Build 11 evidence](Verification/Build11/README.md) contains the native test/build records; four unaltered 3840×2160 native screenshots and the rally/miss recordings have been inspected. The repository videos are uncut 1280×720 AVFoundation exports, without compositing or retiming, and use synthetic hand input. No physical holding, tracking, movement comfort, controller pairing, haptics, latency or headset performance is verified.

Controller alignment captures a natural playing hold after three steady seconds, with cancellation on loss or setup changes. Face turns remain around the tilted shaft, and existing saved fits keep their mounted pose through migration. Move in court offers Thumbstick slide on the free Sense controller (sole-controller fallback), Auto glide, or Stay centred; Hands use Auto glide when Thumbstick slide is selected. Physical walking is not required. Floating Milo, contact flashes and feather turning are native scene features, not evidence of physical tracking quality.

## Previous build 10

Build 10 passes **173 native tests in 17 suites**, with the shared physics unchanged from its prior 16-test pass. It fixes hand acquisition/release, saved angles and setup blocking automatic serving. [Current native evidence](Verification/Build10/README.md) includes test results and actual setup screenshots. The earlier rally recordings remain historical build 9 evidence. These use artificial input and do not verify physical holding, tracking, controller pairing, haptics, latency or headset performance.

Earlier build 8 files remain local historical evidence:

- Signed build log: `/private/tmp/shuttle-build8-device-build.log`
- Failed install result: `/private/tmp/shuttle-build8-install-result.json`
- Signed app: `/private/tmp/shuttle-headset-install/Build/Products/Debug-xros/ShuttleClub.app`
- [Home tracking setup](Preview/Build8-Home-Tracking.png) and [court tracking setup](Preview/Build8-Court-Tracking.png)

Development provisioning is separate from App Store distribution. Before any later authorised installation, build/sign the current source using a valid development profile. The previously inspected profile expires on 18 October 2026 at 11:24:07 UTC; it does not certify a build 11 signature.
