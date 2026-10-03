# Live camera testing build — 2026-10-02

Version 0.2.0+2 is a local iOS/Android testing build with a live scanner, editable hand calculator, local settings and history. It is not a complete universal mahjong release. The current rules engine is 0.1.1; the selected experimental detector is YOLO11n V2, SHA-256 `2b1adbdb6f395eba7ce755f87672c8a4275d6eeae68d26c5206ae6a89f4e628a`.

## What changed

The photo-picker workflow was replaced with continuous rear-camera frames. The app decodes BGRA/YUV planes, corrects orientation, crops the displayed guide and runs one on-device inference at a time. It requests no microphone or photo-library permission. Frames are neither recorded nor uploaded. The browser remains available for manual entry and calculation; the official web camera plugin does not support the required frame stream.

Confirmation requires the selected tile count, every confidence at least 0.80, valid tile multiplicities, a single row, and five consistent observations spanning at least 1.2 seconds. Position and size must remain near both the previous observation and the first observation in the run. Unknown classes, stale observations, rotation, leaving the tab and backgrounding cancel acceptance. Confirmation opens the hand editor, where winning tile, source, melds, flowers and other game facts must still be supplied. A persistent high-confidence mistake can pass temporal consistency, so this is not a correctness guarantee.

Camera teardown explicitly stops its stream before disposing the controller. Permission denial, interruption, pending initialization, concurrent frame arrival, native runtime cleanup errors and repeated reopening have regression coverage. Preview/frame aspect mismatches are rejected rather than displaying a guide for a different crop. Physical CameraX field of view and YUV color range still require hardware checks.

## Automated evidence

**All 196 Flutter tests pass**, and `scripts/flutter.sh analyze` reports no issues. Five separate Python evaluator tests also pass. Test scope includes:

- 71 domain tests with 6,000 independent-oracle structural cases, 1,000 score metamorphic cases, 9,600 payment combinations, custom thresholds and explicit rule counterexamples.
- 18 detector decoding/preprocessing tests, including all 38 V2 classes and 100 seeded repeated-tile rows.
- 38 camera-plane/stability tests, including 200 seeded temporal sequences; frame rotation, strides, crop alignment, malformed buffers, confidence/timing boundaries and cumulative motion.
- 32 persistence tests for immutable snapshots, corruption recovery, backup preservation and rule/result round trips.
- 12 original application widget tests for scoring, settings persistence, saved history, undo and phone/tablet layouts.
- 12 live camera widget tests for permission recovery, five-frame confirmation, low confidence/UNKNOWN, expiry, in-flight backpressure, late initialization, rotation, backgrounding, camera interruptions and geometry mismatch.
- 12 native runtime lifecycle tests using the real ONNX session/value wrappers with controlled platform failures and delayed shutdown.
- One replay test feeds 550 actual public-video timestamps through the real Dart gate for all six expected-count policies. None confirms. This documentary is rejection diagnostics, not a successful hand-scanning demonstration.

The combined Flutter run executes 499/501 scoring lines, 71/71 tile lines, 58/58 camera-frame lines, 97/97 consensus lines and 101/105 detector lines. These are line-execution measures, not proof of complete branches, camera accuracy or rule completeness.

The scoring audit fixed ambiguous winning-tile allocation under custom Taiwanese values, impossible consecutive open-kong chains, structurally impossible HK responsibility, and a heavenly win completed by initial flower replacement. See [rules readiness](RULES_READINESS.md) for exclusions; high test coverage does not establish all regional rules.

## Native and public-data evidence

V2 passed real ONNX loading, repeated inference, disposal and reopening on an iPhone 13 Pro simulator running iOS 17.0. Observed end-to-end pipeline times were about 258 ms cold and 106 ms warm. These are simulator measurements, not physical iPhone measurements.

The Android 15 ARM64 emulator with 16,384-byte memory pages passed the live camera integration test at a requested 15 fps: two actual virtual-camera YUV420 stream → plane-copy → crop/rotation → model → stop/dispose/reopen cycles. Frame size was 640×480, row strides `[640, 320, 320]`, pixel strides `[1, 1, 1]`, and live inference returned no encoded JPEG preview. V2 took about 902 ms cold and 723 ms on reuse in this run. Emulator timings vary substantially with workload; do not compare them with physical-phone speed or infer a camera-frame processing rate from the requested capture fps.

Seven licensed public photographs supplied ten fixed annotated regions with 138 tile faces. V2 matched 117, with eight false positives and 21 misses, and got only 2/7 complete 14-tile regions entirely correct. The 550-frame video uses a fixed 3.2:1 central crop. No evaluated photo or video frame met the confidence/count prerequisites for a live lock. Export parity passed on all ten photo regions. Five evaluator matching/boundary tests also pass. See [the complete online evaluation](ONLINE_VISION_EVALUATION.md) for provenance, correlations, unknown training overlap, source licenses and failure overlays.

## Build outputs and Xcode handoff

Double-click **Open in Xcode.command** in the project folder, or use [the phone guide](TEST_ON_PHONE.md) and `scripts/open-xcode.sh phone`. The project opens `app/ios/Runner.xcworkspace`. Select **Runner iPhone Test**, your iPhone and your development team, then Run. The scheme uses Profile without attaching the Flutter debugger. The ordinary Runner scheme remains for simulator/Debug work. Scripts restore `lib/main.dart` after integration tests and do not change the Mac's global Xcode selection.

The final source passed direct **xcodebuild against Runner.xcworkspace**, using the **Runner iPhone Test / Profile** scheme with signing disabled. Flutter's simulator and physical-device Profile builds also passed. All four Android APKs were produced. The release browser build also passed after resuming. Native artifact versions and bundled model hashes were checked; see [the build manifest](TEST_BUILD_MANIFEST.json).

The iOS home and Android live-camera screenshots were reviewed. The Android emulator displayed the guide, zero tile count and disabled confirmation on its virtual scene with no visible geometry error. Those screenshots establish visible rendering for those test devices, not accuracy or all-device alignment.

Verified native output locations:

- `app/build/ios/iphonesimulator/Runner.app`
- `app/build/ios/iphoneos/Runner.app` — unsigned Profile executable
- `app/build/xcode-phone-test/Build/Products/Profile-iphoneos/Runner.app` — direct Xcode workspace build, unsigned
- `app/build/app/outputs/flutter-apk/app-debug.apk`
- `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk` — optimized, development-signed testing APKs
- `app/build/web/` — final release browser build passed; manual entry/scoring preview

Targets are iOS 16+ and Android 7/API 24+. Compilation for an OS/CPU does not establish acceptable performance on every phone. No physical phone has been installed or modified, and no App Store/TestFlight upload has been made.

## Remaining validation

Physical iPhone/Android camera geometry, unfamiliar tile styles, exact-hand recognition, battery/heat/memory, permission changes in system settings, low-end Android performance, independently reviewed additional rule packs, and a production distribution/model licensing decision remain open. The rules and payment catalogue is not finished; vision is not the only remaining work.
