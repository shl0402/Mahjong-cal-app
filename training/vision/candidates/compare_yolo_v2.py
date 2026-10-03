#!/usr/bin/env python3
"""Restricted export and same-development-set comparison of pretrained sizes.

This does not train, modify the app, or create independent test evidence.
Only writes beneath vision/candidates/.
"""
import ast,datetime,hashlib,importlib,json,os,platform,sys,time
from collections import Counter
from pathlib import Path
import numpy as np
import onnx
import onnxruntime as ort
import torch
from PIL import Image,ImageOps
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'vision'))
from export_v2_weights_only import ALLOWED
from evaluate_online import prepare,match
from evaluate_baseline import decode
os.environ['YOLO_CONFIG_DIR']=str(HERE/'downloads/ultralytics-config')
os.environ['YOLO_AUTOINSTALL']='False'
SPECS={
 'yolo11n-v2':('vision/downloads/mahjong-yolo11n-v2.pt','ea35d50b9568fc67277538038e7c456b3f29ebd65e1de7bd141e5a1d3a9d0ff1'),
 'yolo11s-v2':('vision/candidates/downloads/yolo11s-v2.pt','1b755721c3b581fe550d9568c85a6c5cf12558c6232453943b73dc669eafd6fd'),
 'yolo11m-v2':('vision/candidates/downloads/yolo11m-v2.pt','a00a03dd9229f5809d4de3c9474b9bcdd74b7b42a5a507e92a803755e268d372'),
}

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def load_export(name,path,expected):
    assert sha(path)==expected
    found=set(torch.serialization.get_unsafe_globals_in_checkpoint(path))
    if not found.issubset(set(ALLOWED)):raise ValueError(f'Unexpected checkpoint classes: {found-set(ALLOWED)}')
    classes=[getattr(importlib.import_module(s.rsplit('.',1)[0]),s.rsplit('.',1)[1]) for s in ALLOWED]
    with torch.serialization.safe_globals(classes):checkpoint=torch.load(path,map_location='cpu',weights_only=True)
    model=checkpoint['model'].float().eval();torch.set_num_threads(2)
    from ultralytics.nn.modules.head import Detect
    for module in model.modules():
        if isinstance(module,Detect):module.export=True;module.format='onnx';module.dynamic=False
    assert len(model.names)==38 and model.names[34]=='UNKNOWN'
    target=HERE/'downloads'/f'{name}.onnx'
    torch.onnx.export(model,torch.zeros(1,3,640,640),str(target),opset_version=17,input_names=['images'],output_names=['output0'],dynamo=False)
    proto=onnx.load(target);onnx.helper.set_model_props(proto,{'names':repr(model.names),'task':'detect','license':'Ultralytics AGPL-3.0; repository MIT','source_checkpoint_sha256':expected})
    onnx.checker.check_model(proto);onnx.save(proto,target)
    return model,target,checkpoint.get('version')

def main():
    labels_path=ROOT/'vision/reports/online_annotations.json';sources_path=ROOT/'vision/reports/online_sources.json'
    sources={s['id']:s for s in json.loads(sources_path.read_text())['sources']}
    regions=json.loads(labels_path.read_text())['regions'];reports=[]
    for name,(relative,expected) in SPECS.items():
        print('Export',name,flush=True);model,target,version=load_export(name,ROOT/relative,expected)
        opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
        session=ort.InferenceSession(str(target),sess_options=opts,providers=['CPUExecutionProvider'])
        names=ast.literal_eval(session.get_modelmeta().custom_metadata_map['names']);totals=Counter();records=[];timings=[];parity=[];confusion=Counter()
        for region in regions:
            source=sources[region['source_id']];path=ROOT/source['path'];assert sha(path)==source['sha256']
            image=ImageOps.exif_transpose(Image.open(path)).convert('RGB').crop(region['roi']);w,h=image.size
            gt=[{'tile':a['tile'],'box':[(a['box'][0]-region['roi'][0])/w,(a['box'][1]-region['roi'][1])/h,(a['box'][2]-region['roi'][0])/w,(a['box'][3]-region['roi'][1])/h]} for a in region['annotations']]
            tensor,geometry=prepare(image)
            for _ in range(5):session.run(None,{'images':tensor})
            ts=[]
            for _ in range(10):
                start=time.perf_counter();raw=session.run(None,{'images':tensor})[0];ts.append((time.perf_counter()-start)*1000)
            timings.extend(ts);pred=decode(raw,geometry,names)
            with torch.no_grad():original=model(torch.from_numpy(tensor)).numpy()
            origpred=decode(original,geometry,names);error=np.abs(original-raw)
            key=lambda p:(p['box'][0]+p['box'][2],p['box'][1]+p['box'][3])
            a,b=sorted(origpred,key=key),sorted(pred,key=key)
            sameclasses=[(p['tile'],p['red_five']) for p in a]==[(p['tile'],p['red_five']) for p in b]
            sameboxes=len(a)==len(b) and all(np.allclose(x['box'],y['box'],atol=1e-5,rtol=1e-5) for x,y in zip(a,b))
            passed=bool(np.allclose(raw,original,rtol=1e-4,atol=1e-3)) and sameclasses and sameboxes
            parity.append({'region':region['id'],'passed':passed,'max_coordinate_difference':float(error[:,:4].max()),'max_score_difference':float(error[:,4:].max())})
            matched=match(gt,pred);agnostic=match(gt,pred,False);tp=len(matched);fp=len(pred)-tp;fn=len(gt)-tp;exact=tp==len(gt)==len(pred)
            complete=region['kind']=='hand' and len(gt)==14
            eligible=len(gt) in [2,5,8,11,14,17] and len(pred)==len(gt) and min((p['confidence'] for p in pred),default=0)>=.8
            for g,p,_ in agnostic:confusion[(gt[g]['tile'],pred[p]['tile'])]+=1
            totals.update(tp=tp,fp=fp,fn=fn,regions=1,exact_regions=int(exact),hand_regions=int(region['kind']=='hand'),exact_hand_regions=int(exact and region['kind']=='hand'),complete_14_tile_regions=int(complete),exact_complete_14_tile_regions=int(exact and complete),count_confidence_eligible=int(eligible))
            records.append({'region':region['id'],'predictions':pred,'tp':tp,'fp':fp,'fn':fn,'exact':exact,'matches':matched,'count_confidence_eligible':eligible,'median_ms':float(np.median(ts))})
            print(name,region['id'],f'TP{tp} FP{fp} FN{fn}',flush=True)
        totals['precision']=totals['tp']/(totals['tp']+totals['fp']);totals['recall']=totals['tp']/(totals['tp']+totals['fn'])
        report={'candidate':name,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'purpose':'EXISTING development set model comparison, not independent generalization test',
          'source_repository':'https://github.com/nikmomo/Mahjong-YOLO','source_commit':'28ffceed232ad95fd019c47a6c51ae7c78791a0e',
          'source_checkpoint_sha256':expected,'checkpoint_bytes':(ROOT/relative).stat().st_size,'checkpoint_training_version':version,'onnx_path':str(target.relative_to(ROOT)),'onnx_sha256':sha(target),'onnx_bytes':target.stat().st_size,
          'parameters':sum(p.numel() for p in model.parameters()),'classes':names,'all_export_parity_passed':all(p['passed'] for p in parity),'parity':parity,
          'environment':{'platform':platform.platform(),'torch':torch.__version__,'onnxruntime':ort.__version__,'threads':2,'provider':'CPUExecutionProvider'},
          'annotation_sha256':sha(labels_path),'sources_manifest_sha256':sha(sources_path),
          'method':{'threshold':.25,'nms_iou':.45,'match_iou':.5,'matching':'Hungarian, class-aware','warmups_per_region':5,'timed_runs_per_region':10},
          'inference_median_ms':float(np.median(timings)),'inference_p95_ms':float(np.percentile(timings,95)),'totals':dict(totals),
          'confusion':[{'actual':a,'predicted':p,'count':n} for (a,p),n in sorted(confusion.items())],'regions':records,
          'license':'Repository MIT; Ultralytics-derived model AGPL-3.0/commercial terms. Training image rights and overlap not fully established.'}
        (HERE/f'{name}-results.json').write_text(json.dumps(report,indent=2)+'\n');reports.append({k:v for k,v in report.items() if k not in ['classes','regions','parity','confusion']})
        assert report['all_export_parity_passed'];del model,session
    (HERE/'comparison.json').write_text(json.dumps(reports,indent=2)+'\n')

if __name__=='__main__':main()
