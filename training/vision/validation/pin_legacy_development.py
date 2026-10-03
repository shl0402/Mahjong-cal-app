"""Record previously inspected Commons photos/video as development-only.

Run once per intentional provenance snapshot. Originals and licensing records
are retained in their existing locations; no media is copied or altered.
"""

import json
from pathlib import Path

from vision.validation.manifest import audit, file_sha256, fingerprint_image, verify_files


ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / "vision/validation/legacy_development_manifest.json"


def build():
    sources = json.loads((ROOT / "vision/reports/online_sources.json").read_text())["sources"]
    video = json.loads((ROOT / "vision/reports/online_video_source.json").read_text())
    video["id"] = "commons-video:PLIHWYxBfrE"
    annotations = "vision/reports/online_annotations.json"
    label_hash = file_sha256(ROOT / annotations)
    rows = []
    for source in sources + [video]:
        rid = source["id"]
        row = {
            "id": rid, "path": source["path"], "source_image": source["source_page"],
            "parent_capture": None, "session_id": None, "physical_tile_set": None,
            "dataset_version": "commons-revision:" + source["revision_timestamp"],
            "sha256": source["sha256"], "source_sha256": source["sha256"],
            "split": "dev", "exposure": "development", "upstream_training_status": "unknown",
            "parent_ids": [], "near_duplicate_clusters": [],
            "notes": "Previously evaluated during model selection; all derived crops/frames stay dev. "
                     "Full attribution and license retained in vision/reports/online_sources.json or online_video_source.json.",
        }
        if source is not video:
            fingerprint = fingerprint_image(ROOT / source["path"])
            if fingerprint["sha256"] != source["sha256"]:
                raise ValueError(f"Pinned source changed: {rid}")
            row.update(fingerprint)
            row.update(annotation_path=annotations, annotation_sha256=label_hash)
        if rid in {"commons-31193194", "commons-31195555", "commons-31198498"}:
            row["near_duplicate_clusters"] = ["conservative-review:french-gray-table-suspected-common-tiles"]
            row["notes"] += " Conservative relationship: likely shared physical tile set, not independently verified."
        rows.append(row)
    manifest = {"schema_version": 1, "manifest_id": "legacy-commons-development-2026-10-02", "records": rows}
    audit(manifest, require_assigned=True)
    verify_files(manifest, ROOT)
    return manifest


if __name__ == "__main__":
    manifest = build()
    with DESTINATION.open("x") as output:
        json.dump(manifest, output, indent=2, ensure_ascii=False)
        output.write("\n")
    print(DESTINATION)
