# Headset status — 12 October 2026

**Signed Release Shuttle Club 1.0 (12)** installed successfully on the physical Vision Pro, replacing independently read build 11. All **230 native tests in 25 suites** and **23 Core tests** pass. Strict signature verification passed before installation. [Build 12 evidence](Verification/Build12/README.md) records the corrected alignment, lower opening feeds, compact HUD and bounded near-net robot reach. [Deployment evidence](Verification/Build12/Device-Install-Summary.json) records the installer and version-query outcomes without device identifiers.

Open **Shuttle Club** manually. No remote launch was attempted for build 12. Physical holding comfort, tracking latency and headset performance remain unverified. Some robot countershot lobs can exceed the authored roof; ceiling collisions are absent. Development provisioning expires on **18 October 2026 at 19:24:07 Singapore time**.

## Previous build 11 installation

**Signed Release Shuttle Club 1.0 (11)**, `com.shuttleclub.vision`, was successfully installed on the user's Vision Pro on **12 October 2026**. An independent app query confirms the installed version, upgraded from 1.0 (7). The user explicitly authorised this installation after the earlier test/capture phase without physical-device access.

**Open Shuttle Club manually from the headset launcher.** Remote launch timed out after 30 seconds; a separate process query succeeded but found no running app. A running build 11 app and physical gameplay are not confirmed. The [sanitised installation summary](Verification/Build11/Device-Install-Summary.json) records signing, installation, version and launch outcomes without hardware identifiers.

## Previous build 11

All **209 native tests in 22 suites passed in 28.430 seconds**, with the final unsigned Release compile also successful. Those software checks and simulator captures on 12 October used no physical-device access. The later signed Release build used unchanged source `be46483`; strict code-signature verification passed, and the embedded development profile matched the app's signing entitlements before installation. Installation and the independent version query both succeeded. Shared physics is unchanged from its last direct 16-test run in build 9.

[Build 11 evidence](Verification/Build11/README.md) contains the native test/build records; four unaltered 3840×2160 native screenshots and the rally/miss recordings have been inspected. The repository videos are uncut 1280×720 AVFoundation exports, without compositing or retiming, and use synthetic hand input. No physical holding, tracking, movement comfort, controller pairing, haptics, latency or headset performance is verified.

Controller alignment captures a natural playing hold after three steady seconds, with cancellation on loss or setup changes. Face turns remain around the tilted shaft, and existing saved fits keep their mounted pose through migration. Move in court offers Thumbstick slide on the free Sense controller (sole-controller fallback), Auto glide, or Stay centred; Hands use Auto glide when Thumbstick slide is selected. Physical walking is not required. Floating Milo, contact flashes and feather turning are native scene features, not evidence of physical tracking quality.

## Previous build 10

Build 10 passes **173 native tests in 17 suites**, with the shared physics unchanged from its prior 16-test pass. It fixes hand acquisition/release, saved angles and setup blocking automatic serving. [Current native evidence](Verification/Build10/README.md) includes test results and actual setup screenshots. The earlier rally recordings remain historical build 9 evidence. These use artificial input and do not verify physical holding, tracking, controller pairing, haptics, latency or headset performance.

Build 8 was previously signed, but its installation failed with CoreDevice error 4016 because required usage assertions were unavailable. No successful build 8 install or launch is claimed.

Earlier build 8 files remain local historical evidence:

- Signed build log: `/private/tmp/shuttle-build8-device-build.log`
- Failed install result: `/private/tmp/shuttle-build8-install-result.json`
- Signed app: `/private/tmp/shuttle-headset-install/Build/Products/Debug-xros/ShuttleClub.app`
- [Home tracking setup](Preview/Build8-Home-Tracking.png) and [court tracking setup](Preview/Build8-Court-Tracking.png)

This installation uses development provisioning, which is separate from App Store distribution. The embedded build 11 profile expires on **18 October 2026 at 11:24:07 UTC / 19:24:07 Singapore time**. Renew provisioning and rebuild when needed; this is not an App Store release.
