# 開心計一番 · Point of Happiness

Flutter app **0.4.0+4**, rule engine **0.1.2**. This folder is the Flutter project root: `lib/`, `test/`, `ios/`, `android/`, and `pubspec.yaml` live here.

## Setup

Use Flutter 3.47.6 / Dart 3.13.5. The helper scripts use Flutter on PATH or an SDK at `app/.tools/flutter`. On iOS use Xcode; on Android install Android Studio and its SDK.

The experimental AR42 model is not committed because the publisher's redistribution grant is unresolved. If you already have the tested local model, import it with:

```sh
python3 scripts/setup_model.py --source /path/to/mahjong-ar42-63b683c7.onnx
flutter pub get
flutter test
flutter analyze
```

The pinned upstream source, hash and license status are recorded in [`../training/vision/model_manifest.json`](../training/vision/model_manifest.json). For authorized local research, the existing fetcher can retrieve the exact upstream artifact:

```sh
python3 ../training/vision/candidates/fetch_candidates.py ar42
python3 scripts/setup_model.py --source ../training/vision/candidates/downloads/ar-yolov8-42.onnx
```

This is not a grant to redistribute the model. The application does not upload camera images; these setup downloads are separate developer actions.

## Test on a phone

```sh
./scripts/open-xcode.sh phone
# Choose Runner iPhone Test, your connected iPhone and your development team.
# Android:
./scripts/flutter.sh devices
./scripts/run.sh --profile -d DEVICE_ID
```

You can also double-click **Open in Xcode.command** in this folder. Open `android/` in Android Studio. Targets are iOS 16+ and Android 7/API24+. Physical-device performance remains unmeasured. [Phone guide](docs/TEST_ON_PHONE.md).

Continuous on-device scanning, editable confirmation, local settings/history, supported scoring and settlement are implemented. The app remains experimental: recognition errors, incomplete Hong Kong/Taiwan events and unimplemented rule families are documented in [rules readiness](docs/RULES_READINESS.md).

The checked-in reports under `docs/` describe the original local build and its artifacts. They are historical evidence, not claims that APKs, weights or local SDKs are present in a fresh clone. Vision source references now resolve under the repository's separate `training/vision/` workspace.

## Scan preview update

The current preview can be explicitly accepted after one usable result with **我已核對，使用這排牌**; the stability indicator is advisory. The next screen supports correction before scoring. Empty, stale, unknown or invalid tile sets still require rescanning or manual entry. This changes usability, not model accuracy.

Current validation: **216 Flutter tests pass**, static analysis is clean, and iPhone Profile / Android ARM64 / web builds passed. See [the update report](docs/SCAN_PREVIEW_UPDATE.md) and [competitor review](docs/COMPETITOR_REVIEW_20261003.md).
