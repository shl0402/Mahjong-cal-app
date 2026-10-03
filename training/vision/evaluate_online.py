#!/usr/bin/env python3
"""Evaluate a fixed human-annotated, openly licensed real-photo diagnostic set."""
import argparse,ast,datetime,hashlib,json,platform,time
from collections import Counter
from pathlib import Path
import numpy as np
import onnxruntime as ort
from PIL import Image,ImageOps,ImageDraw,ImageFont
from scipy.optimize import linear_sum_assignment
from evaluate_baseline import ROOT,canonical,decode

def iou(a,b):
    area=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
    union=(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-area
    return area/union if union>0 else 0

def match(gt,pred,classes=True):
    if not gt or not pred:return []
    overlaps=np.array([[iou(g['box'],p['box']) for p in pred] for g in gt])
    allowed=overlaps>=.5
    if classes:allowed &= np.array([[g['tile']==p['tile'] for p in pred] for g in gt])
    # Prioritize number of valid matches, then overlap; every object used at most once.
    weights=np.where(allowed,100+overlaps,0)
    rows,cols=linear_sum_assignment(weights,maximize=True)
    return [(int(r),int(c),float(overlaps[r,c])) for r,c in zip(rows,cols) if allowed[r,c]]

def prepare(image):
    width,height=image.size
    scale=640/max(width,height);w=max(1,int(width*scale+.5));h=max(1,int(height*scale+.5))
    px,py=(640-w)//2,(640-h)//2
    data=np.full((640,640,3),114,dtype=np.float32)
    data[py:py+h,px:px+w]=np.asarray(image.resize((w,h),Image.Resampling.BILINEAR),dtype=np.float32)
    return (data.transpose(2,0,1)[None]/255).copy(),(px,py,w,h)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--model',default='vision/downloads/mahjong-yolo11n.onnx');parser.add_argument('--name',default='yolo11n-v1');args=parser.parse_args()
    model=ROOT/args.model
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(model),sess_options=options,providers=['CPUExecutionProvider'])
    meta=session.get_modelmeta().custom_metadata_map;names=ast.literal_eval(meta['names'])
    sources={s['id']:s for s in json.loads((ROOT/'vision/reports/online_sources.json').read_text())['sources']}
    labels=json.loads((ROOT/'vision/reports/online_annotations.json').read_text());regions=labels['regions']
    totals=Counter();confusion=Counter();records=[];latencies=[];panels=[]
    target=ROOT/'vision/reports/online';target.mkdir(parents=True,exist_ok=True)
    for r in regions:
        source=sources[r['source_id']];path=ROOT/source['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==source['sha256']
        image=ImageOps.exif_transpose(Image.open(path)).convert('RGB').crop(r['roi'])
        width,height=image.size
        gt=[{'tile':a['tile'],'box':[(a['box'][0]-r['roi'][0])/width,(a['box'][1]-r['roi'][1])/height,(a['box'][2]-r['roi'][0])/width,(a['box'][3]-r['roi'][1])/height]} for a in r['annotations']]
        tensor,geometry=prepare(image)
        for _ in range(5):session.run(None,{'images':tensor})
        times=[]
        for _ in range(10):
            start=time.perf_counter();raw=session.run(None,{'images':tensor})[0];times.append((time.perf_counter()-start)*1000)
        latencies.extend(times)
        pred=decode(raw,geometry,names)
        matches=match(gt,pred);agnostic=match(gt,pred,False)
        tp=len(matches);fp=len(pred)-tp;fn=len(gt)-tp
        exact=tp==len(gt)==len(pred)
        multiset=Counter(g['tile'] for g in gt)==Counter(p['tile'] for p in pred)
        for g,p,_ in agnostic:confusion[(gt[g]['tile'],pred[p]['tile'])]+=1
        potential=len(gt) in [2,5,8,11,14,17] and len(pred)==len(gt) and min((p['confidence'] for p in pred),default=0)>=.8
        record={**r,'predictions':pred,'ground_truth_normalized':gt,'matches':matches,'class_agnostic_matches':agnostic,
                'tp':tp,'fp':fp,'fn':fn,'exact_region':exact,'correct_face_multiset':multiset,
                'count_and_min_confidence_eligible':potential,'eligible_but_wrong':potential and not multiset,
                'inference_median_ms':float(np.median(times))}
        records.append(record);totals.update(tp=tp,fp=fp,fn=fn,regions=1,exact_regions=int(exact),correct_face_multisets=int(multiset),
                                           hand_regions=int(r['kind']=='hand'),exact_hand_regions=int(exact and r['kind']=='hand'),
                                           complete_14_tile_regions=int(r['kind']=='hand' and len(gt)==14),
                                           exact_complete_14_tile_regions=int(exact and r['kind']=='hand' and len(gt)==14),
                                           eligible=int(potential),eligible_but_wrong=int(potential and not multiset))
        render=image.copy();draw=ImageDraw.Draw(render);line=max(1,round(width/600))
        # Green = manually labelled face; orange = model prediction, with confidence.
        size=max(10,round(width/80))
        try:font=ImageFont.truetype('/System/Library/Fonts/Menlo.ttc',size)
        except OSError:
            try:font=ImageFont.truetype('DejaVuSans.ttf',size)
            except OSError:font=ImageFont.load_default(size=size)
        for item in gt:
            box=[int(v*(width if i%2==0 else height)) for i,v in enumerate(item['box'])];draw.rectangle(box,outline='#25b86b',width=line)
            draw.text((box[0],max(0,box[1]-font.size-2)),item['tile'],fill='#168448',stroke_width=1,stroke_fill='white',font=font)
        for item in pred:
            box=[int(v*(width if i%2==0 else height)) for i,v in enumerate(item['box'])];draw.rectangle(box,outline='#e05714',width=line)
            draw.text((box[0],box[3]-font.size),f"{item['tile']} {item['confidence']:.2f}",fill='#c94300',stroke_width=1,stroke_fill='white',font=font)
        filename=f"{args.name}-{r['id']}.jpg";render.save(target/filename)
        record['overlay']=str((target/filename).relative_to(ROOT));panels.append((render,r['id'],tp,fp,fn))
        print(r['id'],f'TP{tp} FP{fp} FN{fn} exact{exact} eligible{potential}',flush=True)
    totals['precision']=totals['tp']/(totals['tp']+totals['fp']) if totals['tp']+totals['fp'] else 0
    totals['recall']=totals['tp']/(totals['tp']+totals['fn'])
    report={'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'model':str(model.relative_to(ROOT)),
            'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'model_metadata':meta,
            'annotation_sha256':hashlib.sha256((ROOT/'vision/reports/online_annotations.json').read_bytes()).hexdigest(),
            'environment':{'platform':platform.platform(),'onnxruntime':ort.__version__,'provider':'CPUExecutionProvider','threads':2},
            'method':{'confidence_threshold':.25,'nms_iou':.45,'matching_iou':.5,'matching':'Hungarian, class-aware for metrics; class-agnostic for confusion',
                      'warmup_runs_per_region':5,'timed_runs_per_region':10,'temporal_stability_evaluated':False,
                      'limitations':['Small convenience sample; correlated rows/sets; not representative accuracy','Possible upstream training overlap','Manual annotations by one reviewer','No phone timing or camera-pipeline timing']},
            'totals':dict(totals),'inference_median_ms':float(np.median(latencies)),'inference_p95_ms':float(np.percentile(latencies,95)),
            'confusion':[{'actual':a,'predicted':p,'count':n} for (a,p),n in sorted(confusion.items())], 'regions':records}
    (target/f'{args.name}-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    contact=Image.new('RGB',(1440,5*300),'#f2f3ef');draw=ImageDraw.Draw(contact)
    for i,(panel,name,tp,fp,fn) in enumerate(panels):
        panel.thumbnail((700,245));x=(i%2)*720;y=(i//2)*300;contact.paste(panel,(x+10,y+40))
        draw.text((x+10,y+8),f'{name} | TP {tp} / FP {fp} / FN {fn}',fill='black')
    contact.save(target/f'{args.name}-contact-sheet.jpg')
    print(json.dumps(dict(totals),indent=2))

if __name__=='__main__':main()
