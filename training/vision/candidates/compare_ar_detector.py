#!/usr/bin/env python3
"""Local-research comparison; no redistribution permission inferred from availability."""
import ast,datetime,hashlib,json,sys,time
from pathlib import Path
from collections import Counter
import numpy as np
import onnxruntime as ort
from PIL import Image,ImageOps
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(ROOT/'vision'))
from evaluate_online import prepare,match
from evaluate_baseline import decode

def main():
    path=HERE/'downloads/ar-yolov8-42.onnx';expected='63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a'
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(path),sess_options=options,providers=['CPUExecutionProvider'])
    original=(HERE/'ar-class-names.txt').read_text().splitlines()
    def canonical(x):
        if x in ['EW','SW','WW','NW','WD','GD','RD']:return str(['EW','SW','WW','NW','WD','GD','RD'].index(x)+1)+'z'
        if x[-1] in 'BCD':return x[0]+{'B':'s','C':'m','D':'p'}[x[-1]]
        # The common decoder accepts UNKNOWN for unsupported categories; retain
        # the original 42-class index/name separately in each prediction below.
        return 'UNKNOWN'
    names={i:canonical(x) for i,x in enumerate(original)}
    sources={s['id']:s for s in json.loads((ROOT/'vision/reports/online_sources.json').read_text())['sources']}
    labels_path=ROOT/'vision/reports/online_annotations.json';regions=json.loads(labels_path.read_text())['regions'];records=[];totals=Counter();timings=[]
    for r in regions:
        source=sources[r['source_id']];image=ImageOps.exif_transpose(Image.open(ROOT/source['path'])).convert('RGB').crop(r['roi']);w,h=image.size
        gt=[{'tile':a['tile'],'box':[(a['box'][0]-r['roi'][0])/w,(a['box'][1]-r['roi'][1])/h,(a['box'][2]-r['roi'][0])/w,(a['box'][3]-r['roi'][1])/h]} for a in r['annotations']]
        tensor,geometry=prepare(image)
        for _ in range(5):session.run(None,{'images':tensor})
        ts=[]
        for _ in range(10):
            start=time.perf_counter();raw=session.run(None,{'images':tensor})[0];ts.append((time.perf_counter()-start)*1000)
        pred=decode(raw,geometry,names)
        for p in pred:p['upstream_class_name']=original[p['model_class_id']]
        matches=match(gt,pred);tp=len(matches);fp=len(pred)-tp;fn=len(gt)-tp;exact=tp==len(gt)==len(pred)
        eligible=len(gt) in [2,5,8,11,14,17] and len(pred)==len(gt) and min((p['confidence'] for p in pred),default=0)>=.8
        complete=r['kind']=='hand' and len(gt)==14
        totals.update(tp=tp,fp=fp,fn=fn,regions=1,exact_regions=int(exact),complete_14_tile_regions=int(complete),exact_complete_14_tile_regions=int(exact and complete),count_confidence_eligible=int(eligible))
        records.append({'region':r['id'],'predictions':pred,'matches':matches,'tp':tp,'fp':fp,'fn':fn,'exact':exact,'count_confidence_eligible':eligible,'median_ms':float(np.median(ts))});timings.extend(ts)
        print(r['id'],tp,fp,fn,flush=True)
    totals['precision']=totals['tp']/(totals['tp']+totals['fp']);totals['recall']=totals['tp']/(totals['tp']+totals['fn'])
    report={'purpose':'Existing development-set comparison only; no training-independence claim','candidate':'AR-Mahjong YOLOv8n 42-class',
        'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':'https://github.com/LYiHub/AR-Mahjong-Assistant-preview','commit':'e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299',
        'source_path':'server/models/yolo/weights.onnx','sha256':expected,'bytes':path.stat().st_size,'metadata':session.get_modelmeta().custom_metadata_map,'classes':original,
        'license':'Publisher grant unresolved; exporter auto-inserts AGPL metadata. Jon Chan mahjong-baq4s family credited, exact version/split unknown. Local research only.',
        'method':{'input':'RGB bilinear letterbox640 padding114, /255','threshold':.25,'nms':.45,'matching_iou':.5,'warmups':5,'timed_runs':10,'threads':2,'provider':'CPUExecutionProvider'},
        'annotation_sha256':hashlib.sha256(labels_path.read_bytes()).hexdigest(),'inference_median_ms':float(np.median(timings)),'inference_p95_ms':float(np.percentile(timings,95)),'totals':dict(totals),'regions':records}
    (HERE/'ar-yolov8-42-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(totals,indent=2))

if __name__=='__main__':main()
