# Headset status — 12 October 2026

Current source and simulator version: **Shuttle Club 1.0 (10)**, `com.shuttleclub.vision`. The unsigned Vision Pro Release compile passed. **Build 10 is not signed or installed.** The user declined physical Vision Pro access for this task; no device query, install or launch was performed.

The last independently confirmed installed version is **1.0 (7)**. Build 8 was previously signed, but its installation failed with CoreDevice error 4016 because required usage assertions were unavailable. No successful build 8 install or launch is claimed.

Build 10 passes **173 native tests in 17 suites**, with the shared physics unchanged from its prior 16-test pass. It fixes hand acquisition/release, saved angles and setup blocking automatic serving. [Current native evidence](Verification/Build10/README.md) includes test results and actual setup screenshots. The earlier rally recordings remain historical build 9 evidence. These use artificial input and do not verify physical holding, tracking, controller pairing, haptics, latency or headset performance.

Earlier build 8 files remain local historical evidence:

- Signed build log: `/private/tmp/shuttle-build8-device-build.log`
- Failed install result: `/private/tmp/shuttle-build8-install-result.json`
- Signed app: `/private/tmp/shuttle-headset-install/Build/Products/Debug-xros/ShuttleClub.app`
- [Home tracking setup](Preview/Build8-Home-Tracking.png) and [court tracking setup](Preview/Build8-Court-Tracking.png)

Development provisioning is separate from App Store distribution. Before any later authorised installation, build/sign the current source using a valid development profile. The previously inspected profile expires on 18 October 2026 at 11:24:07 UTC; it does not certify a build 10 signature.
