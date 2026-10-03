# Test the live camera app in Xcode

牌照 / Mahjong Vision is one Flutter project with native iOS and Android apps. Xcode builds its native iPhone application even though the shared UI, recognition pipeline, and scoring engine are written in Dart. The scanner uses a continuous camera feed; it does not ask you to take or import a photo.

The current local testing version is **0.3.0+3**, with the experimental 42-class AR detector (`63b683c7…`). It distinguishes standard tiles, flowers and seasons, but does not identify red fives separately. This build does not provide red-five-specific scoring. The pretrained checkpoint's public redistribution rights are unresolved, so these are local research builds, not a cleared public release. See [the model provenance review](VISION_DATA_AUDIT.md#appendix-ar-detector-provenance-and-redistribution-review).

## iPhone 13 Pro: prepare, open, run

1. Connect your iPhone to this Mac and trust the computer. Enable **Developer Mode** if iOS requests it.
2. In Finder, double-click **Open in Xcode.command** in this project folder. Alternatively, run:

   ```sh
   ./scripts/open-xcode.sh phone
   ```

   This prepares the dependencies, resets the application entry point to `lib/main.dart`, and opens `app/ios/Runner.xcworkspace` in Xcode. It does not sign or install the app and does not change the Mac's global Xcode selection.
3. In Xcode's top bar, select the **Runner iPhone Test** scheme and your physical iPhone. Under the **Runner** target → **Signing & Capabilities**, select your own development team. If Xcode requests it, choose a unique bundle identifier.
4. Press **Run**. Allow camera access when you choose **開啟相機掃描** in the app. Microphone and photo-library access are not needed.

The **Runner iPhone Test** scheme uses an optimized **Profile** build. This is the right configuration for assessing camera response and heat; it also avoids requiring the Flutter debugger for every launch. The normal **Runner** scheme remains available for Debug development and simulators. Signing still controls installation and how long a personally signed app remains usable.

A free personal Apple development account can be used for local testing with Apple's signing limits. Sharing through TestFlight requires the appropriate Apple Developer Program setup. No App Store or TestFlight upload is performed by these scripts.

If you previously ran an integration test and Xcode launches a test harness, run `open-xcode.sh phone` again. It restores the normal application target before opening the workspace.

## Try a real hand

1. Choose the rules preset and the number of concealed tiles inside the guide. Include the winning tile. Use 14 for a complete ordinary Hong Kong concealed hand or 17 for a complete Taiwanese concealed hand; reduce the count when there are declared melds.
2. Tap **開啟相機掃描**. Point the rear camera at one row of face-up tiles, with the whole row inside the guide. Keep exposed melds and flowers outside it; add those separately afterward.
3. Hold the phone steady and check the tile identities shown. The app compares several observations and enables **確認這排牌，前往計算** only after the count and recognition agree. Agreement is a consistency check, not a guarantee of correctness.
4. Confirm the row, correct any tile errors in the hand editor, and supply the game facts: self-draw/discard, dealer, winds, and any relevant special circumstances. Camera images cannot establish these facts.
5. Use **暫停相機** to stop scanning. Manual entry stays available when lighting, tile styles, or device performance prevent a reliable reading.

Frames are processed locally. The live path does not save photos or videos, encode JPEG previews, request microphone access, or upload the camera feed. Camera resources are stopped when leaving the scanner or backgrounding the app.

## Compatibility and simulators

| Platform | Current target | What to test |
|---|---|---|
| iPhone / iPad | iOS 16 or newer | iPhone 13 Pro is a supported target; real camera accuracy and thermal behaviour still need measurement. |
| Android | Android 7 / API 24 or newer | ARM64, ARMv7 and x86-64 builds; actual speed and camera behaviour vary. |
| Browser | Modern browser | Hand entry, settings, and scoring preview. Live frame scanning is disabled because the official browser camera plugin has no frame-stream support. |

These are build targets, not a claim that every device has passed camera, memory, heat, and accuracy testing.

For simulator UI and scoring tests:

```sh
./scripts/open-xcode.sh simulator
```

Select the **Runner** scheme and an iPhone simulator. The simulator has no physical rear camera; use the sample hand or manual entry. An Android emulator can provide a simulated camera scene, which tests the camera pipeline but cannot measure accuracy on real mahjong tiles.

## Android Studio and APKs

Open `app` in Android Studio with its Flutter and Dart plugins installed, start an emulator or connect a phone with USB debugging, and run `lib/main.dart`. The native Android Gradle module is `app/android`.

```sh
./scripts/flutter.sh devices
./scripts/run.sh --profile -d DEVICE_ID
./scripts/build.sh android
./scripts/build.sh android-test-release
```

- `app/build/app/outputs/flutter-apk/app-debug.apk`: universal debugging build, relatively large.
- `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`: smaller optimized test build for most recent Android phones.
- `app-armeabi-v7a-release.apk` and `app-x86_64-release.apk`: matching older ARM phones and x86-64 devices/emulators.

Transfer the matching APK to the phone and allow installation from that source. All these APKs use the development signing key; the optimized filenames do not indicate a production release. Test builds share the pubspec version code across CPU variants so switching build types does not normally require deleting local history. Production distribution needs a release key and a deliberate choice of model licensing.

## Build and verification commands

The local SDK is `.tools/flutter` (Flutter 3.47.6 / Dart 3.13.5). Helpers can use a Flutter installation on PATH on another computer. They select Xcode and Android Studio Java only for the invoked process.

```sh
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/build.sh ios-simulator
./scripts/build.sh ios-device
./scripts/verify-xcode.sh
./scripts/build.sh web
```

`verify-xcode.sh` invokes **xcodebuild against Runner.xcworkspace**, using the same **Runner iPhone Test** Profile configuration as Xcode Run, with signing explicitly disabled. It validates compilation without choosing a team or modifying a phone.

Outputs:

- Flutter simulator build: `app/build/ios/iphonesimulator/Runner.app`.
- Flutter physical-device Profile build: `app/build/ios/iphoneos/Runner.app` — unsigned; sign through Xcode before installation.
- Direct Xcode workspace build: `app/build/xcode-phone-test/Build/Products/Profile-iphoneos/Runner.app` — also unsigned.
- Browser preview: `app/build/web/`; serve over HTTP/HTTPS rather than double-clicking `index.html`. `./scripts/run.sh` starts a local preview on port 8080.

The temporary `path_provider_foundation: 2.5.1` pin avoids an upstream Objective-C build hook that drops `DEVELOPER_DIR` when the Mac globally selects Command Line Tools. It uses the supported Swift package implementation and avoids altering global settings. Revisit the pin after the hook is corrected.

## Real-phone check list

Try 10–20 known hands under daylight and warm indoor light, straight-on and slightly angled, with mild glare, repeated tiles, honors, and more than one tile set if possible. Include 14-tile and 17-tile cases plus smaller concealed rows with declared melds. Record the exact expected tiles and whether the **entire row** is correct. Per-tile accuracy alone can hide frequent full-hand errors.

Also check permission denial and retry, rotating the phone, moving or replacing a tile after a stable reading, covering a tile, incorrect expected counts, pausing and resuming, switching tabs, backgrounding, repeated confirmations, and airplane mode. Compare first-run and warmed-up response, and run for several minutes to assess heat. Use the Profile scheme on iPhone for these measurements.

## What has actually been verified

- Version 0.3.0's AR42 model correctly identified all **14 manually annotated tiles in a real licensed photograph**, in order, on both the iPhone 13 Pro simulator (iOS 17.0) and Android 15 ARM64 emulator. This exercised actual Dart image decoding/preprocessing, native ONNX inference, class mapping, and suppression. It is one development fixture, not live-camera or independent accuracy evidence.
- Both platforms passed blank-image, repeated inference, model disposal and reopening tests. Photo pipeline times were 317 ms on iOS and 1,364 ms on Android; blank reuse was 157 ms and 917 ms respectively. These are simulator/emulator measurements under concurrent model-training load, **not physical-phone benchmarks**.
- The current AR42 Android camera integration passed two **640 × 480 YUV420** start/stream/stop/dispose/reopen cycles on a **16,384-byte memory-page** emulator. Row strides were `[640, 320, 320]`, pixel strides `[1, 1, 1]`; the live path returned no encoded JPEG. Requested capture rate was 15 FPS; observed pipeline times were 1,937 ms and 976 ms. Requested camera FPS is not inference throughput.
- A separate real tournament video has a manually verified **13-tile** row. Its timestamped detections never passed the actual Dart confirmation gate. It is not a complete-hand success example, and red-five identity is normalized by this model. See [the video reference](../vision/video_candidates/README.md).
- The native permission configuration requests camera access without microphone or photo-library access. Physical camera alignment is still unverified.
- Previous 0.2.0 UI screenshots and V2 model timings are historical evidence, preserved in [the earlier phone guide](history/TEST_ON_PHONE_0.2.0.md); they are not current model accuracy evidence.
- Physical iPhone and Android camera accuracy, battery/heat, memory pressure, and unfamiliar tile sets remain unverified.

Native tests can be run on a chosen test device with:

```sh
./scripts/flutter.sh test integration_test/camera_stream_test.dart -d DEVICE_ID
./scripts/flutter.sh test integration_test/native_inference_test.dart -d DEVICE_ID
./scripts/open-xcode.sh phone --prepare-only
```

The camera test needs camera permission; it skips on devices without an available camera. On Android, the automated run used only the emulator's virtual scene, not this Mac's camera. The final command restores the normal Xcode application entry point after testing.

Sources: [official Flutter camera plugin](https://pub.dev/packages/camera), [CameraX implementation](https://pub.dev/packages/camera_android_camerax), [browser camera limitations](https://pub.dev/packages/camera_web), [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup), [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup), [ONNX plugin requirements](https://pub.dev/packages/flutter_onnxruntime).
