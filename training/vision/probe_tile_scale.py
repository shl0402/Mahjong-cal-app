#!/usr/bin/env python3
"""Controlled scale diagnostic. Synthetic padding is NOT a real-hand benchmark."""
import ast
from collections import Counter
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

from evaluate_baseline import ROOT, canonical, decode, digest, EXPECTED_SHA256, load_and_audit


def main():
    model = ROOT / "vision/downloads/mahjong-yolo11n.onnx"
    assert digest(model) == EXPECTED_SHA256
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model), sess_options=options, providers=["CPUExecutionProvider"])
    names = ast.literal_eval(session.get_modelmeta().custom_metadata_map["names"])
    covered = {canonical(name) for name in names.values()}
    rows, _ = load_and_audit(ROOT / "train/data.csv", ROOT / "train/images")
    results = {}
    for height in [64, 128, 256]:
        totals = Counter()
        records = []
        for row in rows:
            expected = canonical(row["label-name"])
            if expected not in covered:
                continue
            with Image.open(ROOT / "train/images" / row["image-name"]) as source:
                image = ImageOps.exif_transpose(source).convert("RGB")
                width = max(1, int(image.width * height / image.height + .5))
                image = image.resize((width, height), Image.Resampling.BILINEAR)
                data = np.full((640, 640, 3), 114, dtype=np.float32)
                x, y = (640-width)//2, (640-height)//2
                data[y:y+height, x:x+width] = np.asarray(image, dtype=np.float32)
                tensor = (data.transpose(2, 0, 1)[None] / 255).copy()
            raw = session.run(None, {"images": tensor})[0]
            predictions = decode(raw, (0, 0, 640, 640), names)
            best = predictions[0]["tile"] if predictions else None
            totals.update(total=1, top_correct=int(best == expected),
                          exactly_one_correct=int(len(predictions) == 1 and best == expected),
                          no_detection=int(not predictions))
            records.append({"image": row["image-name"], "expected": expected,
                            "predicted": best, "detections": len(predictions)})
        results[str(height)] = {"metrics": dict(totals), "records": records}
        print(height, dict(totals), flush=True)
    destination = ROOT / "vision/reports/scale_probe.json"
    destination.write_text(json.dumps({"purpose": "Synthetic single-crop scale diagnostic, not validation accuracy",
                                       "model_sha256": EXPECTED_SHA256, "canvas": [640, 640],
                                       "padding": [114, 114, 114], "tile_heights": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
