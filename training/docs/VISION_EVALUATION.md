# Vision evaluation and training experiments

Assessment: 2–3 October 2026. Measurements below distinguish model recognition, app integration and physical-phone readiness. Every recognised hand still requires human confirmation.

## Integrated local test model

Version **0.3.0+3** uses AR-Mahjong YOLOv8n with 42 classes from the pinned [source repository](https://github.com/LYiHub/AR-Mahjong-Assistant-preview/tree/e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299). The 12,270,403-byte asset has SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. Its manifest is `vision/model_manifest.json`; the previous YOLO11n V2 model and manifest remain on disk for comparison.

Of the 42 outputs, 34 represent ordinary tiles. Eight flower/season outputs map to unsupported (-1) and prevent confirmation. There is no dedicated red-five or generic unknown class. Red tiles may be recognised as ordinary fives, but the red attribute is not preserved. Mapping some outputs to unsupported does not establish rejection of every unfamiliar object.

The input contract is float32 RGB NCHW `1×3×640×640`, aspect-preserving letterbox, padding 114 and pixel/255. Output is `1×46×8400`: four box channels plus 42 class scores, without objectness or embedded NMS. Class mapping comes from the publisher's separate class list because ONNX metadata contains numeric placeholders. All class mappings and runtime output shape/type checks have regression coverage.

The existing detector threshold 0.25, class-agnostic NMS 0.45, maximum 40 detections and scan minimum confidence 0.80 are unchanged. Tile multiplicity, row geometry, temporal agreement and human confirmation remain required. A high model score is not calibrated certainty.

Actual native tests have recovered all 14 annotated identities from a fixed development photo on both iOS and Android, and passed blank-image/repeat/dispose/reopen checks. Android also passed the YUV camera-stream path. These verify integration, not general recognition accuracy or physical-phone speed. Final build status and timings are in [BUILD_VALIDATION.md](BUILD_VALIDATION.md).

The model publisher's redistribution grant remains unresolved; AGPL metadata was inserted automatically by the exporting library. This is an authorised **local research/test integration**, with source notices retained, not a cleared public release. The README credits Jon Chan's dataset family, but its exact training version and image inventory remain unknown. See [the data and provenance audit](VISION_DATA_AUDIT.md).

## Pretrained comparison

The [full comparison](VISION_CANDIDATES_20261002.md) covers three YOLO11 sizes, AR42 and a ViT classifier. All models were tested rather than ranked from publisher claims.

| Fixed diagnostic | Previous YOLO11n V2 | AR42 |
| --- | ---: | ---: |
| Exact complete 14-tile regions in old development photos | 2/7 | 6/7 |
| Correct / extra / missed tiles in those photos | 117 / 8 / 21 | 137 / 0 / 1 |
| Tile precision on a different 156-image dataset | 69.0% | 78.1% |
| Tile recall on that dataset | 24.4% | 76.2% |
| Exact whole images on that dataset | 10/156 | 69/156 |

The old photos are small, correlated development material. The 156-image diagnostic contains 1,589 labels but no image with exactly 14 labelled tiles. Unknown upstream training overlap prevents a guaranteed unseen-data claim for either pretrained model. High-confidence wrong identities remain: AR42 has 85 wrong detections at confidence ≥0.80 on that dataset. Neither table establishes reliable live-camera locks.

The earlier 550-frame tile-carving documentary evaluation remains a historical V2 rejection diagnostic. It is not footage of a complete playing hand; none of its observations enabled confirmation. Its sources and preserved results are in [ONLINE_VISION_EVALUATION.md](ONLINE_VISION_EVALUATION.md).

Two further public offline artifacts were inspected and tested on the same development photos and actual video. Their packages were never installed and their downloaded Python/TypeScript sources were never executed; our evaluator loaded only verified ONNX files. Provenance, exact class maps and preprocessing are recorded in `vision/candidates/research/offline_candidate_review.json`.

| Additional candidate | Exact photo hands | Video identity matches | Extra video identities | Exact video rows |
| --- | ---: | ---: | ---: | ---: |
| [mahjong-detector 0.0.6](https://pypi.org/project/mahjong-detector/), 34-class YOLO11n, 10.6 MB | 0/7 | 1/260 | 22 | 0/20 |
| [Historical public RiichiCam model](https://github.com/MMitch42/RiichiCam/tree/8d13cbe40824c118278a7eca13e7b1d99a463d7e), 37 classes, 80.5 MB, single ROI | 4/7 | 225/260 | 29 | 0/20 |
| Same historical model with its documented row-window wrapper | 1/7 | 224/260 | 131 | 0/20 |

The first model's package uses grayscale/autocontrast and black padding; related author projects describe screenshot-focused training. Its MIT package metadata and embedded AGPL model metadata do not establish complete dataset/weight rights. RiichiCam's **current** service uses private weights; these results concern its distinct older public artifact, whose redistribution license and exact Roboflow dataset version were not found. The current private model was not accessed or evaluated.

Fixed confidence 0.25 and IoU 0.45 were used. Single-pass comparisons use our capped, clipped, class-agnostic decoder. The separate RiichiCam-wrapper experiment follows its 20% overlapping windows, per-class suppression/merge and lack of a detection cap or clipping; it is not a controlled tiling-only ablation. All calls were sequential in one two-thread CPU session. Integer Pillow resizing approximates the original browser's fractional Canvas interpolation. Six geometry/NMS/decoder tests protect that wrapper implementation. Single-pass RiichiCam inference took a desktop median 94.1 ms; its wrapper took 193.4 ms summed inference / 205.4 ms pipeline, versus the earlier AR42 measurement around 17 ms per inference. These are neither phone timings nor measurements of the current RiichiCam service. Neither extra model is integrated.

## Dataset acquired and grouped before training

RF100-VL Mahjong v2 supplies **2,135 images and 15,037 labelled boxes**. Download bytes and annotations were verified. Related originals and conservative duplicate candidates stay together: 1,619 training images, 360 development images and 156 reserved internal-test images. Sixty-nine groups crossed the publisher's original splits; those groups were promoted toward training/development, not divided or discarded to improve a score.

All 34 ordinary classes are represented. Physical tile-set and session identities are unavailable, so this is not an unseen-physical-set benchmark. Source notices, exact versions, class mapping and limitations are preserved in [VISION_DATA_AUDIT.md](VISION_DATA_AUDIT.md). The source manifest was locked before fitting and testing. Once results informed subsequent experiments, the 156 images were marked consumed; further adaptive comparisons are follow-up diagnostics, not new untouched tests.

The source is not a complete-row benchmark. The grouped training split contains only eight images with 14 annotations and eight with 17; the development split has six and two respectively; internal test has zero and one. Counts alone do not mean a legal hand or even a single row: an inspected 17-annotation training example shows scattered dot tiles. These exact counts are saved in `hand_count_coverage.json`. Learning individual detections from these scenes is useful, but task-matched row/video validation and more varied physical sets remain necessary.

## Actual MobileNet training and negative pipeline result

MobileNetV3 Small was trained locally from official general ImageNet weights for 12 precommitted epochs. It used 13,937 training crops, including background examples, and 3,468 development crops for checkpoint selection. Crops inherit their original-image groups. Augmentation changes physical orientation, scale, shear, blur and lighting; Chinese characters are never mirrored. The architecture, settings and development-only selection rule were fixed before reserved-test results.

| Measurement | Result and interpretation |
| --- | --- |
| Development checkpoint selection | 96.86% crop accuracy; 96.21% macro recall; epoch 12 |
| Reserved internal-test crops | 1,849/1,900 correct (97.32%), including 312 background crops |
| Ordinary faces only in that test | 1,537/1,588 correct (96.79%); one additional annotation smaller than 8 pixels was explicitly excluded |
| All evaluated foreground crops correct per source | 131/156 source images; true boxes supplied, **not whole-image detection** |
| Confidence ≥0.80 | 1,547 accepted foreground predictions, 25 wrong |
| Different-source Commons development crops | 117/138 correct (84.78%), with true face rectangles supplied |
| AR42 boxes followed by replacement classifier labels | Exact 14-tile regions worsen from 6/7 to 2/7 |

The classifier is **not installed in the app**. Its high same-source crop score did not translate to better complete-hand recognition. This negative result is retained instead of being hidden or presented as 97% scanner accuracy.

The Mac GPU run took 167 seconds. Its checkpoint SHA-256 is `3881dd8444e934c0cb2ff9e8d39f97e65ace09f34e0d66ed7ada3ae31f438c78`; configuration, history, locks, confusion matrices and all predictions are under `vision/runs/mobilenetv3_rf100_v1/`. A 6.23 MB ONNX research export passed logit/top-1 parity on 35 real development crops. Desktop CPU inference medians were 1.30 ms for one crop and 14.93 ms for 14 crops, excluding detection and camera work. These are not phone measurements.

Seven training-pipeline tests cover grouping, changed crop bytes, bounds, crowd/background exclusion, protected-image isolation and normalization. Twenty-seven provenance/validation tests cover source and label hashes, locks, transitive duplicate grouping, randomized oracle cases and risk arithmetic. They validate experiment machinery, not label truth or universal model accuracy.

## Completed detector training and cross-source failure

A separate YOLO11n detector completed 20 epochs from official generic COCO weights, using only the grouped RF100 training/development partitions. The [complete experiment report](../vision/training/detector_REPORT.md) preserves configuration, resource changes, checkpoints, selection and per-example results. The active training/validation time was 82.3 minutes, excluding preparation, build pauses and the timing probe.

The training framework's MPS validation suffered NMS timeouts. Those partial metrics were not used for final selection: all 13 preserved checkpoints from epochs 8–20 were revalidated on all 360 development images with timeout-free CPU NMS, under the same precommitted fitness criterion. Epoch 20 won. Early checkpoints 1–7 were unavailable; this is not a claim to have retrospectively compared every original epoch. Batch/worker reductions and deferred intermediate validation were recorded as resource repairs. The process deliberately exited after the verified epoch-20 save, before redundant post-training validation; the completion record does not misrepresent this as a normal trainer return.

| Fixed comparison | Current AR42 | Own 20-epoch detector |
| --- | ---: | ---: |
| RF100 consumed follow-up: correct / extra / missed tiles | 1,211 / 339 / 378 | 1,195 / 318 / 394 |
| RF100 tile precision / recall | 78.13% / 76.21% | 78.98% / 75.20% |
| RF100 exact images, varying counts | 69/156 | 88/156 |
| Different-source Commons matched tiles | 137/138 | 70/138 |
| Commons exact complete hands | 6/7 | 0/7 |
| Actual video exact ordered rows | 0/20 | 0/20 |

The new detector produced no detections at the fixed 0.25 threshold on any of the 20 video frames. A raw first-frame check confirms maximum class score 0.043, valid finite output and the expected shape before decoding; this is not a class-map failure. The more favorable exact-image count on the RF100 source therefore did not transfer to the different camera/photo conditions. This supports a **domain transfer failure**, not a proof of classical training overfit; the development curve was still improving. No fresh untouched-test or unseen-physical-set claim is made.

The detector is **not integrated**. Its 10,597,705-byte ONNX export has SHA-256 `1a78e66672b643b972f8836efab49c61b1256604d3d6d7f612629bd9b1d2400e`, 34 ordinary classes and no flower/red-five/unknown outputs. Torch/ONNX parity passed on three real development images, including exact decoded predictions. All training, checkpoint watchers and evaluation processes have exited; the artifacts remain available for a separately defined future experiment.

## Real hand-row video

A second source is actual Mahjong play: an eight-second excerpt of [Nicopro footage](https://commons.wikimedia.org/w/index.php?curid=74794134), by ニコプロ -ニコニコプロレスチャンネル-, licensed CC BY 3.0, also [published on YouTube](https://www.youtube.com/watch?v=s9g9TGOxxq8). Attribution, original source evidence and lossless trimming/crop details are in `vision/video_candidates/README.md` and `provenance.json`.

Two reviewers independently read the 13-tile row before inference. Twenty distinct frames at approximately 400 ms spacing were checked for unchanged labels and visibility. The fixed ROI, labels and presentation timestamps were pinned with reference hash `8b49ac8b4aa4ae5491f721c06ebe47e7e53f903a7e4e2f1588e016e4c8f4f940`. The source has 239 decoded frames; its container estimates 240, so the evaluator checks all explicitly annotated frame indices and does not invent another frame.

| Sampled video diagnostic | Previous YOLO11n V2 | AR42 |
| --- | ---: | ---: |
| Correct canonical identities, multiset matched over 20 frames | 199/260 | 225/260 |
| Extra/wrong identities | 30 | 32 |
| Missing/wrong identities | 61 | 35 |
| Entire ordered 13-tile row correct | 0/20 | 0/20 |
| Actual Dart confirmation gate accepted | None | None |

These are identity-multiset counts without per-frame IoU labels, not detection AP or independent hand-success trials. Adjacent frames from one set are correlated. The row is tilted, has 13 tiles and includes a red five; canonical comparison normalizes the red tile to an ordinary five because AR42 cannot preserve that attribute. It is a broadcast camera, not a handheld phone. It cannot demonstrate a successful 14/17-tile winning-hand scan or training independence.

The actual `ScanConsensus` code was replayed with original timestamps for all six UI counts and separately for 13 as a diagnostic configuration. For AR42 at 13, 17 frames failed confidence and three failed count. The replay and individual predictions are saved under `vision/video_candidates/`; `app/test/vision/real_hand_video_replay_test.dart` is the regression. No stills were duplicated to manufacture temporal evidence.

## Geometry-only follow-up (development)

A separate probe estimated the row's angle from detected box centres, without using the true tile labels, then rotated the crop and ran the same AR42 model again. The policy required at least five boxes, a robust single-row fit and an angle between 2 and 20 degrees. It used the same already exposed 20-frame clip.

It did not help: canonical identity matches fell from 225/260 to 220/260, extra/wrong identities rose from 32 to 40, and exact rows remained 0/20. This correction is **not integrated into the app**. Simple straightening was insufficient for these errors, and a second inference would add cost. Parameters and predictions are preserved in `vision/probe_row_deskew.py` and `vision/video_candidates/deskew-development-probe.json`.

A review also caught that the shared Python NMS helper returns detections in confidence order. The video evaluator now explicitly sorts by horizontal position before comparing an ordered row; two regression tests cover physical order and repeated/red-five identities. Superseded reports are preserved with hashes. The correction did not change the reported zero exact rows or any identity-multiset counts, and the actual Dart gate already sorted by position.

An overlapping-window probe tested more pixels per tile: two 60%-width crops with 20% overlap, midpoint ownership and the same confidence/NMS thresholds. It reached 7/7 exact hands on the old photo diagnostic, but the video worsened sharply to 115/260 identity matches, 110 extra/wrong identities and 145 misses, still zero exact rows. It is **not integrated**. This illustrates why even 7/7 on a small exposed photo set would not establish broad improvement. Three coordinate/ownership/NMS regression tests passed; the experiment is preserved in `vision/probe_row_windows.py` and `vision/video_candidates/windows-development-probe.json`.

Three fixed smaller-content probes also retained the 640-pixel model canvas and padding but shrank the row before inference. These were development follow-ups, not independent tests or retraining:

| Content longest side | Exact 14-tile photo hands | Video identity matches | Exact video rows |
| --- | ---: | ---: | ---: |
| Current 640 | 6/7 | 225/260 | 0/20 |
| 480 | 7/7 | 222/260 | 0/20 |
| 384 | 4/7 | 221/260 | 0/20 |
| 256 | 1/7 | 195/260 | 0/20 |

No tested scale improved both diagnostics, so the app preprocessing remains unchanged. The `scale*-development-probe.json` files preserve all predictions. These comparisons show sensitivity to tile scale; they do not establish a universally best scale or explain every failure.

## Historical V1 legacy-crop measurements

The historical reproducible diagnostic is `vision/evaluate_baseline.py`, with machine-readable predictions in `vision/reports/baseline.json`. It tests the original **V1 model**, not the current AR42 asset, on all 628 unique legacy crops; 540 are ordinary tiles covered by the model and 88 are unsupported flowers/seasons. Threshold is 0.25, class-agnostic suppression IoU is 0.45. Pillow and Dart's image library can differ slightly in bilinear interpolation, so this is not a bit-for-bit runtime equivalence test.

| Legacy crop diagnostic | Measured result |
| --- | ---: |
| Covered single-tile crops | 540 |
| Correct highest-confidence tile prediction | 4 / 540 (0.74%) |
| Exactly one detection with the correct face | 3 / 540 (0.56%) |
| No detection | 441 / 540 |
| Unsupported flower crops with an ordinary-tile prediction | 19 / 88 |
| Warm CPU inference median / 95th percentile | 18.8 / 29.6 ms |
| Image preparation + inference + decoding median / 95th percentile | 25.1 / 38.4 ms |

Timing uses this Mac's CPU, two ONNX Runtime inference threads, five warmup runs and Python ONNX Runtime 1.30.0. It excludes loading the model and camera capture. It is **not an iPhone or Android performance result**, and does not measure the Flutter bridge, peak memory, camera latency, battery use or thermal throttling.

The poor crop result is real, but is not a valid estimate of whole-hand accuracy: resizing one isolated tile to almost the entire 640-pixel input differs greatly from a row of 14 tiles. A controlled follow-up kept the same 540 faces, placed each on a gray 640×640 canvas, and changed only its pixel height. Results are recorded in `vision/reports/scale_probe.json`.

| Synthetic tile height | Correct top prediction | Exactly one correct detection | No detection |
| --- | ---: | ---: | ---: |
| 64 px | 321 / 540 (59.4%) | 321 / 540 | 111 / 540 |
| 128 px | 170 / 540 (31.5%) | 163 / 540 | 140 / 540 |
| 256 px | 5 / 540 (0.93%) | 4 / 540 | 367 / 540 |

This shows substantial V1 scale sensitivity. The synthetic 59.4% result is also **not** real-hand accuracy, nor evidence the model is ready for general use. It supports guided row capture as an appropriate test scenario and argues against close-up single-tile capture with this detector. The later online diagnostic supplies real annotated photos, but a larger test set with verified training independence and physical-set/session splits is still needed. No high-accuracy claim is currently justified.

## What was wrong with the old data pipeline

The audit found 629 CSV rows describing 628 images; `582.jpg` appears twice with the same label. Every image is 240×320. There are no exact-byte duplicate images, unreadable images, missing images, or filename overlap between the generated train/validation folders. This does not rule out near duplicates or images from the same physical set crossing the split.

CSV labels are 1–42. `train/formatfile.py` writes those values directly into YOLO labels, which must be zero-based. All generated IDs are shifted and ten labels use invalid class 42 for a 42-class detector. The audit corrects IDs for analysis without modifying the original files.

All 628 generated boxes cover the whole image. That can describe an isolated crop, but provides no examples of locating several faces in a camera frame. These labels must not be treated as annotations for hand detection. Training a new detector on them alone would preserve the central data problem.

The local CSV rows exactly match the upstream [Camerash dataset CSV](https://github.com/Camerash/mahjong-dataset/blob/master/tiles-data/data.csv), including ordering and duplicate; bytes differ because of formatting. Individual image provenance has not been proved by comparing every upstream file. The [upstream README](https://github.com/Camerash/mahjong-dataset) says the images mostly came from web image searches, eBay and Alibaba. Repository licensing alone does not establish the rights to every scraped source image. Keep these as a local diagnostic corpus until provenance is resolved.

## Earlier candidate survey (historical)

| Candidate | Verified information | Proposed use and limitation |
| --- | --- | --- |
| [Jon Chan Mahjong](https://universe.roboflow.com/jon-chan-gnsoa/mahjong-baq4s) | 42 classes including flowers; project lists 3,506 source images and version 83 lists 7,650 images; CC BY 4.0 label | Best first broader-class detection dataset to inspect. Version count may include augmentations; split source captures before augmentation and review provenance. Downloadable local weights have not been obtained. Hosted inference is not the offline app architecture. |
| [RF100-VL Mahjong](https://universe.roboflow.com/roboflow100vl-full/mahjong-vtacs-mexax-xwwj) | 2,127 images, 34 classes, MIT label | Secondary detector training candidate, with no flower coverage. Check original sources and class definitions before merging. |
| [Mobile-camera Mahjong photographs](https://www.kaggle.com/datasets/shinz114514/mahjong-hand-photos-taken-with-mobile-camera/data) | Linked as the selected model's training source | Useful to examine failure modes. It cannot automatically serve as an independent test set for that model; training overlap must be checked. License and exact version still need inspection. |
| [RF-DETR](https://github.com/roboflow/rf-detr) | Apache-designated package/models use Apache 2.0; Plus components have a separate license | Non-YOLO detection comparison. Nano has 30.5M parameters according to its publisher, so it is not assumed lighter or faster on a phone than YOLO11n. Train/evaluate on the same split. |
| [HaseLab pipeline](https://huggingface.co/HaseLab/mahjong-models) | Region detector → generic tile-face detector → ResNet-50 classifier, 39 classes including a back and special red white dragon | Useful architectural reference for separating localization and recognition. Not a 42-class Chinese flower recognizer. A clear license was not found in the model card, so do not redistribute its weights by assumption. |
| [MobileNetV3 Small](https://docs.pytorch.org/vision/main/models/mobilenetv3.html) | Official pretrained classification architecture | Lightweight classifier candidate behind a generic tile-face detector. ImageNet pretraining is not mahjong recognition. Train on crops extracted from rights-cleared real hand photos, including flowers and rejection examples. |

The next controlled comparison should be (A) a compact detector with every supported face class and (B) a generic face detector followed by a small classifier. Both must use the same physical-set/session-held-out evaluation. Quantize only after the full-precision baseline is measured; run output-parity and accuracy checks after every conversion. Core ML and Android CPU/GPU delegates should be timed on actual devices, not inferred from desktop GPU benchmark tables. [Ultralytics export documentation](https://docs.ultralytics.com/modes/export) describes available formats and calibration requirements.

## Data collection and acceptance protocol

Start with 20–30 original iPhone 13 Pro photos from the user's own set: a clearly visible row of 14 and 17 ordinary tiles, repeated identical faces, red/green/white dragons, a separate flower row, open pungs/chows and kongs laid apart. Include daylight, warm indoor light, moderate glare and a slanted view. Include a few blurred/occluded rows that the app should reject or ask to recapture. Avoid faces and private background content where practical. Preserve original resolution; do not crop all images down to one tile.

This is a diagnostic collection, not enough to certify universal accuracy. A training corpus needs several physical tile sets, fonts, phones, tables and sessions. Record source image, physical set ID, capture session, phone, lighting, orientation, visible face boxes, canonical identities and rights/consent. Keep an untouched test set grouped by physical set/session; derived crops and augmented versions inherit their source image's split.

For each candidate measure tile precision/recall, exact complete-row count and face accuracy, false acceptance of unsupported faces, manual corrections per row and rejection rate. Record per-class failures, especially white dragons and flowers. Also record cold load, end-to-end scan median/p95, peak memory and a sustained capture run on the iPhone and at least one representative Android device. Any target is a proposed release gate until measured; none is claimed achieved here.

## Reproducing the historical crop audit

From the repository root:

```sh
sh vision/fetch_baseline.sh
python3 -m venv .venv
.venv/bin/pip install -r vision/requirements.txt
.venv/bin/python vision/evaluate_baseline.py
.venv/bin/python vision/probe_tile_scale.py
cd app
../.tools/flutter/bin/flutter test test/vision
```

The baseline download script pins both repository commit and V1 model checksum. The evaluation does not train or change the legacy data. `vision/reports/baseline.json` includes the environment, model metadata, audit, per-class counts and individual predictions. `vision/model_manifest.json` records the current AR42 app contract; `vision/model_manifest_v1.json` and `vision/model_manifest_v2.json` retain the historical contracts. Follow the [online report](ONLINE_VISION_EVALUATION.md#reproduction) to reproduce V2 export and real-photo/video evaluation.

The original vision unit suite passed 18 tests, including V1's 37 class mappings and 100 seeded random 14-tile rows. Current tests are updated separately for V2/UNKNOWN and live capture. They check preprocessing channel order/padding, confidence boundaries, malformed outputs, nonfinite coordinates, repeated tiles, conflicting classes, clipping and physical order. A malformed three-byte image exposed an exception in the image decoder; the app now converts that exception into a recoverable format error. These tests verify input/output handling, not learned model accuracy; see the current build validation report for the final suite count.

The source repository has an MIT license. The historical V1 ONNX artifact explicitly embeds **AGPL-3.0**. V2 derives from Ultralytics YOLO11; our export adds an AGPL provenance annotation, without presenting it as an upstream checkpoint declaration. [Ultralytics' license guidance](https://www.ultralytics.com/license) describes its open-source and enterprise options. These models are for local experimentation; a release must deliberately resolve model distribution terms, retain relevant notices, or replace the model. A permissive repository label is not a substitute for checking model and training-data terms.
