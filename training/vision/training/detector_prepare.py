#!/usr/bin/env python3
"""Create detector train/dev inputs only; never link the consumed evaluation set."""
import collections
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'vision/training'
DATA = BASE / 'detector_data'
MANIFEST = ROOT / 'vision/datasets/rf100vl_mahjong/image_manifest.json'
LOCK = ROOT / 'vision/validation/rf100vl_internal_test_v1.lock.json'
WEIGHTS = BASE / 'detector_downloads/yolo11n-coco.pt'
WEIGHTS_SHA = '0ebbc80d4a7680d14987a577cd21342b65ecfd94632bd9a8da63ae6417644ee1'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    source = json.loads(MANIFEST.read_text())
    protected = set(json.loads(LOCK.read_text())['protected_ids'])
    classes = source['classes']
    assert len(classes) == 34 and sha(WEIGHTS) == WEIGHTS_SHA
    test = [r for r in source['records'] if r['split'] == 'internal_test']
    assert {r['id'] for r in test} == protected
    test_groups = {r['group_id'] for r in test}
    summary = collections.Counter()
    clipped = []
    rows = []
    for record in source['records']:
        split = record['split']
        if split not in ('train', 'dev'):
            continue
        assert record['id'] not in protected and record['group_id'] not in test_groups
        src = ROOT / record['path']
        assert sha(src) == record['sha256'], src
        stem = hashlib.sha256(record['id'].encode()).hexdigest()[:24]
        image = DATA / 'images' / split / (stem + src.suffix)
        label = DATA / 'labels' / split / (stem + '.txt')
        image.parent.mkdir(parents=True, exist_ok=True)
        label.parent.mkdir(parents=True, exist_ok=True)
        if not image.exists():
            image.symlink_to(src)
        w, h = record['width'], record['height']
        lines = []
        for annotation in record['annotations']:
            x, y, bw, bh = annotation['bbox']
            x1, y1, x2, y2 = max(0, x), max(0, y), min(w, x + bw), min(h, y + bh)
            assert x2 > x1 and y2 > y1
            if (x1, y1, x2-x1, y2-y1) != (x, y, bw, bh):
                clipped.append({'image_id':record['id'], 'annotation_id':annotation['id']})
            values = (classes.index(annotation['label']), (x1+x2)/2/w, (y1+y2)/2/h, (x2-x1)/w, (y2-y1)/h)
            lines.append(f'{values[0]} ' + ' '.join(f'{v:.10f}' for v in values[1:]))
        label.write_text('\n'.join(lines) + '\n')
        rows.append({'id':record['id'],'split':split,'group_id':record['group_id'], 'image_sha256':record['sha256'], 'label_sha256':sha(label), 'prepared_image':str(image.relative_to(ROOT))})
        summary[split + '_images'] += 1
        summary[split + '_boxes'] += len(lines)
    data_yaml = DATA / 'dataset.yaml'
    data_yaml.write_text('path: ' + json.dumps(str(DATA)) + '\ntrain: images/train\nval: images/dev\nnames:\n' + ''.join(f'  {i}: {name}\n' for i,name in enumerate(classes)))
    plan = {
        'experiment_id':'rf100vl-yolo11n-coco-v1', 'frozen_at':datetime.now(timezone.utc).isoformat(),
        'source_manifest_sha256':sha(MANIFEST), 'source_lock_sha256':sha(LOCK),
        'source_test_already_consumed':True,
        'evaluation_status':'Any later evaluation on the 156 images is a follow-up diagnostic, not a fresh holdout; the decision to train followed previous model results.',
        'initial_weights':{'url':'https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11n.pt','sha256':WEIGHTS_SHA,'bytes':WEIGHTS.stat().st_size,'task':'generic COCO, not mahjong-specific'},
        'class_names':classes, 'counts':dict(summary), 'clipped_boxes':clipped,
        'hyperparameters':{'epochs':20,'imgsz':640,'batch':8,'seed':20261002,'workers':2,'device':'mps','fliplr':0.0,'flipud':0.0,'degrees':180.0,'translate':0.05,'scale':0.25,'perspective':0.0005,'mosaic':0.2,'close_mosaic':5,'mixup':0.0,'amp':False,'optimizer':'auto','deterministic':True,'patience':100,'cache':False,'plots':False},
        'selection':'Ultralytics standard detection fitness = 0.1 * dev mAP50 + 0.9 * dev mAP50-95; best.pt; no test-based selection',
        'probe':'One epoch in a separate run, discarded; fresh initialization and seed for the full 20 epochs.',
        'license':'Ultralytics generic weights/code AGPL-3.0 or commercial terms; RF100 mirror labels MIT, individual image rights provenance not reconstructed.',
        'prepared_records':rows,
    }
    destination = BASE / 'detector_EXPERIMENT_PLAN.json'
    if destination.exists():
        raise RuntimeError('Refusing to overwrite frozen experiment plan')
    destination.write_text(json.dumps(plan,indent=2)+'\n')
    print(json.dumps({'plan':str(destination),'sha256':sha(destination),'counts':dict(summary),'clipped_boxes':len(clipped)},indent=2))

if __name__ == '__main__':
    main()
