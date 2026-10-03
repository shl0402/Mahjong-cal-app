#!/usr/bin/env python3
"""Bounded development diagnostic of the pinned legacy RiichiCam row wrapper.

This is our own implementation of the inspected window/merge equations. No
downloaded Python or TypeScript is imported or executed. Pillow integer image
resampling approximates the source's fractional browser Canvas letterbox.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import time

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

from evaluate_hand_video import canonical_order, ordinary
from evaluate_online import ROOT, match


MODEL_SHA256 = '2655fe44da2743541d4b02ef590c4e871657c9cf58efa33bf78f3d4e9a9768e8'
SOURCE_COMMIT = '8d13cbe40824c118278a7eca13e7b1d99a463d7e'
CONFIDENCE = .25
NMS_IOU = .45
WINDOW_OVERLAP = .2
CLASS_NAMES = [
    '1m', '1p', '1s', '1z', '2m', '2p', '2s', '2z',
    '3m', '3p', '3s', '3z', '4m', '4p', '4s', '4z',
    '5m', '5mr', '5p', '5pr', '5s', '5sr', '5z',
    '6m', '6p', '6s', '6z', '7m', '7p', '7s', '7z',
    '8m', '8p', '8s', '9m', '9p', '9s',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def round_positive(value):
    """JavaScript Math.round for the nonnegative dimensions used here."""
    return math.floor(value + .5)


def inference_windows(width, height, max_aspect=2, overlap=WINDOW_OVERLAP):
    """Return x,y,width,height using the pinned inferenceTiles equations."""
    if width <= 0 or height <= 0 or max_aspect <= 1:
        return [(0, 0, width, height)]
    overlap = min(max(overlap, 0), .9)
    horizontal = width > height
    long_side, short_side = (width, height) if horizontal else (height, width)
    if long_side / short_side <= max_aspect:
        return [(0, 0, width, height)]
    length = min(long_side, max(1, round_positive(short_side * max_aspect)))
    stride = max(1, round_positive(length * (1 - overlap)))
    starts = [i * stride for i in range(math.floor((long_side - length) / stride) + 1)]
    last = long_side - length
    if starts[-1] != last:
        starts.append(last)
    return [(start, 0, length, height) if horizontal else (0, start, width, length)
            for start in starts]


def iou(a, b):
    intersection = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0, min(a[3], b[3]) - max(a[1], b[1]))
    union = ((a[2] - a[0]) * (a[3] - a[1])
             + (b[2] - b[0]) * (b[3] - b[1]) - intersection)
    return intersection / union if union > 0 else 0


def merge_per_class(predictions, threshold=NMS_IOU):
    """Stable confidence sort and strict IoU>threshold, matching source merge.

    Compare original model class IDs: red and ordinary fives stay separate even
    though their normalized face identity is equal for our evaluation metric.
    """
    kept = []
    for candidate in sorted(predictions, key=lambda p: p['confidence'], reverse=True):
        if not any(candidate['model_class_id'] == previous['model_class_id']
                   and iou(candidate['box'], previous['box']) > threshold
                   for previous in kept):
            kept.append(candidate)
    return kept


def prepare_integer_pillow(image):
    width, height = image.size
    scale = 640 / max(width, height)
    scaled_w = max(1, round_positive(width * scale))
    scaled_h = max(1, round_positive(height * scale))
    px, py = (640 - scaled_w) // 2, (640 - scaled_h) // 2
    canvas = Image.new('RGB', (640, 640), (114, 114, 114))
    canvas.paste(image.convert('RGB').resize(
        (scaled_w, scaled_h), Image.Resampling.BILINEAR), (px, py))
    tensor = (np.asarray(canvas, dtype=np.float32).transpose(2, 0, 1)[None] / 255).copy()
    return tensor, (scale, px, py)


def decode_window(raw, geometry, window, full_size):
    if raw.shape != (1, 41, 8400) or not np.isfinite(raw).all():
        raise ValueError('Unexpected or nonfinite model output')
    values = raw[0]
    classes = values[4:].argmax(axis=0)
    scores = values[4:].max(axis=0)
    scale, px, py = geometry
    ox, oy, _, _ = window
    width, height = full_size
    candidates = []
    for anchor in np.flatnonzero(scores >= CONFIDENCE):
        x, y, w, h = (float(n) for n in values[:4, anchor])
        if w <= 0 or h <= 0:
            continue
        class_id = int(classes[anchor])
        label = CLASS_NAMES[class_id]
        red = label.endswith('r')
        tile = label[:-1] if red else label
        # Source does not clip boxes or cap detections. NMS IoU is invariant
        # under this common translation/scale within one window.
        box = [((x - w / 2 - px) / scale + ox) / width,
               ((y - h / 2 - py) / scale + oy) / height,
               ((x + w / 2 - px) / scale + ox) / width,
               ((y + h / 2 - py) / scale + oy) / height]
        candidates.append({
            'tile': tile,
            'tile_index': {'m': 0, 'p': 9, 's': 18, 'z': 27}[tile[1]] + int(tile[0]) - 1,
            'red_five': red, 'model_class_id': class_id, 'model_class_name': label,
            'confidence': float(scores[anchor]), 'box': box,
        })
    return merge_per_class(candidates)


def main():
    research = ROOT / 'vision/candidates/research'
    output = research / 'riichicam-legacy-tiled-development-evaluation.json'
    if output.exists():
        raise ValueError('Preserve previous evaluation; this comparison is one bounded run')
    review_path = research / 'offline_candidate_review.json'
    review = json.loads(review_path.read_text())
    candidate = next(c for c in review['candidates'] if c['id'] == 'riichicam-legacy-8d13cbe')
    if candidate['class_names'] != CLASS_NAMES:
        raise ValueError('Reviewed class order changed')
    for source in candidate['source']['verified_source_files']:
        if sha(ROOT / source['local_path']) != source['sha256']:
            raise ValueError('Pinned inspected source changed')
    model = ROOT / candidate['model']['path']
    if sha(model) != MODEL_SHA256:
        raise ValueError('Model changed')
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    session = ort.InferenceSession(str(model), sess_options=options,
                                   providers=['CPUExecutionProvider'])
    if session.get_inputs()[0].shape != [1, 3, 640, 640]:
        raise ValueError('Input shape changed')
    for _ in range(5):
        session.run(None, {'images': np.zeros((1, 3, 640, 640), np.float32)})

    def predict(image):
        started = time.perf_counter()
        windows = inference_windows(*image.size)
        combined, records = [], []
        for window in windows:  # One session; windows are deliberately sequential.
            x, y, w, h = window
            crop = image.crop((x, y, x + w, y + h))
            tensor, geometry = prepare_integer_pillow(crop)
            t = time.perf_counter()
            raw = session.run(None, {'images': tensor})[0]
            elapsed = (time.perf_counter() - t) * 1000
            proposals = decode_window(raw, geometry, window, image.size)
            combined.extend(proposals)
            records.append({'window_xywh': list(window), 'inference_ms': elapsed,
                            'proposals_after_window_nms': len(proposals)})
        predictions = merge_per_class(combined)
        return predictions, {
            'windows': records, 'window_count': len(windows),
            'inference_ms': sum(w['inference_ms'] for w in records),
            'pipeline_ms': (time.perf_counter() - started) * 1000,
            'proposals_before_cross_window_merge': len(combined),
        }

    source_path = ROOT / 'vision/reports/online_sources.json'
    annotation_path = ROOT / 'vision/reports/online_annotations.json'
    sources = {s['id']: s for s in json.loads(source_path.read_text())['sources']}
    regions = json.loads(annotation_path.read_text())['regions']
    if len(regions) != 10:
        raise ValueError('Bounded diagnostic expects exactly 10 photo regions')
    totals, photos = Counter(), []
    for region in regions:
        source = sources[region['source_id']]
        path = ROOT / source['path']
        if sha(path) != source['sha256']:
            raise ValueError('Photo changed')
        roi = region['roi']
        with Image.open(path) as opened:
            image = ImageOps.exif_transpose(opened).convert('RGB').crop(roi)
        w, h = image.size
        gt = [{'tile': a['tile'], 'box': [(a['box'][0] - roi[0]) / w,
              (a['box'][1] - roi[1]) / h, (a['box'][2] - roi[0]) / w,
              (a['box'][3] - roi[1]) / h]} for a in region['annotations']]
        predictions, timing = predict(image)
        correct = len(match(gt, predictions))
        exact = correct == len(gt) == len(predictions)
        hand14 = region['kind'] == 'hand' and len(gt) == 14
        totals.update(correct=correct, extra=len(predictions) - correct,
                      missed=len(gt) - correct, exact_regions=int(exact),
                      exact_hands14=int(exact and hand14), hands14=int(hand14))
        photos.append({'id': region['id'], 'image_size': list(image.size),
                       'predictions': predictions, 'correct': correct, 'exact': exact,
                       'ground_truth_count': len(gt), **timing})
        print(region['id'], correct, '/', len(gt), 'windows', timing['window_count'], flush=True)

    base_path = ROOT / 'vision/video_candidates/ar42-row-results.json'
    base = json.loads(base_path.read_text())
    reference = base['source']
    video = ROOT / reference['video_path']
    if sha(video) != reference['video_sha256']:
        raise ValueError('Pinned video changed')
    selected = {f['frame_index']: f for f in base['frames']}
    if len(selected) != 20:
        raise ValueError('Bounded diagnostic expects exactly 20 video frames')
    expected = [ordinary(t) for t in reference['expected_tiles']]
    rows, index = [], 0
    cap = cv2.VideoCapture(str(video))
    try:
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            if index in selected:
                image = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
                digest = hashlib.sha256(np.asarray(image).tobytes()).hexdigest()
                if digest != selected[index]['rgb_sha256']:
                    raise ValueError('Pinned frame pixels changed')
                predictions, timing = predict(image.crop(reference['roi']))
                actual = canonical_order(predictions)
                hits = sum((Counter(actual) & Counter(expected)).values())
                rows.append({'frame_index': index, 'timestamp_ms': selected[index]['timestamp_ms'],
                             'rgb_sha256': digest, 'predictions': predictions,
                             'exact_row': actual == expected, 'correct': hits,
                             'extra': len(actual) - hits, 'missed': len(expected) - hits,
                             **timing})
            index += 1
    finally:
        cap.release()
    if {r['frame_index'] for r in rows} != set(selected):
        raise ValueError('Not all pinned frames were evaluated')

    single_path = research / 'riichicam-legacy-development-evaluation.json'
    single = json.loads(single_path.read_text())
    if {r['id'] for r in photos} != {r['id'] for r in single['photo_regions']}:
        raise ValueError('Single-pass comparison photo regions differ')
    if {r['frame_index'] for r in rows} != {r['frame_index'] for r in single['video_frames']}:
        raise ValueError('Single-pass comparison frames differ')
    all_rows = photos + rows
    report = {
        'candidate': 'riichicam-legacy-source-row-wrapper-integer-pillow',
        'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'model_sha256': MODEL_SHA256, 'source_commit': SOURCE_COMMIT,
        'script_sha256': sha(Path(__file__)), 'review_sha256': sha(review_path),
        'annotation_sha256': sha(annotation_path), 'sources_sha256': sha(source_path),
        'video_reference_sha256': base['reference_sha256'],
        'video_results_reference_sha256': sha(base_path),
        'method': {'confidence': CONFIDENCE, 'per_class_nms_iou': NMS_IOU,
                   'cross_window_same_class_merge_iou': NMS_IOU, 'window_overlap_fraction': WINDOW_OVERLAP,
                   'maximum_window_aspect': 2, 'suppression_comparison': 'strict IoU > threshold',
                   'max_detections': None, 'clip_boxes': False, 'photo_matching_iou': .5,
                   'provider': 'CPUExecutionProvider', 'intra_op_threads': 2,
                   'inter_op_threads': 1, 'one_session': True, 'sequential_windows': True,
                   'warmup_runs': 5, 'timed_repeats': 1, 'optional_coverage_windows': False},
        'preprocessing': {
            'implemented': 'RGB; integer Pillow bilinear resize with positive half-up rounded dimensions, pad114 at floored integer centered offsets; float32 NCHW /255; inverse shared scale and actual integer pad.',
            'source_difference': 'Browser source computes pad from rounded dimensions/2 (possibly half-pixels), then draws at unrounded W*scale,H*scale with Canvas interpolation. This diagnostic is not fractional-Canvas pixel parity.',
        },
        'photo_totals': dict(totals),
        'video_totals': {**{k: sum(r[k] for r in rows) for k in ['correct', 'extra', 'missed']},
                         'exact_rows': sum(r['exact_row'] for r in rows), 'frames': len(rows)},
        'desktop_median_sum_of_window_inference_ms': float(np.median([r['inference_ms'] for r in all_rows])),
        'desktop_median_pipeline_ms': float(np.median([r['pipeline_ms'] for r in all_rows])),
        'total_windows': sum(r['window_count'] for r in all_rows),
        'photo_regions': photos, 'video_frames': rows,
        'single_pass_reference': {'path': str(single_path.relative_to(ROOT)), 'sha256': sha(single_path),
                                  'photo_totals': single['photo_totals'], 'video_totals': single['video_totals'],
                                  'desktop_inference_median_ms': single['desktop_inference_median_ms']},
        'limitations': [
            'Exposed convenience development photos and one correlated broadcast clip; not an untouched test or physical-phone benchmark.',
            'Video counts normalize red fives and match identities without per-frame IoU ground truth; zero or nonzero exact rows cannot establish generalization.',
            'Source-style tiling and per-class merge at fixed .25/.45; source confidence default was .45 and NMS default was .5.',
            'Compared with the previous shared single-pass decoder, this source-style decoder also preserves per-class NMS, unclipped coordinates and no arbitrary40-detection cap; differences are not attributable solely to tiling.',
            'Integer Pillow approximates fractional Canvas; no imported or executed downloaded source code.',
            'One timed evaluation per sample; desktop timing is provisional and excludes session load/warmup.',
            'No native integration, phone measurement, training, further model search or app confirmation-gate replay.',
        ],
    }
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['candidate', 'photo_totals', 'video_totals',
                     'desktop_median_sum_of_window_inference_ms', 'desktop_median_pipeline_ms', 'total_windows']}, indent=2))


if __name__ == '__main__':
    main()
