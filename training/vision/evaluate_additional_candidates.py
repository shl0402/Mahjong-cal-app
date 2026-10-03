#!/usr/bin/env python3
"""Real-photo/video diagnostics for two statically reviewed public ONNX files.

Only ONNX Runtime and our own evaluation code execute. Downloaded Python and
TypeScript sources are reference data, never imported or executed.
"""
import argparse
import ast
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
from evaluate_online import ROOT, match, prepare


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grayscale_input(image):
    # Match the package's stated Pillow recipe, including truncated dimensions.
    grey = ImageOps.autocontrast(image.convert('L'))
    scale = 640 / max(image.size)
    w, h = [max(1, int(d * scale)) for d in image.size]
    px, py = (640 - w) // 2, (640 - h) // 2
    canvas = Image.new('L', (640, 640), 0)
    canvas.paste(grey.resize((w, h), Image.Resampling.BILINEAR), (px, py))
    tensor = (np.asarray(canvas.convert('RGB'), dtype=np.float32)
              .transpose(2, 0, 1)[None] / 255).copy()
    return tensor, (px, py, w, h)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', choices=['ssttkkl', 'riichicam-legacy'], required=True)
    args = parser.parse_args()
    research = ROOT / 'vision/candidates/research'
    output = research / f'{args.candidate}-development-evaluation.json'
    if output.exists():
        raise ValueError('Preserve previous evaluation')
    if args.candidate == 'ssttkkl':
        model = research / 'mahjong_detector-0.0.6-static/model.onnx'
        expected_hash = 'fffd6d29aacf850526a4411b68b4e7c4a96957ee2f00f9076982b30dfde78c07'
        names = None
        preprocessor = grayscale_input
        recipe = 'Pillow L then autocontrast; bilinear resize with truncated dimensions; black centered letterbox; repeat into RGB float32 NCHW /255.'
    else:
        model = research / 'riichicam-legacy-8d13cbe-tile-detector.onnx'
        expected_hash = '2655fe44da2743541d4b02ef590c4e871657c9cf58efa33bf78f3d4e9a9768e8'
        # Pinned publisher class order; red fives translated to our existing
        # decoder's 0m/0p/0s spelling, retaining red_five on each prediction.
        labels = ['1m', '1p', '1s', '1z', '2m', '2p', '2s', '2z',
                  '3m', '3p', '3s', '3z', '4m', '4p', '4s', '4z',
                  '5m', '0m', '5p', '0p', '5s', '0s', '5z',
                  '6m', '6p', '6s', '6z', '7m', '7p', '7s', '7z',
                  '8m', '8p', '8s', '9m', '9p', '9s']
        names = dict(enumerate(labels))
        preprocessor = prepare
        recipe = 'Our standard single-ROI RGB bilinear centered letterbox pad114, /255; no original web-app tiling. Browser fractional canvas interpolation is not bit-identical to Pillow.'
    if sha(model) != expected_hash:
        raise ValueError('Candidate model changed')
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model), sess_options=options,
                                   providers=['CPUExecutionProvider'])
    if names is None:
        source_names = ast.literal_eval(session.get_modelmeta().custom_metadata_map['names'])
        honors = {'tou': '1z', 'nan': '2z', 'sha': '3z', 'pe': '4z',
                  'haku': '5z', 'hatsu': '6z', 'chun': '7z'}
        names = {i: honors.get(n, n) for i, n in source_names.items()}
        expected_classes = {str(n) + s for s in 'mps' for n in range(1, 10)} | {str(n) + 'z' for n in range(1, 8)}
        assert len(names) == 34 and set(names.values()) == expected_classes
    for _ in range(5):
        session.run(None, {'images': np.zeros((1, 3, 640, 640), dtype=np.float32)})

    def predict(image):
        tensor, geometry = preprocessor(image)
        start = time.perf_counter()
        raw = session.run(None, {'images': tensor})[0]
        elapsed = (time.perf_counter() - start) * 1000
        return decode(raw, geometry, names, threshold=.25, nms=.45), elapsed

    sources = {s['id']: s for s in json.loads((ROOT / 'vision/reports/online_sources.json').read_text())['sources']}
    regions = json.loads((ROOT / 'vision/reports/online_annotations.json').read_text())['regions']
    photos = []
    photo_totals = Counter()
    for region in regions:
        source = sources[region['source_id']]
        path = ROOT / source['path']
        assert sha(path) == source['sha256']
        roi = region['roi']
        image = ImageOps.exif_transpose(Image.open(path)).convert('RGB').crop(roi)
        w, h = image.size
        gt = [{'tile': a['tile'], 'box': [(a['box'][0] - roi[0]) / w,
              (a['box'][1] - roi[1]) / h, (a['box'][2] - roi[0]) / w,
              (a['box'][3] - roi[1]) / h]} for a in region['annotations']]
        predictions, elapsed = predict(image)
        correct = len(match(gt, predictions))
        exact = correct == len(gt) == len(predictions)
        hand14 = region['kind'] == 'hand' and len(gt) == 14
        photo_totals.update(correct=correct, extra=len(predictions) - correct,
                            missed=len(gt) - correct, exact_regions=int(exact),
                            exact_hands14=int(exact and hand14), hands14=int(hand14))
        photos.append({'id': region['id'], 'predictions': predictions, 'correct': correct,
                       'exact': exact, 'inference_ms': elapsed})

    base_path = ROOT / 'vision/video_candidates/ar42-row-results.json'
    base = json.loads(base_path.read_text())
    reference = base['source']
    video = ROOT / reference['video_path']
    assert sha(video) == reference['video_sha256']
    selected = {f['frame_index']: f for f in base['frames']}
    expected = [ordinary(t) for t in reference['expected_tiles']]
    cap = cv2.VideoCapture(str(video))
    rows = []
    index = 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        if index in selected:
            image = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
            assert hashlib.sha256(np.asarray(image).tobytes()).hexdigest() == selected[index]['rgb_sha256']
            predictions, elapsed = predict(image.crop(reference['roi']))
            actual = canonical_order(predictions)
            hits = sum((Counter(actual) & Counter(expected)).values())
            rows.append({'frame_index': index, 'timestamp_ms': selected[index]['timestamp_ms'],
                         'predictions': predictions, 'exact_row': actual == expected,
                         'correct': hits, 'extra': len(actual) - hits,
                         'missed': len(expected) - hits, 'inference_ms': elapsed})
        index += 1
    cap.release()
    assert {r['frame_index'] for r in rows} == set(selected)
    report = {
        'candidate': args.candidate, 'model_sha256': expected_hash,
        'model_bytes': model.stat().st_size, 'preprocessing': recipe,
        'canonical_model_names': names, 'reference_sha256': base['reference_sha256'],
        'method': {'confidence': .25, 'nms': .45, 'max_detections': 40,
                   'photo_matching_iou': .5, 'threads': 2, 'provider': 'CPUExecutionProvider'},
        'photo_totals': dict(photo_totals),
        'video_totals': {**{k: sum(r[k] for r in rows) for k in ['correct', 'extra', 'missed']},
                         'exact_rows': sum(r['exact_row'] for r in rows), 'frames': len(rows)},
        'photo_regions': photos, 'video_frames': rows,
        'desktop_inference_median_ms': float(np.median([r['inference_ms'] for r in photos + rows])),
        'limitations': ['Exposed development photos and one correlated video clip; upstream training overlap unknown.',
                        'Fixed app comparison thresholds, not the original applications full pipelines or default thresholds.',
                        'Video compares canonical identities; no per-frame IoU ground truth or red-five accuracy claim.',
                        'No native integration, actual phone timing, or app gate replay for these candidates.',
                        'Downloaded package source was inspected statically, never installed or executed.']}
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['candidate', 'photo_totals', 'video_totals', 'desktop_inference_median_ms']}))


if __name__ == '__main__':
    main()
