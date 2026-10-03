# Vision data acquisition and leakage audit

This audit prepares a **training-disjoint internal diagnostic**, not an unseen-phone, unseen-session, or unseen-physical-tile-set benchmark. Unknown identities stay null. The existing Commons photos and video were already used to choose models and remain development material.

## Acquired source

RF100-VL Mahjong version 2 was acquired from the public [LibreYOLO redistribution](https://huggingface.co/datasets/LibreYOLO/rf100-vl), revision `1987e22ed542539fb3d0b8a3456455c2725079a1`. No account, API key, or gated-download workaround was used. The exact archive is 1,911,848,960 bytes; its computed SHA-256 matches the published `f2352bc102a8f177b886d57e1acfe2d5b53c27b137e6f2f79fe9a6c010db598e`.

The [primary RF100-VL project](https://universe.roboflow.com/rf100-vl/mahjong-vtacs-mexax-m4vyu-sjtd) lists 2,135 images and 34 tile classes. The archive retains Roboflow's per-dataset README, COCO license entries, and export metadata. The export describes auto-orientation with EXIF orientation stripping and no image augmentation. Its `date_captured` fields match export timestamps and must not be interpreted as camera-session identifiers.

The current project, archive README, and COCO metadata declare **MIT**. A [Roboflow training article](https://blog.roboflow.com/train-rf-detr-on-a-custom-dataset/) instead calls the dataset Apache-2.0; that inconsistency is recorded rather than silently resolved. These are publisher license declarations, not verification that the uploader owns every image. Source metadata and notices are preserved under `vision/datasets/sources/`.

The [RF100-VL paper](https://arxiv.org/abs/2505.20612) cites [Roman Nguyen's Mahjong project](https://universe.roboflow.com/roman-nguyen/mahjong-vtacs). This source chain does not identify each photographed tile set, capture session, or camera. Visual samples from the training split show real tiles on desks, floors, packaging and other backgrounds; visual resemblance is insufficient to assign a verified physical-set ID.

## Class mapping and files

Raw files are at `vision/datasets/rf100vl_mahjong/{train,valid,test}/`, with `_annotations.coco.json` in each directory. COCO boxes use `[x, y, width, height]` in the supplied image's pixel coordinates. Do not independently EXIF-rotate these images after loading their boxes.

| Source COCO IDs | Source names | Canonical labels |
|---|---|---|
| 0–8 | Bamboo 1–9 | 1s–9s |
| 9–17 | Character 1–9 | 1m–9m |
| 18–26 | Circle 1–9 | 1p–9p |
| 27 | East | 1z |
| 28 | Green dragon | 6z |
| 29 | North | 4z |
| 30 | Red dragon | 7z |
| 31 | South | 2z |
| 32 | West | 3z |
| 33 | White dragon | 5z |

There are no flower, season, red-five or unknown classes in this source. The classifier output order is separately declared in the generated manifest; it is not the COCO category order.

## Split policy

1. Keep all boxes/crops/augmentations descended from one source image in one split.
2. Join shared pre-`.rf.` source filename roots, equal JPEG bytes, equal decoded pixels, and conservative perceptual duplicate candidates transitively.
3. Join all dHash64 candidates at Hamming distance ≤4. Also join same-aspect pairs with pHash64 distance ≤6 and 32×32 RGB mean absolute difference ≤12/255. These heuristics may over-group similar backgrounds and miss different crops, lighting or angles.
4. Preserve upstream split membership except that a connected group containing training material moves entirely to `train`; a remaining group containing validation material moves entirely to `dev`. Only test-only groups remain `internal_test`.
5. Leave camera capture, session and physical-set identities null. This split does not establish separation by those unknown attributes or prove disjointness from a pretrained model's training set.

The audit checks file integrity, category consistency, image dimensions and box geometry. It does not claim exhaustive human relabelling. Inspection uses training images only. The internal test manifest should be locked before the chosen candidate is evaluated, and repeated model selection must continue to use development data.

## Reproduce

```sh
./vision/datasets/fetch_rf100vl.sh
.venv/bin/python vision/datasets/audit_rf100vl.py
```

The fetch helper resumes downloads and verifies the pinned checksum before extraction. Extraction rejects absolute/traversing paths, symlinks, hardlinks, special files, duplicate members and unexpected file types. `--partial` extraction is available only for early inspection and is explicitly marked unverified; the audit refuses it.

Generated outputs include an enriched `image_manifest.json` with source boxes and training groups, a strict `validation_manifest.json` for the independent leakage validator, `audit_summary.json`, the grouping graph, and split-specific image lists. All asset paths are relative to the project root. Crop builders must inherit each source record's split and group.

## Measured result

| Split | Original images / boxes | Grouped images / boxes | Classes covered |
|---|---:|---:|---:|
| Train | 1,494 / 10,440 | 1,619 / 10,700 | 34/34 |
| Development | 427 / 2,902 | 360 / 2,748 | 34/34 |
| Internal test | 214 / 1,695 | 156 / 1,589 | 34/34 |
| Total | 2,135 / 15,037 | 2,135 / 15,037 | 34 |

- All 2,135 image dimensions match COCO; all 15,037 boxes passed positive-size, finite-value and image-boundary checks.
- No exact JPEG-byte or decoded-pixel duplicate was found. The visual audit produced 268 dHash candidate links and 322 additional pHash/colour candidate links, resulting in 1,772 graph components. These are conservative candidate groups, not proof that every linked image is the same photograph.
- There are 110 components containing multiple images; the largest contains 48. Sixty-nine components cross the original splits, requiring 128 images to change destination. Related images were kept together rather than discarded or split to balance counts.
- Training/development/internal-test classes have at least 240/63/30 boxes respectively. Class coverage alone does not establish variation in cameras, lighting or physical tile artwork.
- Exact SHA-256 and dHash≤4 checks against the pinned legacy development originals found no candidate match. This does not detect every crop/angle derivative and does not establish unknown pretrained-data independence. Evidence: `legacy_overlap_audit.json`.
- Strict manifest canonical SHA-256: `02989763bbafaf7182c0af1019f15aa2c5529046a32be54c2fc2e75c4957d144`. The separate validation agent verifies and locks this manifest before candidate evaluation.

## Other sources reviewed

- [Jon Chan's 42-class Mahjong project](https://universe.roboflow.com/jon-chan-gnsoa/mahjong-baq4s) declares CC BY 4.0 and includes flowers/seasons. [Version 83](https://universe.roboflow.com/jon-chan-gnsoa/mahjong-baq4s/dataset/83) contains 7,650 augmented examples from fewer source images, with flips, rotation, shear, colour changes and blur. No ungated annotated archive was acquired in this pass; a public project page is not the same as a verified downloadable data bundle. Any future acquisition must reunite augmentation siblings before splitting.
- [ShinZ's mobile-camera dataset](https://www.kaggle.com/datasets/shinz114514/mahjong-hand-photos-taken-with-mobile-camera) is publicly listed by Kaggle as MIT, version 1, approximately 2.23 GB. [Nikmomo's model repository](https://github.com/nikmomo/Mahjong-YOLO) identifies it as training data for the existing candidate family, so it cannot be treated as independent evaluation for those weights. It was not downloaded here.
- [Camerash's dataset](https://github.com/Camerash/mahjong-dataset) is labelled MIT but explicitly describes images scraped from Google image search, eBay and Alibaba. It supplies tile classification crops rather than a well-provenanced phone-session detection holdout, and is not added to this training set.

Machine-readable evidence is retained in `vision/datasets/rf100vl_mahjong/audit_summary.json`, `duplicate_edges.json`, `duplicate_groups.json`, `split_promotions.json`, `validation_manifest.json`, and `sources/provenance.json` (the last path is relative to `vision/datasets/`).

## Appendix: AR detector provenance and redistribution review

Reviewed on 2026-10-02. The candidate is `server/models/yolo/weights.onnx` from [LYiHub/AR-Mahjong-Assistant-preview at commit e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299](https://github.com/LYiHub/AR-Mahjong-Assistant-preview/tree/e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299). The exact file is 12,270,403 bytes, SHA-256 `63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a`. It is a 42-class YOLOv8n ONNX export; the publisher's adjacent `class_names.txt` supplies the tile names because the graph metadata contains numeric class strings.

### What the publisher documents

The [pinned README](https://github.com/LYiHub/AR-Mahjong-Assistant-preview/blob/e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299/README.md) credits [Jon Chan's Mahjong dataset](https://universe.roboflow.com/jon-chan-gnsoa/mahjong-baq4s) as supporting its computer-vision training. Therefore the dataset **family is documented**, while the exact training version, image list, split, preprocessing, base checkpoint and training recipe remain unknown. Do not describe provenance as wholly unknown, or assume that a differently named dataset is independent.

The ONNX export reports Ultralytics 8.0.196 and an export timestamp of 2025-11-22. This predates Jon Chan version 83's displayed generation date of 2025-11-26, so the currently visible version 83 is not established as this checkpoint's training export. A timestamp embedded by software is not a verified training history. The GitHub weight history contains one initial commit dated 2026-02-13; it supplies no earlier training lineage.

The full pinned repository tree has 235 entries and no `LICENSE`, `COPYING`, or `NOTICE` file. The README has no explicit repository/model license grant, and GitHub's repository API reports `license: null`. The different repository named in its installation instructions, `fAres4s/ARmahjongAssist`, returned HTTP 404 through the public GitHub API. Three public issue bodies did not provide a license or training recipe. These observations describe the reviewed evidence, not proof that no separate permission exists.

### Why the embedded license field is insufficient

The ONNX metadata says `AGPL-3.0 https://ultralytics.com/license` and names Ultralytics as author. The [matching Ultralytics v8.0.196 exporter](https://github.com/ultralytics/ultralytics/blob/v8.0.196/ultralytics/engine/exporter.py#L230) hardcodes both fields when exporting models. Thus those strings are evidence of the export tool's default labelling; they do not independently verify the trained checkpoint publisher's rights or supply missing corresponding source.

Jon Chan's project declares CC BY 4.0. That license allows sharing and adaptation subject to attribution and other conditions, but it does not establish that this separate trained checkpoint is offered under CC BY or verify every image's ownership. The [Creative Commons deed](https://creativecommons.org/licenses/by/4.0/) also notes that other rights can require additional permission.

Public GitHub availability is not a substitute for a grant. [GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) distinguishes the platform's view/fork permissions from a license to reproduce, distribute or create derivatives.

### Local testing and an eventual downloadable app

| Intended use | Conclusion from the available evidence |
|---|---|
| Technical desktop/native comparison | The ONNX format is technically usable; performance results do not resolve permissions. Keep it identified as a research candidate with unresolved publisher licensing. |
| Private local use under a valid AGPL grant | AGPL section 2 permits running the unmodified program and non-conveyed covered works while the license remains valid. Private experimentation alone is not an automatic obligation to publish everything. This is conditional: the exact checkpoint's valid grant and rights chain have not been established here. |
| Bundling weights in a downloadable iOS/Android app | Redistribution is not cleared by the evidence found. Obtain an explicit grant covering these weights and a workable source/compliance route, or use a replacement with documented rights and reproducible provenance. |
| Proprietary commercial release | Do not assume an Ultralytics enterprise license alone clears a third-party author's checkpoint or underlying image rights. The scope of all necessary grants must be confirmed. |

The [AGPL text](https://www.gnu.org/licenses/agpl.en.html) distinguishes private running from conveying copies: sections 5–6 address covered source/object-code distribution and corresponding source; section 13 addresses modified versions offered over a network. AGPL is not categorically a non-commercial license. [Ultralytics' current licensing page](https://www.ultralytics.com/license) states its broader vendor position that trained/fine-tuned YOLO models default to AGPL and proprietary integration needs its enterprise terms. That position is recorded separately from the license text and from the absent third-party checkpoint grant. The exact scope for a shipped app requires resolution before release; this audit makes no blanket legal clearance claim.

Evidence is preserved under `vision/datasets/sources/`: `ar-pinned-README.md`, `ar-pinned-tree.json`, `ar-github-repository.json`, `ar-weight-history.json`, `ar-linked-original-repository.json`, `ar-public-issues.json`, `ar-onnx-metadata.json`, `ultralytics-v8.0.196-exporter.py.txt`, and `agpl-3.0.txt`. This review did not modify or integrate a model into the app.
