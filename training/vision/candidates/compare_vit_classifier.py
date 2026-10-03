#!/usr/bin/env python3
"""Compare a real pretrained non-YOLO classifier on manual and detected crops.
Manual crops are an oracle-localization diagnostic, not whole-image detection.
"""
import datetime,hashlib,json,sys,time
from pathlib import Path
from collections import Counter
import numpy as np
import torch
from PIL import Image,ImageOps
from safetensors.torch import load_file
from transformers import ViTConfig,ViTForImageClassification
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT/'vision'))
from evaluate_online import match

def main():
    path=HERE/'downloads/mahjong-vit.safetensors';expected='6ce2fa4fb1cc052ebdfb181e34e35ea341dbe471bc5b9090f5dbd84ab1e5c796'
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected
    config=ViTConfig.from_dict(json.loads((HERE/'vit-config.json').read_text()));model=ViTForImageClassification(config)
    model.load_state_dict(load_file(str(path)),strict=True);model.eval();torch.set_num_threads(2)
    processor=json.loads((HERE/'vit-processor.json').read_text());assert processor['image_mean']==[.5,.5,.5] and processor['image_std']==[.5,.5,.5]
    # Exact standard processor contract from the publisher; no remote model code.
    def tensor(crop):return torch.from_numpy(((np.asarray(crop.resize((224,224),Image.Resampling.BILINEAR),dtype=np.float32)/255-.5)/.5).transpose(2,0,1).copy())[None]
    def classify(crop):
        x=tensor(crop);start=time.perf_counter()
        with torch.no_grad():p=model(pixel_values=x).logits.softmax(dim=-1)[0]
        elapsed=(time.perf_counter()-start)*1000;index=int(p.argmax());label=config.id2label[index]
        label={'East':'1z','South':'2z','West':'3z','North':'4z','Haku':'5z','Hatsu':'6z','Chun':'7z'}.get(label,label)
        return label,float(p[index]),elapsed
    for _ in range(5):classify(Image.new('RGB',(224,224),'white'))
    source_manifest=ROOT/'vision/reports/online_sources.json';annotations=ROOT/'vision/reports/online_annotations.json'
    sources={s['id']:s for s in json.loads(source_manifest.read_text())['sources']};regions=json.loads(annotations.read_text())['regions']
    proposals={r['region']:r for r in json.loads((HERE/'yolo11n-v2-results.json').read_text())['regions']}
    records=[];timings=[];totals=Counter();confusion=Counter()
    for r in regions:
        source=sources[r['source_id']];image=ImageOps.exif_transpose(Image.open(ROOT/source['path'])).convert('RGB');crop=image.crop(r['roi']);w,h=crop.size
        gt=[];oracle=[]
        for a in r['annotations']:
            label,score,elapsed=classify(image.crop(a['box']));timings.append(elapsed)
            oracle.append({'expected':a['tile'],'predicted':label,'confidence':score,'milliseconds':elapsed});confusion[(a['tile'],label)]+=1
            gt.append({'tile':a['tile'],'box':[(a['box'][0]-r['roi'][0])/w,(a['box'][1]-r['roi'][1])/h,(a['box'][2]-r['roi'][0])/w,(a['box'][3]-r['roi'][1])/h]})
        predicted=[];classification_ms=0
        for p in proposals[r['id']]['predictions']:
            b=[max(0,min(int(v*(w if i%2==0 else h)+.5),w if i%2==0 else h)) for i,v in enumerate(p['box'])]
            if b[2]<=b[0] or b[3]<=b[1]:continue
            label,score,elapsed=classify(crop.crop(b));classification_ms+=elapsed
            predicted.append({'tile':label,'confidence':score,'box':p['box'],'detector_confidence':p['confidence']})
        matches=match(gt,predicted);tp=len(matches);fp=len(predicted)-tp;fn=len(gt)-tp
        correct=sum(x['expected']==x['predicted'] for x in oracle);exact=tp==len(gt)==len(predicted);complete=r['kind']=='hand' and len(gt)==14
        totals.update(oracle_correct=correct,oracle_tiles=len(gt),oracle_exact_regions=int(correct==len(gt)),regions=1,
          pipeline_tp=tp,pipeline_fp=fp,pipeline_fn=fn,pipeline_exact_regions=int(exact),pipeline_exact_14_tile_regions=int(exact and complete),complete_14_tile_regions=int(complete))
        records.append({'region':r['id'],'oracle':oracle,'pipeline_predictions':predicted,'pipeline_tp':tp,'pipeline_fp':fp,'pipeline_fn':fn,'pipeline_classifier_ms':classification_ms})
        print(r['id'],'oracle',correct,'/',len(gt),'pipeline',tp,fp,fn,flush=True)
    totals['oracle_accuracy']=totals['oracle_correct']/totals['oracle_tiles'];totals['pipeline_precision']=totals['pipeline_tp']/(totals['pipeline_tp']+totals['pipeline_fp']);totals['pipeline_recall']=totals['pipeline_tp']/(totals['pipeline_tp']+totals['pipeline_fn'])
    result={'candidate':'s-seow/mahjong-tile-classifier-vit','revision':'997e76ef44835b4f582226c4f2826f6335af42d9','sha256':expected,'bytes':path.stat().st_size,'parameters':sum(p.numel() for p in model.parameters()),
      'license':'Unspecified model-card license; local research only. Not app asset. Training-data provenance unknown.',
      'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'purpose':'Existing DEVELOPMENT data only; manual oracle crops are not detection accuracy',
      'loading':'safetensors, strict standard ViTForImageClassification; no trust_remote_code or arbitrary pickle',
      'method':{'input':'224x224 RGB bilinear stretch; (pixel/255-.5)/.5 from model processor','threads':2,'device':'CPU','dtype':'float32','oracle':'manual ground-truth face rectangles','pipeline':'same YOLO11n V2 proposals at threshold.25/NMS.45, then classifier top1, no confidence rejection; IoU.5 Hungarian matching'},
      'annotation_sha256':hashlib.sha256(annotations.read_bytes()).hexdigest(),'classifier_per_tile_median_ms':float(np.median(timings)),'classifier_per_tile_p95_ms':float(np.percentile(timings,95)),
      'pipeline_classifier_per_region_median_ms':float(np.median([r['pipeline_classifier_ms'] for r in records])),
      'totals':dict(totals),'confusion':[{'actual':a,'predicted':p,'count':n} for (a,p),n in sorted(confusion.items())],'regions':records}
    (HERE/'vit-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(dict(totals),indent=2))

if __name__=='__main__':main()
