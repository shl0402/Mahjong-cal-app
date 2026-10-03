#!/usr/bin/env python3
"""Real motion/negative-domain diagnostic; no claim of hand detection accuracy.

Sample the entire licensed documentary at 2 fps, with a fixed centered 3.2:1
guide. The video depicts carving, interviews, and display tiles, not a legal
concealed hand held inside the scanner guide. Never synthesize repeated frames.
"""
import ast,datetime,hashlib,json,time
from collections import Counter
import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image,ImageDraw
from evaluate_online import ROOT,prepare
from evaluate_baseline import decode

def main():
    source=json.loads((ROOT/'vision/reports/online_video_source.json').read_text())
    path=ROOT/source['path'];assert hashlib.sha256(path.read_bytes()).hexdigest()==source['sha256']
    model=ROOT/'vision/downloads/mahjong-yolo11n-v2.onnx'
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(model),sess_options=options,providers=['CPUExecutionProvider'])
    names=ast.literal_eval(session.get_modelmeta().custom_metadata_map['names'])
    cap=cv2.VideoCapture(str(path));fps=cap.get(cv2.CAP_PROP_FPS);frame_count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    selected={int(i*fps/2+.5) for i in range(int(frame_count/fps*2))}
    records=[];eligible=Counter();counts=Counter();latencies=[];panels=[]
    # Timestamps picked after watching the coarse contact sheet, before inference.
    illustrate={0,50,100,150,200,260}
    for frame_index in range(frame_count):
        ok,bgr=cap.read()
        if not ok:break
        if frame_index not in selected:continue
        image=Image.fromarray(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB));width,height=image.size
        rw=int(width*.92+.5);rh=int(rw/3.2+.5);left=(width-rw)//2;top=(height-rh)//2
        roi=[left,top,left+rw,top+rh];crop=image.crop(roi);tensor,geometry=prepare(crop)
        start=time.perf_counter();raw=session.run(None,{'images':tensor})[0];latencies.append((time.perf_counter()-start)*1000)
        pred=decode(raw,geometry,names);counts[len(pred)]+=1
        confidence=min((p['confidence'] for p in pred),default=0)
        # Necessary-only gate condition. The real app also checks single-row
        # arrangement, tile multiplicities, UNKNOWN, and temporal agreement.
        possible=[n for n in [2,5,8,11,14,17] if len(pred)==n and confidence>=.8]
        eligible.update(possible)
        record={'frame_index':frame_index,'timestamp_ms':int(frame_index/fps*1000+.5),
                'rgb_sha256':hashlib.sha256(np.asarray(image).tobytes()).hexdigest(),'roi':roi,
                'predictions':pred,'count_and_min_confidence_eligible_for_counts':possible}
        records.append(record)
        sec=int(frame_index/fps)
        if sec in illustrate and frame_index==int(sec*fps):
            render=crop.copy();draw=ImageDraw.Draw(render)
            for p in pred:
                box=[v*(rw if i%2==0 else rh) for i,v in enumerate(p['box'])]
                draw.rectangle(box,outline='#ff8500',width=2)
                draw.text((box[0],box[1]),f"{p['tile']} {p['confidence']:.2f}",fill='black',stroke_width=1,stroke_fill='white')
            panels.append((sec,render,len(pred)))
        if len(records)%100==0:print(len(records),'frames evaluated',flush=True)
    cap.release()
    report={'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':source,
            'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'source_fps':fps,'source_frame_count':frame_count,
            'sample_rate_fps':2,'evaluated_frames':len(records),'roi_policy':'centered width92%, aspect3.2:1, fixed before inference',
            'inference_median_ms':float(np.median(latencies)),'inference_p95_ms':float(np.percentile(latencies,95)),
            'detection_count_histogram':dict(sorted(counts.items())),
            'confidence_and_count_eligible_frames':{str(n):eligible[n] for n in [2,5,8,11,14,17]},
            'temporal_gate_replay_performed':False,
            'limitations':['Domain footage, not a complete-hand video benchmark; no per-tile video ground truth.',
                           'Confidence/count checks are necessary conditions only, not a duplicate implementation of the app gate.',
                           'Desktop CPU only; excludes phone camera conversion, Dart, rendering, and device thermals.',
                           'A rejected documentary does not establish recognition accuracy or safety on real player hands.'],
            'frames':records}
    (ROOT/'vision/reports/online/video-v2-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    sheet=Image.new('RGB',(1200,3*220),'#f3f3ef');draw=ImageDraw.Draw(sheet)
    for i,(sec,panel,n) in enumerate(panels):
        panel.thumbnail((580,185));x=(i%2)*600;y=(i//2)*220
        sheet.paste(panel,(x+10,y+25));draw.text((x+10,y+5),f'{sec}s | {n} detections | domain footage, not a hand',fill='black')
    sheet.save(ROOT/'vision/reports/online/video-v2-contact-sheet.jpg')
    print(json.dumps({k:v for k,v in report.items() if k not in ['frames','source']},indent=2))

if __name__=='__main__':main()
