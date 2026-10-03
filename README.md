# 開心計一番 · Point of Happiness

Two separate workspaces:

- **[app/](app/)** — Flutter application, iOS/Xcode and Android projects, local settings/history, rule engine, tests and phone-testing guides.
- **[training/](training/)** — dataset preparation, training/export/evaluation scripts, experiment manifests and measured results, plus the original training source.

App version **0.4.0+4**, rules engine **0.1.2**. The original workspace passed 206 Flutter tests and iOS/Android/web builds. This repository reorganizes that source; it is an experimental test app, not a finished universal mahjong product. Hong Kong and a partial Taiwanese house preset are implemented; other regional packs remain unfinished.

## Run the app

Install Flutter 3.47.6 / Dart 3.13.5 and the platform tools. From the repository root:

```sh
python3 app/scripts/setup_model.py --source /path/to/mahjong-ar42-63b683c7.onnx
cd app
flutter pub get
flutter test
./scripts/open-xcode.sh phone
```

The model importer verifies the exact SHA-256. See [app setup](app/README.md) for the pinned upstream source and model limitations. The GitHub copy deliberately excludes model binaries with unresolved redistribution permission, downloaded datasets/videos, generated builds, environments, signing keys and machine settings. They remain in the original local workspace. A fresh clone needs the model before Flutter can bundle its declared asset.

## Current external recognition evidence

| Diagnostic | Current AR42 model |
| --- | --- |
| Small public-photo development benchmark | 6/7 complete hands correct |
| Different 156-image diagnostic | 69/156 exact images; 78.1% tile precision, 76.2% recall |

Upstream training overlap is unknown. These are not guarantees of unseen-data accuracy. Newly trained candidates did not generalize well enough to replace the current app model. Detailed results are in [the evaluation report](training/docs/VISION_EVALUATION.md).

Images are processed on the phone without uploading. Stable predictions still require human review. Training results and report manifests are retained as historical evidence, including failed experiments.

## Scan preview update

The current preview can be explicitly accepted after one usable result with **我已核對，使用這排牌**; the stability indicator is advisory. The next screen supports correction before scoring. Empty, stale, unknown or invalid tile sets still require rescanning or manual entry. This changes usability, not model accuracy.
