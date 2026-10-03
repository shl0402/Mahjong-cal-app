"""Extract only regular RF100-VL dataset files, rejecting unsafe tar paths.

--partial is for early inspection while a public archive downloads. It does not
assert archive integrity. A complete extraction requires the pinned SHA-256.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile

EXPECTED_SHA256 = "f2352bc102a8f177b886d57e1acfe2d5b53c27b137e6f2f79fe9a6c010db598e"
MAX_ARCHIVE_BYTES = 2_000_000_000


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--partial", action="store_true")
    args = parser.parse_args()
    base = Path(__file__).resolve().parent
    archive = base / "sources/mahjong.tar"
    destination = base / "rf100vl_mahjong"
    size = archive.stat().st_size
    if size > MAX_ARCHIVE_BYTES:
        raise ValueError("Archive exceeds pinned download size budget")
    digest = None
    if not args.partial:
        with archive.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if digest != EXPECTED_SHA256:
            raise ValueError(f"Archive SHA-256 mismatch: {digest}")
    destination.mkdir(exist_ok=True)
    total = 0
    files = 0
    seen: set[str] = set()
    with tarfile.open(archive, "r:") as tar:
        for member in tar:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "mahjong":
                raise ValueError(f"Unsafe tar path: {member.name!r}")
            if member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
                raise ValueError(f"Unsafe tar member type: {member.name!r}")
            if member.name in seen:
                raise ValueError(f"Duplicate tar member: {member.name!r}")
            seen.add(member.name)
            if member.offset_data + member.size > size:
                if args.partial:
                    break
                raise ValueError("Truncated archive")
            target = destination.joinpath(*path.parts[1:])
            if not target.resolve().is_relative_to(destination.resolve()):
                raise ValueError(f"Target escapes destination: {member.name!r}")
            if target.is_symlink() or any(p.is_symlink() for p in target.parents if p != destination.parent):
                raise ValueError(f"Existing symlink at destination: {member.name!r}")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if target.suffix.lower() not in {".jpg", ".jpeg", ".png", ".json", ".txt"}:
                raise ValueError(f"Unexpected dataset file: {member.name!r}")
            total += member.size
            if total > MAX_ARCHIVE_BYTES:
                raise ValueError("Extracted data exceeds size budget")
            stream = tar.extractfile(member)
            assert stream is not None
            data = stream.read()
            if len(data) != member.size:
                raise ValueError("Truncated member")
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.read_bytes() != data:
                target.write_bytes(data)
            files += 1
    report = {
        "archive": str(archive.relative_to(base)),
        "archive_bytes_at_start": size,
        "expected_sha256": EXPECTED_SHA256,
        "verified_sha256": digest,
        "partial": args.partial,
        "files_extracted": files,
        "extracted_bytes": total,
    }
    (destination / "extraction_status.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
