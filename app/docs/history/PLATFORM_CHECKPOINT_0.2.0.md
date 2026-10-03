# Platform handoff — 2 October 2026

The battery pause has ended. Final-source direct Xcode workspace verification **passed** after resuming. The newest iOS home and Android live-camera screenshots have now been visually reviewed: Android shows an active virtual-camera preview, guide, 0/14 tiles and disabled confirmation, with no visible geometry error.

All native builds below remain saved. No emulator needed to be restarted for the final checks. `FLUTTER_TARGET` remains `lib/main.dart`. See `BUILD_VALIDATION.md`, `TEST_BUILD_MANIFEST.json` and `TEST_ON_PHONE.md` for the current handoff.

## Historical battery-pause checkpoint

## Completed on final frozen source

- Android universal debug APK built: `app/build/app/outputs/flutter-apk/app-debug.apk`.
- Optimized Android test APKs built: ARM64 56.2 MB, ARMv7 48.3 MB, x86-64 61.5 MB. These use the development signing key.
- Android optional-camera manifest override verified; camera permission present, no microphone or storage permission. ARM64 APK version is 0.2.0 / 2.
- iPhone simulator normal app built, installed and launched: `app/build/ios/iphonesimulator/Runner.app`.
- Physical-device Profile app built successfully, unsigned: `app/build/ios/iphoneos/Runner.app` (80.2 MB). No real phone was modified.
- Final detector native smoke test passed on iPhone 13 Pro simulator: real v2 ONNX loading, repeat inference (258 ms first / 106 ms warm), disposal and reopening.
- Earlier v2 Android live stream integration passed two camera start/stop/dispose/reopen cycles with real emulator YUV420 buffers (902 ms first / 723 ms reused).
- Fresh screenshots saved: `docs/screenshots/android-live-home.png`, `ios-live-home.png`, and `android-camera-live.png`. The last two captures have not yet been visually reviewed. Camera permission was granted before the latest Android camera capture.
- Added executable `Open in Xcode.command` Finder launcher. `scripts/open-xcode.sh phone` prepares the Profile scheme without signing or installing.
- `app/ios/Flutter/Generated.xcconfig` was checked immediately before pausing and targets **lib/main.dart**.

## Remaining after “continue”

- Rerun `scripts/verify-xcode.sh` against the final source. The actual workspace Profile build passed before the last camera lifecycle/detector cleanup; the final Flutter Profile build passed afterward.
- Visually inspect the two latest native screenshots, and confirm the Android live preview displays its guide without an aspect-mismatch error. This last UI check was interrupted by the battery pause.
- Update the phone guide's iOS smoke timings from its earlier 325/148 ms to final 258/106 ms and mention the Finder launcher.
- Physical iPhone camera accuracy, heat, battery, memory and signing remain user-device checks.

## Background cleanup

- Stopped only our headless Android emulator `emulator-5554` / `Medium_Phone`; adb confirmed shutdown.
- The Profile build completed successfully before cancellation was needed. No build was left running by this agent.
- The already-running iPhone simulator was left for the parent to close if it was task-created; this agent did not boot it during the final build pass. No physical devices were touched.

Build logs are in `/tmp/mahjong-final-ios-profile.log`, `/tmp/mahjong-final-ios-simulator.log`, `/tmp/mahjong-final-ios-inference.log`, `/tmp/mahjong-final-android-debug.log`, and `/tmp/mahjong-final-android-release.log`.
