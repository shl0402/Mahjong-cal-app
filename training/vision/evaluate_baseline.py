#!/usr/bin/env python3
"""Audit the legacy crops and evaluate the pinned ONNX detector on them.

This is a crop-domain diagnostic, NOT object detection mAP or whole-hand accuracy.
No training, remote code, network access, or changes to original data are involved.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import platform
import statistics
import time

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SHA256 = "3c7732c022d41c1a3f48cea931ce626416d92486ab5b86692312941d0cc22226"


def canonical(name: str) -> str:
    """CSV classes and ONNX names use different orders and dragon conventions."""
    if name == "UNKNOWN":
        return name
    if len(name) == 2 and name[1] in "mpsz":
        return "5" + name[1] if name[0] == "0" else name
    suit, value = name.split("-", 1)
    if suit in ("dots", "bamboo", "characters"):
        return value + {"dots": "p", "bamboo": "s", "characters": "m"}[suit]
    if suit == "honors":
        return str({"east": 1, "south": 2, "west": 3, "north": 4,
                    "white": 5, "green": 6, "red": 7}[value]) + "z"
    return name  # Flowers deliberately remain outside model coverage.


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_and_audit(csv_path: Path, images: Path):
    rows = list(csv.DictReader(csv_path.open()))
    grouped = defaultdict(list)
    for row in rows:
        grouped[row["image-name"]].append(row)
    conflicts = {name: group for name, group in grouped.items()
                 if len({(r["label"], r["label-name"]) for r in group}) > 1}
    if conflicts:
        raise ValueError(f"Conflicting labels: {conflicts}")
    unique = [group[0] for group in grouped.values()]
    hashes = defaultdict(list)
    sizes = Counter()
    missing, unreadable = [], []
    for row in unique:
        path = images / row["image-name"]
        if not path.is_file():
            missing.append(row["image-name"])
            continue
        hashes[digest(path)].append(row["image-name"])
        try:
            with Image.open(path) as image:
                image.load()
                sizes[f"{image.width}x{image.height}"] += 1
        except Exception as error:
            unreadable.append({"image": row["image-name"], "error": str(error)})
    labels = sorted({int(r["label"]) for r in unique})
    # Establish consistent zero-based IDs from the CSV, never reuse YOLO output labels.
    label_names = defaultdict(set)
    for row in unique:
        label_names[int(row["label"]) - 1].add(row["label-name"])
    if any(len(names) != 1 for names in label_names.values()):
        raise ValueError("A CSV label ID maps to conflicting names")
    train = ROOT / "train/dataset/images/train"
    val = ROOT / "train/dataset/images/val"
    train_names = {p.name for p in train.glob("*.jpg")}
    val_names = {p.name for p in val.glob("*.jpg")}
    generated_labels = list((ROOT / "train/dataset/labels").glob("*/*.txt"))
    generated_ids = Counter()
    full_frame = 0
    for label in generated_labels:
        for line in label.read_text().splitlines():
            parts = line.split()
            generated_ids[int(parts[0])] += 1
            full_frame += parts[1:] == ["0.5", "0.5", "1.0", "1.0"]
    audit = {
        "csv_rows": len(rows), "unique_images": len(unique),
        "duplicate_csv_rows": {n: len(g) for n, g in grouped.items() if len(g) > 1},
        "conflicting_labels": conflicts, "csv_label_range": [min(labels), max(labels)],
        "corrected_yolo_range": [min(labels)-1, max(labels)-1],
        "missing_images": missing, "unreadable_images": unreadable,
        "exact_duplicate_image_groups": [v for v in hashes.values() if len(v) > 1],
        "image_sizes": dict(sizes),
        "legacy_train_images": len(train_names), "legacy_val_images": len(val_names),
        "filename_split_overlap": sorted(train_names & val_names),
        "generated_label_count": sum(generated_ids.values()),
        "generated_full_frame_boxes": full_frame,
        "generated_invalid_class_42_count": generated_ids[42],
        "canonical_class_counts": dict(sorted(Counter(canonical(r["label-name"]) for r in unique).items())),
        "zero_based_classes": {str(i): next(iter(names)) for i, names in sorted(label_names.items())},
        "limitations": ["No capture-session or physical tile-set identity is present; leakage-safe splits cannot be established.",
                        "No real multi-tile bounding-box annotations are present.",
                        "Byte-deduplication does not detect near-duplicate source crops."]}
    return unique, audit


def prepare(path: Path):
    with Image.open(path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
        scale = 640 / max(image.size)
        # Dart rounds .5 upwards; Python's built-in round uses ties-to-even.
        width, height = (max(1, int(d * scale + .5)) for d in image.size)
        small = image.resize((width, height), Image.Resampling.BILINEAR)
    pad_x, pad_y = (640-width)//2, (640-height)//2
    tensor = np.full((640, 640, 3), 114, dtype=np.float32)
    tensor[pad_y:pad_y+height, pad_x:pad_x+width] = np.asarray(small, dtype=np.float32)
    return (tensor.transpose(2, 0, 1)[None] / 255).copy(), (pad_x, pad_y, width, height)


def decode(raw, geometry, names, threshold=.25, nms=.45):
    if raw.shape != (1, 4 + len(names), 8400):
        raise ValueError(f"Unexpected output shape {raw.shape}")
    values = raw[0]
    confidences = np.where(np.isfinite(values[4:]), values[4:], 0)
    classes = confidences.argmax(axis=0)
    scores = confidences.max(axis=0)
    pad_x, pad_y, width, height = geometry
    candidates = []
    for index in np.flatnonzero(scores >= threshold):
        x, y, w, h = values[:4, index]
        if not np.isfinite([x, y, w, h]).all() or w <= 0 or h <= 0:
            continue
        box = np.clip([(x-w/2-pad_x)/width, (y-h/2-pad_y)/height,
                       (x+w/2-pad_x)/width, (y+h/2-pad_y)/height], 0, 1)
        if box[2] <= box[0] or box[3] <= box[1]:
            continue
        model_name = names[int(classes[index])]
        tile = canonical(model_name)
        tile_index = -1 if tile == "UNKNOWN" else {"m": 0, "p": 9, "s": 18, "z": 27}[tile[1]] + int(tile[0]) - 1
        candidates.append({"tile": tile, "tile_index": tile_index,
                           "red_five": model_name in ("0m", "0p", "0s"),
                           "model_class_id": int(classes[index]), "model_class_name": model_name,
                           "confidence": float(scores[index]), "box": box.tolist()})
    candidates.sort(key=lambda item: item["confidence"], reverse=True)
    kept = []
    for candidate in candidates:
        a = candidate["box"]
        keep = True
        for existing in kept:
            b = existing["box"]
            intersection = max(0, min(a[2], b[2])-max(a[0], b[0])) * max(0, min(a[3], b[3])-max(a[1], b[1]))
            union = (a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-intersection
            if union > 0 and intersection / union >= nms:
                keep = False
                break
        if keep:
            kept.append(candidate)
            if len(kept) >= 40:
                break
    return kept


def percentile(values, p):
    return float(np.percentile(values, p)) if values else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=ROOT / "vision/downloads/mahjong-yolo11n.onnx")
    parser.add_argument("--csv", type=Path, default=ROOT / "train/data.csv")
    parser.add_argument("--images", type=Path, default=ROOT / "train/images")
    parser.add_argument("--output", type=Path, default=ROOT / "vision/reports/baseline.json")
    parser.add_argument("--limit", type=int, default=0, help="Optional smoke-test limit; zero means all unique images")
    args = parser.parse_args()
    rows, audit = load_and_audit(args.csv, args.images)
    sha = digest(args.model)
    if sha != EXPECTED_SHA256:
        raise ValueError("Model checksum differs from the reviewed baseline")
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(args.model), sess_options=options, providers=["CPUExecutionProvider"])
    metadata = session.get_modelmeta().custom_metadata_map
    names = ast.literal_eval(metadata["names"])
    covered = {canonical(name) for name in names.values()}
    timings, full_timings, records, per_class = [], [], [], defaultdict(Counter)
    warm, _ = prepare(args.images / rows[0]["image-name"])
    for _ in range(5):
        session.run(None, {"images": warm})
    selected = rows[:args.limit] if args.limit else rows
    for index, row in enumerate(selected):
        start = time.perf_counter()
        tensor, geometry = prepare(args.images / row["image-name"])
        begin_inference = time.perf_counter()
        raw = session.run(None, {"images": tensor})[0]
        timings.append((time.perf_counter()-begin_inference)*1000)
        predictions = decode(raw, geometry, names)
        full_timings.append((time.perf_counter()-start)*1000)
        expected = canonical(row["label-name"])
        supported = expected in covered
        best = predictions[0]["tile"] if predictions else None
        exact_single = len(predictions) == 1 and best == expected
        records.append({"image": row["image-name"], "expected": expected, "covered": supported,
                        "predictions": predictions, "top_correct": best == expected,
                        "exactly_one_correct": exact_single})
        per_class[expected].update(total=1, top_correct=int(best == expected),
                                   exactly_one_correct=int(exact_single), missing=int(not predictions))
        if (index+1) % 100 == 0:
            print(f"Evaluated {index+1}/{len(selected)} crops", flush=True)
    supported_records = [record for record in records if record["covered"]]
    unsupported_records = [record for record in records if not record["covered"]]
    report = {"purpose": "Legacy single-crop domain diagnostic; not whole-hand accuracy or detection mAP",
              "model": {"sha256": sha, "bytes": args.model.stat().st_size, "metadata": metadata,
                        "input": [1, 3, 640, 640], "output": [1, 41, 8400]},
              "environment": {"platform": platform.platform(), "processor": platform.processor(),
                              "python": platform.python_version(), "onnxruntime": ort.__version__,
                              "numpy": np.__version__, "provider": "CPUExecutionProvider", "threads": 2},
              "method": {"confidence_threshold": .25, "nms_iou_threshold": .45, "warmup_runs": 5,
                         "resize": "Pillow bilinear RGB letterbox; 114 padding; CHW float32 /255",
                         "resize_caveat": "Pillow and Dart image bilinear implementations may differ slightly.",
                         "sample_count": len(records), "partial": bool(args.limit)},
              "audit": audit,
              "metrics": {"covered_crops": len(supported_records),
                          "top_correct": sum(r["top_correct"] for r in supported_records),
                          "exactly_one_correct": sum(r["exactly_one_correct"] for r in supported_records),
                          "no_detection": sum(not r["predictions"] for r in supported_records),
                          "unsupported_flower_crops": len(unsupported_records),
                          "unsupported_with_false_detection": sum(bool(r["predictions"]) for r in unsupported_records),
                          "inference_median_ms": statistics.median(timings), "inference_p95_ms": percentile(timings, 95),
                          "prepare_infer_decode_median_ms": statistics.median(full_timings),
                          "prepare_infer_decode_p95_ms": percentile(full_timings, 95)},
              "per_class": dict(sorted(per_class.items())), "records": records}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["metrics"], indent=2))
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
