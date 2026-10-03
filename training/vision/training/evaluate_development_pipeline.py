#!/usr/bin/env python3
"""Development-only full detector/crop-classifier experiment, including failures."""
import argparse, json, sys, time
from collections import Counter
from pathlib import Path
import numpy as np
import torch
from PIL import Image, ImageOps
from train_classifier import classifier, transform, sha256, load_classifier_checkpoint
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'vision'))
from evaluate_online import match

def main():
    p=argparse.ArgumentParser();p.add_argument('--checkpoint',required=True);p.add_argument('--output',required=True)
    a=p.parse_args();output=Path(a.output)
    if output.exists():raise ValueError('Preserve existing results')
    state=load_classifier_checkpoint(a.checkpoint);cfg=state['config']
    torch.set_num_threads(2);model=classifier(len(cfg['classes']));model.load_state_dict(state['state_dict']);model.eval()
    def classify(crops):
        if not crops:return []
        x=torch.stack([transform(c,cfg['size']) for c in crops]);t=time.perf_counter()
        with torch.inference_mode():probs=model(x).softmax(1).numpy()
        elapsed=(time.perf_counter()-t)*1000
        return [{'tile':cfg['classes'][int(q.argmax())],'confidence':float(q.max()),'batch_ms':elapsed} for q in probs]
    classify([Image.new('RGB',(100,150),'white')]*14)
    source_path=ROOT/'vision/reports/online_sources.json';annotation_path=ROOT/'vision/reports/online_annotations.json'
    sources={s['id']:s for s in json.loads(source_path.read_text())['sources']}
    regions=json.loads(annotation_path.read_text())['regions']
    names=['yolo11n-v2','yolo11s-v2','ar-yolov8-42']
    proposals={name:{r['region']:r for r in json.loads((ROOT/f'vision/candidates/{name}-results.json').read_text())['regions']} for name in names}
    totals={name:Counter() for name in names};records=[];oracle_correct=0;oracle_count=0;oracle_regions=0
    for region in regions:
        photo=ImageOps.exif_transpose(Image.open(ROOT/sources[region['source_id']]['path'])).convert('RGB')
        roi=region['roi'];scene=photo.crop(roi);w,h=scene.size
        gt=[dict(tile=b['tile'],box=[(b['box'][0]-roi[0])/w,(b['box'][1]-roi[1])/h,(b['box'][2]-roi[0])/w,(b['box'][3]-roi[1])/h]) for b in region['annotations']]
        # Match the trained context policy; boundaries clip to the original.
        def context_crop(image,box):
            x,y,r,b=box;dx=(r-x)*.06;dy=(b-y)*.06
            return image.crop((max(0,int(x-dx)),max(0,int(y-dy)),min(image.width,int(r+dx+.999)),min(image.height,int(b+dy+.999))))
        oracle=classify([context_crop(photo,b['box']) for b in region['annotations']])
        correct=sum(g['tile']==q['tile'] for g,q in zip(gt,oracle));oracle_correct+=correct;oracle_count+=len(gt);oracle_regions+=int(correct==len(gt))
        record={'region':region['id'],'oracle':oracle,'oracle_correct':correct,'pipelines':{}}
        for name in names:
            detections=proposals[name][region['id']]['predictions']
            classes=classify([context_crop(scene,[v*(w if i%2==0 else h) for i,v in enumerate(d['box'])]) for d in detections])
            # Fixed top-1 background rejection, no post-test threshold tuning.
            pred=[{'tile':q['tile'],'box':d['box'],'confidence':q['confidence'],'detector_confidence':d['confidence']} for d,q in zip(detections,classes) if q['tile']!='background']
            pairs=match(gt,pred);tp=len(pairs);fp=len(pred)-tp;fn=len(gt)-tp;exact=tp==len(gt)==len(pred)
            complete=region['kind']=='hand' and len(gt)==14
            totals[name].update(tp=tp,fp=fp,fn=fn,exact_regions=int(exact),regions=1,exact_complete_14_tile_regions=int(exact and complete),complete_14_tile_regions=int(complete))
            record['pipelines'][name]={'predictions':pred,'tp':tp,'fp':fp,'fn':fn,'classification_batch_ms':classes[0]['batch_ms'] if classes else 0}
        records.append(record)
    for v in totals.values():v['precision']=v['tp']/max(1,v['tp']+v['fp']);v['recall']=v['tp']/max(1,v['tp']+v['fn'])
    report={'checkpoint_sha256':sha256(a.checkpoint),'annotation_sha256':sha256(annotation_path),'split':'development only',
            'method':'Same precomputed detector proposals at .25 confidence/.45NMS; 6% crop context, classifier top-1, background excluded; IoU>=.5 class-aware match. CPU2threads.',
            'oracle':{'correct':oracle_correct,'count':oracle_count,'accuracy':oracle_correct/oracle_count,'all_crops_correct_regions':oracle_regions,'regions':len(regions)},
            'pipeline_totals':{k:dict(v) for k,v in totals.items()},'regions':records,
            'limitations':['Manual true boxes are a classification diagnostic only.','Old public examples were used for model selection and are not independent tests.','Static regions are not evidence of camera locks or phone speed.']}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k in ['oracle','pipeline_totals']},indent=2))
if __name__=='__main__':main()
