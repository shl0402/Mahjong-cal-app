#!/usr/bin/env python3
"""Development-only overlapping-window inference; never changes the app.

Policy fixed before this probe: two windows spanning 60% of a wide row each,
20% overlap, centre ownership at the row midpoint, original thresholds. This
tests whether more input pixels per tile help. It is not a new held-out test.
"""
import argparse
import hashlib
import json
import time
from collections import Counter

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

from evaluate_baseline import decode
from evaluate_hand_video import canonical_order, ordinary
from evaluate_online import ROOT, iou, match, prepare


def windows(width, height):
    if width / height < 2:
        return [(0, width, 0.0, 1.0)]
    return [(0, round(width * .6), 0.0, .5),
            (round(width * .4), width, .5, 1.0)]


def merge_windows(parts, width):
    candidates = []
    for (left, right, owner_left, owner_right), predictions in parts:
        for original in predictions:
            prediction = dict(original)
            x1, y1, x2, y2 = original['box']
            box = [(left + x1 * (right - left)) / width, y1,
                   (left + x2 * (right - left)) / width, y2]
            centre = (box[0] + box[2]) / 2
            # Half-open ownership means a midpoint tile has exactly one owner.
            if centre < owner_left or (centre >= owner_right and owner_right < 1):
                continue
            prediction['box'] = box
            candidates.append(prediction)
    kept = []
    for prediction in sorted(candidates, key=lambda p: p['confidence'], reverse=True):
        if all(iou(prediction['box'], previous['box']) < .45 for previous in kept):
            kept.append(prediction)
            if len(kept) == 40:
                break
    return kept


def predict(session, names, image):
    parts = []
    start = time.perf_counter()
    for window in windows(*image.size):
        left, right, _, _ = window
        tensor, geometry = prepare(image.crop((left, 0, right, image.height)))
        raw = session.run(None, {'images': tensor})[0]
        parts.append((window, decode(raw, geometry, names)))
    return merge_windows(parts, image.width), (time.perf_counter() - start) * 1000


def predict_scaled(session, names, image, extent):
    """Smaller content on the unchanged 640-square model input, without tiling."""
    start = time.perf_counter()
    scale = extent / max(image.size)
    width, height = [max(1, int(d * scale + .5)) for d in image.size]
    px, py = (640 - width) // 2, (640 - height) // 2
    tensor = np.full((640, 640, 3), 114, dtype=np.float32)
    tensor[py:py + height, px:px + width] = np.asarray(
        image.resize((width, height), Image.Resampling.BILINEAR), dtype=np.float32)
    tensor = (tensor.transpose(2, 0, 1)[None] / 255).copy()
    raw = session.run(None, {'images': tensor})[0]
    predictions = decode(raw, (px, py, width, height), names)
    return predictions, (time.perf_counter() - start) * 1000


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scale', type=int, choices=[256, 384, 480],
                        help='Separate fixed-scale follow-up; does not use overlapping windows')
    args = parser.parse_args()
    name = f'scale{args.scale}' if args.scale else 'windows'
    output = ROOT / f'vision/video_candidates/{name}-development-probe.json'
    if output.exists():
        raise ValueError('Preserve previous experiment')
    base_path = ROOT / 'vision/video_candidates/ar42-row-results.json'
    base = json.loads(base_path.read_text())
    reference = base['source']
    model = ROOT / 'vision/candidates/downloads/ar-yolov8-42.onnx'
    assert hashlib.sha256(model.read_bytes()).hexdigest() == base['model_sha256']
    class_path = ROOT / 'vision/candidates/ar-class-names.txt'
    assert hashlib.sha256(class_path.read_bytes()).hexdigest() == '58f9fa2c2b01f554a5dcb5526a579fe6e79c3c5acc5f206ce1535163c376046e'
    winds = ['EW', 'SW', 'WW', 'NW', 'WD', 'GD', 'RD']
    names = {i: str(winds.index(n) + 1) + 'z' if n in winds else
             n[0] + {'B': 's', 'C': 'm', 'D': 'p'}[n[-1]] if n[-1] in 'BCD'
             else 'UNKNOWN' for i, n in enumerate(class_path.read_text().splitlines())}
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model), sess_options=options,
                                   providers=['CPUExecutionProvider'])
    run_predict = (lambda image: predict_scaled(session, names, image, args.scale)) if args.scale else (lambda image: predict(session, names, image))
    video = ROOT / reference['video_path']
    assert hashlib.sha256(video.read_bytes()).hexdigest() == reference['video_sha256']
    cap = cv2.VideoCapture(str(video))
    selected = {f['frame_index']: f for f in base['frames']}
    expected = [ordinary(t) for t in reference['expected_tiles']]
    rows = []
    index = 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        if index in selected:
            image = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
            assert hashlib.sha256(np.asarray(image).tobytes()).hexdigest() == selected[index]['rgb_sha256']
            predictions, elapsed = run_predict(image.crop(reference['roi']))
            actual = canonical_order(predictions)
            hits = sum((Counter(actual) & Counter(expected)).values())
            rows.append({'frame_index': index, 'predictions': predictions,
                         'exact_row': actual == expected, 'correct': hits,
                         'extra': len(actual) - hits, 'missed': len(expected) - hits,
                         'pipeline_ms': elapsed})
        index += 1
    cap.release()
    assert {r['frame_index'] for r in rows} == set(selected)

    sources = {s['id']: s for s in json.loads((ROOT / 'vision/reports/online_sources.json').read_text())['sources']}
    regions = json.loads((ROOT / 'vision/reports/online_annotations.json').read_text())['regions']
    photo_rows = []
    photo_totals = Counter()
    for region in regions:
        source = sources[region['source_id']]
        path = ROOT / source['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == source['sha256']
        roi = region['roi']
        image = ImageOps.exif_transpose(Image.open(path)).convert('RGB').crop(roi)
        w, h = image.size
        gt = [{'tile': a['tile'], 'box': [(a['box'][0] - roi[0]) / w,
              (a['box'][1] - roi[1]) / h, (a['box'][2] - roi[0]) / w,
              (a['box'][3] - roi[1]) / h]} for a in region['annotations']]
        predictions, elapsed = run_predict(image)
        correct = len(match(gt, predictions))
        exact = correct == len(gt) == len(predictions)
        hand14 = region['kind'] == 'hand' and len(gt) == 14
        photo_totals.update(correct=correct, extra=len(predictions) - correct,
                            missed=len(gt) - correct, exact_regions=int(exact),
                            exact_hands14=int(exact and hand14), hands14=int(hand14))
        photo_rows.append({'id': region['id'], 'predictions': predictions,
                           'correct': correct, 'exact_region': exact, 'pipeline_ms': elapsed})
    report = {
        'experiment': f'Development-only {name} input probe; not integrated',
        'model_sha256': base['model_sha256'],
        'reference_sha256': base['reference_sha256'],
        'policy': f'Resize content longest side to {args.scale} on unchanged 640 RGB input padded114; confidence .25, class-agnostic NMS .45 and cap40.' if args.scale else 'For aspect ratio >=2, two 60%-width crops with 20% overlap; midpoint centre ownership; otherwise one crop. Same 640 RGB letterbox, confidence .25, class-agnostic NMS .45 and cap40.',
        'video_totals': {**{k: sum(r[k] for r in rows) for k in ['correct', 'extra', 'missed']},
                         'exact_rows': sum(r['exact_row'] for r in rows), 'frames': len(rows)},
        'photo_totals': dict(photo_totals), 'video_frames': rows, 'photo_regions': photo_rows,
        'limitations': ['Previously exposed development material, not independent trials or a fresh holdout.',
                        'One model call per scaled row; no phone performance claim.' if args.scale else 'Two model calls per wide row; no phone performance claim.',
                        'Video uses identity multisets; photos use class-aware IoU matching.']}
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['video_totals', 'photo_totals']}))


if __name__ == '__main__':
    main()
