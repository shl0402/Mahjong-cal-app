# 開心計一番 / Point of Happiness — 0.4.0+4

3 October 2026. Rules engine remains 0.1.2; model remains the AR42 detector with SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. No scoring formula, bundle identifier or saved preference/history format changed.

## Behavior

- iOS/Android display names use Point of Happiness by default, 開心計一番 for Traditional Chinese and 开心计一番 for Simplified Chinese. Header and About show both names. This does not add a full English translation.
- **我已核對，使用這排牌** can accept the first complete, fresh preview. Confidence and stability do not lock human confirmation. The selected tile count must match; every identity must be supported and no identity may occur more than four times. Unknown/empty/invalid results require rescanning or manual entry.
- Pressing the button takes a copy of the current ordered tiles, stops the camera, and opens the editable hand stage. It does not calculate or save a result automatically. A replacement prompt may appear when a draft already exists.
- Live stability guidance uses three agreeing observations spanning at least 700ms, confidence >=0.80 and gaps up to3000ms. Results expire4000ms after capture, including low-confidence previews; taps recheck age. Rotation/background/tab changes, stop and camera failure revoke the preview. One inference remains in flight at a time.
- The old five-frame gate is preserved as the default in historical benchmark replay tests, so earlier accuracy evidence is not retroactively changed.
- **更正牌面** offers an explicit tile picker, then the existing replace/delete editor. The active rules preset stays visible below the bilingual header. Concealed-only/meld instructions now appear above the camera.

## Why it previously waited

The previous one-second maximum interval was shorter than some devices' inference time, so the five-frame streak could reset continuously. A single uncertain or moving tile also reset it. Human confirmation now bypasses that streak; the wider live timing window also permits slower devices to accumulate guidance.

## Validation

- 216 Flutter tests passed, including first-frame/low-confidence confirmation, slow inference, freshness at tap time, unknown/count/physical rejection, double-tap protection, in-flight frame rejection, unpainted-result race rejection, rotation/background/permission recovery, visible correction, renamed narrow-screen layout and all existing scoring/persistence tests.
- Flutter analysis: no issues.
- Web visual check: bilingual branding, current rules label and concealed-hand scan instructions render correctly. Native camera interaction is covered by fake-platform tests here, not a new physical-phone measurement.
- Model accuracy has not been remeasured or improved by this UI change. New physical-phone latency/heat and localized launcher appearance still need device observation.
- Final unsigned iPhone Profile build passed: `app/build/ios/iphoneos/Runner.app` (82.0MB). Open `app/ios/Runner.xcworkspace` and choose Runner iPhone Test plus your device/development team to install.
- Final optimized Android ARM64 test build passed: `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (57.6MB), using the development signing key.
- Final web release build passed: `app/build/web`.
- All three builds pinned the same app/lib source digest before/after compilation: `d0cee320238fb50362bdb2c0a690272b1b4b3775f491ccb23609627f5e64948a` (sorted repo-relative Dart paths, NUL, file bytes, NUL).
- Packaged artifact details: [TEST_BUILD_040.json](TEST_BUILD_040.json). The older BUILD_VALIDATION.md and TEST_BUILD_MANIFEST.json describe the0.3.0 original-workspace artifacts. The initial clone Swift dependency resolution failed once, then succeeded using Xcode package resolution; final builds all exited successfully.
- No new physical-device installation, signing-team selection, simulator runtime accuracy measurement or public binary upload occurred.

See [competitor comments and comparison](COMPETITOR_REVIEW_20261003.md) for source links and remaining single-row, recognition and house-payment gaps.
