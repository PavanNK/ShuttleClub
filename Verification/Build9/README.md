# Build 9 native verification — 11 October 2026

This evidence comes from the running SwiftUI/RealityKit application in the visionOS simulator. No physical Vision Pro query, installation or launch was performed. Inputs are artificial poses through the same hand-motion, finite string-sweep and impact path; they do not prove physical holding comfort or hand/Sense tracking.

- [Native rally](Native-Rally.mp4): full captured timeline, including startup, a player contact, Milo's actual string-contact return and a second player contact. The process output records four player contacts and one Milo contact, followed by genuine net faults. There is no outgoing shot correction after impact.
- [Deliberate miss](Deliberate-Miss.mp4): the same swing shifted 0.8 m sideways. The process output records zero contacts and four missed-point landings awarded to Milo.
- [Actual string contact](Actual-String-Contact.png): an unaltered simulator screenshot frozen only after an actual player impact. The inspection scene is offset 0.8 m from the camera to show the impact; relative cork/string positions are unchanged.
- [Measurements](Contact-Measurements.json): maximum logged rally cork-to-string gap is 0.040002266 m, within the 0.04 m radius plus numerical tolerance. Raw process output is in `Rally-Output.txt`, `Miss-Output.txt` and `Contact-Output.txt`. Log and recording intervals differ slightly; counts apply to logs, not a frame-by-frame annotation of the clips.

Recordings were exported locally with AVFoundation at 1080p, preserving the full timeline without cuts, overlays or generated frames. [Recording metadata](Recording-Metadata.json) records original/stored hashes, sizes and durations. Container rounding changes duration by less than one frame. Video encoding metadata is not headset frame-rate measurement. The initial serve is an authored launch from Milo's visible strings; player and subsequent Milo returns require real collision.

## Automated checks

All **145 native tests in 16 suites passed in 14.754 seconds**, with zero failures or skipped tests. See [Xcode summary](Native-Test-Summary.json) and [complete output](Native-Test-Output.txt). All **16 shared-physics tests passed**; see [output](Core-Test-Output.txt). The unsigned Vision Pro Release SDK compile also passed. The recorded application is debug build 1.0 (9).

Gameplay regressions check every difficulty at 30/60/90 Hz for actual Milo string contact, net clearance, and a descending return inside a reachable player area (z=-0.25 m, |x|<0.8 m, height 1–2.3 m). Friendly/Club cases continue to a second actual player contact. Alternating frame intervals preserve the synthetic 5.5 m/s swing and reject a deliberate miss. Previous suites cover grabbing/holding/release, tracking recovery, fitted controller poses, duplicate/reordered samples, rotating contacts, fault chronology, automatic feeds and menu guards.

## Work reduction

The native resource tests preserve original buffers, UVs, transforms and parent relationships. The warm 20-racket batch creates **zero additional meshes** with **1,420 cache hits**. Repeated court construction creates **zero additional meshes**, with **612 hits** and **164 retained entries**. The LRU is capped at 256 entries and eviction preserves live entities.

One diagnostic run recorded 1,271.35/1,256.65 ms for cold/warm batches of 20 rackets and 597.76/452.69 ms for mesh-cold/warm court construction. Texture caches were not reset. These are development simulator construction diagnostics, not a controlled benchmark against the previous implementation or a headset FPS claim.

The frame-gate tests submit 1,000 queued callbacks and assert one pending task while retaining all elapsed time. Background producer and cancellation tests verify long interruptions remain visible to the court pause policy and obsolete scenes cannot commit updates. Court, lobby and racket-card previews use this gate. Reattachment avoids duplicated preview meshes and studio lights.

## Reproduce

Run Xcode's Test action on the ShuttleClub scheme, then `swift test` inside `Core`. For release compilation use `xcodebuild -project ShuttleClub.xcodeproj -scheme ShuttleClub -configuration Release -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build`.

With the debug build installed on a simulator, select Hands, then launch `com.shuttleclub.vision` with `--preview-court --demo`. Add `--demo-miss` for the missed swing or `--pause-at-contact` for the frozen inspection. The debug label remains visible; these are not release play modes. `Verification/measure_contacts.py` reproduces the contact measurements from the committed logs.

[Source hashes](Source-Manifest.json) identify the app/core/tests/resources and project files used for this verification. Physical tracking, controller pairing/haptics, grip comfort, audio, headset frame rate and thermal behaviour remain unverified. Visuals remain a recreation with visible differences from the reference, and physics parameters are provisional.
