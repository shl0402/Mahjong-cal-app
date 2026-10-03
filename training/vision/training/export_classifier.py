#!/usr/bin/env python3
"""Export the research classifier and verify real development-crop parity."""
import argparse, json, time
from pathlib import Path
import numpy as np
import onnx
import onnxruntime as ort
import torch
from train_classifier import CropDataset, classifier, load_classifier_checkpoint, sha256

def main():
    p=argparse.ArgumentParser();p.add_argument('--checkpoint',required=True);p.add_argument('--manifest',required=True);p.add_argument('--output',required=True)
    a=p.parse_args();dest=Path(a.output)
    if dest.exists():raise ValueError('Refuse to overwrite export')
    state=load_classifier_checkpoint(a.checkpoint);cfg=state['config'];torch.set_num_threads(2)
    model=classifier(len(cfg['classes']));model.load_state_dict(state['state_dict']);model.eval()
    data=CropDataset(a.manifest,'dev',cfg['size']);indices=[];seen=set()
    for i,r in enumerate(data.rows):
        if r['label'] not in seen:indices.append(i);seen.add(r['label'])
    samples=torch.stack([data[i][0] for i in indices]);dest.parent.mkdir(parents=True,exist_ok=True)
    torch.onnx.export(model,samples[:1],str(dest),opset_version=17,input_names=['tiles'],output_names=['logits'],
                      dynamic_axes={'tiles':{0:'batch'},'logits':{0:'batch'}},dynamo=False)
    graph=onnx.load(dest);onnx.checker.check_model(graph)
    for key,value in {'classes':json.dumps(cfg['classes']),'input':'RGB /255, ImageNet mean/std; aspect-preserving letterbox160 with gray114',
                      'purpose':'Experimental classifier; ground-truth crops are not complete-hand detection',
                      'checkpoint_sha256':sha256(a.checkpoint)}.items():
        entry=graph.metadata_props.add();entry.key=key;entry.value=value
    onnx.save(graph,dest)
    opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
    session=ort.InferenceSession(str(dest),sess_options=opts,providers=['CPUExecutionProvider'])
    with torch.inference_mode():expected=model(samples).numpy()
    actual=session.run(None,{'tiles':samples.numpy()})[0]
    np.testing.assert_allclose(actual,expected,rtol=1e-4,atol=1e-4)
    assert np.array_equal(actual.argmax(1),expected.argmax(1))
    timing={}
    for batch in [1,14]:
        x=samples[:batch].numpy()
        for _ in range(5):session.run(None,{'tiles':x})
        times=[]
        for _ in range(30):
            t=time.perf_counter();session.run(None,{'tiles':x});times.append((time.perf_counter()-t)*1000)
        timing[str(batch)]={'median_ms':float(np.median(times)),'p95_ms':float(np.percentile(times,95))}
    result={'checkpoint_sha256':sha256(a.checkpoint),'onnx_sha256':sha256(dest),'bytes':dest.stat().st_size,
            'classes':cfg['classes'],'parity_development_crops':len(indices),'max_abs_logit_error':float(np.max(np.abs(actual-expected))),
            'input':['batch',3,cfg['size'],cfg['size']],'output':['batch',len(cfg['classes'])],
            'desktop_cpu_inference_only':timing,'limitations':['Not phone latency; excludes tile detection, crop preparation and camera.','Not installed in app: replacing detector labels worsened development complete-hand results.']}
    dest.with_suffix('.manifest.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
