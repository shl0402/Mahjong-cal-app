# Pretrained model comparison — 2 October 2026

The **42-class AR-Mahjong YOLOv8n** is the strongest new research candidate on the existing development photos. It is about 12 MB and has similar model-only desktop CPU cost to the current nano model. It is not yet evidence of broad generalization: its exact training-image inventory is unknown, and this comparison alone does not certify it. It is now integrated in0.3.0+3 for localtest use with unresolved publisher rights documented; native checks are tracked in BUILD_VALIDATION.md.

## Measured comparison on existing development photos

All detector rows use the same seven public photographs, ten fixed regions and 138 manually labelled tiles documented in [ONLINE_VISION_EVALUATION.md](ONLINE_VISION_EVALUATION.md). Four regions share one photo. The set has already influenced model choices and must remain labelled **development**, never a fresh independent test. No training/fine-tuning occurred here.

| Pretrained candidate | Correct / extra / missed tiles | Precision / recall | Exact 14-tile regions | Exact all regions | FP32 ONNX bytes | CPU median / p95 |
| --- | --- | --- | --- | --- | ---: | --- |
| YOLO11n V2 control | 117 / 8 / 21 | 93.6% / 84.8% | 2 / 7 | 3 / 10 | 10,440,536 | 17.8 / 18.5 ms |
| YOLO11s V2 | 121 / 6 / 17 | 95.3% / 87.7% | 4 / 7 | 5 / 10 | 37,792,440 | 37.0 / 41.0 ms |
| YOLO11m V2 | 121 / 9 / 17 | 93.1% / 87.7% | 3 / 7 | 3 / 10 | 80,336,681 | 88.3 / 91.0 ms |
| AR-Mahjong YOLOv8n, 42 classes | 137 / 0 / 1 | 100.0% / 99.3% | 6 / 7 | 9 / 10 | 12,270,403 | 17.3 / 17.8 ms |

“Correct” requires correct canonical identity and IoU ≥ 0.50 using one-to-one Hungarian matching. A wrong identity contributes an extra and a miss. This is fixed-threshold precision/recall, not mAP or calibrated probability. Confidence threshold is 0.25, class-agnostic NMS IoU is 0.45, maximum detections 40. RGB images are bilinearly letterboxed to 640×640 with padding 114 and divided by 255. Timing is ONNX Runtime 1.30.0 CPUExecutionProvider with two threads, five warmups and ten measured runs per region, on this Mac. It excludes loading, preprocessing, Flutter/native bridging, the camera, battery use and thermals. No iPhone/Android performance claim follows.

The nano was re-exported for a controlled same-environment comparison; its graph serialization/hash differs from the app's existing export, but all ten regions pass numerical and post-NMS parity against the identical pinned checkpoint and produce identical development counts. The baseline evidence remains preserved; the subsequent0.3.0localtest migration usesAR42, with separate nativechecks. The small and medium exports also pass parity on all ten regions using the original checkpoint with restricted loading. Exact artifact/checkpoint hashes, parameter counts, output metadata, environment and all predictions are in [comparison.json](../vision/candidates/comparison.json) and the three corresponding `yolo11*-v2-results.json` files.

Small improves this development set with approximately twice nano's inference cost. Medium is slower without a corresponding improvement and is not preferred. Small's two count/minimum confidence 0.80 eligible stills are `ting-row-1` (minimum 0.81396) and `ting-row-4` (0.81492), both correct. These are correlated tight crops, not actual camera guide/video tests.

AR42 misses one tile in `chinitsu-table-hand`; all other fixed regions have correct labels and count. Four stills meet the necessary count/confidence condition: `orphans-close-two-rows`, `ting-row-1`, `ting-row-2`, `ting-row-3`. They are all correct at the measured matching threshold. The two-row scene would still fail the app's single-row arrangement rule. These results do not demonstrate temporal stability or justify saying recognition is 100% correct. The model could have seen some public photographs during training.

## Provenance, safe loading and app contract

The YOLO11 checkpoints are from [nikmomo/Mahjong-YOLO](https://github.com/nikmomo/Mahjong-YOLO/tree/28ffceed232ad95fd019c47a6c51ae7c78791a0e/trained_models_v2), commit `28ffceed232ad95fd019c47a6c51ae7c78791a0e`. The repository lists nano/small/medium V2 checkpoints; its larger V2 variants are not available at this commit. Source training is linked to [shinz114514's mobile-camera dataset](https://www.kaggle.com/datasets/shinz114514/mahjong-hand-photos-taken-with-mobile-camera/data). No per-image training manifest was obtained, so external-image overlap remains unknown. Repository MIT and Ultralytics AGPL/commercial model terms are distinct.

Checkpoint bytes were verified against pinned hashes before `torch.load(weights_only=True)` with an explicit reviewed allowlist of standard PyTorch/Ultralytics library classes. No arbitrary unpickling or remote checkpoint code was used. Export is fixed 640 ONNX opset 17. Torch/ONNX raw outputs and decoded labels/boxes after NMS are checked on all ten development regions. `compare_yolo_v2.py` records that evidence.

The AR42 source is [LYiHub/AR-Mahjong-Assistant-preview](https://github.com/LYiHub/AR-Mahjong-Assistant-preview/tree/e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299), commit `e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299`, path `server/models/yolo/weights.onnx`. Its SHA-256 is `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. The pinned README credits [Jon Chan’s mahjong-baq4s dataset family](https://universe.roboflow.com/jon-chan-gnsoa/mahjong-baq4s) as supporting CV training, but the exact version, split, image inventory and base weights remain unknown. The ONNX export is dated 22 November 2025, before the currently visible v83 dated 26 November; v83 must not be assumed to be its training set. The **AGPL-3.0** metadata is inserted automatically by Ultralytics 8.0.196 and does not independently establish a publisher license grant. The repository has no LICENSE or README grant. It remains a local evaluation candidate; availability is not a substitute for release-rights review. See the provenance appendix in [VISION_DATA_AUDIT.md](VISION_DATA_AUDIT.md).

The exact contract is in [ar-model-manifest.json](../vision/candidates/ar-model-manifest.json):

- Input `images`: float32 RGB NCHW `[1,3,640,640]`, aspect-preserving letterbox, padding 114, pixel/255.
- Output `output0`: `[1,46,8400]`; four center/size box channels followed by 42 class scores. No objectness channel or embedded NMS.
- ONNX opset 12; checker passes; only standard operators, no custom domains or external tensor data. The graph has 3,013,838 initializer elements, including non-parameter constants.
- ONNX class metadata contains numeric placeholders. The pinned [class_names.txt](https://github.com/LYiHub/AR-Mahjong-Assistant-preview/blob/e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299/server/models/yolo/class_names.txt) is essential. `B/C/D` indicate bamboo/characters/circles; `EW/SW/WW/NW` indicate winds; `WD/GD/RD` indicate dragons. Eight `F/S` flower/season categories have not been semantically/photo validated here and must initially be treated as unsupported. No red-five or UNKNOWN class exists.

This ONNX was provided directly, so no PyTorch-to-ONNX equivalence claim is made for it. Native app preprocessing and class-decoder parity must be checked before integration. Four benchmark images containing particular Chinese fonts are not validation of all 42 classes.

## Actual non-YOLO experiment

The [s-seow/mahjong-tile-classifier-vit](https://huggingface.co/s-seow/mahjong-tile-classifier-vit) checkpoint was tested at revision `997e76ef44835b4f582226c4f2826f6335af42d9`. Its 343,322,416-byte safetensors file has SHA-256 `6ce2fa4fb1cc052ebdfb181e34e35ea341dbe471bc5b9090f5dbd84ab1e5c796`. Loading uses the standard local `ViTForImageClassification` class, strict safetensors state loading and no remote model code. The supplied processor specifies 224×224 RGB bilinear stretch and `(pixel/255−0.5)/0.5` normalization. It has 85,824,802 parameters and 34 output identities. The model card does not specify training data or a license, so it is research-only.

On the **manual ground-truth face crops**, it correctly classified 57/138 tiles (41.3%). This supplies perfect localization and is not whole-image detector accuracy. Using the same YOLO11n boxes followed by this classifier produced 48 correct matches, 77 extras/wrong labels and 90 misses/wrong labels, with no exact regions. Median/p95 classifier-only CPU cost was 47.5/50.7 ms **per tile**; classification for a proposed region took a median 641.7 ms before adding detector/preprocessing cost. These results make this particular checkpoint unsuitable for the app. They do not show that every two-stage architecture is inferior. See [vit-results.json](../vision/candidates/vit-results.json).

## Other primary-source alternatives reviewed

| Alternative | What is available and what remains unproven |
| --- | --- |
| [RF-DETR](https://github.com/roboflow/rf-detr) | Apache-designated package/models; Plus models have separate terms. Nano has 30.5M parameters. COCO/Objects365 pretraining does not recognize mahjong identities without fine-tuning. A [publisher tutorial](https://blog.roboflow.com/train-rf-detr-on-a-custom-dataset/) demonstrates a mahjong-trained model, but an ungated downloadable checkpoint was not established. Do not treat its tutorial metrics as this app's results. |
| [D-FINE](https://github.com/Peterande/D-FINE) | A compact non-YOLO detector architecture worth a same-data training comparison. Generic pretraining alone is not a mahjong recognizer; it was not benchmarked as one here. |
| [HaseLab/mahjong-models](https://huggingface.co/HaseLab/mahjong-models) | Public YOLO26 region/tile segmentation plus ResNet50 classifier. Pipeline rectifies tile polygons to 224×224 before classification. Different task/class coverage, missing clear license and incomplete exact preprocessing provenance make it an architectural reference here, not a measured substitute. Its weights were not loaded in this comparison. |
| [MobileNetV3 Small](https://docs.pytorch.org/vision/main/models/generated/torchvision.models.mobilenet_v3_small.html) | Lightweight classification backbone suited to training a separate face classifier. ImageNet weights require mahjong training; no accuracy is claimed before that experiment. The parent task owns the new controlled training run. |

## Selection frozen before external evaluation

At `2026-10-02T15:39:38Z`, [external_evaluation_lock.json](../vision/candidates/external_evaluation_lock.json) fixed AR42 as primary research candidate, YOLO11s V2 as secondary and YOLO11n V2 as control, with unchanged 0.25 confidence, 0.45 NMS and 0.50 matching IoU. The existing Commons development comparison was the sole selection basis. Medium and ViT were excluded before new-test inference. The new RF100-VL grouped internal test has unknown physical tile sets/capture sessions and unknown overlap with these pretrained models; even a strong result must be called an **external-dataset diagnostic**, not guaranteed unseen-data generalization.

The independently verified source-test lock was then completed at `2026-10-02T15:46:31Z`. The parent task confirmed its separate classifier architecture, hyperparameters and dev-only epoch selection rule were already frozen before any external result disclosure. No RF100 test-image inference preceded these locks. All source-test examples are now marked consumed for future model selection in [external_evaluation_exposure.json](../vision/candidates/external_evaluation_exposure.json). Do not describe a subsequent tuned run on these same examples as a new untouched test.

## External-dataset diagnostic: 156 images, 1,589 labelled tiles

The locked RF100-VL Mahjong grouped internal split contains 156 images in 156 duplicate groups and all 34 standard classes. Known duplicates are kept out of local training/development, but original capture-session and physical-set identities remain unknown. These pretrained checkpoints may have used this data or related sources upstream. Results therefore measure transfer to a different published dataset **without establishing guaranteed training independence**.

The full original image is evaluated at the frozen preprocessing/thresholds. Existing COCO boxes and labels are used without tuning or relabelling after inference. The archive and all input image hashes are verified. Five images contain more than 40 labelled tiles; the app's fixed 40-detection cap is retained. There are **zero images with exactly 14 annotated tiles**, so this split cannot supply an exact 14-tile hand success rate. It includes isolated/pair/triple examples and crowded scenes, which also differ from guided live row capture.

| Frozen candidate | Correct / extra / missed | Precision / recall at 0.25 | Exact full images | CPU median / p95 |
| --- | --- | --- | --- | --- |
| YOLO11n V2 control | 388 / 174 / 1,201 | 69.0% / 24.4% | 10 / 156 | 15.0 / 18.1 ms |
| YOLO11s V2 | 446 / 104 / 1,143 | 81.1% / 28.1% | 8 / 156 | 36.7 / 38.6 ms |
| AR42 | 1,211 / 339 / 378 | 78.1% / 76.2% | 69 / 156 | 18.6 / 20.2 ms |

The AR model retains substantially better recall on this different dataset, but its 99.3% development recall does not transfer unchanged. A larger YOLO11 model alone is insufficient. This supports AR42 as a stronger experimental candidate while showing the need for new data, orientation handling and validation. It does not establish universal phone scanning readiness.

At the existing live score operating point, retaining detections with confidence **≥0.80** gives:

| Candidate | Correct / wrong high-score detections | High-score precision | Recall over all 1,589 labels |
| --- | --- | --- | --- |
| YOLO11n V2 | 12 / 7 | 63.2% | 0.8% |
| YOLO11s V2 | 79 / 3 | 96.3% | 5.0% |
| AR42 | 953 / 85 | 91.8% | 60.0% |

These are detection-score filters, **not app scan eligibility**, calibrated probabilities or observed temporal acceptance. AR42 has 24 images with both a supported annotation count and that many predictions all scoring at least 0.80; four of those contain wrong identities. All four are two-tile scenes, not validated live rows. Visual inspection confirmed the ground-truth identities: `000827` and `000857` have 7s misread as 6s; `001050` has an upside-down 1m misread as 2m; `001094` has a rotated 4s misread as 6s. The wrong-class scores range from 0.801 to 0.907. The [failure contact sheet](../vision/candidates/external-high-confidence-errors.jpg) shows these source images with ground truth and predictions. Row-layout and temporal checks may reject these scenes; the evidence is that high model confidence by itself is insufficient. No still frame was duplicated to fabricate a live-lock result.

AR42's poorest class recalls include bird-style 1s (4/37), West (18/54), 7s (21/53) and 2m (18/40). The largest identity confusions include West→South and 7s→6s, 26 each. Twenty-five 1s labels are predicted as an unsupported flower/season category. In the evaluator these categories are reported as `UNKNOWN` with their original class IDs preserved; this is an interface mapping, **not an UNKNOWN class learned by this model**. Full class counts and all detections/matches are in [external-ar-yolov8-42-results.json](../vision/candidates/external-ar-yolov8-42-results.json), alongside the [three-model comparison](../vision/candidates/external-comparison.json).

The RF100-VL [source project](https://universe.roboflow.com/rf-100-vl/mahjong-vtacs-mexax-m4vyu-sjtd) identifies the provider as a Roboflow user and labels the dataset MIT. The dataset agent retained its original notices and [acquisition/audit files](../vision/datasets/). The local failure sheet adds boxes/text and preserves the source identity; original individual-photo provenance has not been independently reconstructed.

## Completed controlled detector training

The follow-up experiment trained YOLO11n from official generic COCO weights for all 20 planned epochs on the grouped RF100 training split. Complete timeout-free CPU development validation selected epoch20 (mAP50 0.78287, mAP50–95 0.56009). Its 10.60MB ONNX export passed Torch parity, but **it should not replace AR42**: the consumed RF100 diagnostic improved to88/156 exact images, while the existing Commons photos fell to0/7 complete hands (AR42:6/7). The same pinned20 real-video frames yielded no detections at0.25; a raw-score check confirmed low model scores before decoding. These results demonstrate poor domain transfer, not a proved statistical overfitting diagnosis. The [complete training report](../vision/training/detector_REPORT.md) records data, resource adjustments, validation timeouts and their repair, checkpoint hashes, exact metrics, rights and reproduction. The RF100 follow-up and existing photo/video development sets are not new untouched tests.

## Reproduction

```sh
.venv/bin/pip install -r vision/candidates/requirements.txt
.venv/bin/python vision/candidates/fetch_candidates.py
.venv/bin/python vision/candidates/compare_yolo_v2.py
.venv/bin/python vision/candidates/compare_ar_detector.py
.venv/bin/python vision/candidates/compare_vit_classifier.py
.venv/bin/python vision/candidates/evaluate_external.py
```

The nano checkpoint and existing fixed image/annotation manifests come from the previous evaluation's pinned fetchers. Candidate downloads remain under ignored `vision/candidates/downloads`; no weights or dataset images were copied into the app. All comparative outputs are under `vision/candidates`. The existing [online report](ONLINE_VISION_EVALUATION.md#attribution-and-derivative-images) retains photo attributions and licenses.
