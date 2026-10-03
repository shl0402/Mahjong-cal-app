#!/usr/bin/env python3
"""Evaluate the dev-selected detector at fixed operating points; no selection here."""
import collections
import datetime
import hashlib
import json
import sys
import time
from pathlib import Path
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'vision/training'
RUN=BASE/'detector_runs/full20'
sys.path.insert(0,str(ROOT/'vision'))
from evaluate_online import prepare,match
from evaluate_baseline import decode

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def evaluate(session,names,rows):
    totals=collections.Counter();classes={};confusion=collections.Counter();records=[];times=[]
    for row in rows:
        image=row['image']()
        tensor,geometry=prepare(image)
        start=time.perf_counter();raw=session.run(None,{'images':tensor})[0];elapsed=(time.perf_counter()-start)*1000
        times.append(elapsed);pred=decode(raw,geometry,names,threshold=.25,nms=.45);gt=row['ground_truth']
        matches=match(gt,pred);agnostic=match(gt,pred,False)
        tp=len(matches);fp=len(pred)-tp;fn=len(gt)-tp;exact=tp==len(gt)==len(pred)
        multiset_correct=collections.Counter(g['tile'] for g in gt)==collections.Counter(p['tile'] for p in pred)
        high=[p for p in pred if p['confidence']>=.8];high_tp=len(match(gt,high));high_fp=len(high)-high_tp;high_fn=len(gt)-high_tp
        eligible=len(gt) in (2,5,8,11,14,17) and len(pred)==len(gt) and min((p['confidence'] for p in pred),default=0)>=.8
        matched_gt={g for g,_,_ in matches};matched_pred={p for _,p,_ in matches}
        for g,p,_ in agnostic:confusion[(gt[g]['tile'],pred[p]['tile'])]+=1
        for g,a in enumerate(gt):classes.setdefault(a['tile'],collections.Counter()).update(gt=1,tp=int(g in matched_gt),fn=int(g not in matched_gt))
        for p,a in enumerate(pred):classes.setdefault(a['tile'],collections.Counter()).update(predictions=1,fp=int(p not in matched_pred))
        totals.update(tp=tp,fp=fp,fn=fn,images=1,exact_images=int(exact),correct_tile_multisets=int(multiset_correct),annotated_tiles=len(gt),complete_14_tile_regions=int(row.get('complete_14',False)),exact_complete_14_tile_regions=int(row.get('complete_14',False) and exact),count_confidence_eligible=int(eligible),count_confidence_eligible_wrong=int(eligible and not exact),count_confidence_eligible_wrong_tile_multiset=int(eligible and not multiset_correct),high_confidence_tp=high_tp,high_confidence_fp=high_fp,high_confidence_fn=high_fn,prediction_cap_reached=int(len(pred)==40))
        records.append({k:v for k,v in row.items() if k!='image'}|{'predictions':pred,'matches':matches,'tp':tp,'fp':fp,'fn':fn,'exact':exact,'correct_tile_multiset':multiset_correct,'count_confidence_eligible':eligible,'inference_ms':elapsed})
    for prefix in ('','high_confidence_'):
        tp,fp,fn=(totals[prefix+s] for s in ('tp','fp','fn'))
        totals[prefix+'precision']=tp/(tp+fp) if tp+fp else 0
        totals[prefix+'recall']=tp/(tp+fn) if tp+fn else 0
    per_class={}
    for label in sorted(set(names.values()) | set(classes)):
        c=classes.get(label,collections.Counter())
        per_class[label]={k:c[k] for k in ('gt','tp','fp','fn','predictions')}
        per_class[label]['precision']=c['tp']/(c['tp']+c['fp']) if c['tp']+c['fp'] else None
        per_class[label]['recall']=c['tp']/(c['tp']+c['fn']) if c['tp']+c['fn'] else None
    return {'totals':dict(totals),'inference_median_ms':float(np.median(times)),'inference_p95_ms':float(np.percentile(times,95)),'class_counts':per_class,'confusion':[{'actual':a,'predicted':p,'count':n} for (a,p),n in sorted(confusion.items())],'records':records}

def main():
    export_path=RUN/'export_manifest.json';export=json.loads(export_path.read_text());path=ROOT/export['model_path']
    assert sha(path)==export['onnx_sha256']
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(path),sess_options=options,providers=['CPUExecutionProvider'])
    names=dict(enumerate(export['class_names']))
    for _ in range(5):session.run(None,{'images':np.zeros((1,3,640,640),dtype=np.float32)})
    manifest_path=ROOT/'vision/datasets/rf100vl_mahjong/image_manifest.json';manifest=json.loads(manifest_path.read_text())
    metadata={'model_sha256':sha(path),'export_manifest_sha256':sha(export_path),'selected_epoch':export['selected_epoch_from_csv'],'source_manifest_sha256':sha(manifest_path),'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'method':{'confidence':.25,'nms_iou':.45,'matching_iou':.5,'matching':'class-aware Hungarian','max_detections':40,'high_confidence_threshold':.8,'cpu_threads':2,'provider':'CPUExecutionProvider','timed_runs_per_image':1,'warmups':5,'phone_timing':False,'temporal_validation':False}}
    for split in ('dev','internal_test'):
        rows=[]
        for r in manifest['records']:
            if r['split']!=split:continue
            source=ROOT/r['path'];assert sha(source)==r['sha256'];w,h=r['width'],r['height'];gt=[]
            for a in r['annotations']:
                x,y,bw,bh=a['bbox'];gt.append({'tile':a['label'],'box':[x/w,y/h,(x+bw)/w,(y+bh)/h]})
            rows.append({'id':r['id'],'path':r['path'],'sha256':r['sha256'],'group_id':r['group_id'],'ground_truth':gt,'image':lambda p=source:Image.open(p).convert('RGB')})
        result=metadata|{'split':split,'status':'development diagnostic' if split=='dev' else 'FOLLOW-UP DIAGNOSTIC: source test already consumed before this experiment was proposed; not a fresh unseen holdout','locally_excluded_from_training':split=='internal_test'}|evaluate(session,names,rows)
        (RUN/f'evaluation-{split}.json').write_text(json.dumps(result,indent=2)+'\n');print(split,json.dumps(result['totals']),flush=True)
    sources={s['id']:s for s in json.loads((ROOT/'vision/reports/online_sources.json').read_text())['sources']}
    regions=json.loads((ROOT/'vision/reports/online_annotations.json').read_text())['regions'];rows=[]
    for r in regions:
        source=sources[r['source_id']];roi=r['roi'];w,h=roi[2]-roi[0],roi[3]-roi[1]
        gt=[{'tile':a['tile'],'box':[(a['box'][0]-roi[0])/w,(a['box'][1]-roi[1])/h,(a['box'][2]-roi[0])/w,(a['box'][3]-roi[1])/h]} for a in r['annotations']]
        rows.append({'id':r['id'],'source_id':r['source_id'],'ground_truth':gt,'complete_14':r['kind']=='hand' and len(gt)==14,'image':lambda p=ROOT/source['path'],box=roi:ImageOps.exif_transpose(Image.open(p)).convert('RGB').crop(box)})
    result=metadata|{'split':'commons_development','status':'Existing development photos; not a new independent test'}|evaluate(session,names,rows)
    (RUN/'evaluation-commons-development.json').write_text(json.dumps(result,indent=2)+'\n');print('commons_development',json.dumps(result['totals']),flush=True)

if __name__=='__main__':
    main()
