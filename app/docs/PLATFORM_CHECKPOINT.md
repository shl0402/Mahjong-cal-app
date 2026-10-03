# Platform checkpoint — 3 October 2026 (Hong Kong)

Final handoff: **app 0.3.0+3 / rules engine 0.1.2**, with AR42 model SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. All requested platform outputs have been refreshed after the Hong Kong direct kong-replacement liability correction and its explanatory UI text.

## Current source verification

- The parent reran all **206 Flutter tests** after the final UI text; all passed. Domain tests: 76 passed.
- Both changed Dart files were formatted/checked; only `main.dart` needed whitespace formatting. Whole-app analysis then passed with no issues in 3.5 seconds.
- Final source SHA-256: `017a497674d1c2d01c7f5ac26e96546c0a4813e4714952069e42395db44bc475`.
- Digest method: sorted repository-relative `app/lib/**.dart` paths, including the `app/lib/` prefix, then NUL, file bytes, NUL.

## Current outputs

All six build stages passed sequentially after GPU training released memory. No emulator was started for this refresh.

- Normal iOS simulator Debug app **rebuilt only**: 251,679,802-byte bundle.
- Physical-device unsigned Profile app: 81,945,645-byte bundle.
- Direct `Runner.xcworkspace` / `Runner iPhone Test` / Profile `xcodebuild`: **BUILD SUCCEEDED**, unsigned 81,944,989-byte bundle.
- Normal Android debug APK: 247,839,155 bytes.
- Optimized development-signed APKs: ARM64 57,612,175 bytes, ARMv7 49,697,283 bytes, x86-64 62,920,583 bytes.
- Web release: passed; manual entry/settings/calculation, without continuous browser camera scanning.

All native outputs and web metadata report **0.3.0/build 3**, contain the expected AR42 model, and were rebuilt from engine 0.1.2 source. APK permissions include camera and omit microphone/external storage. Profile AOT binaries, all APK hashes and web JavaScript differ from the pre-fix outputs; complete hashes and build logs are recorded in `TEST_BUILD_MANIFEST.json`.

`Generated.xcconfig` is restored to `FLUTTER_TARGET=lib/main.dart`, with `FLUTTER_BUILD_NAME=0.3.0` and `FLUTTER_BUILD_NUMBER=3`. No signing team or physical phone was modified.

## Earlier native scanner evidence

The actual native tests below ran on **0.3.0+3 / engine 0.1.1**, source SHA-256 `15837a498eee47dd4f6186f07e49e5d1714bcae1824d9683fa4b45e1009e77cd`. They were not rerun for the final settlement/UI correction because the AR model, camera and inference paths are unchanged.

- iPhone 13 Pro / iOS 17 simulator: all 14 photo identities in order (317 ms; minimum confidence 0.882904), plus blank/repeat/dispose/reopen (171/157 ms).
- Android 15 ARM64 emulator with 16 KB pages: the same 14 identities (1,364 ms; same confidence), plus blank/repeat/dispose/reopen (1,679/917 ms).
- Android live camera: two 640×480 YUV420 stream/stop/dispose/reopen cycles, row strides 640/320/320, pixel strides 1/1/1, no JPEG (1,937/976 ms).
- The earlier normal engine 0.1.1 simulator app was installed and launched. Current engine 0.1.2 simulator output was compiled without installation or launch.

These are simulated-device measurements under concurrent training load and one development photograph, not physical-phone speed or general accuracy results. Native logs remain `/tmp/mahjong-030-ios-native.log`, `/tmp/mahjong-030-android-native.log`, and `/tmp/mahjong-030-android-camera.log`.

## Cleanup and remaining work

`adb devices` and the booted iOS simulator list are empty. No build or emulator remains running from this task. The model-evaluation agent was notified that compilation finished before its inference timing run. No user app, physical device, signing team, App Store or TestFlight state was changed.

Physical signing, camera geometry, complete-hand accuracy, unfamiliar tile sets, heat/battery/memory and phone response remain user-device checks. Public model redistribution rights and broader rules coverage remain unresolved.

Current analysis/build logs use `/tmp/mahjong-030-engine012-*.log`; the permanent artifact manifest records all six completed stages. Earlier 0.2.0 and 0.3.0/engine 0.1.1 documents/manifests are preserved under `docs/history/` and do not describe current binaries.
