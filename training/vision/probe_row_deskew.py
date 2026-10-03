#!/usr/bin/env python3
"""Development-only geometry experiment; does not change the shipped app.

Estimate a single row angle from box centres, without using ground-truth labels.
Only rotate2–20 degrees when median line residual <=25% median tile height.
The existing video reference is already development material, not a fresh test.
"""
import hashlib, json, math, statistics, time
from collections import Counter
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image
from evaluate_online import ROOT, prepare
from evaluate_baseline import decode
from evaluate_hand_video import canonical_order, ordinary

def angle_from_boxes(predictions,width,height):
    if len(predictions)<5:return 0.
    points=[((p['box'][0]+p['box'][2])*width/2,(p['box'][1]+p['box'][3])*height/2) for p in predictions]
    slopes=[(b[1]-a[1])/(b[0]-a[0]) for i,a in enumerate(points) for b in points[i+1:] if abs(b[0]-a[0])>=width*.2]
    if not slopes:return 0.
    slope=statistics.median(slopes);offset=statistics.median(y-slope*x for x,y in points)
    tile_height=statistics.median((p['box'][3]-p['box'][1])*height for p in predictions)
    if tile_height<=0 or statistics.median(abs(y-slope*x-offset) for x,y in points)>tile_height*.25:return 0.
    angle=math.degrees(math.atan(slope))
    return angle if 2<=abs(angle)<=20 else 0.

def main():
    output=ROOT/'vision/video_candidates/deskew-development-probe.json'
    if output.exists():raise ValueError('Preserve previous experiment')
    baseline_path=ROOT/'vision/video_candidates/ar42-row-results.json';base=json.loads(baseline_path.read_text());reference=base['source']
    model=ROOT/'vision/candidates/downloads/ar-yolov8-42.onnx'
    if hashlib.sha256(model.read_bytes()).hexdigest()!=base['model_sha256']:raise ValueError('Model changed')
    raw_names=(ROOT/'vision/candidates/ar-class-names.txt').read_text().splitlines();winds=['EW','SW','WW','NW','WD','GD','RD']
    names={i:str(winds.index(n)+1)+'z' if n in winds else n[0]+{'B':'s','C':'m','D':'p'}[n[-1]] if n[-1] in 'BCD' else 'UNKNOWN' for i,n in enumerate(raw_names)}
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(model),sess_options=options,providers=['CPUExecutionProvider'])
    video=ROOT/reference['video_path']
    if hashlib.sha256(video.read_bytes()).hexdigest()!=reference['video_sha256']:raise ValueError('Video changed')
    cap=cv2.VideoCapture(str(video));selected={f['frame_index']:f for f in base['frames']};expected=[ordinary(t) for t in reference['expected_tiles']]
    rows=[];index=0
    while True:
        ok,bgr=cap.read()
        if not ok:break
        if index in selected:
            row=selected[index];scene=Image.fromarray(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)).crop(reference['roi'])
            angle=angle_from_boxes(row['predictions'],scene.width,scene.height)
            corrected=scene.rotate(angle,Image.Resampling.BICUBIC,expand=True,fillcolor=(114,114,114)) if angle else scene
            tensor,geometry=prepare(corrected);start=time.perf_counter();pred=decode(session.run(None,{'images':tensor})[0],geometry,names);elapsed=(time.perf_counter()-start)*1000
            actual=canonical_order(pred);hits=sum((Counter(actual)&Counter(expected)).values())
            rows.append({'frame_index':index,'timestamp_ms':row['timestamp_ms'],'estimated_angle_degrees':angle,'predictions_in_rotated_roi':pred,
                         'exact_ordered_canonical_row':actual==expected,'identity_multiset_correct':hits,'extra':len(actual)-hits,'missed':len(expected)-hits,
                         'minimum_confidence':min((p['confidence'] for p in pred),default=0),'second_inference_ms':elapsed})
        index+=1
    cap.release()
    report={'experiment':'label-free geometry deskew on already exposed video development clip','source_reference_sha256':base['reference_sha256'],
            'model_sha256':base['model_sha256'],'base_report_sha256':hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
            'method':'Median wide-pair box-centre slope; need5boxes, dx>=20%width, residual<=25%medianheight, angle2–20deg; bicubicexpandedrotation/pad114 then same640letterbox/.25conf/.45NMS. No ground-truth labels used to choose angle.',
            'frames':rows,'totals':{'exact_rows':sum(r['exact_ordered_canonical_row'] for r in rows),'frames':len(rows),'correct':sum(r['identity_multiset_correct'] for r in rows),'extra':sum(r['extra'] for r in rows),'missed':sum(r['missed'] for r in rows)},
            'limitations':['One already exposed13tile video, not a new holdout or completewinninghand.','Predictions are in rotatedcrop coordinates; not integrated with nativepreview or appgate.','Adds a second model inference. Improvement here would need cross-source/device validation.']}
    output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report['totals']))
if __name__=='__main__':main()
