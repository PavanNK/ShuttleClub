# Build 11 controller fit, movement and Milo — 12 October 2026

All **209 native tests in 22 suites passed in 28.430 seconds**, with zero failures or skipped tests. The final unsigned Vision Pro Release compile passed, with version **1.0 (11)** and bundle identifier `com.shuttleclub.vision`. See the [Xcode summary](Native-Test-Summary.json), [complete test output](Native-Test-Output.txt), and [Release output](Release-Build-Output.txt).

No physical Vision Pro query, signing, installation or launch occurred. This build is not installed. These checks use simulator rendering and artificial measured inputs; they do not establish physical holding comfort, controller recognition, haptics, movement comfort, latency or headset performance. No external asset-generation service was used. The shared physics source is unchanged from its last direct 16-test pass in build 9.

## Corrected behavior

Sense fitting now captures a comfortable playing hold after three steady seconds, instead of capturing a controller pointing at a menu. Both shaft and string orientation are solved in the court frame, independently for each hand. Motion restarts the stable window; loss/background/input changes cancel it, and serves wait for capture to finish. A new default attachment is fitted before its first automatic serve. Existing chosen fits are retained. Fine face turns rotate around the tilted shaft; legacy saved rotation order migrates without changing the complete mounted pose. Refit and invalid edits cannot create a swing or replace a valid fit with invalid data.

Thumbstick slide reads the free Sense controller, with a sole-controller fallback. Hands default to Auto glide; Stay centred keeps the virtual position fixed and feeds toward the current spot. Movement has a radial dead zone, bounded acceleration, a 1.25 m/s diagonal speed cap, and player-half boundaries. Loss, pauses, panels and inactive scenes stop movement. The room tracking origin stays physical while the court slides; controls remain in front of the player. Measured world-space motion supplies impact velocity, so sliding the court adds no artificial swing energy. A repeated fresh controller packet remaps its last accepted physical pose without changing or rearming it. Auto glide uses a stable ready-racket offset, preventing the same comfortable hand offset from accumulating sideways movement on each feed.

Milo has an original floating chassis, thrust light and arms, with no legs or shoes. Hover/bank animation preserves the physical shoulder/racket chain and supports reduced motion. Footstep playback is removed. Preparation and recovery ease toward bounded poses; world-facing strings remain aimed as the parent arm swings. Incoming shots toward Milo advance his actual movement, shuttle flight and swept string contact in intervals no larger than 1/240 second. This corrects coarse-frame contact-velocity errors without changing a returned shuttle's velocity afterward. Reachable weak shots and high lobs pass the return-area and net-clearance checks at 30, 60 and 90 Hz. Unreachable or missed strings do not cause a return.

Confirmed contacts show a pooled 0.15-second ring/spark effect. Feather orientation settles briefly into the new flight direction while the physical cork position and trajectory remain exact to the solver. There is no automatic player return.

## Native visual evidence

- [Floating Milo and court](Floating-Milo-Court.png)
- [Expanded movement setup](Movement-Setup.png)
- [Sense shaft/face fitting](Sense-Angle-Setup.png)
- [Frozen actual cork/string contact](Actual-String-Contact.png)
- [Native rally](Native-Rally.mp4)
- [Deliberate miss](Deliberate-Miss.mp4)

The four screenshots are unaltered 3840×2160 simulator pixels. The movement and Sense panels fit the viewport; their text, selected states and visible controls were inspected. The simulator cannot provide tracked hands or controllers, so disabled fitting controls and waiting status are intentional. The court shows the floating character. The frozen contact preview moves only the inspection scene 0.8 m back from the camera to keep the cork and racket visible; their relative geometry is unchanged.

The videos are complete simulator recordings exported at 1280×720 with the native media framework. No deliberate cuts, compositing or retiming were applied. Exported durations are **41.805 seconds** for the rally and **42.735 seconds** for the miss; [actual recording metadata](Recording-Metadata.json) records their dimensions and nominal encoded cadence. This cadence is not a headset performance measurement. Frames at 2, 6, 12 and 20 seconds were inspected before and after export. The rally shows repeated player/Milo string contacts and legitimate net faults; the deliberate miss shows Rally/Best remaining zero while Milo receives points.

## Contact telemetry scope

[Measured contacts](Contact-Measurements.json) are extracted by the existing `Verification/measure_contacts.py`, which does not generate or alter gameplay. [Rally output](Rally-Output.txt) contains 19 player and 10 Milo contacts; it is a buffered partial process trace whose interval differs from the recording. Every recorded cork/string distance is at most **0.040004848 m**, within the 0.04 m cork radius plus the solver's 6 µm tolerance.

[Frozen-contact output](Contact-Output.txt) uses a separate repeat of the same final source and contact-preview flags, with a line-buffered console. Its measured distance is **0.040002284 m**. [Miss output](Miss-Output.txt) is a separate line-buffered repeat of the same deliberate-miss fixture, and shows missed-rally faults with zero player or Milo string contacts. These process traces must not be treated as exact frame-by-frame annotations of the videos.

The debug launches use `--preview-court --demo`, add `--demo-miss` for the miss or `--pause-at-contact` for the frozen contact, and explicitly select Hand tracking. `--preview-court --preview-court-tracking --preview-court-movement` opens the movement panel. `--preview-sense-fit` opens the actual Sense fitting panel. These inspection flags are absent from Release behavior; they are not selectable gameplay input modes.

[Source hashes](Source-Manifest.json) identify the verified app, core, tests, resources and project configuration. Physical validation remains listed in `HardwareValidation.md`.
