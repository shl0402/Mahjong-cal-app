# Continue here — 3 October 2026

The user asked for better models, data, training and accuracy outside the training data. Work is active. The earlier battery pause was explicitly revoked by “continue.” No phone test is required before further model work. Do not repeat the misleading comparison of 95% test-build preparation with 30% whole-product completion.

## Current app and native handoff

- **Build refresh pending:** a follow-up audit found that the adopted Chinese HK rules exempt direct kong-replacement self-draws from declared bao liability. The narrow fix and regressions are complete, advancing engine 0.1.1 to **0.1.2**. App version stays **0.3.0+3**. Existing artifacts below predate this fix; refresh their builds/hashes after detector training completes. Do not describe those binaries as containing the new payment correction until rebuilt.
- Current source: **206 Flutter tests pass**, including 76 domain tests; domain analysis is clean. Native artifacts below were built before the narrow scoring fix, when 201 tests passed. Rerun whole-app analysis and refresh builds without repeating unchanged native model/camera tests.
- Bundled detector: `mahjong-ar42-63b683c7.onnx`; SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. See `vision/model_manifest.json`; previous V2 manifest/model retained for comparison.
- AR42 has 34 ordinary identities and eight flower/season outputs mapped to unsupported (-1). It has no dedicated red-five or generic unknown class. No scan thresholds changed. Publisher redistribution grant remains unresolved; this is a local research/test build, not a cleared public release.
- Actual iOS 17 / iPhone 13 Pro simulator and Android 15 ARM64 / 16 KB-page emulator tests recovered all 14 manually annotated identities in a real development photo. Both passed blank/repeat/dispose/reopen; Android passed two actual YUV camera-stream cycles. No physical-phone results are claimed.
- Final normal Android debug and three optimized test APKs, normal iOS simulator app, unsigned physical iPhone Profile build, direct Xcode workspace/Profile build and web build all passed. Artifact versions, model hashes and the source digest have been verified and saved. Read `BUILD_VALIDATION.md`, `PLATFORM_CHECKPOINT.md`, `TEST_BUILD_MANIFEST.json`, and `TEST_ON_PHONE.md` for final artifacts.
- Emulators were shut down. Do not restart them without a new verification need. Normal main entry point must remain `lib/main.dart` after integration tests.
- Open the root **Open in Xcode.command**, then use **Runner iPhone Test**, the user's development team and connected iPhone. No signing team was selected; no App Store/TestFlight/public upload occurred.

## Active detector training — do not abandon

Agent `/root/vision_eval` is completing a separate, fixed 20-epoch YOLO11n experiment from official generic COCO weights, using grouped RF100 train/development only. It is NOT the currently bundled AR42 model.

- Scripts/data: `vision/training/detector_*`.
- Run: `vision/training/detector_runs/full20/`.
- Original log: `vision/training/detector_full20.log`.
- Training saved epoch 5, then stopped at a checkpoint boundary because of sustained Mac memory thrashing. Platform builds ran while GPU memory was released.
- **Resumed at epoch 6 with batch 4**, session **15564**, log `vision/training/detector_resume_batch4.log`. No other training parameter changed. Resource exception and checkpoint hash are in `full20/resource_adjustment.json`; original arguments are in `args_epoch1to5.yaml`.
- Epoch 5 checkpoint SHA-256: `191a885c70ef11b165d4c4630418feacaee394ef422f8e7872f9834dc7ce97f7`; dev mAP50 0.25294, mAP50–95 0.13136. These are incomplete training diagnostics, not app accuracy.
- Original batch-8 run took about 1,191 seconds through five epochs under changing resource pressure. Do not promise an exact completion time. User explicitly permits longer work. Mac is on AC power; leave unrelated user apps alone.
- Best/last checkpoints save every epoch. For a later interruption, use `.venv/bin/python vision/training/detector_train.py --resume --batch-override 4` with approved MPS access. Check current process/status first; never launch a duplicate run.
- Early Ultralytics validation emitted NMS time-limit warnings. Track whether the selected epoch is affected. The final independent CPU decoder/evaluator has no such timeout.
- The warnings continued after resume: epochs 7/8/9 had 3/7/12 respectively (epoch 6 had none). Agent preserved best epoch 8 and last epoch 9, and is preserving subsequent checkpoints for development-only revalidation with timeout-free NMS. Epochs 1–7 snapshots are unavailable; disclose that selection limitation. This recovery uses development data only, never the consumed test.
- **Second resource repair:** epoch 11 was saved. Resume at epoch 12 uses batch 4 with both loaders at zero workers (the framework had created six children), and skips redundant intermediate MPS validation. `full20/runtime_epoch12.json` verifies the applied runtime, restored optimizer state and unchanged 20-epoch schedule/patience. Every subsequent checkpoint is saved for the same timeout-free CPU development selection. Skipped metrics must remain explicitly unavailable, not be quoted from stale CSV columns. Ask the vision agent for the current session/log; session 15564 has stopped.
- Agent has export/parity/follow-up evaluation scripts ready. Finish the experiment, preserve negative results, and compare against AR42 before any further app replacement. Do not stop just because the first test build is ready.

## Completed model/data experiments

See `VISION_EVALUATION.md` and `VISION_CANDIDATES_20261002.md`.

- Compared YOLO11 nano/small/medium, AR42 YOLOv8n and a ViT classifier. AR42 improved the old development diagnostic from **2/7 to 6/7** exact 14-tile regions. These photos are correlated development material, with unknown upstream training overlap.
- On a different published 156-image / 1,589-box diagnostic, AR42 had 1,211 correct, 339 extra and 378 missed detections: 78.1% precision / 76.2% recall. Previous nano recall was 24.4%. Confident mistakes remain. No images in this split have exactly 14 annotations.
- Acquired and SHA-verified RF100-VL Mahjong v2: 2,135 images / 15,037 boxes. Duplicate-aware grouping gives 1,619 train / 360 dev / 156 internal test, with all 34 ordinary classes. Physical tile-set/session identity is unknown. See `VISION_DATA_AUDIT.md`.
- Source manifest was verified and locked before fitting/testing. The 156 test images are now consumed for later adaptive experiments. The new detector's results on them must be called a **follow-up diagnostic**, not a fresh untouched or guaranteed unseen-set test.
- Own MobileNetV3 Small classifier completed 12 fixed epochs from ImageNet weights in 167 seconds. Its held-out crop result is 1,849/1,900 correct (97.32%); ordinary faces alone are 1,537/1,588. These use true crop boxes, not complete-hand detection.
- Critical negative result: MobileNet gets only 117/138 true-face crops right on the Commons source, and replacing AR42 labels worsens exact complete hands from 6/7 to 2/7. It is NOT in the app. The 6.23 MB ONNX export passed parity on 35 real dev crops; retain it as a research artifact.
- Classifier artifacts: `vision/runs/mobilenetv3_rf100_v1/`, including locks, history, internal test, development pipeline failures and export manifest.
- Seven training-pipeline tests and 27 provenance/validation tests pass. Original `train/` files remain untouched.

## Real video evidence

An actual CC BY 3.0 tournament-camera excerpt contains 239 frames over eight seconds. Two reviewers manually agreed on the tilted 13-tile row before model inference; 20 sampled frames and their timestamps/ROI were pinned in `vision/video_candidates/niconico_reference.json`.

AR42 matched 225/260 repeated canonical tile identities versus 199/260 for the old model, but **both recovered zero complete ordered rows out of 20 frames**. These adjacent frames are correlated. The row contains a red five, normalised to an ordinary five for AR42 comparison, and is not a complete 14/17-tile hand.

Actual Dart `ScanConsensus` replay rejected every observation for all UI counts and separately for diagnostic count 13. Reports and attribution are under `vision/video_candidates/`. Do not fabricate successful live recognition from repeated stills or claim this is a physical-phone test.

## Remaining product scope

Continuous on-device camera scanning, editable confirmation, local preferences and local history are implemented. Only HK and an explicitly partial Taiwanese 16-tile house preset are executable. Other rule families and some event-history rules remain unfinished; see `RULES_READINESS.md` and `SCORING_IMPLEMENTATION.md`. The whole universal product is not complete, and physical-phone testing is not the only remaining work.

Future physical tests establish actual camera framing/permissions, lighting and the user's tile style, sustained latency, battery/heat and Android device variation. They do not replace dataset evaluation or rule testing.

## Coordination and environment

- `/root/vision_eval`: active detector training, export and final measurements.
- `/root/platform_build`: completed native checks, builds, artifact hashes and build documentation.
- `/root/rules_tests`: completed app AR42 migration, unit tests and provenance safeguards.
- Parent: vision reports, actual-video evaluator/replay, final evidence review and user handoff.

Workspace: `/Users/samuel/Documents/leisure/mahjong vision`. Flutter wrapper: `scripts/flutter.sh`; Python environment: `.venv`. MPS and native build/cache access require approved unsandboxed execution. Do not change global Xcode selection, sign with an invented team, close unrelated apps or publish anything. Older battery-pause details are archived in `docs/history/` and do not override this active status.
