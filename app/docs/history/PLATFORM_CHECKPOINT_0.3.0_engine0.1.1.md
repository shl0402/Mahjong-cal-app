# Platform checkpoint — 3 October 2026 (Hong Kong)

Current source is **0.3.0+3**, using AR42 model SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. The old 0.2.0 documents and artifact manifest are preserved under `docs/history/`; their binaries may be overwritten by the current rebuild.

## Completed

- Full Flutter suite: 201 passed (reported by the source/test owner); whole-app analysis: no issues, `/tmp/mahjong-ar42-analysis.log`.
- Actual iPhone 13 Pro / iOS 17 simulator: native real-photo test identified all 14 expected identities in order (317 ms; minimum confidence 0.882904), and blank/repeated/dispose/reopen smoke passed (171/157 ms).
- Actual Android 15 ARM64 emulator with 16 KB pages: same native 14-tile fixture passed (1,364 ms; same minimum confidence), plus blank/repeated/dispose/reopen smoke (1,679/917 ms).
- Android live virtual-camera test: two 640×480 YUV420 plane-copy/crop/rotation/model/stop/dispose/reopen cycles passed, row strides 640/320/320, pixel strides 1/1/1, no encoded JPEG (1,937/976 ms).
- Normal simulator application rebuilt from `lib/main.dart`, installed and launched successfully. A new screenshot was not captured: the intended output directory was absent. No current screenshot is claimed.

These timings were measured during concurrent training and are not phone benchmarks. The photo is one development fixture, not live-camera accuracy evidence.

## Final packages completed

All cached builds completed sequentially during an agreed GPU-training pause, with no simulators running. Training was notified to resume afterward.

- Normal Android debug APK: 247,836,506 bytes; replaces the integration-test harness.
- Optimized development-signed APKs: ARM64 57,612,175 bytes, ARMv7 49,697,283 bytes, x86-64 62,920,583 bytes.
- Physical-device unsigned Profile app: 81,945,645-byte bundle.
- Direct `Runner.xcworkspace` / `Runner iPhone Test` / Profile `xcodebuild`: **BUILD SUCCEEDED**, unsigned 81,945,297-byte bundle.
- Normal iOS simulator app: 251,717,352-byte Debug bundle.
- Web release build: passed; manual entry/settings/calculation, no continuous browser camera stream.

Every native output and web build reports version **0.3.0/build 3**, with the exact AR42 model hash. APK permissions contain camera and omit microphone/storage. `Generated.xcconfig` ends with `FLUTTER_TARGET=lib/main.dart`, `FLUTTER_BUILD_NAME=0.3.0`, and `FLUTTER_BUILD_NUMBER=3`. The final source digest and artifact hashes are in `TEST_BUILD_MANIFEST.json`.

Remaining user-device work: choose a signing team in Xcode and test physical camera geometry, accuracy, unfamiliar tile sets, heat/battery/memory and response. Public release/model rights and broader rules coverage remain unresolved.

## Cleanup

- iPhone simulator `2D55114D-7797-4E4A-97AF-8963BED88DF8` was initially stopped, started only for this task, and shut down before Android.
- Headless `Medium_Phone` / `emulator-5554` was initially absent, started only for this task, and stopped with `adb emu kill` immediately after tests. `adb devices` is empty.
- No emulator, simulator, Xcode build, or Flutter build remains running from this phase. The pre-existing older Gradle daemon was left alone.
- No physical phone, signing team, App Store, or TestFlight installation/upload was changed.

Logs: `/tmp/mahjong-030-ios-native.log`, `/tmp/mahjong-030-ios-simulator.log`, `/tmp/mahjong-030-android-native.log`, `/tmp/mahjong-030-android-camera.log`.

Final build logs: `/tmp/mahjong-030-android-debug.log`, `/tmp/mahjong-030-android-release.log`, `/tmp/mahjong-030-ios-profile.log`, `/tmp/mahjong-030-xcode-profile.log`, `/tmp/mahjong-030-web.log`. Serial build results are recorded in the permanent artifact manifest.
