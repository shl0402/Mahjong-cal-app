> Archived handoff from the original workspace. For this repository use `app/README.md` and `training/README.md`; binary artifacts and local SDKs described below are not committed.

# Continue here — 3 October 2026

This research, training and local-build pass is complete. The broader universal Mahjong product is still unfinished. The user most recently asked about accuracy on outside data; answer with the measured external results below, not training accuracy. Earlier percentages (95% test-build preparation versus 30% whole product) mixed different scopes and were misleading. Do not repeat them as comparable completion figures.

No user phone test is required before further dataset/model/rules work. Physical-phone testing later establishes actual camera geometry, the user's tile styles, speed and heat. The earlier battery pause was revoked by “continue”; all completed work is saved here.

## Current test app

- App **0.3.0+3**, rules engine **0.1.2**. **206 Flutter tests pass**, including 76 domain tests; whole-app analysis is clean.
- Integrated detector remains **AR42 YOLOv8n**, asset `app/assets/models/mahjong-ar42-63b683c7.onnx`, SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`, 12,270,403 bytes. None of the unsuccessful research candidates was substituted into the app.
- AR42 has 34 ordinary identities and eight flower/season outputs mapped to unsupported (-1). It has no dedicated red-five or generic unknown class. Confirmation thresholds are unchanged: count, minimum confidence 0.80, five agreeing observations over at least 1.2 seconds, legal multiplicity, row geometry and freshness. Human review remains mandatory.
- Continuous native camera scanning, editable confirmation, local preferences and local hand history work. Images are not uploaded. Browser build provides manual entry/settings/scoring, without live frame scanning.
- Engine 0.1.2 fixes the adopted Chinese HK source's direct kong-replacement self-draw exemption from bao. The independent seven-faan fixture now pays 96 from each opponent, instead of 288 from the declared liable player. Ordinary/flower-replacement liability and robbed-kong policies are preserved. The UI explains the exception. Saved historical transfers remain unchanged.
- Only HK and an explicitly partial Taiwanese 16-tile house preset are executable. Instant flower wins, event-history adjudication, full game accounting and other families remain unfinished. See `RULES_READINESS.md` and `SCORING_IMPLEMENTATION.md`; vision testing is not the only remaining work.

## Verified handoff

All final builds passed: normal iOS simulator, unsigned iPhone Profile, direct Xcode workspace/Profile, Android debug, three optimized test APKs and web. Artifact versions/model hashes were checked. `Generated.xcconfig` targets `lib/main.dart`.

Final source digest: `017a497674d1c2d01c7f5ac26e96546c0a4813e4714952069e42395db44bc475`, using sorted repository-relative `app/lib/**/*.dart` paths including the `app/lib/` prefix, NUL, file bytes, NUL. The parent independently verified this matches `TEST_BUILD_MANIFEST.json`.

- In Finder, double-click root **Open in Xcode.command**. Select **Runner iPhone Test**, the connected iPhone and the user's development team, then Run. No team was selected on the user's behalf.
- Android ARM64 optimized test APK: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (57.6 MB). Other architectures and debug APK are also built.
- Targets: iOS 16+, Android 7/API24+. Physical-phone performance is not yet measured.
- `BUILD_VALIDATION.md`, `PLATFORM_CHECKPOINT.md`, `TEST_BUILD_MANIFEST.json`, and `TEST_ON_PHONE.md` contain the exact outputs and signing/testing steps.
- Native real-photo inference and lifecycle tests previously passed on iPhone 13 Pro/iOS17 simulator and Android15 ARM64/16KB-page emulator. Both recovered all 14 fixture identities; Android exercised actual YUV stream cycles. These ran on engine 0.1.1 with the same unchanged model/camera code. The 0.1.2 rebuild did not repeat or re-label them as new native measurements.
- Simulators/emulators are stopped; no phone installation, signing-team change, TestFlight or public upload occurred.
- Current model publisher redistribution permission remains unresolved. This is a local research/test build, not a cleared public release.

## Actual outside-data accuracy

Current AR42 model:

| Diagnostic | Result |
| --- | --- |
| Old public-photo development sample | 6/7 exact complete 14-tile hands; 137/138 matched tiles across ten regions; old model was 2/7 |
| Different 156-image / 1,589-box dataset | 1,211 correct, 339 extra and 378 missed; precision 78.13%, recall 76.21%; 69/156 exact images |
| Actual tournament video, 20 sampled frames | 225/260 canonical identity matches, 32 extras, 35 misses; 0/20 exact ordered rows; actual Dart gate accepts none |

The seven-photo sample is small, correlated and used for development. The 156 images have no exactly-14-annotation image. Pretrained training inventories are unavailable: external source does not prove zero upstream training overlap. The video is one tilted 13-tile row (including a red five normalized to ordinary five), not 20 independent complete winning hands. Confident wrong predictions remain.

See `VISION_EVALUATION.md`, `VISION_CANDIDATES_20261002.md`, the candidate reports and `vision/video_candidates/` for references, per-example predictions and limitations.

## Completed own training — do not resume the completed run

RF100-VL Mahjong v2: 2,135 images / 15,037 boxes, hash-verified and grouped before training. Splits: 1,619 train / 360 development / 156 internal test. Physical-set/session IDs are unknown. The 156 test images are now consumed; future adaptive evaluations on them are follow-up diagnostics, not fresh untouched tests. Training excludes their groups.

**MobileNetV3 Small classifier:** 12 fixed epochs from generic ImageNet weights. Reserved crop result 1,849/1,900 (97.32%) includes background and uses true boxes. Different-source Commons crops are only 117/138 correct; replacing AR42 labels worsens exact hands from 6/7 to 2/7. Not integrated. Saved under `vision/runs/mobilenetv3_rf100_v1/` with 6.23 MB ONNX export and parity checks.

**Own YOLO11n detector:** completed all 20 epochs from official generic COCO weights. Run/artifacts: `vision/training/detector_runs/full20/`. Initial batch8 was reduced to4 after epoch5. Six implicit loader workers were removed after epoch11, and redundant intermediate MPS validation deferred. All resource changes are recorded; training data/augmentation/epoch schedule were retained. The final process deliberately exited130 after the verified epoch20 save, before redundant post-training validation. `run_summary.json` records this accurately; it is not a normal-return claim.

Full report: `vision/training/detector_REPORT.md`. All task-owned training, checkpoint watchers, export and evaluation processes have exited. No model-training or native-build job is left running.

MPS validation had timeouts, so the authoritative checkpoint selection reran all 13 preserved epochs8–20 on the 360 development images using two-thread CPU validation without NMS timeouts. Early epochs1–7 were not retained, a documented limitation. Epoch20 won the precommitted dev criterion. The consumed test did not choose the checkpoint.

- Research export: `mahjong-yolo11n-rf100v1.onnx`, 10,597,705 bytes, SHA-256 `1a78e66672b643b972f8836efab49c61b1256604d3d6d7f612629bd9b1d2400e`.
- RGB640/pad114 input; output `1×38×8400`; 34 ordinary identities only. Torch/ONNX raw and decoded parity passed on three dev images.
- Reserved-source follow-up: 1,195 correct / 318 extra / 394 missed; precision78.98%, recall75.20%, 88/156 exact images.
- Different-source Commons: 70/138 matched tiles, **0/7 exact complete hands**.
- Actual video: **zero detections at confidence0.25 across20frames**, zero exact rows. Raw first-frame maximum class score0.043 confirms low scores before decoding, not an output-shape/class-map failure.
- This is poor domain transfer, not proof of classical training overfit. The model is **not in the app**. Preserve checkpoints/results as evidence and a starting point for a separately named future experiment; do not overwrite/resume this completed run as if its original protocol were still active.

## Other completed experiments

- Pretrained YOLO11 nano/small/medium, AR42 and a ViT classifier were compared. Bigger models did not consistently help.
- A distinct screenshot-focused 34-class model from mahjong-detector0.0.6 got0/7 photo hands and0/20 video rows. A historical public80.5MB RiichiCam model got4/7 and0/20; its source-style row-window wrapper worsened to1/7 and0/20. Current private RiichiCam weights were not accessed. Exact provenance/recipes/results are under `vision/candidates/research/`.
- Label-free row straightening did not help. Overlapping windows or smaller input content could improve the old photo score to7/7 while worsening video, so none were integrated.
- Video physical-order comparison was corrected and regression-tested; preserved superseded reports document that overall zero-exact-row conclusions did not change.
- Original `train/` data/code remain untouched. Downloaded package Python/TypeScript was inspected statically, never installed/executed.

## Useful next work

1. Improve training-domain coverage: rights-documented standing14/17-tile rows, unfamiliar physical sets/fonts, blur/glare/oblique camera views and rejection examples. Existing source has only eight14-annotation and eight17-annotation training images, and count alone does not imply a row or legal hand. Do not just tune against the same seven exposed photos.
2. Create a genuinely fresh physical-set/session-held-out evaluation before another adaptive model experiment. Record source and train exposure, retain complete-hand accuracy and confident-error rates. Treat synthetic scenes as supplementary data requiring real-scene validation.
3. Continue source-based rule-pack implementation and independent fixtures, including excluded HK/Taiwan events and the researched remaining families. Avoid describing partial presets as complete regional support.
4. Physical iPhone13Pro and representative Android tests then measure focus/framing, actual tile styles, sustained latency, heat and battery. User testing is helpful here, not a prerequisite for steps1–3.

Workspace: `/Users/samuel/Documents/leisure/mahjong vision`. Python: `.venv`; Flutter wrapper: `scripts/flutter.sh`. Native caches/MPS may require approved unsandboxed execution. Do not change global Xcode selection, pick a signing identity, close unrelated apps, or publish without authorization. Detailed historical handoffs remain in `docs/history/`.
