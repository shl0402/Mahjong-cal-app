"""Leakage-aware manifests. Run with ``python -m vision.validation.manifest``.

Metadata and perceptual hashes cannot prove absence of undiscovered duplicates.
These helpers enforce all declared and detected relationships, transitively.
"""

from __future__ import annotations

import argparse
from collections import Counter, deque
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re


SPLITS = {"train", "dev", "internal_test", "holdout", "quarantine", "unassigned"}
PROTECTED = {"internal_test", "holdout"}
REQUIRED = {
    "id", "path", "source_image", "parent_capture", "session_id",
    "physical_tile_set", "dataset_version", "sha256", "source_sha256",
    "split", "exposure", "upstream_training_status", "parent_ids",
    "near_duplicate_clusters",
}
OPTIONAL = {
    "dhash64", "annotation_path", "annotation_sha256", "upstream_evidence", "notes",
}
GROUP_FIELDS = ("source_image", "parent_capture", "session_id", "physical_tile_set")


class ManifestError(ValueError):
    pass


def _require(condition, message):
    if not condition:
        raise ManifestError(message)


def _text(value):
    return isinstance(value, str) and bool(value.strip()) and value == value.strip()


def _hex(value, length):
    return isinstance(value, str) and re.fullmatch(f"[0-9a-f]{{{length}}}", value) is not None


def _path(value):
    return (_text(value) and "\\" not in value and
            not PurePosixPath(value).is_absolute() and
            not set(PurePosixPath(value).parts) & {"..", "."} and value != ".")


def _fields(manifest):
    _require(isinstance(manifest, dict), "manifest must be an object")
    _require(set(manifest) == {"schema_version", "manifest_id", "records"},
             "manifest needs exactly schema_version, manifest_id, records")
    _require(type(manifest["schema_version"]) is int and manifest["schema_version"] == 1,
             "unsupported schema_version")
    _require(_text(manifest["manifest_id"]), "manifest_id must be nonempty")
    records = manifest["records"]
    _require(isinstance(records, list) and bool(records), "records must be a nonempty list")
    ids = set()
    for record in records:
        _require(isinstance(record, dict), "record must be an object")
        _require(REQUIRED <= set(record) <= REQUIRED | OPTIONAL,
                 f"record fields missing/unknown: {record.get('id', '?')}")
        rid = record["id"]
        _require(_text(rid) and rid not in ids, f"invalid/duplicate id: {rid}")
        ids.add(rid)
        for key in ("source_image", "dataset_version"):
            _require(_text(record[key]), f"{rid}: invalid {key}")
        for key in ("parent_capture", "session_id", "physical_tile_set"):
            value = record[key]
            _require(value is None or (_text(value) and value.lower() not in
                     {"unknown", "none", "n/a", "null"}), f"{rid}: use null for unknown {key}")
        _require(_path(record["path"]), f"{rid}: path must stay relative to the dataset root")
        for key in ("sha256", "source_sha256"):
            _require(_hex(record[key], 64), f"{rid}: invalid {key}")
        _require(isinstance(record["split"], str) and record["split"] in SPLITS, f"{rid}: invalid split")
        _require(isinstance(record["exposure"], str) and record["exposure"] in {"unexposed", "development", "training"},
                 f"{rid}: invalid exposure")
        _require(isinstance(record["upstream_training_status"], str) and record["upstream_training_status"] in
                 {"unknown", "known_in_training", "verified_disjoint"},
                 f"{rid}: invalid upstream_training_status")
        if record["upstream_training_status"] == "verified_disjoint":
            _require(_text(record.get("upstream_evidence")), f"{rid}: upstream evidence required")
        for key in ("parent_ids", "near_duplicate_clusters"):
            value = record[key]
            _require(isinstance(value, list) and all(_text(v) for v in value)
                     and len(set(value)) == len(value), f"{rid}: invalid {key}")
        _require(rid not in record["parent_ids"], f"{rid}: self parent")
        if "dhash64" in record:
            _require(_hex(record["dhash64"], 16), f"{rid}: invalid dhash64")
        has_annotation = "annotation_path" in record or "annotation_sha256" in record
        if has_annotation:
            _require(_path(record.get("annotation_path")) and
                     _hex(record.get("annotation_sha256"), 64), f"{rid}: invalid annotation pair")
        for key in ("notes", "upstream_evidence"):
            if key in record:
                _require(_text(record[key]), f"{rid}: invalid {key}")
    by_id = {r["id"]: r for r in records}
    # Kahn's algorithm avoids recursion limits on deeply nested augmentations.
    indegree = {r["id"]: len(r["parent_ids"]) for r in records}
    children = {rid: [] for rid in ids}
    for record in records:
        for parent in record["parent_ids"]:
            _require(parent in by_id, f"{record['id']}: dangling parent {parent}")
            children[parent].append(record["id"])
    queue = deque(rid for rid, count in indegree.items() if count == 0)
    visited = 0
    while queue:
        visited += 1
        for child in children[queue.popleft()]:
            indegree[child] -= 1
            if indegree[child] == 0:
                queue.append(child)
    _require(visited == len(records), "cyclic derivation parents")
    return records


def grouped_components(manifest, *, near_distance=4):
    """Join all known relationships; hashes are compared across dataset versions."""
    records = _fields(manifest)
    _require(type(near_distance) is int and 0 <= near_distance <= 64,
             "near_distance must be an integer in 0..64")
    parent = {r["id"]: r["id"] for r in records}

    def root(rid):
        while parent[rid] != rid:
            parent[rid] = parent[parent[rid]]
            rid = parent[rid]
        return rid

    def join(a, b):
        a, b = root(a), root(b)
        if a != b:
            parent[max(a, b)] = min(a, b)

    owners = {}
    for record in records:
        rid = record["id"]
        keys = [(key, record[key]) for key in GROUP_FIELDS if record[key] is not None]
        # An original's asset hash and any derivative's source hash also match.
        keys += [("hash", record[key]) for key in ("sha256", "source_sha256")]
        keys += [("near_cluster", value) for value in record["near_duplicate_clusters"]]
        for key in keys:
            if key in owners:
                join(rid, owners[key])
            else:
                owners[key] = rid
        for pid in record["parent_ids"]:
            join(rid, pid)
    hashes = [(r["id"], int(r["dhash64"], 16)) for r in records if "dhash64" in r]
    # Deliberately conservative candidate grouping, not a claim of visual identity.
    for i, (rid, value) in enumerate(hashes):
        for other, other_value in hashes[:i]:
            if (value ^ other_value).bit_count() <= near_distance:
                join(rid, other)
    components = {}
    for rid in parent:
        components.setdefault(root(rid), []).append(rid)
    return sorted(sorted(group) for group in components.values())


def _eligible(record, split):
    if split not in PROTECTED:
        return True
    if record["exposure"] != "unexposed" or record["upstream_training_status"] == "known_in_training":
        return False
    if split == "holdout":
        return (all(record[key] is not None for key in
                    ("parent_capture", "session_id", "physical_tile_set")) and
                "annotation_sha256" in record)
    return True


def audit(manifest, *, near_distance=4, require_assigned=False):
    components = grouped_components(manifest, near_distance=near_distance)
    by_id = {r["id"]: r for r in manifest["records"]}
    for group in components:
        splits = {by_id[rid]["split"] for rid in group} - {"unassigned"}
        _require(len(splits) <= 1, f"split leakage in component {group}: {sorted(splits)}")
        if splits:
            split = next(iter(splits))
            for rid in group:
                _require(_eligible(by_id[rid], split), f"{rid}: not eligible for {split}")
        if require_assigned:
            _require(all(by_id[rid]["split"] != "unassigned" for rid in group),
                     f"unassigned records in {group}")
    records = manifest["records"]
    protected = [r for r in records if r["split"] in PROTECTED]
    return {
        "records": len(records), "component_count": len(components),
        "split_records": dict(sorted(Counter(r["split"] for r in records).items())),
        "split_components": dict(sorted(Counter(by_id[g[0]]["split"] for g in components).items())),
        "components": components,
        "upstream_unknown_test_records": sum(r["upstream_training_status"] == "unknown" for r in protected),
        "physical_identity_unknown_test_records": sum(r["physical_tile_set"] is None for r in protected),
        "missing_perceptual_hashes": sum("dhash64" not in r for r in records),
        "warning": "Known relationship separation only; unknown lineage and undetected duplicates remain possible.",
    }


def assign_splits(manifest, *, seed, ratios=None, near_distance=4):
    """Assign entire components reproducibly; preserve every explicit split.

    Ratios apply to groups, not files. Small/large correlated groups can produce
    imbalanced sample counts, reported by audit; never break a group to balance.
    """
    _require(_text(seed), "seed must be a nonempty string")
    ratios = ratios if ratios is not None else {"train": .7, "dev": .15, "internal_test": .15}
    _require(isinstance(ratios, dict) and bool(ratios) and set(ratios) <= SPLITS - {"unassigned"},
             "invalid split ratios")
    _require(all(type(v) in (int, float) and math.isfinite(v) and v >= 0 for v in ratios.values())
             and math.isfinite(sum(ratios.values())) and sum(ratios.values()) > 0,
             "ratios must be finite nonnegative and nonzero")
    report = audit(manifest, near_distance=near_distance)
    result = deepcopy(manifest)
    by_id = {r["id"]: r for r in result["records"]}
    for group in report["components"]:
        fixed = {by_id[rid]["split"] for rid in group} - {"unassigned"}
        if fixed:
            selected = next(iter(fixed))
        else:
            exposures = {by_id[rid]["exposure"] for rid in group}
            if "training" in exposures:
                selected = "train"
            elif "development" in exposures:
                selected = "dev"
            else:
                choices = sorted((s, weight) for s, weight in ratios.items() if weight > 0
                                 and all(_eligible(by_id[rid], s) for rid in group))
                _require(bool(choices), f"no eligible destination for component {group}")
                digest = hashlib.sha256((seed + "\0" + "\0".join(group)).encode()).digest()
                value = int.from_bytes(digest, "big") / 2 ** 256 * sum(w for _, w in choices)
                selected = choices[-1][0]
                for split, weight in choices:
                    if value < weight:
                        selected = split
                        break
                    value -= weight
        for rid in group:
            by_id[rid]["split"] = selected
    audit(result, near_distance=near_distance, require_assigned=True)
    return result


def canonical_hash(manifest):
    _fields(manifest)
    normalized = deepcopy(manifest)
    normalized["records"].sort(key=lambda r: r["id"])
    for record in normalized["records"]:
        for key in ("parent_ids", "near_duplicate_clusters"):
            record[key].sort()
    raw = json.dumps(normalized, sort_keys=True, ensure_ascii=False, allow_nan=False,
                     separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _resolve(root, relative):
    _require(_path(relative), "unsafe relative asset path")
    root = Path(root).resolve()
    path = (root / relative).resolve()
    _require(path.is_relative_to(root), "asset symlink escapes dataset root")
    _require(path.is_file(), f"missing asset: {relative}")
    return path


def file_sha256(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def verify_files(manifest, root):
    _fields(manifest)
    verified = {}
    for record in manifest["records"]:
        pairs = [(record["path"], record["sha256"])]
        if "annotation_path" in record:
            pairs.append((record["annotation_path"], record["annotation_sha256"]))
        for path, expected in pairs:
            if path not in verified:
                verified[path] = file_sha256(_resolve(root, path))
            _require(verified[path] == expected, f"hash mismatch: {path}")
    return len(verified)


def make_lock(manifest, *, near_distance=4, locked_at=None):
    report = audit(manifest, near_distance=near_distance, require_assigned=True)
    protected = sorted(r["id"] for r in manifest["records"] if r["split"] in PROTECTED)
    _require(bool(protected), "nothing to lock: need internal_test or holdout records")
    result = {
        "schema_version": 1, "manifest_id": manifest["manifest_id"],
        "manifest_sha256": canonical_hash(manifest), "near_distance": near_distance,
        "locked_at": locked_at or datetime.now(timezone.utc).isoformat(),
        "protected_ids": protected, "audit": report,
    }
    result["lock_sha256"] = hashlib.sha256(json.dumps(
        result, sort_keys=True, ensure_ascii=False, allow_nan=False,
        separators=(",", ":")).encode("utf-8")).hexdigest()
    return result


def verify_lock(manifest, lock):
    _require(isinstance(lock, dict) and set(lock) == {
        "schema_version", "manifest_id", "manifest_sha256", "near_distance",
        "locked_at", "protected_ids", "audit", "lock_sha256"}, "invalid lock structure")
    _require(type(lock["schema_version"]) is int and lock["schema_version"] == 1, "invalid lock version")
    _require(_text(lock["locked_at"]), "missing lock timestamp")
    expected = make_lock(manifest, near_distance=lock["near_distance"], locked_at=lock["locked_at"])
    _require(lock == expected, "locked manifest changed; do not relabel this as an untouched test")
    return True


def fingerprint_image(path):
    """Byte hash + upright dHash; Pillow is optional until this function is used.

    dHash is a coarse duplicate candidate tool, not crop/rotation invariant and
    not a replacement for provenance or human duplicate review.
    """
    from PIL import Image, ImageOps
    with Image.open(path) as image:
        gray = ImageOps.exif_transpose(image).convert("L").resize((9, 8), Image.Resampling.LANCZOS)
        pixels = list(gray.getdata())
    value = 0
    for y in range(8):
        for x in range(8):
            value = (value << 1) | (pixels[y * 9 + x] > pixels[y * 9 + x + 1])
    return {"sha256": file_sha256(path), "dhash64": f"{value:016x}"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["audit", "split", "lock", "verify", "fingerprint"])
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--seed", default="mahjong-split-v1")
    parser.add_argument("--near-distance", type=int, default=4)
    args = parser.parse_args()
    if args.command == "fingerprint":
        result = fingerprint_image(args.input)
    else:
        manifest = json.loads(args.input.read_text())
        if args.command == "audit":
            result = audit(manifest, near_distance=args.near_distance)
        elif args.command == "split":
            result = assign_splits(manifest, seed=args.seed, near_distance=args.near_distance)
        elif args.command == "lock":
            _require(args.output is not None, "lock requires --output")
            verify_files(manifest, args.root)
            result = make_lock(manifest, near_distance=args.near_distance)
        else:
            _require(args.output is not None, "verify requires --output pointing to the existing lock")
            verify_files(manifest, args.root)
            verify_lock(manifest, json.loads(args.output.read_text()))
            print(json.dumps({"verified": True, "manifest_sha256": canonical_hash(manifest)}))
            return
    encoded = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        # A lock or split is a new artifact; never silently overwrite one.
        with args.output.open("x") as handle:
            handle.write(encoded)
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
