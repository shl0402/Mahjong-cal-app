#!/usr/bin/env python3
"""Evaluate frozen pretrained choices once on a grouped external-data diagnostic.

All model choices/thresholds are fixed before reading predictions. The supplied
split is NOT asserted independent of unknown upstream model training images.
"""
import argparse,ast,datetime,hashlib,json,platform,sys,time
from pathlib import Path
from collections import Counter
import numpy as np
import onnxruntime as ort
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT/'vision'))
from evaluate_online import prepare,match
from evaluate_baseline import decode

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def ar_names():
    names={}
    for i,x in enumerate((HERE/'ar-class-names.txt').read_text().splitlines()):
        if x in ['EW','SW','WW','NW','WD','GD','RD']:names[i]=str(['EW','SW','WW','NW','WD','GD','RD'].index(x)+1)+'z'
        elif x[-1] in 'BCD':names[i]=x[0]+{'B':'s','C':'m','D':'p'}[x[-1]]
        else:names[i]='UNKNOWN'
    return names

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--manifest',default='vision/datasets/rf100vl_mahjong/image_manifest.json');parser.add_argument('--split',default='internal_test',choices=['internal_test']);args=parser.parse_args()
    manifest_path=ROOT/args.manifest;manifest=json.loads(manifest_path.read_text());lock_path=HERE/'external_evaluation_lock.json';lock=json.loads(lock_path.read_text())
    assert lock['tuning_on_external_test'] is False and lock['confidence_threshold']==.25 and lock['nms_iou']==.45
    assert json.loads((manifest_path.parent/'extraction_status.json').read_text())['partial'] is False
    rows=[r for r in manifest['records'] if r['split']==args.split]
    assert rows and all(r['group_id'] for r in rows)
    validation_lock=ROOT/'vision/validation/rf100vl_internal_test_v1.lock.json'
    assert validation_lock.is_file(), 'The independent source-test lock must exist before inference.'
    # Assert no known group straddles train/development and internal test.
    test_groups={r['group_id'] for r in rows};assert not test_groups.intersection(r['group_id'] for r in manifest['records'] if r['split']!=args.split)
    classifier_plan=ROOT/'vision/training/EXPERIMENT_PLAN.json'
    assert classifier_plan.is_file(), 'Classifier experiment policy must also be frozen.'
    begun=datetime.datetime.now(datetime.timezone.utc).isoformat();all_reports=[]
    exposure_path=HERE/'external_evaluation_exposure.json'
    exposure={'started_at':begun,'manifest_sha256':sha(manifest_path),'record_ids':[r['id'] for r in rows],
              'models':lock['models'],'classifier_plan_sha256':sha(classifier_plan),
              'status':'evaluation started; source test consumed for future selection even if this process fails'}
    exposure_path.write_text(json.dumps(exposure,indent=2)+'\n')
    for candidate in [lock['control'],lock['secondary_candidate'],lock['primary_research_candidate']]:
        target=HERE/'downloads'/f'{candidate}.onnx';assert sha(target)==lock['models'][candidate]
        options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
        session=ort.InferenceSession(str(target),sess_options=options,providers=['CPUExecutionProvider'])
        names=ar_names() if candidate=='ar-yolov8-42' else ast.literal_eval(session.get_modelmeta().custom_metadata_map['names'])
        for _ in range(5):session.run(None,{'images':np.zeros((1,3,640,640),dtype=np.float32)})
        totals=Counter();class_counts={};confusion=Counter();records=[];times=[]
        for index,r in enumerate(rows):
            path=ROOT/r['path'];assert sha(path)==r['sha256']
            # This export is already upright. Keep COCO coordinates unchanged.
            image=Image.open(path).convert('RGB');w,h=image.size;gt=[]
            for a in r['annotations']:
                x,y,bw,bh=a['bbox'];gt.append({'tile':a['label'],'box':[x/w,y/h,(x+bw)/w,(y+bh)/h]})
            tensor,geometry=prepare(image);start=time.perf_counter();raw=session.run(None,{'images':tensor})[0];elapsed=(time.perf_counter()-start)*1000;times.append(elapsed)
            pred=decode(raw,geometry,names,threshold=lock['confidence_threshold'],nms=lock['nms_iou'])
            matches=match(gt,pred);agnostic=match(gt,pred,False);tp=len(matches);fp=len(pred)-tp;fn=len(gt)-tp;exact=tp==len(gt)==len(pred)
            high=[p for p in pred if p['confidence']>=.8];high_matches=match(gt,high)
            high_tp=len(high_matches);high_fp=len(high)-high_tp;high_fn=len(gt)-high_tp
            matched_gt={g for g,_,_ in matches};matched_pred={p for _,p,_ in matches}
            for g,p,_ in agnostic:confusion[(gt[g]['tile'],pred[p]['tile'])]+=1
            for g,a in enumerate(gt):class_counts.setdefault(a['tile'],Counter()).update(gt=1,tp=int(g in matched_gt),fn=int(g not in matched_gt))
            for p,a in enumerate(pred):class_counts.setdefault(a['tile'],Counter()).update(predictions=1,fp=int(p not in matched_pred))
            eligible=len(gt) in [2,5,8,11,14,17] and len(pred)==len(gt) and min((p['confidence'] for p in pred),default=0)>=.8
            totals.update(tp=tp,fp=fp,fn=fn,images=1,exact_images=int(exact),annotated_tiles=len(gt),fourteen_tile_images=int(len(gt)==14),exact_fourteen_tile_images=int(exact and len(gt)==14),gt_more_than_40_images=int(len(gt)>40),prediction_cap_reached=int(len(pred)==40),count_confidence_eligible=int(eligible),count_confidence_eligible_wrong=int(eligible and not exact),high_confidence_tp=high_tp,high_confidence_fp=high_fp,high_confidence_fn=high_fn)
            records.append({'id':r['id'],'path':r['path'],'sha256':r['sha256'],'group_id':r['group_id'],'ground_truth':gt,'predictions':pred,'tp':tp,'fp':fp,'fn':fn,'exact':exact,'count_confidence_eligible':eligible,'high_confidence_tp':high_tp,'high_confidence_fp':high_fp,'high_confidence_fn':high_fn,'inference_ms':elapsed,'matches':matches})
            if (index+1)%25==0:print(candidate,index+1,'/',len(rows),flush=True)
        totals['precision']=totals['tp']/(totals['tp']+totals['fp']) if totals['tp']+totals['fp'] else 0;totals['recall']=totals['tp']/(totals['tp']+totals['fn'])
        totals['high_confidence_precision']=totals['high_confidence_tp']/(totals['high_confidence_tp']+totals['high_confidence_fp']) if totals['high_confidence_tp']+totals['high_confidence_fp'] else None
        totals['high_confidence_recall']=totals['high_confidence_tp']/(totals['high_confidence_tp']+totals['high_confidence_fn'])
        report={'candidate':candidate,'started_at':begun,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'external-dataset grouped internal diagnostic; upstream model overlap UNKNOWN',
            'selection_lock_sha256':sha(lock_path),'source_validation_lock_sha256':sha(validation_lock),'classifier_plan_sha256':sha(classifier_plan),'manifest_sha256':sha(manifest_path),'manifest_id':manifest['manifest_id'],'split':args.split,'group_count':len(test_groups),'model_sha256':sha(target),
            'method':{'full_images':True,'max_detections':40,'confidence':.25,'nms_iou':.45,'match_iou':.5,'matching':'class-aware Hungarian','timed_runs_per_image':1,'warmups':5,'threads':2,'provider':'CPUExecutionProvider','no_phone_timing':True,'no_test_tuning':True},
            'environment':{'platform':platform.platform(),'onnxruntime':ort.__version__},'totals':dict(totals),'inference_median_ms':float(np.median(times)),'inference_p95_ms':float(np.percentile(times,95)),
            'class_counts':{k:dict(v) for k,v in sorted(class_counts.items())},'confusion':[{'actual':a,'predicted':p,'count':n} for (a,p),n in sorted(confusion.items())],'records':records,
            'limitations':['Unknown overlap with upstream pretrained model training data','No verified physical tile-set/session holdout','Existing COCO annotations not exhaustively re-labelled','Full-frame scenes differ from the app guided-row crop','App cap of40detections retained; crowded-scene recall can be limited by this cap']}
        (HERE/f'external-{candidate}-results.json').write_text(json.dumps(report,indent=2)+'\n');all_reports.append({k:v for k,v in report.items() if k not in ['records','class_counts','confusion']});print(candidate,json.dumps(dict(totals)),flush=True)
    (HERE/'external-comparison.json').write_text(json.dumps(all_reports,indent=2)+'\n')
    exposure['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    exposure['status']='consumed for frozen-choice evaluation; do not relabel as untouched future test'
    exposure_path.write_text(json.dumps(exposure,indent=2)+'\n')

if __name__=='__main__':main()
