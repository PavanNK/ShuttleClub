# Headset status — 11 October 2026

Current source and simulator version: **Shuttle Club 1.0 (9)**, `com.shuttleclub.vision`. The unsigned Vision Pro Release compile passed. **Build 9 is not signed or installed.** The user declined physical Vision Pro access for this task; no device query, install or launch was performed.

The last independently confirmed installed version is **1.0 (7)**. Build 8 was previously signed, but its installation failed with CoreDevice error 4016 because required usage assertions were unavailable. No successful build 8 install or launch is claimed.

Build 9 passes **145 native simulator tests in 16 suites**, plus **16 shared-physics tests**. It improves Milo's reachable return planning and resource/update lifecycles. [Native evidence](Verification/Build9/README.md) includes uncut rally/miss recordings, actual contact measurements and a frozen string-contact screenshot. These use artificial input and do not verify physical holding, tracking, controller pairing, haptics, latency or headset performance.

Earlier build 8 files remain local historical evidence:

- Signed build log: `/private/tmp/shuttle-build8-device-build.log`
- Failed install result: `/private/tmp/shuttle-build8-install-result.json`
- Signed app: `/private/tmp/shuttle-headset-install/Build/Products/Debug-xros/ShuttleClub.app`
- [Home tracking setup](Preview/Build8-Home-Tracking.png) and [court tracking setup](Preview/Build8-Court-Tracking.png)

Development provisioning is separate from App Store distribution. Before any later authorised installation, build/sign the current source using a valid development profile. The previously inspected profile expires on 18 October 2026 at 11:24:07 UTC; it does not certify a build 9 signature.
