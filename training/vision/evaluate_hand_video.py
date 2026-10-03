#!/usr/bin/env python3
"""Real timestamped row diagnostic, with reference frozen before inference.

This is a broadcast table camera, not a phone test or a winning-hand benchmark.
Never duplicate a still to simulate temporal evidence.
"""
import argparse, ast, datetime, hashlib, json, time
from collections import Counter
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image
from evaluate_online import ROOT, prepare
from evaluate_baseline import decode

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def ordinary(tile):return '5'+tile[1] if tile in ['0m','0p','0s'] else tile
def canonical_order(predictions):
    # The shared Python detector returns NMS results in confidence order.
    # Whole-row identity comparison must use physical order, as the app does.
    return [ordinary(p['tile']) for p in sorted(predictions,key=lambda p:p['box'][0]+p['box'][2])]

def main():
    p=argparse.ArgumentParser();p.add_argument('--reference',required=True);p.add_argument('--candidate',choices=['ar42','baseline','trained'],required=True);p.add_argument('--output',required=True)
    a=p.parse_args();out=Path(a.output)
    if out.exists():raise ValueError('Preserve existing video evaluation')
    ref=json.loads(Path(a.reference).read_text());path=ROOT/ref['video_path']
    if sha(path)!=ref['video_sha256']:raise ValueError('Video hash changed')
    if a.candidate=='ar42':
        model=ROOT/'vision/candidates/downloads/ar-yolov8-42.onnx'
        expected_hash='63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a'
        class_path=ROOT/'vision/candidates/ar-class-names.txt'
        if sha(class_path)!='58f9fa2c2b01f554a5dcb5526a579fe6e79c3c5acc5f206ce1535163c376046e':raise ValueError('Class map changed')
        raw_names=class_path.read_text().splitlines()
        winds=['EW','SW','WW','NW','WD','GD','RD']
        names={i: str(winds.index(n)+1)+'z' if n in winds else n[0]+{'B':'s','C':'m','D':'p'}[n[-1]] if n[-1] in 'BCD' else 'UNKNOWN' for i,n in enumerate(raw_names)}
    elif a.candidate=='trained':
        export_path=ROOT/'vision/training/detector_runs/full20/export_manifest.json'
        export=json.loads(export_path.read_text())
        model=ROOT/export['model_path'];expected_hash=export['onnx_sha256']
        classes=export['class_names']
        expected_classes={str(n)+s for s in 'mps' for n in range(1,10)}|{str(n)+'z' for n in range(1,8)}
        if len(classes)!=34 or set(classes)!=expected_classes:raise ValueError('Trained class map changed')
        names=dict(enumerate(classes))
    else:
        model=ROOT.parent/'app/assets/models/mahjong-yolo11n-v2-2b1adbdb.onnx';expected_hash='2b1adbdb6f395eba7ce755f87672c8a4275d6eeae68d26c5206ae6a89f4e628a';names=None
    if sha(model)!=expected_hash:raise ValueError('Model hash changed')
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(model),sess_options=options,providers=['CPUExecutionProvider'])
    if names is None:names=ast.literal_eval(session.get_modelmeta().custom_metadata_map['names'])
    cap=cv2.VideoCapture(str(path));fps=cap.get(cv2.CAP_PROP_FPS);count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if not fps or not count:raise ValueError('Cannot decode video')
    period=ref['sample_period_ms'];selected={f['frame_index']:f['clip_pts_ms'] for f in ref['reviewed_frames']}
    pts_offset=min(selected.values());decoded=0
    expected=[ordinary(t) for t in ref['expected_tiles']];frames=[];latencies=[]
    for index in range(count):
        ok,bgr=cap.read()
        if not ok:break
        decoded+=1
        if index not in selected:continue
        # Pinned reference includes ffprobe presentation timestamps. OpenCV
        # normalizes the first timestamp to0; verify that offset explicitly.
        decoder_timestamp=round(cap.get(cv2.CAP_PROP_POS_MSEC))
        timestamp=selected[index]
        if abs(timestamp-(decoder_timestamp+pts_offset))>2:raise ValueError('Decoder/reference timestamp mismatch')
        if frames and timestamp<=frames[-1]['timestamp_ms']:raise ValueError('Nonmonotonic video timestamps')
        in_reference=any(start<=timestamp<end for start,end in ref['valid_intervals_ms'])
        image=Image.fromarray(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB));crop=image.crop(ref['roi']);tensor,geometry=prepare(crop)
        t=time.perf_counter();raw=session.run(None,{'images':tensor})[0];latencies.append((time.perf_counter()-t)*1000)
        predictions=decode(raw,geometry,names);actual=canonical_order(predictions)
        hits=sum((Counter(actual)&Counter(expected)).values()) if in_reference else None
        frames.append({'frame_index':index,'timestamp_ms':timestamp,'source_timestamp_ms':ref['source_start_ms']+timestamp,
                       'rgb_sha256':hashlib.sha256(np.asarray(image).tobytes()).hexdigest(),'predictions':predictions,
                       'reference_valid':in_reference,'exact_ordered_canonical_row':actual==expected if in_reference else None,
                       'identity_multiset_correct':hits,'identity_multiset_extra':len(actual)-hits if in_reference else None,
                       'identity_multiset_missed':len(expected)-hits if in_reference else None})
    cap.release()
    if {f['frame_index'] for f in frames}!=set(selected):raise ValueError('Not all pinned reference frames decoded')
    valid=[f for f in frames if f['reference_valid']]
    report={'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'candidate':a.candidate,'model_sha256':expected_hash,
            'reference_path':a.reference,'reference_sha256':sha(a.reference),'source':ref,'source_fps':fps,'source_frame_count':decoded,
            'container_frame_count_estimate':count,
            'timestamp_origin':'Pinned ffprobe presentation timestamps verified against normalized OpenCV decoder time; source absolute times approximate within one frame',
            'threshold':.25,'nms':.45,'sample_period_ms':period,'evaluated_frames':len(frames),'reference_frames':len(valid),
            'exact_ordered_canonical_rows':sum(f['exact_ordered_canonical_row'] for f in valid),
            'minimum_confidence_ge_080_and_correct_count':sum(len(f['predictions'])==len(expected) and min((d['confidence'] for d in f['predictions']),default=0)>=.8 for f in valid),
            'identity_multiset_totals':{k:sum(f['identity_multiset_'+k] for f in valid) for k in ['correct','extra','missed']},
            'desktop_inference_median_ms':float(np.median(latencies)), 'desktop_inference_p95_ms':float(np.percentile(latencies,95)),
            'temporal_gate_replay_performed':False,
            'limitations':['One short video of one tile set; adjacent frames are correlated, not independent trials.',
                           '13 tiles, including one red five, are not a complete14-tile winning hand; app count menu does not include13.',
                           'Canonical comparison normalizes redfive to5; AR42 cannot preserve the red attribute.',
                           'Manual fixed cropped ROI is a controlled diagnostic, not automatic table reconstruction.',
                           'Identity multiset counts do not require IoU matching and are not detection precision/recall.',
                           'Upstream training overlap unknown; no unseen-set or actual-phone performance claim.'], 'frames':frames}
    out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ['frames','source','limitations']},indent=2))
if __name__=='__main__':main()
