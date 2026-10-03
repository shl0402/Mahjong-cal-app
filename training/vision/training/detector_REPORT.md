# Controlled detector training: RF100-VL Mahjong

Completed 2 October 2026 UTC / 3 October Hong Kong time.

**Keep AR42 in the experimental app.** We completed the requested 20-epoch training run, selected and exported a small detector, and tested it against labelled photographs. It improves exact-image results on the RF100 dataset, but transfers poorly to the existing Commons real-hand photos: **0/7 complete hands correct**, compared with **6/7 for AR42**. This is a completed negative experiment, not a claim of universal recognition. The files are retained for reproducibility and further controlled work; this run did not modify app assets.

## What was trained

The model starts from the official generic [Ultralytics YOLO11n COCO weights](https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11n.pt), not an existing mahjong checkpoint. The downloaded file is 5,613,764 bytes, SHA-256 `0ebbc80d4a7680d14987a577cd21342b65ecfd94632bd9a8da63ae6417644ee1`. It was loaded with `weights_only=True` and an explicit standard-library class allowlist. Later reloads inside Ultralytics use only our locally generated checkpoints; export and revalidation also use the restricted loader.

The grouped RF100-VL split supplies **1,619 training images / 10,700 boxes** and **360 development images / 2,748 boxes**. Training data links contain no internal-test images. The 156-image test split had already been consumed by previous candidate comparisons before this experiment was proposed. Its new scores are therefore a **follow-up diagnostic**, even though those images and known duplicate groups were excluded from local training. Unknown capture sessions and physical tile sets prevent a stronger independence claim. See the [data audit](../../docs/VISION_DATA_AUDIT.md) and [source manifest](../datasets/rf100vl_mahjong/image_manifest.json).

The fixed [experiment plan](detector_EXPERIMENT_PLAN.json), SHA-256 `158e994ecaf21b96781a099871f4ca87a3aaf1cc28ef5f77b794797365a75f9d`, uses 20 epochs, 640-pixel input, seed 20261002, no horizontal or vertical flips, 180-degree rotation range, translate 0.05, scale 0.25, perspective 0.0005, mosaic 0.2 disabled for the last five epochs, and no mixup. Optimizer `auto` resolved to AdamW, learning rate 0.000263 and weight decay 0.0005. Development selection uses the unchanged fitness `0.1 × mAP50 + 0.9 × mAP50–95`, with a later epoch winning a tie.

Coverage is the **34 ordinary identities only**, ordered `1m…9m, 1p…9p, 1s…9s, 1z…7z`. There is no learned UNKNOWN class, flower/season support or red-five distinction.

## Resource and validation repairs

All 20 training epochs completed. The recorded active training time was **4,935.5 seconds (82.3 minutes)**, including in-loop validation but excluding the discarded one-epoch probe, app-build pause and later CPU comparison. The run used MPS on this Mac.

Two documented resource adjustments were necessary: batch size changed from 8 to 4 after epoch 5; loader workers changed from requested 2 to 0 after epoch 11. The library had actually created six persistent loader subprocesses across training and validation. Persistent compression/swapping slowed epoch 11 to 692 seconds; epoch 12 with zero workers took 130 seconds. Optimizer state was restored at both boundaries. Batch/resume changes mean this is not a bit-for-bit execution of the original batch-8 plan. The data, total epochs, augmentation settings and selection criterion remained unchanged. [Resource history](detector_runs/full20/resource_adjustment_history.json) and [runtime assertions](detector_runs/full20/runtime_epoch12.json) record the actual configuration.

Standard MPS validation produced **187 NMS timeout warnings**: 2, 14, 23, 15, 19, 0, 3, 7, 12, 14 and 35 for epochs 1–11, and 43 for epoch 20. A timeout can skip predictions for remaining images in a batch. These scores are not the final accuracy evidence. Epochs 12–19 explicitly skipped redundant validation; their raw CSV bookkeeping values are unavailable/stale, not newly measured metrics. The epoch-driven learning-rate scheduler and gradients were unchanged, patience 100 cannot stop this fixed 20-epoch run, and checkpoint saving remained enabled. See the [validation audit](detector_runs/full20/validation_log_audit.json).

The [selection repair](detector_SELECTION_REPAIR.json) was committed before its results: run complete, timeout-free CPU development validation on **all preserved epochs 8–20**, using two CPU threads, batch 8, rectangular 640 input, confidence 0.001, class-aware multilabel NMS at IoU 0.7, max 300 detections. Earlier snapshots 1–7 were unavailable, so this is the best preserved candidate, not a retrospective claim about every original epoch. Each of the 13 candidates processed all 360 development images, with **zero timeout warnings**, in 192.6 seconds total. No test images selected the checkpoint.

Epoch 20 was selected: **mAP50 0.78287; mAP50–95 0.56009; fitness 0.58236**. Detailed per-epoch and per-class results are in [timeout_free_selection.json](detector_runs/full20/timeout_free_selection.json).

After epoch 20 and its in-loop validation, we preserved and verified the full final checkpoint and 255 optimizer states. We deliberately interrupted the redundant library `best.pt` GPU validation before completing that extra pass. The process exited with SIGINT/130, not a normal trainer return; the [completion record](detector_runs/full20/run_summary.json) states this explicitly. Final full-checkpoint SHA-256 is `a1d4ed8fb0427ddf77ba63f06a391e852c4816f1b7a0d21af3382bb883c8f701`; the separate optimizer snapshot is `af1d2f6494ba1d17efaee288a2e655280d69ca0f2142e7836356b7d673078364`. This omission did not replace or truncate the subsequent complete CPU validation.

## Export verification

The selected model is [mahjong-yolo11n-rf100v1.onnx](detector_runs/full20/mahjong-yolo11n-rf100v1.onnx), **10,597,705 bytes / 2,596,470 parameters**, SHA-256 `1a78e66672b643b972f8836efab49c61b1256604d3d6d7f612629bd9b1d2400e`.

Input is float32 RGB NCHW `[1,3,640,640]`, bilinear aspect-preserving letterbox with padding 114, divided by 255. Output is `[1,38,8400]`: four center/size box channels followed by **34 class scores**, without objectness or embedded NMS. Opset 17 uses standard operators with no external tensor data or custom domains. The ONNX checker passed.

On three deterministically chosen local-development photos, Torch versus ONNX had maximum score delta **2.81×10⁻⁶** and maximum box delta **0.0080 pixels**. Active top classes and all decoded detections matched, with matched box IoU above 0.999. This tests export consistency, not recognition accuracy. Historical upstream filenames containing `test` do not change those images' locally grouped `dev` membership. See the [export manifest](detector_runs/full20/export_manifest.json) and [graph audit](detector_runs/full20/onnx_graph_audit.json).

## Fixed-threshold detection results

The following evaluation is distinct from low-threshold mAP selection. It uses the app's fixed confidence 0.25, class-agnostic NMS IoU 0.45, maximum 40 detections and class-aware Hungarian matching at IoU 0.50. A wrong identity contributes both an extra and a missed label. Exact images require all labels and boxes to match with no extras. RF100 images are full annotated scenes; the Commons set contains ten predetermined regions from seven real photos, including seven complete 14-tile hands. No threshold was tuned after these results.

| Evaluation | Correct / extra / missed | Precision / recall | Exact images or regions | CPU median / p95 |
| --- | --- | --- | --- | --- |
| RF100 development, 360 images | 2,115 / 487 / 633 | 81.28% / 76.97% | 226 / 360 | 15.12 / 18.01 ms |
| RF100 consumed test, 156 images | 1,195 / 318 / 394 | 78.98% / 75.20% | 88 / 156 | 14.63 / 17.97 ms |
| Commons development, 10 regions | 70 / 37 / 68 | 65.42% / 50.72% | 1 / 10; **0 / 7 complete hands** | 15.95 / 18.00 ms |

These are single-inference timings after five warmups, ONNX Runtime CPU provider with two threads, measured after app builds ended. They exclude image preprocessing, decoding, camera transfer and UI. They are **Mac timings, not iPhone or Android measurements**.

For comparison, the previous AR42 diagnostic on the same RF100 split was 1,211 / 339 / 378, precision 78.13%, recall 76.21%, and 69/156 exact images. Our model improves exact-scene count and slightly improves precision, while slightly reducing recall. On the same Commons regions, AR42 was 137 / 0 / 1, with **9/10 exact regions and 6/7 complete hands**. The new model's small RF100 gains do not compensate for its large whole-hand regression.

At confidence ≥0.80, the new model's RF100 diagnostic has **835 correct / 46 wrong detections**, precision **94.78%**, recall **52.55%**. Thirty-three scenes have a supported count and every predicted score ≥0.80, with zero incorrect tile multisets in that subset. This is only a count/score filter; it is not the app's row geometry or temporal consensus gate. On development data, the same filter has **5 wrong scenes among 94 eligible scenes**. On Commons it has **no eligible regions** and high-score precision 81.82% / recall 32.61%. Confidence alone still does not establish correctness.

Commons failures include 8m→1m, 2p→3p and 6s→7s confusions. The model recognized one nine-tile, three-pung region exactly, but missed every tile in the thirteen-tile ron row at the fixed threshold. RF100 confusions include 5m→6m and East→North. Full predictions, boxes, per-class counts and confusion tables are retained in [development results](detector_runs/full20/evaluation-dev.json), [follow-up diagnostic](detector_runs/full20/evaluation-internal_test.json) and [Commons results](detector_runs/full20/evaluation-commons-development.json).

The parent task also tested the exported model on the same pinned, manually reviewed **20 real broadcast-video frames**, containing one fixed 13-tile row: **zero detections at 0.25, 0/260 canonical tile matches and 0/20 exact rows**. A raw-output check on frame 0 found a maximum class score of only **0.043017**, finite `[1,38,8400]` output and zero anchors above threshold, confirming that this failure occurs before decoding. These are correlated frames of one physical set, with a manually fixed crop; they are not 20 independent hands, a phone-camera test or a positive temporal-lock example. Canonical comparison normalizes the red five. Identity-multiset matching in this video diagnostic is also distinct from the photo experiment's IoU matching. See [video results](../video_candidates/trained-row-results.json), [raw-score check](../video_candidates/trained-low-confidence-check.json) and the linked frozen reference/source metadata. No threshold was lowered to hide the failure.

## Limits, rights and next experiment

These results demonstrate a **domain transfer failure**. They do not alone prove statistical overfitting; the complete development curve continued improving through epoch 20. More epochs on the same source cannot be assumed to solve different tile fonts, table lighting, viewpoint, spacing and physical sets. The existing Commons examples were already used for development comparisons and are not a new untouched test. Hash/pixel/perceptual checks found no exact or close whole-image matches with the local training images, but cannot rule out related crops, edits, sessions or physical sets; see [overlap checks](detector_development_overlap.json).

A subsequent experiment should freeze its training and selection policy and acquire a new, rights-reviewed multi-set/session evaluation set before interpreting it as new generalization evidence. Source-dataset scores should remain separate from complete-hand and temporal video outcomes. The current frozen photo/video diagnostics can continue to reveal regressions, but cannot regain untouched-test status.

The RF100-VL [source project](https://universe.roboflow.com/rf-100-vl/mahjong-vtacs-mexax-m4vyu-sjtd) labels the dataset MIT; original per-photo authorship is not fully reconstructed. The Commons photos retain their individual licenses and attribution in the [online report](../../docs/ONLINE_VISION_EVALUATION.md#attribution-and-derivative-images). [Ultralytics' published licensing terms](https://www.ultralytics.com/license) apply AGPL-3.0/enterprise choices to its code and derived trained weights. This experiment did not buy a license or establish proprietary-app distribution rights. AR42's separate unresolved publisher license is unchanged.

## Reproduction

Use the source manifests, pinned initial weights and checksums in the experiment plan. The measured environment was Python 3.12.7, Torch 2.10.0, Ultralytics 8.3.162, ONNX 1.23.1, ONNX Runtime 1.30.0, NumPy 2.4.4 and Pillow 12.1.1. The preparation script asserts grouped separation and never uses the consumed test for training. The four integrity tests pass.

```sh
.venv/bin/python -m unittest vision.training.detector_test_integrity
.venv/bin/python vision/training/detector_prepare.py
.venv/bin/python vision/training/detector_train.py
# Recorded resource resumes for this run:
.venv/bin/python vision/training/detector_train.py --resume --batch-override 4
.venv/bin/python vision/training/detector_train.py --resume --batch-override 4 --workers-override 0 --skip-intermediate-validation
# Preserve each checkpoint; final selection needs all saved epochs 8–20.
.venv/bin/python vision/training/detector_revalidate_selection.py
.venv/bin/python vision/training/detector_export.py
.venv/bin/python vision/training/detector_evaluate.py
.venv/bin/python vision/training/detector_audit_logs.py
```

These resume commands document checkpoint-boundary operations and must not run concurrently. `detector_preserve_checkpoints.py` records checkpoints during training; the final omission was executed by `detector_finish_at_checkpoint.py` against the verified task-owned PID. Full run logs and explicit resource/validation histories remain beside this report. Training checkpoints, ONNX weights and source images remain local ignored artifacts.
