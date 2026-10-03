"""Audit RF100-VL Mahjong and retain image-level, duplicate-grouped splits.

Unknown physical tile sets and capture sessions remain unknown. These grouped
splits are internal diagnostics, never an unseen-physical-set test claim.
"""
from __future__ import annotations

import collections
import hashlib
import json
import math
from pathlib import Path
import re
import sys

import numpy as np
from PIL import Image

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
DATA = BASE / "rf100vl_mahjong"
VERSION = "rf100vl-mahjong-v2@1987e22ed542539fb3d0b8a3456455c2725079a1"
NS = "rf100vl-mahjong-v2"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(name: str) -> str:
    for prefix, suit in [("Bamboo ", "s"), ("Character ", "m"), ("Circle ", "p")]:
        if name.startswith(prefix):
            return name[len(prefix):] + suit
    return {"East": "1z", "South": "2z", "West": "3z", "North": "4z", "White": "5z", "Green": "6z", "Red": "7z"}[name]


def bits_hex(bits: np.ndarray) -> str:
    value = 0
    for bit in bits.reshape(-1):
        value = (value << 1) | bool(bit)
    return f"{value:016x}"


def fingerprints(path: Path) -> dict:
    with Image.open(path) as image:
        # RF100 export already auto-oriented pixels and stripped EXIF. Never
        # rotate pixels again independently of the supplied COCO boxes.
        rgb = image.convert("RGB")
        width, height = rgb.size
        pixel_hash = sha(f"{width}x{height}:RGB:".encode() + rgb.tobytes())
        gray = rgb.convert("L")
        small = np.asarray(gray.resize((9, 8), Image.Resampling.LANCZOS))
        dhash = bits_hex(small[:, :-1] > small[:, 1:])
        grid = np.asarray(gray.resize((32, 32), Image.Resampling.LANCZOS), dtype=np.float64)
        # Orthonormal DCT-II without another dependency. DC is excluded from
        # the threshold; the remaining 63 low frequencies describe structure.
        x = np.arange(32)
        cosine = np.cos(np.pi * (2 * x[None, :] + 1) * x[:, None] / 64)
        cosine[0] *= 1 / math.sqrt(2)
        dct = cosine @ grid @ cosine.T
        low = dct[:8, :8].reshape(-1)
        phash = bits_hex(low > np.median(low[1:]))
        thumb = np.asarray(rgb.resize((32, 32), Image.Resampling.BILINEAR), dtype=np.uint8)
        return {"width": width, "height": height, "pixel_sha256": pixel_hash, "dhash64": dhash, "phash64": phash, "thumb": thumb}


def main() -> None:
    status = json.loads((DATA / "extraction_status.json").read_text())
    if status["partial"] or status["verified_sha256"] is None:
        raise ValueError("Complete checksum-verified extraction required before splitting")
    rows = []
    categories = None
    invalid = []
    dims_mismatch = []
    source_split_counts = {}
    source_annotation_counts = {}
    by_category = collections.Counter()
    date_counts = collections.Counter()
    for split in ["train", "valid", "test"]:
        annotation_path = DATA / split / "_annotations.coco.json"
        annotation_bytes = annotation_path.read_bytes()
        doc = json.loads(annotation_bytes)
        if categories is None:
            categories = doc["categories"]
        elif categories != doc["categories"]:
            raise ValueError("Category maps differ between exports")
        classes = {c["id"]: canonical(c["name"]) for c in categories}
        annotations = collections.defaultdict(list)
        source_split_counts[split] = len(doc["images"])
        source_annotation_counts[split] = len(doc["annotations"])
        for ann in doc["annotations"]:
            if ann["category_id"] not in classes:
                raise ValueError(f"Unknown category {ann['category_id']}")
            annotations[ann["image_id"]].append(ann)
        for meta in sorted(doc["images"], key=lambda x: x["file_name"]):
            filename = meta["file_name"]
            if Path(filename).name != filename:
                raise ValueError(f"Unsafe image filename: {filename}")
            path = DATA / split / filename
            image_sha = sha(path.read_bytes())
            fp = fingerprints(path)
            if [fp["width"], fp["height"]] != [meta["width"], meta["height"]]:
                dims_mismatch.append({"path": str(path.relative_to(ROOT)), "coco": [meta["width"], meta["height"]], "actual": [fp["width"], fp["height"]]})
            original = re.sub(r"\.rf\.[0-9a-f]+\.[^.]+$", "", filename)
            root_id = f"{NS}:source:{original}"
            row_id = f"{NS}:{split}:{filename}"
            row_annotations = []
            for ann in annotations[meta["id"]]:
                x, y, w, h = ann["bbox"]
                if not all(math.isfinite(v) for v in [x, y, w, h]) or min(w, h) <= 0 or x < 0 or y < 0 or x + w > meta["width"] + .01 or y + h > meta["height"] + .01:
                    invalid.append({"record_id": row_id, "annotation_id": ann["id"], "bbox": ann["bbox"]})
                row_annotations.append({"id": ann["id"], "category_id": ann["category_id"], "label": classes[ann["category_id"]], "bbox": ann["bbox"]})
                by_category[classes[ann["category_id"]]] += 1
            date_counts[meta.get("date_captured")] += 1
            rows.append({
                "id": row_id, "path": str(path.relative_to(ROOT)),
                "source_image": root_id, "source_id": root_id,
                "parent_capture": None, "session_id": None, "physical_tile_set": None,
                "dataset_version": VERSION, "sha256": image_sha,
                "source_sha256": image_sha, "upstream_split": split,
                "split": {"train": "train", "valid": "dev", "test": "internal_test"}[split],
                "exposure": "training" if split == "train" else "development" if split == "valid" else "unexposed",
                "upstream_training_status": "unknown", "parent_ids": [],
                "near_duplicate_clusters": [], "annotation_path": str(annotation_path.relative_to(ROOT)),
                "annotation_sha256": sha(annotation_bytes), "coco_image_id": meta["id"],
                "annotations": row_annotations,
                "notes": "Root is the published auto-oriented export image, not a verified original camera capture. COCO date_captured is an export timestamp. Physical tile set/session unknown.",
                **fp,
            })
        print(f"hashed {split}: {source_split_counts[split]} images", flush=True)
    if dims_mismatch or invalid:
        (DATA / "annotation_errors.json").write_text(json.dumps({"dimension_mismatches": dims_mismatch, "invalid_boxes": invalid}, indent=2) + "\n")
        raise ValueError("Annotation geometry errors require review before training")
    parents = list(range(len(rows)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    def union(i, j):
        a, b = find(i), find(j)
        if a != b:
            parents[max(a, b)] = min(a, b)

    edges = []
    for key in ["source_image", "sha256", "pixel_sha256"]:
        seen = {}
        for i, row in enumerate(rows):
            value = row[key]
            if value in seen:
                j = seen[value]
                edges.append({"a": rows[j]["id"], "b": row["id"], "reason": key})
                union(i, j)
            else:
                seen[value] = i
    dh = [int(r["dhash64"], 16) for r in rows]
    ph = [int(r["phash64"], 16) for r in rows]
    near_candidates = 0
    for i in range(len(rows)):
        for j in range(i):
            dh_distance = (dh[i] ^ dh[j]).bit_count()
            reason = None
            if dh_distance <= 4:
                reason = "dhash64_hamming_le_4"
            elif (ph[i] ^ ph[j]).bit_count() <= 6:
                ratio_a = rows[i]["width"] / rows[i]["height"]
                ratio_b = rows[j]["width"] / rows[j]["height"]
                if abs(ratio_a / ratio_b - 1) <= .05:
                    mae = np.abs(rows[i]["thumb"].astype(np.float32) - rows[j]["thumb"].astype(np.float32)).mean()
                    if mae <= 12:
                        reason = "phash64_hamming_le_6_rgb32_mae_le_12"
            if reason:
                near_candidates += 1
                edges.append({"a": rows[j]["id"], "b": rows[i]["id"], "reason": reason, "dhash_distance": dh_distance})
                union(i, j)
    components = collections.defaultdict(list)
    for i in range(len(rows)):
        components[find(i)].append(i)
    promotions = []
    groups = []
    for members in components.values():
        ids = sorted(rows[i]["id"] for i in members)
        group_id = f"{NS}:group:{sha(chr(10).join(ids).encode())[:20]}"
        original_splits = {rows[i]["upstream_split"] for i in members}
        split = "train" if "train" in original_splits else "dev" if "valid" in original_splits else "internal_test"
        groups.append({"group_id": group_id, "record_ids": ids, "split": split, "upstream_splits": sorted(original_splits), "group_basis": "published-source-root, exact-file/pixel hash, conservative visual-near-duplicate graph; not verified physical identity"})
        for i in members:
            row = rows[i]
            if row["split"] != split:
                promotions.append({"id": row["id"], "from": row["split"], "to": split, "group_id": group_id})
            row["split"] = split
            row["exposure"] = "training" if split == "train" else "development" if split == "dev" else "unexposed"
            row["group_id"] = group_id
            row["near_duplicate_clusters"] = [group_id] if len(members) > 1 else []
            row["notes"] += f" Upstream split {row['upstream_split']}; grouped destination {split}; related groups promote toward train, then dev."
            row.pop("thumb")
    counts = collections.Counter(r["split"] for r in rows)
    class_counts = {split: dict(collections.Counter(ann["label"] for r in rows if r["split"] == split for ann in r["annotations"])) for split in ["train", "dev", "internal_test"]}
    report = {
        "dataset_version": VERSION, "archive_sha256": status["verified_sha256"],
        "images": len(rows), "annotations": sum(len(r["annotations"]) for r in rows),
        "upstream_image_counts": source_split_counts, "upstream_annotation_counts": source_annotation_counts,
        "grouped_image_counts": dict(counts), "group_count": len(groups),
        "multi_image_groups": sum(len(g["record_ids"]) > 1 for g in groups),
        "largest_group_images": max(len(g["record_ids"]) for g in groups),
        "evidence_edge_counts": dict(collections.Counter(e["reason"] for e in edges)),
        "cross_upstream_split_groups": sum(len(g["upstream_splits"]) > 1 for g in groups),
        "promoted_image_count": len(promotions), "class_counts": class_counts,
        "invalid_boxes": len(invalid), "dimension_mismatches": len(dims_mismatch),
        "export_timestamp_counts": dict(date_counts), "known_capture_sessions": 0,
        "known_physical_tile_sets": 0, "upstream_model_training_overlap": "unknown",
        "limits": ["Duplicate heuristics can miss differently angled or cropped copies and over-group visually similar scenes.", "No verified physical tile-set or capture-session holdout is available.", "Original and grouped test images are internal diagnostics; broader upstream model overlap is unknown.", "COCO boxes were format/geometry checked, not exhaustively re-labelled."],
    }
    manifest = {"schema_version": 1, "manifest_id": VERSION + ":grouped-v1", "root": ".", "classes": [f"{n}{s}" for s in "mps" for n in range(1, 10)] + [f"{n}z" for n in range(1, 8)], "source_categories": categories, "split_policy": "Preserve upstream splits; whole duplicate groups promote toward train, then dev. Never split crops independently.", "records": rows}
    sys.path.insert(0, str(ROOT))
    from vision.validation.manifest import REQUIRED, OPTIONAL, audit, canonical_hash
    strict = {"schema_version": 1, "manifest_id": manifest["manifest_id"], "records": [{k: v for k, v in row.items() if k in REQUIRED | OPTIONAL} for row in rows]}
    strict_audit = audit(strict, require_assigned=True)
    report["strict_manifest_sha256"] = canonical_hash(strict)
    (DATA / "validation_manifest.json").write_text(json.dumps(strict, indent=2) + "\n")
    (DATA / "validation_audit.json").write_text(json.dumps(strict_audit, indent=2) + "\n")
    for name, value in [("image_manifest.json", manifest), ("audit_summary.json", report), ("duplicate_groups.json", groups), ("duplicate_edges.json", edges), ("split_promotions.json", promotions)]:
        (DATA / name).write_text(json.dumps(value, indent=2) + "\n")
    for split in ["train", "dev", "internal_test"]:
        (DATA / f"{split}_images.txt").write_text("".join(r["path"] + "\n" for r in rows if r["split"] == split))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
