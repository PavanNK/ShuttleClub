# Build 10 hand interaction and startup fixes — 12 October 2026

All **173 native tests in 17 suites passed in 16.035 seconds**, with no failures or skipped tests. The unsigned Vision Pro Release SDK compile passed. See [Xcode summary](Native-Test-Summary.json), [complete native test output](Native-Test-Output.txt), and [release build output](Release-Build-Output.txt).

No physical Vision Pro query, installation or launch was performed. The user's device-access restriction remains in effect. These are software checks using artificial measured joint/pose inputs, not proof of physical tracking recognition, comfort, latency or controller pairing. The current build is 1.0 (10); it is unsigned and not installed.

## Confirmed blockers corrected

Tracking setup opened through CourtMenu previously left `showCourtMenu` set after Done, so automatic serving stayed blocked. Back to court now closes all nested court panels and resets the ready countdown. An interrupted rally stays paused and requires a tracked Resume. An idle player can leave the menu while waiting for tracking.

The open-palm mount previously expired after 0.35 seconds. A gradual closure could therefore lose acquisition before its 0.10-second closed dwell completed, despite fresh wrist data. The wrist-local mount now persists through continuous valid closing and is discarded after actual unheld tracking loss, reordered input, backgrounding, or hand/provider changes. The regression keeps the hand in the intermediate band for 0.6 seconds before completing the grab.

Initial palm construction now supports middle plus one measured side knuckle, while preserving the original full-palm basis when all three are available. Partial data cannot overwrite a cached complete-palm angle. The native adapter uses the tracked hand anchor at the wrist and retains an already acquired mount when finger joints are occluded.

When fewer than two fingertip pairs are tracked, acquisition can use two measured first finger segments to recognize bending. Release remains separate: it requires at least three observed fingertip pairs, each fully open, for the sustained release dwell. Partial/mixed fingers and menu pinching cannot release the racket. Missing finger evidence now asks for a new opening gesture instead of incorrectly promising that closing alone can grab.

Hand angle controls save front/back tilt, side tilt and face turn separately for each hand. They preserve the palm handle position, discard collision motion history when adjusted, and migrate previous quaternion-only saved fits. Invalid edits cannot overwrite a saved fit. Alignment instructions and saved-fit acknowledgement are visible in setup.

## Relevant passing regressions

- `gradualClosureSurvivesMoreThanTheOldPalmCacheLifetime`
- `nestedTrackingSetupClosesAllPanelsAndAutomaticallyLaunchesAfterARealGrab`: feeds the actual grab handler, leaves nested setup, checks the full readiness countdown and windup, and verifies shuttle launch without calling a serve button. The inputs are synthetic; “RealGrab” in the test name refers to the gesture path.
- `closingSetupCannotStartWithNoGripOrResumeAnInterruptedRally`
- `unheldWristLossDiscardsTheOldPalmBeforeReacquisition`
- `trackedFingerBasesCanFinishAcquisitionWhileTipsAreOccluded`
- `fingerDataLossRequestsANewOpenInsteadOfPromisingAClosedGrab`
- `partialOpenFingersAndMenuPinchingCannotReleaseTheHeldRacket`
- `fineAngleFitIsAppliedToTheHeldRacketAndCannotInventSwingMotion`

Additional gesture, palm, fit, physics/contact, serving, controller, frame-gate and resource regressions also passed. Recovery fixtures preserve timestamp ordering and wait for the clock to advance before replaying fresh acquisition history.

Native setup screenshots show [default setup](Hand-Tracking-Setup.png) and [expanded angle controls](Hand-Angle-Setup.png). They are unaltered simulator pixels. Hardware hand tracking is unavailable there, so fitting controls are disabled and the waiting status is intentional. Layout, text and control visibility were inspected; the expanded panel fits the native viewport. The debug `--preview-hand-angles` flag opens the disclosure for layout review only.

[Source hashes](Source-Manifest.json) identify the verified app/core/tests/resources/project files. Historical build 9 rally recordings use the prior source and do not validate build 10 physical hand input. Physical recognition thresholds, holding comfort, fast real swings, headset performance and audio remain pending device verification. No external asset-generation service was used.
