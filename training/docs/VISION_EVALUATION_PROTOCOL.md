# Measuring vision improvement without hiding overlap

Protocol v1, 2026-10-02. This defines how to evaluate future candidates; it does not claim that a candidate has passed. The previous **2/7 exact 14-tile regions** is a small development diagnostic, not a generalization score. All seven original public photographs and the documentary video are now explicitly pinned to `dev` in [legacy_development_manifest.json](../vision/validation/legacy_development_manifest.json). Crops, frames, augmentations, and re-encodings inherit that status.

## Four different claims

| Partition | Allowed use and claim |
| --- | --- |
| `train` | Fit weights and learn preprocessing. Generate training augmentations only after assigning original groups. |
| `dev` | Choose architecture, checkpoint, crop policy, calibration, confidence/NMS/temporal thresholds and stopping point. Report development performance honestly. |
| `internal_test` | Newly withheld from this training and selection run, with all known source/duplicate relationships kept together. Unknown capture or physical tile-set identities are permitted and reported; this does **not** establish unseen-tile-set performance. |
| `holdout` | A separately collected, unexposed external test with known capture/session/physical-set IDs and pinned labels, withheld as entire connected groups. Supports an unseen-physical-set claim relative to the recorded local training collection, subject to provenance completeness. |

`quarantine` is for unresolved data/label/rights problems; `unassigned` is an intake state. Neither is used for model fitting or reported tests. Splits are separate from `upstream_training_status`: `unknown`, `known_in_training`, or `verified_disjoint`. An independent publisher, a new download, or a local split does not prove absence from a pretrained model's data. Record the base model/checkpoint hash and the evidence for any verified-disjoint claim in the experiment report. Starting from general ImageNet/COCO weights avoids inheriting known mahjong fine-tuning exposure but does not prove every pretraining image is disjoint.

The separation of model selection from final evaluation, and the use of group-aware splitting for related observations, follow the [scikit-learn evaluation guidance](https://scikit-learn.org/stable/modules/cross_validation.html). This protocol adds project-specific provenance and temporal checks.

## Machine-readable contract and grouping

[manifest.schema.json](../vision/validation/manifest.schema.json) describes JSON structure; [manifest.py](../vision/validation/manifest.py) additionally checks semantic constraints. The document has `schema_version: 1`, a `manifest_id`, and nonempty `records`. Each record requires:

| Field | Meaning |
| --- | --- |
| `id`, `path` | Unique record ID and file path relative to the verification root. Paths cannot escape the root, including through symlinks. |
| `source_image` | Stable, namespaced identity of the original source image/video. Do not substitute a crop's generated filename. |
| `parent_ids` | IDs of immediate derivation parents, including every source of a mosaic. Parents must be present; cycles are rejected. |
| `parent_capture`, `session_id`, `physical_tile_set` | Actual known identities; use JSON `null` when unknown. An export timestamp is not a capture session. |
| `dataset_version` | Pinned source dataset/export/revision. Versions do not exempt duplicates from grouping. |
| `sha256`, `source_sha256` | File bytes and root-source bytes. An original may use the same hash for both. A multi-source composite lists all parents. |
| `split`, `exposure` | Partition plus prior use: `unexposed`, `development`, or `training`. Previously exposed data cannot become either untouched test partition. |
| `upstream_training_status` | Pretraining overlap status, independently of this project's split. `verified_disjoint` requires `upstream_evidence`. |
| `near_duplicate_clusters` | Namespaced candidate groups from visual/manual duplicate review; a record may join several groups. |

Optional `dhash64` is the upright 64-bit difference hash produced by the supplied fingerprint helper. Optional `annotation_path` and `annotation_sha256` must appear together. Strict `holdout` requires pinned annotations; an internal test must also pin its annotation files before making a final scored claim. `notes` records qualifications or upstream split promotions.

Connected components join **any** shared source image, known capture/session/tile set, derivation parent, exact source/asset hash, declared near-duplicate cluster, or dHash Hamming distance ≤4. Connections are transitive: if A resembles B and B resembles C, all three stay together even if A and C do not directly match. Existing explicit splits are preserved; remaining cross-split conflicts fail validation. A dataset importer may explicitly promote a contaminated upstream test component to train/dev, recording that policy and the resulting smaller test denominator. Do not silently discard hard test examples or reshuffle until scores improve.

dHash is only a conservative candidate screen: low-detail tiles can over-group, while crops, rotations or major appearance changes can evade it. Add source lineage and manually reviewed clusters, optionally using other similarity methods. Unknown provenance and undetected duplicates remain limitations. Do not claim the validator proves all possible duplicates absent. Known physical-set grouping is stricter than capture grouping; if one set connects most images, accept that few independent groups exist rather than splitting it to manufacture a large test.

## Freeze before selection, then use once

1. Collect originals with licensing/provenance; annotate visible identities and face boxes without consulting candidate predictions. Resolve difficult labels with a second reviewer when available; retain unresolved cases as explicitly uncertain, not silently correct.
2. Audit the **combined** candidate-training, legacy-development and proposed-test inventory. A separate audit of each dataset cannot catch cross-dataset duplicates. Keep existing public examples in dev. Source/duplicate grouping precedes all crops and augmentations.
3. Freeze the manifest, original bytes and annotations. The `lock` command verifies files and writes an exclusive new lock file containing canonical manifest/policy hashes, protected IDs and audit counts. Publish the lock hash and version in the experiment record before fitting/selecting candidates. A checksum detects accidental edits; it is not a signature or an access-control system.
4. Train and select using train/dev only. Select checkpoint, preprocessing, all thresholds and the app's temporal policy before reading internal-test or holdout predictions. Record a candidate SHA-256 and the frozen decision policy before the final test.
5. Verify the lock and bytes, then run the selected candidate once on the test. If failures inform another change, retire that test to dev for subsequent claims and collect a new untouched test. Keep the original report rather than overwriting the unfavorable result. Merely rerunning identical inference for reproducibility is different from selecting a new candidate using its outcomes.

The test loader must filter `internal_test`/`holdout` out of **both** fitting and checkpoint/threshold selection. Validation-image crops cannot enter training. Label-based class weights and normalization statistics must come from train only. All benchmark/diagnostic predictions used to make a design decision count as exposure, even if the images were never used for gradient updates.

The classifier's separate selection lock requires `schema_version: 1`, a timezone-aware `selected_at`, `checkpoint_sha256`, `evaluation_manifest_sha256`, `source_manifest_path`, `source_lock_path`, `source_lock_sha256`, `source_split_manifest_path`, sorted unique `thresholds`, and an `operating_threshold` from that list. The SHA fields here hash the raw files; the source lock also contains its own canonical manifest/policy hashes. Paths are relative to the repository verification root. [evaluate_classifier.py](../vision/training/evaluate_classifier.py) verifies the source lock, image and annotation bytes, the training configuration's actual source-split file, and every crop's original/split/group identity before protected evaluation. The selected crop manifest must be generated and pinned before reading predictions. An experiment can predeclare several model training/selection procedures together, provided none changes after any shared test results are disclosed; record the exposure ledger.

From the repository root:

```sh
python3 -m unittest discover -s vision/validation -p 'test_*.py' -v
python3 -m vision.validation.manifest audit path/to/combined-manifest.json
python3 -m vision.validation.manifest split path/to/intake.json --seed experiment-v1 --output path/to/split-v1.json
python3 -m vision.validation.manifest lock path/to/split-v1.json --root . --output path/to/split-v1.lock.json
python3 -m vision.validation.manifest verify path/to/split-v1.json --root . --output path/to/split-v1.lock.json
```

The default splitter assigns approximately 70/15/15 percent of groups to train/dev/internal_test; it never creates strict external holdout automatically. It preserves fixed splits and marks previously exposed connected groups train/dev. Ratios are not guaranteed per-file counts or class balance. Inspect resulting class, group and stress-stratum counts before freezing; missing classes are a sampling limitation. Never split a connected group to fill a quota. After a lock, adding records/relationships/labels requires a new manifest version and a new experiment record.

## What to measure

For still photographs, keep the same fixed regions and preprocessing for every candidate. Use one-to-one matching of predicted face boxes and identities at IoU ≥0.50, with unmatched predictions counted as false positives and unmatched annotations as false negatives. Report per-class confusion/support, fixed-threshold tile precision/recall, exact face multiset, and **exact ordered row** (all visible supported tiles, correct order/count, no extras). Localization-exact success and identity/count-exact success are separate fields; do not call fixed-threshold recall “mAP.” A classifier tested on ground-truth crops measures identity recognition conditional on perfect localization, not end-to-end hand capture. Rows assembled synthetically from independent crops remain synthetic diagnostics.

For genuine live sequences, replay original timestamps through the actual Dart pipeline. One evaluation unit is a predeclared capture attempt, with a maximum duration (initial proposal: 10 seconds from the first complete eligible view), and at most one **first accepted lock**. Repeated frames, adjacent video windows, repeated manual retries and identical stills are not independent attempts. Partition and uncertainty analysis retain session/physical-set clusters. Ground truth includes changes during the sequence; a lock on the previous arrangement after tiles change is wrong.

| Metric | Denominator and interpretation |
| --- | --- |
| Coverage | Accepted attempts / all attempts; state in-scope and negative/stress coverage separately. |
| Selective wrong-acceptance risk | Wrong first locks / accepted attempts. Undefined if nothing is accepted. |
| Unconditional wrong acceptance | Wrong first locks / all attempts, including unsupported/negative scenes. |
| Correct lock yield | Correct first locks / in-scope attempts. A system that always abstains scores zero here. |
| Exact ordered-row accuracy | Entire correctly recovered rows / independently defined evaluated rows; report count 2/5/8/11/14/17 separately. |
| Time to correct lock | Median/p95 among correct accepts, plus the timeout/abstention count over all in-scope attempts. Do not hide failures by timing successes alone. |
| Device cost | Camera-to-result latency, sustained throughput, memory, battery/thermal behavior measured on named phones; desktop inference time is separate. |

Freeze and report both the tile-class score and the **whole-row** decision policy; a 0.8 detector confidence is not an 80% chance the entire row is correct. Compare dev risk-versus-coverage curves without lowering the threshold just to increase successful locks. Final testing uses the already-selected operating point. Persistent wrong labels can be temporally stable.

Initial external collection should deliberately span physical tile sets and glyph styles (including bird 1s, wind and dragon variants), worn/shiny tiles, lighting/reflection, backgrounds, angles, rotation, distance/small tiles, ordinary repeated identities, gaps and separated winning tiles. Include both iPhone 13 Pro and additional Android/iOS devices as available. Separate in-scope rows from flowers/red fives/backs/jokers, partial rows, hands entering frame, overlapping rows, tile changes and non-mahjong negatives. Unknown/unsupported faces must not be quietly counted as supported classes. A practical first collection is 6–10 independent physical sets and 2 sessions per set; this is a discovery target, not statistical certification or a claim of universal coverage.

## Small samples and acceptance goals

[metrics.py](../vision/validation/metrics.py) implements explicit denominators, two-sided Wilson intervals and an exact one-sided zero-failure bound. Wilson intervals avoid the zero-width certainty of a naive normal interval at 0/n or n/n; see the [NIST confidence-interval reference](https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm). The formulae assume independent trials, so report session/tile-set counts and per-cluster outcomes; with enough clusters, also resample whole clusters for uncertainty rather than individual frames.

For illustration, 2/7 has a Wilson 95% interval of approximately **8.2%–64.1%** under an independence assumption. The existing photos are correlated and selected for convenience, so even that interval is not a valid population-generalization guarantee. Zero wrong locks among zero accepted attempts provides no estimate of selective risk. Zero errors among 20 independent accepted attempts still permits an approximately **13.9%** one-sided 95% upper bound. To place that upper bound below 1% requires at least **299** independent accepted attempts with zero errors; below 0.1% requires **2,995**. Frames from one video do not supply those sample sizes. These bounds do not establish performance on unrepresented tile sets or phones.

For this iteration, aim to improve the frozen dev exact-row result and internal-test identity/localization metrics while preserving conservative rejection. Treat successful real-phone stable locks as a separate milestone. A release-quality claim needs a preregistered risk/coverage target on a sufficiently broad locked external test; no numerical release threshold is represented as achieved here.

## Verification of these helpers

The current suite has 27 named tests. It includes 200 seeded relationship graphs checked against an independent pairwise-graph/flood-fill oracle, transitive duplicate boundaries, cross-version hashes, crop/mosaic ancestry, 1,500-deep derivation chains, malformed metadata, protected-test eligibility, disk/annotation hashes, symlink escapes, lock mutation, and all 5,150 binomial count pairs for n=1…100. Six classifier selection-lock tests also check model/manifest replacement, actual image/label mutation, altered splits, invented crop identities, path escapes and invalid threshold commitments. These test the data safeguards and arithmetic, not model accuracy, truth of supplied metadata, completeness of duplicate discovery, or physical-phone behavior.

RF100-VL intake checkpoint: independently verified 2,135 image files and three annotation files; known relationship grouping yields 1,619 train / 360 dev / 156 internal-test images. The combined audit with all eight legacy public-media originals finds no declared/exact/dHash cross-dataset links. All 156 test images have unknown physical-set identity and upstream overlap. [rf100vl_internal_test_v1.lock.json](../vision/validation/rf100vl_internal_test_v1.lock.json) was created at 2026-10-02T15:46:31Z before the declared training/evaluation use. Its canonical source-manifest hash is `02989763bbafaf7182c0af1019f15aa2c5529046a32be54c2fc2e75c4957d144`. The lock records provenance, not an accuracy result or proof that undetected related photographs are absent.
