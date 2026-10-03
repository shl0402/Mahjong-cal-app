from copy import deepcopy
import hashlib
import json
from pathlib import Path
import random
import tempfile
import unittest

from vision.validation.manifest import (
    GROUP_FIELDS, ManifestError, assign_splits, audit, canonical_hash,
    file_sha256, grouped_components, make_lock, verify_files, verify_lock,
)


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def record(rid, **overrides):
    result = {
        "id": rid, "path": f"images/{rid}.jpg", "source_image": f"source:{rid}",
        "parent_capture": f"capture:{rid}", "session_id": f"session:{rid}",
        "physical_tile_set": f"tileset:{rid}", "dataset_version": "source-v1",
        "sha256": sha(rid), "source_sha256": sha("source:" + rid),
        "split": "unassigned", "exposure": "unexposed",
        "upstream_training_status": "unknown", "parent_ids": [],
        "near_duplicate_clusters": [],
    }
    return result | overrides


def manifest(*records):
    return {"schema_version": 1, "manifest_id": "test-v1", "records": list(records)}


def independently_connected(data, distance=4):
    """Pairwise graph + flood fill, independent of union-find/key-owner code."""
    records = data["records"]
    edges = {r["id"]: set() for r in records}
    for a in records:
        for b in records:
            related = any(a[k] is not None and a[k] == b[k] for k in GROUP_FIELDS)
            related |= bool({a["sha256"], a["source_sha256"]} & {b["sha256"], b["source_sha256"]})
            related |= bool(set(a["near_duplicate_clusters"]) & set(b["near_duplicate_clusters"]))
            related |= a["id"] in b["parent_ids"] or b["id"] in a["parent_ids"]
            if "dhash64" in a and "dhash64" in b:
                related |= bin(int(a["dhash64"], 16) ^ int(b["dhash64"], 16)).count("1") <= distance
            if related:
                edges[a["id"]].add(b["id"])
    unseen = set(edges)
    components = []
    while unseen:
        reached, frontier = set(), {min(unseen)}
        while frontier:
            reached |= frontier
            frontier = set().union(*(edges[rid] for rid in frontier)) - reached
        unseen -= reached
        components.append(sorted(reached))
    return sorted(components)


class ManifestTests(unittest.TestCase):
    def test_every_declared_relationship_prevents_cross_split_leakage(self):
        for field in GROUP_FIELDS + ("sha256", "source_sha256"):
            with self.subTest(field=field):
                a, b = record("a", split="train"), record("b", split="dev")
                b[field] = a[field]
                with self.assertRaisesRegex(ManifestError, "split leakage"):
                    audit(manifest(a, b))
        for field, value in [("parent_ids", ["a"]), ("near_duplicate_clusters", ["cluster-1"])]:
            a, b = record("a", split="train"), record("b", split="internal_test")
            b[field] = value
            if field == "near_duplicate_clusters":
                a[field] = value
            with self.assertRaises(ManifestError):
                audit(manifest(a, b))

    def test_exact_original_hash_matches_a_different_derivatives_source_hash(self):
        a, b = record("a"), record("b", dataset_version="another-export-v99")
        b["source_sha256"] = a["sha256"]
        self.assertEqual(grouped_components(manifest(a, b)), [["a", "b"]])

    def test_transitive_sources_sessions_tilesets_and_near_clusters(self):
        a, b, c, d, e = [record(rid) for rid in "abcde"]
        b["source_image"] = a["source_image"]
        c["session_id"] = b["session_id"]
        d["physical_tile_set"] = c["physical_tile_set"]
        d["near_duplicate_clusters"] = ["manual-review:near-8"]
        e["near_duplicate_clusters"] = d["near_duplicate_clusters"]
        self.assertEqual(grouped_components(manifest(a, b, c, d, e)), [list("abcde")])

    def test_perceptual_boundary_and_transitive_not_just_representative_matching(self):
        a = record("a", dhash64="0000000000000000")
        b = record("b", dhash64="000000000000000f")  # four differing bits
        c = record("c", dhash64="00000000000000ff")  # four from b, eight from a
        self.assertEqual(grouped_components(manifest(a, b, c)), [["a", "b", "c"]])
        self.assertEqual(grouped_components(manifest(a, b, c), near_distance=3), [["a"], ["b"], ["c"]])
        d = record("d", dhash64="000000000000001f")  # five from a
        self.assertEqual(grouped_components(manifest(a, d)), [["a"], ["d"]])

    def test_unknown_metadata_does_not_fabricate_a_shared_or_unique_identity(self):
        rows = [record(rid, parent_capture=None, session_id=None, physical_tile_set=None) for rid in "ab"]
        data = assign_splits(manifest(*rows), seed="fixed", ratios={"internal_test": 1})
        self.assertEqual(audit(data)["physical_identity_unknown_test_records"], 2)
        self.assertEqual(audit(data)["component_count"], 2)
        self.assertEqual(audit(data)["upstream_unknown_test_records"], 2)

    def test_crop_augmentation_and_mosaic_parents_always_stay_together(self):
        rows = [record("original"), record("other"), record("crop", parent_ids=["original"]),
                record("rotate", parent_ids=["crop"]), record("mosaic", parent_ids=["rotate", "other"])]
        data = assign_splits(manifest(*rows), seed="a")
        self.assertEqual(len({r["split"] for r in data["records"]}), 1)
        self.assertEqual(audit(data)["component_count"], 1)

    def test_exposed_or_upstream_training_data_cannot_become_untouched_tests(self):
        for split in ("internal_test", "holdout"):
            for exposure in ("development", "training"):
                with self.subTest(split=split, exposure=exposure), self.assertRaises(ManifestError):
                    audit(manifest(record("a", split=split, exposure=exposure)))
            with self.assertRaises(ManifestError):
                audit(manifest(record("a", split=split, upstream_training_status="known_in_training")))
        data = assign_splits(manifest(record("a", exposure="development"),
                                     record("b", source_image="source:a")), seed="fixed",
                             ratios={"internal_test": 1})
        self.assertEqual({r["split"] for r in data["records"]}, {"dev"})

    def test_holdout_requires_known_capture_session_tileset_and_pinned_annotations(self):
        valid = record("a", split="holdout", annotation_path="labels/a.json", annotation_sha256=sha("labels"))
        audit(manifest(valid))
        for field in ("parent_capture", "session_id", "physical_tile_set"):
            with self.subTest(field=field), self.assertRaises(ManifestError):
                audit(manifest(valid | {field: None}))
        invalid = {k: v for k, v in valid.items() if not k.startswith("annotation_")}
        with self.assertRaises(ManifestError):
            audit(manifest(invalid))

    def test_existing_splits_preserved_and_conflicts_never_silently_resolved(self):
        data = manifest(record("a", split="dev"), record("b", source_image="source:a"), record("c", split="train"))
        result = assign_splits(data, seed="s", ratios={"internal_test": 1})
        self.assertEqual([r["split"] for r in result["records"]], ["dev", "dev", "train"])
        self.assertEqual(data["records"][1]["split"], "unassigned", "input must not be mutated")
        data["records"][1]["split"] = "train"
        with self.assertRaises(ManifestError):
            assign_splits(data, seed="s")

    def test_200_seeded_graphs_match_independent_oracle_and_group_splits(self):
        rng = random.Random(830721)
        for trial in range(200):
            rows = [record(str(i)) for i in range(20)]
            for i, row in enumerate(rows):
                if i and rng.random() < .5:
                    earlier = rng.choice(rows[:i])
                    key = rng.choice(list(GROUP_FIELDS) + ["sha256"])
                    row[key] = earlier[key]
                if i and rng.random() < .15:
                    row["parent_ids"] = [rng.choice(rows[:i])["id"]]
                if rng.random() < .2:
                    row["near_duplicate_clusters"] = [f"cluster:{rng.randrange(8)}"]
                row["dhash64"] = f"{rng.getrandbits(64):016x}"
            data = manifest(*rows)
            expected = independently_connected(data)
            self.assertEqual(grouped_components(data), expected, f"trial {trial}")
            result = assign_splits(data, seed="frozen")
            by_id = {r["id"]: r["split"] for r in result["records"]}
            for group in expected:
                self.assertEqual(len({by_id[rid] for rid in group}), 1)
            rng.shuffle(data["records"])
            self.assertEqual(canonical_hash(result), canonical_hash(assign_splits(data, seed="frozen")))

    def test_malformed_manifest_fields_and_boundaries_fail_closed(self):
        for field, invalid in [
            ("sha256", "x" * 64), ("sha256", "A" * 64), ("source_sha256", "0" * 63),
            ("id", " "), ("source_image", None), ("path", "../private.jpg"),
            ("path", "/absolute.jpg"), ("path", "a\\b.jpg"), ("split", []),
            ("exposure", {}), ("upstream_training_status", []),
            ("parent_ids", ["missing"]), ("parent_ids", ["a"]),
            ("parent_ids", ["b", "b"]), ("near_duplicate_clusters", [None]),
            ("dhash64", "0" * 17), ("physical_tile_set", "unknown"),
            ("annotation_path", "labels.json"),
            ("upstream_training_status", "verified_disjoint"),
        ]:
            with self.subTest(field=field, invalid=invalid), self.assertRaises(ManifestError):
                audit(manifest(record("a", **{field: invalid})))
        for data in [None, [], {}, manifest(), manifest(record("a"), record("a")),
                     manifest(record("a")) | {"schema_version": True},
                     manifest(record("a")) | {"typo": 1}]:
            with self.subTest(data=data), self.assertRaises(ManifestError):
                audit(data)
        for distance in (-1, 65, True, 1.5):
            with self.assertRaises(ManifestError):
                grouped_components(manifest(record("a")), near_distance=distance)
        for ratios in ({}, {"test": 1}, {"train": 0}, {"train": -1}, {"train": float("nan")}, {"train": True}):
            with self.assertRaises(ManifestError):
                assign_splits(manifest(record("a")), seed="s", ratios=ratios)

    def test_parent_cycles_fail_and_long_valid_chains_avoid_recursion_limit(self):
        with self.assertRaises(ManifestError):
            audit(manifest(record("a", parent_ids=["b"]), record("b", parent_ids=["a"])))
        rows = [record(str(i), parent_ids=[str(i - 1)] if i else []) for i in range(1500)]
        self.assertEqual(len(grouped_components(manifest(*rows))), 1)

    def test_lock_pins_records_labels_policy_and_exposure_but_not_order(self):
        data = manifest(record("a", split="internal_test"), record("b", split="train"))
        lock = make_lock(data, locked_at="2026-10-02T00:00:00Z")
        self.assertTrue(verify_lock(data, lock))
        self.assertTrue(verify_lock(manifest(*reversed(data["records"])), lock))
        for field, value in [("sha256", sha("changed")), ("split", "dev"), ("notes", "new note")]:
            changed = deepcopy(data)
            changed["records"][0][field] = value
            with self.assertRaises(ManifestError):
                verify_lock(changed, lock)
        with self.assertRaises(ManifestError):
            verify_lock(data, lock | {"near_distance": 3})
        with self.assertRaises(ManifestError):
            make_lock(manifest(record("a", split="dev")))
        with self.assertRaises(ManifestError):
            make_lock(manifest(record("a")))

    def test_files_and_annotations_checked_against_disk_and_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as temp, tempfile.TemporaryDirectory() as outside:
            root = Path(temp)
            (root / "image.bin").write_bytes(b"image data")
            (root / "label.json").write_text('{"tiles": [0]}')
            data = manifest(record("a", path="image.bin", sha256=file_sha256(root / "image.bin"),
                                   annotation_path="label.json", annotation_sha256=file_sha256(root / "label.json")))
            self.assertEqual(verify_files(data, root), 2)
            (root / "label.json").write_text('{"tiles": [1]}')
            with self.assertRaisesRegex(ManifestError, "hash mismatch"):
                verify_files(data, root)
            (Path(outside) / "private.bin").write_bytes(b"private")
            (root / "escape.bin").symlink_to(Path(outside) / "private.bin")
            with self.assertRaisesRegex(ManifestError, "escapes"):
                verify_files(manifest(record("a", path="escape.bin")), root)
            with self.assertRaisesRegex(ManifestError, "missing asset"):
                verify_files(manifest(record("a", path="missing.bin")), root)


if __name__ == "__main__":
    unittest.main()
