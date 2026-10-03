# Local AR42 testing build — 3 October 2026

Version **0.3.0+3 / rules engine 0.1.2** uses 42-class AR42 with the live camera scanner, editable calculator and local settings/history. The model SHA-256 is `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. This is a local research build: the checkpoint publisher's redistribution grant remains unresolved, and red fives are not distinguished separately. See [the provenance review](VISION_DATA_AUDIT.md#appendix-ar-detector-provenance-and-redistribution-review).

Engine 0.1.2 fixes the adopted Hong Kong direct kong-replacement self-draw exemption from bao liability. Settlement now keeps the three opponents' payments under the chosen self-draw option; the UI explains this beside the bao selector. Regression tests cover the payment modes and distinguish ordinary draws, flower replacements and robbed kongs.

## Current source checks

**206 Flutter tests pass**, including 76 domain tests; whole-app static analysis reports **no issues**. Formatting was checked for both changed Dart files. The tests include independent-oracle scoring/payment boundaries, detector mapping/preprocessing, camera planes/rotation, temporal stability, corrupted storage recovery, widget lifecycle, native runtime cleanup, and real/historical video replay. The current detector covers 34 ordinary tile identities plus eight flowers/seasons. Unknown/low-confidence, invalid multiplicity, wrong count, row geometry, motion, stale frames, interruption and tab/background changes prevent confirmation.

Confirmation still needs every tile confidence at least 0.80 and five consistent observations spanning at least 1.2 seconds. Agreement is a consistency filter, not a correctness guarantee. Winning tile, source, exposed melds, flowers, winds and other game facts still require entry or confirmation. [Rules readiness](RULES_READINESS.md) records unsupported rule variants and exclusions.

## Actual native runtime tests

The following native checks ran on the earlier **0.3.0+3 / engine 0.1.1** source, digest `15837a498eee47dd4f6186f07e49e5d1714bcae1824d9683fa4b45e1009e77cd`. The normal engine 0.1.1 simulator app was also installed and launched during that earlier pass. The final engine 0.1.2 refresh changes settlement and explanatory UI only; the model, camera and inference paths remain unchanged. Native tests were not repeated for this refresh, and no emulator was booted. Current artifact/source hashes and the historical native-test scope are separated in [the manifest](TEST_BUILD_MANIFEST.json).

| Check | iPhone 13 Pro simulator, iOS 17 | Android 15 ARM64 emulator, 16 KB pages |
|---|---|---|
| Licensed real-photo row | All 14 manually labelled identities in order | All 14 identities in order |
| Minimum confidence | 0.882904 | 0.882904 |
| Photo pipeline | 317 ms | 1,364 ms |
| Blank/repeat/dispose/reopen | Passed; blank 171/157 ms | Passed; blank 1,679/917 ms |
| Actual camera stream | No physical camera on simulator | Two YUV420 stream/stop/dispose/reopen cycles passed |

These tests load the actual bundled ONNX model through Dart image decoding/letterboxing, native inference, mapping and suppression. They are stronger than mocked runtime tests, but the single photo is an already inspected development fixture, not a live-phone accuracy benchmark.

Android camera frames were 640×480, with row strides `[640,320,320]` and pixel strides `[1,1,1]`. Actual plane bytes went through copy, crop, orientation and inference; results returned no JPEG preview. With a requested 15 FPS capture rate, the two pipeline observations took 1,937/976 ms. Capture FPS is not inference throughput. All timings were measured on simulated devices while model training was running and must not be presented as physical-phone speed.

## Public-video evidence

An actual [CC BY 3.0 tournament excerpt](../../training/vision/video_candidates/README.md) supplies 239 camera frames and a manually annotated tilted 13-tile row. Two reviewers agreed on the sequence before model inference; 20 sampled frames were checked. AR42 found 13 tiles in 17/20 sampled frames, but the current confidence/count/geometry checks never accepted the row in the actual Dart gate. There were no accepted frames under any supported UI count or the separate diagnostic count of 13. A 13-tile row is not a complete 14/17-tile success case. Red-five identity must also be reported separately from normalized face identity.

Public photos, grouped internal-data diagnostics and training experiments have their own reports. Their source sessions/physical tile sets and overlap with pretrained training data are not fully known. A better development score does not establish universal recognition.

## Build outputs

**All final 0.3.0+3 / engine 0.1.2 builds passed.** The normal app entry point is restored to `lib/main.dart`. Direct `xcodebuild` succeeded against `Runner.xcworkspace`, using the **Runner iPhone Test / Profile** scheme with signing disabled. Every native artifact and the browser build contains the expected AR42 SHA-256; all report version 0.3.0/build 3. [The artifact manifest](TEST_BUILD_MANIFEST.json) records hashes, sizes, source digest and completed build stages.

| Output | Result |
|---|---|
| `build/ios/iphonesimulator/Runner.app` | Normal Debug app rebuilt; 251.7 MB bundle |
| `build/ios/iphoneos/Runner.app` | Unsigned Profile app; 81.9 MB |
| `build/xcode-phone-test/Build/Products/Profile-iphoneos/Runner.app` | Direct workspace unsigned Profile app; 81.9 MB |
| `build/app/outputs/flutter-apk/app-debug.apk` | Normal app, universal development APK; 247.8 MB |
| `app-arm64-v8a-release.apk` in the same directory | Optimized, development-signed test APK; 57.6 MB |
| `app-armeabi-v7a-release.apk` / `app-x86_64-release.apk` | Matching optimized test APKs; 49.7 / 62.9 MB |
| `build/web/` | Release build passed; manual/scoring preview |

APK permissions were checked from the built packages: camera is present; microphone and external-storage permissions are absent. Debug includes internet permission for development tooling; the optimized APKs do not. Native frame-stream tests passed, but a fresh final Android UI screenshot was not taken during this build pass.

The Xcode entry point is `ios/Runner.xcworkspace`. Double-click **Open in Xcode.command**, select **Runner iPhone Test**, choose your iPhone and development team, then Run. This scheme uses Profile without requiring the Flutter debugger. Scripts restore `lib/main.dart` after integration testing and leave the Mac's global Xcode setting alone. [Phone instructions](TEST_ON_PHONE.md) explain testing and signing.

## Scope and history

Targets remain iOS 16+ and Android 7/API24+. Browser builds support manual entry/settings/calculation; the official web camera plugin cannot supply the continuous frame stream used here. No physical phone has been installed or modified and no signing team, TestFlight or public store upload has been selected.

The task-created iOS simulator and Android emulator are shut down. Physical camera geometry, unfamiliar artwork, complete-hand recognition, heat/battery/memory and lower-end Android performance remain unverified. Regional rules/payment coverage is also unfinished.

Historical V2 timings, screenshots, 196-test counts and 0.2.0 build hashes are preserved in [the previous report](history/BUILD_VALIDATION_0.2.0.md) and [manifest](history/TEST_BUILD_MANIFEST_0.2.0.json). They are not current AR42 evidence.

The earlier AR42 native-test run and pre-fix build hashes are preserved separately in [the engine 0.1.1 report](history/BUILD_VALIDATION_0.3.0_engine0.1.1.md) and [manifest](history/TEST_BUILD_MANIFEST_0.3.0_engine0.1.1.json).
