# Real online photographs and video: measured diagnostic

Evaluated 2 October 2026. **The newer model is a better experimental starting point, but reliable automatic hand capture has not been demonstrated.** Manual confirmation remains necessary. This report records actual inference on public, licensed photographs and a real video; the earlier isolated-crop and synthetic-scale results are separate diagnostics.

## Models and export validation

Both models come from [nikmomo/Mahjong-YOLO at the pinned commit](https://github.com/nikmomo/Mahjong-YOLO/tree/28ffceed232ad95fd019c47a6c51ae7c78791a0e).

| Item | Original V1 | Selected V2 |
| --- | --- | --- |
| Upstream artifact | `models/nano/mahjong-yolon-best.onnx` | `trained_models_v2/yolo11n_best.pt` |
| ONNX size | 10,611,888 bytes | 10,600,801 bytes |
| ONNX SHA-256 | `3c7732c022d41c1a3f48cea931ce626416d92486ab5b86692312941d0cc22226` | `2b1adbdb6f395eba7ce755f87672c8a4275d6eeae68d26c5206ae6a89f4e628a` |
| Classes | 37 | 38, including UNKNOWN |
| Output | `1×41×8400` | `1×42×8400` |

V2 checkpoint SHA-256 is `ea35d50b9568fc67277538038e7c456b3f29ebd65e1de7bd141e5a1d3a9d0ff1`. It was exported locally using PyTorch 2.10.0, Ultralytics 8.3.162, ONNX opset 17, and a fixed `1×3×640×640` RGB input. The restricted `weights_only=True` loader permits an explicit reviewed list of library classes; no checkpoint-defined code or arbitrary pickle loading was used. Export and allowlist details are in [v2_export.json](../vision/reports/v2_export.json).

PyTorch versus ONNX comparisons passed on **all ten fixed real-photo regions**, including identical model class metadata, identical candidate top-class IDs above the detection threshold, and matching labels/boxes after NMS. Maximum raw coordinate difference was **0.00419 input pixels**; maximum class-score difference was **0.00001653**. The numeric tolerance was `rtol=1e-4, atol=1e-3`; normalized NMS boxes also passed `rtol=1e-5, atol=1e-5`. These checks establish export parity, not equivalence between desktop Pillow interpolation and the phone camera pipeline. See [parity records](../vision/reports/v2_export_parity.json).

The app asset is `app/assets/models/mahjong-yolo11n-v2-2b1adbdb.onnx`. UNKNOWN is model index 34 and maps to app tile `-1`; red fives are indices 35–37, with the red flag retained. Ordinary classes remain indices 0–33 in the model's interleaved order. Flowers, seasons, jokers and backs are unsupported.

## Fixed photo set and evaluation method

Seven original photographs contain **ten annotated regions and 138 visible tile faces**. Eight regions depict a player's hand or concealed row; seven have 14 tiles and one has only 13 visible concealed tiles. Two other regions contain 18 example tiles or nine tiles in pungs. A 14-tile region need not be a winning hand under a particular ruleset; this evaluation checks visible faces, not scoring.

Tile identities, visible-face boxes and crop coordinates were manually fixed before inference, at `2026-10-02T11:14:25Z`. There is one annotator, so boundary and transcription uncertainty remain. The [annotation file](../vision/reports/online_annotations.json) gives original upright-image pixel coordinates. The [source manifest](../vision/reports/online_sources.json) pins page IDs, original URLs, revision timestamps, authors, licenses, dimensions and SHA-256 hashes. No benchmark photographs were used for training or fine-tuning.

The set was selected for legible physical tiles, accessible licensing and varied framing, not sampled randomly. Four rows are crops of the same `Ting-de-base` photograph; three gray-table photographs likely share one physical tile set. This is a small, correlated convenience diagnostic. It also became a **development/model-selection set** when V2 was chosen; it is not an untouched release test. The publisher is independent of the model repository, but training overlap is **unknown** because a per-image upstream training manifest is unavailable. No flowers, red-five accuracy, phone diversity or temporal hand stability are covered by these photos.

The row crops from `Ting-de-base` tightly exclude neighboring rows and have aspect ratios around 8–10:1. They are **not simulations of the live 3.2:1 guide**. `orphans-table-hand`, `chinitsu-table-hand` and `ron-concealed-row` use approximately 3.2:1 crops, selected to include the whole visible hand and a margin. The first two include a separated tile above the main row. The close-up two-row layout is explicitly a stress case. Results are reported for these fixed regions; crop coordinates were not optimized after seeing predictions.

Each crop uses RGB aspect-preserving bilinear resize to a 640×640 canvas, padding 114, float32 divided by 255. Detection confidence threshold is 0.25, class-agnostic NMS IoU is 0.45, maximum detections is 40. Boxes are restored to crop-normalized coordinates.

Hungarian assignment matches detections to ground truth at **IoU ≥ 0.50 and the correct canonical identity**, maximizing match count first and overlap second. Each tile/detection can be used once. Unmatched predictions are false positives; unmatched labels are false negatives. A wrong identity therefore creates both. Exact-region success requires every tile to match, no extra predictions, and the correct count. Face-multiset equality is also recorded separately; it happens to give the same totals here. Class-agnostic matching records identity confusions. These are fixed-threshold precision/recall results, **not mAP**. Five boundary/global-matching unit tests validate the evaluator.

## Actual photo results

| Metric on the same fixed regions | V1 | V2 |
| --- | ---: | ---: |
| Correct matched tiles / 138 | 108 | 117 |
| Extra/wrong detections | 13 | 8 |
| Missing/wrong tiles | 30 | 21 |
| Tile precision | 89.3% | 93.6% |
| Tile recall | 78.3% | 84.8% |
| Exact regions, including group scenes | 1 / 10 | 3 / 10 |
| Exact hand/row regions, including the 13-tile row | 1 / 8 | 2 / 8 |
| Exact 14-tile hand regions | 1 / 7 | 2 / 7 |
| Regions eligible by expected count and minimum confidence 0.80 | 0 | 0 |
| Model-only Mac CPU median / p95 | 18.0 / 22.2 ms | 18.4 / 21.5 ms |

Timing uses Python ONNX Runtime 1.30.0, CPUExecutionProvider, two inference threads, five warmups and ten timed runs per region. These are local measurements, not phone speed, camera latency, battery or thermal results. Small differences between runs are not evidence that one model is faster.

V2 recovers the entire first `Ting-de-base` row, all nine tiles in the pungs example, and all 14 circles in `chinitsu-table-hand`. It is worse than V1 on some individual regions, including the second ting row and the 13-tile ron row. Its mistakes include a bird-style 1s interpreted as red dragon, West interpreted as South/green dragon, white dragon interpreted as a character/West, and 7m/9m interpreted as 6m. Several tiles are missed entirely. The rotated West and upside-down character tiles are useful failure examples; the set is too small to assign reliable per-class rates.

Machine-readable [V1 results](../vision/reports/online/yolo11n-v1-results.json) and [V2 results](../vision/reports/online/yolo11n-v2-results.json) contain all detections, confidences, matching assignments, confusion counts and individual failures. The [V2 overlay contact sheet](../vision/reports/online/yolo11n-v2-contact-sheet.jpg) uses green ground-truth boxes and orange predictions. A correct-looking row alone is insufficient evidence: `orphans-table-hand` has 14 V2 detections but four wrong identities.

## Genuine video diagnostic

The documentary [手雕麻将“末代女师傅”：方寸之间刻琢半世情怀](https://www.youtube.com/watch?v=PLIHWYxBfrE), by 中国新闻网, is available under CC BY 3.0 from its [Wikimedia Commons mirror](https://commons.wikimedia.org/wiki/File:2021%E5%B9%B44%E6%9C%881%E6%97%A5_%E6%89%8B%E9%9B%95%E9%BA%BB%E5%B0%86%E2%80%9C%E6%9C%AB%E4%BB%A3%E5%A5%B3%E5%B8%88%E5%82%85%E2%80%9D%EF%BC%9A%E6%96%B9%E5%AF%B8%E4%B9%8B%E9%97%B4%E5%88%BB%E7%90%A2%E5%8D%8A%E4%B8%96%E6%83%85%E6%80%80.webm). The mirror was downloaded directly without bypassing YouTube controls. Its original SHA-256 is `7972c9a10fd5522ef875db2237cce23e4e0705e2013f822cd319fe10e1956feb`; full provenance is in [online_video_source.json](../vision/reports/online_video_source.json).

The actual 640×360, 25 fps video was decoded, and **550 distinct frames at approximately 2 fps** were evaluated over its full 275-second duration. Every frame used the same centered 92%-width, 3.2:1 crop, before 640×640 letterboxing. Frames were not duplicated or synthesized. This film shows carving, interviews, decorative tiles and displays; it is **domain/rejection footage, not a video of a complete hand positioned for this app**. It has no exhaustive per-tile annotations, so no video precision, recall or exact-hand accuracy is claimed.

V2 returned zero detections on 485 sampled frames and one or more detections on 65. None of the 550 frames simultaneously met a supported expected count (2, 5, 8, 11, 14 or 17) and minimum detection confidence of 0.80. Therefore none could satisfy the app's stricter stability gate. The Python script computes these necessary conditions only. **A separate downstream Flutter test then replayed all 550 timestamps through the actual Dart `ScanConsensus` for all six expected counts: no frame was confirmed.** The passing regression is [public_video_replay_test.dart](../app/test/vision/public_video_replay_test.dart); this is 3,300 real-observation gate checks, not 3,300 independent video samples. Video inference-only Mac CPU median/p95 was 15.6/18.4 ms. The [video overlays](../vision/reports/online/video-v2-contact-sheet.jpg) show fixed sample times, including false predictions on decorative characters.

The [per-frame output](../vision/reports/online/video-v2-results.json) supports actual Dart consensus replay. Each record includes original frame index, `timestamp_ms`, RGB-frame hash, original pixel `roi`, and `predictions`. Each prediction provides `tile` in canonical notation, `tile_index` (0–33, or -1 for UNKNOWN), `red_five`, confidence, original model class name/ID, and `box = [left, top, right, bottom]` normalized to the crop. Sort by horizontal center if needed; `ScanConsensus.observe` itself sorts. All timestamps come from original video positions, not wall-clock inference duration.

## What the stability result means

The app's intended gate requires five agreeing frames spanning at least 1.2 seconds, correct user-selected count, minimum confidence 0.80, physically plausible tiles, row arrangement and stable boxes. No photo is eligible even before the temporal checks, and the real video provides no eligible frame. **No successful live hand lock has been demonstrated by this evaluation.** Duplicating a correct still five times would not change that and was not used.

No false acceptance was observed under the necessary confidence/count conditions. This does not establish a low false-accept rate: high-confidence persistent misclassifications can pass temporal agreement, and high-confidence photo crops with missing ground-truth labels could be misleading. Confidence is a model score, not calibrated probability that the whole hand is correct. Do not reduce the threshold just to make these examples lock. Keep final visual confirmation and manual correction; obtain a real complete-hand motion sequence before claiming a dependable live scanner.

## Attribution and derivative images

All crops, bounding-box overlays, rotated inspection details and contact sheets are adaptations/compilations of the following photographs. Original copyrights remain with the named authors. The individual photo adaptations retain their source license; the combined photo contact sheets are provided under CC BY-SA 4.0, with the original attribution and license information retained below. The video frame contact sheets/overlays retain CC BY 3.0 attribution to 中国新闻网. Changes made here are cropping, scaling, inspection rotation and annotation overlays. No endorsement by the authors is implied.

| Source | Author | License |
| --- | --- | --- |
| [13yao.JPG](https://commons.wikimedia.org/wiki/File:13yao.JPG) | Oscarcwk | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| [Ting-de-base.JPG](https://commons.wikimedia.org/wiki/File:Ting-de-base.JPG) | Dominique D'Issy | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| [Série-ma-jiang.JPG](https://commons.wikimedia.org/wiki/File:S%C3%A9rie-ma-jiang.JPG) | Dominique D'Issy | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| [Triples-ma-jiang.JPG](https://commons.wikimedia.org/wiki/File:Triples-ma-jiang.JPG) | Dominique D'Issy | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| [13orphans.jpg](https://commons.wikimedia.org/wiki/File:13orphans.jpg) | Cangjie6 | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |
| [Monzen chin'itsu.jpg](https://commons.wikimedia.org/wiki/File:Monzen_chin%27itsu.jpg) | HIBIKIFL | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
| [Mahjong ron.jpg](https://commons.wikimedia.org/wiki/File:Mahjong_ron.jpg) | kei51 | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |

The model repository carries MIT copyright © 2024 Shin Zhang. Ultralytics has separate [AGPL/commercial model licensing](https://www.ultralytics.com/license); the export's AGPL provenance annotation was added by us and is not presented as an upstream checkpoint declaration. MIT and AGPL notices are retained under `app/assets/licenses`. Dataset/media permissions and model licensing are separate questions.

## Reproduction

The source/model fetchers verify pinned hashes. Originals live in the ignored `vision/data` and `vision/downloads` folders. Keep the checked-in source and annotation manifests; fetching again must not silently relabel or replace the benchmark. The annotation-construction script documents the manual coordinates; do not regenerate its timestamp/hash unless intentionally issuing a new annotation version.

```sh
.venv/bin/pip install -r vision/requirements-export.txt
sh vision/fetch_baseline.sh
sh vision/fetch_v2.sh
.venv/bin/python vision/fetch_online_evaluation.py
.venv/bin/python vision/fetch_online_video.py
.venv/bin/python vision/export_v2_weights_only.py
.venv/bin/python vision/check_v2_export_parity.py
.venv/bin/python vision/test_evaluation.py
.venv/bin/python vision/evaluate_online.py --name yolo11n-v1
.venv/bin/python vision/evaluate_online.py --model vision/downloads/mahjong-yolo11n-v2.onnx --name yolo11n-v2
.venv/bin/python vision/evaluate_online_video.py
cd app
../.tools/flutter/bin/flutter test test/vision/public_video_replay_test.dart
```

Export serialization and timings can vary with environment. Check the generated ONNX hash, class metadata and parity report before replacing an app asset. No training or fine-tuning is performed by these scripts.
