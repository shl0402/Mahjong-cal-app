#!/usr/bin/env python3
"""Export the dev-selected local detector and verify Torch/ONNX parity on dev."""
import ast
import csv
import hashlib
import importlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'vision/training'
os.environ['YOLO_AUTOINSTALL'] = 'False'
os.environ['YOLO_CONFIG_DIR'] = str(BASE/'detector_downloads/config')
sys.path.insert(0,str(ROOT/'vision'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    import numpy as np
    import onnx
    import onnxruntime as ort
    import torch
    from PIL import Image
    from evaluate_online import prepare, match
    from evaluate_baseline import decode
    from export_v2_weights_only import ALLOWED
    os.environ['YOLO_CONFIG_DIR'] = str(BASE/'detector_downloads/config')
    from ultralytics.nn.modules.head import Detect
    torch.set_num_threads(2)
    run = BASE/'detector_runs/full20'
    assert (run/'run_summary.json').exists(), 'Full training must finish before selected-model evaluation'
    checkpoint_path = run/'weights/selected_dev.pt'
    assert (run/'timeout_free_selection.json').exists(), 'Timeout-free dev selection must precede export'
    allowed = list(ALLOWED) + ['numpy.core.multiarray.scalar', 'numpy._core.multiarray.scalar', 'numpy.dtype',
        'ultralytics.utils.loss.BboxLoss', 'ultralytics.utils.loss.DFLoss',
        'ultralytics.utils.loss.v8DetectionLoss', 'ultralytics.utils.tal.TaskAlignedAssigner',
        'ultralytics.utils.IterableSimpleNamespace', 'torch.nn.modules.loss.BCEWithLogitsLoss']
    found = set(torch.serialization.get_unsafe_globals_in_checkpoint(checkpoint_path))
    assert found.issubset(set(allowed)), found-set(allowed)
    trusted = [(getattr(importlib.import_module(n.rsplit('.',1)[0]),n.rsplit('.',1)[1]),n) for n in allowed]
    trusted += [type(np.dtype(np.float64)), type(np.dtype(np.float32))]
    with torch.serialization.safe_globals(trusted):
        checkpoint = torch.load(checkpoint_path,map_location='cpu',weights_only=True)
    model = (checkpoint.get('ema') or checkpoint['model']).float().eval()
    classes = json.loads((BASE/'detector_EXPERIMENT_PLAN.json').read_text())['class_names']
    assert model.names == dict(enumerate(classes))
    for module in model.modules():
        if isinstance(module,Detect):
            module.export=True;module.format='onnx';module.dynamic=False
    sample=torch.zeros(1,3,640,640)
    with torch.no_grad():
        output=model(sample)
    assert tuple(output.shape)==(1,38,8400)
    destination=run/'mahjong-yolo11n-rf100v1.onnx'
    torch.onnx.export(model,sample,str(destination),opset_version=17,input_names=['images'],output_names=['output0'],dynamo=False)
    exported=onnx.load(destination)
    onnx.helper.set_model_props(exported,{'names':repr(model.names),'task':'detect','license':'AGPL-3.0 Ultralytics-derived weights; source data provenance in detector_EXPERIMENT_PLAN.json','source_checkpoint_sha256':sha(checkpoint_path),'initial_weights_sha256':json.loads((BASE/'detector_EXPERIMENT_PLAN.json').read_text())['initial_weights']['sha256']})
    onnx.checker.check_model(exported);onnx.save(exported,destination)
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(destination),sess_options=options,providers=['CPUExecutionProvider'])
    manifest=json.loads((ROOT/'vision/datasets/rf100vl_mahjong/image_manifest.json').read_text())
    parity=[]
    for record in sorted((r for r in manifest['records'] if r['split']=='dev'),key=lambda r:r['id'])[:3]:
        tensor,geometry=prepare(Image.open(ROOT/record['path']).convert('RGB'))
        with torch.no_grad():
            torch_output=model(torch.from_numpy(tensor)).numpy()
        ort_output=session.run(None,{'images':tensor})[0]
        delta=np.abs(torch_output-ort_output)
        torch_classes=np.argmax(torch_output[:,4:,:],axis=1)
        ort_classes=np.argmax(ort_output[:,4:,:],axis=1)
        active=np.max(torch_output[:,4:,:],axis=1)>=.25
        entry={'id':record['id'],'max_box_delta_pixels':float(delta[:,:4,:].max()),'max_score_delta':float(delta[:,4:,:].max()),'active_anchor_count':int(active.sum()),'active_top_class_equal':bool(np.array_equal(torch_classes[active],ort_classes[active]))}
        assert entry['max_box_delta_pixels']<.1 and entry['max_score_delta']<1e-4 and entry['active_top_class_equal'],entry
        torch_pred=decode(torch_output,geometry,model.names)
        ort_pred=decode(ort_output,geometry,model.names)
        decoded_matches=match(torch_pred,ort_pred)
        entry['decoded_detection_count']=len(torch_pred)
        entry['decoded_nms_parity']=len(torch_pred)==len(ort_pred)==len(decoded_matches) and all(iou>.999 for _,_,iou in decoded_matches)
        assert entry['decoded_nms_parity'],entry
        parity.append(entry)
    with (run/'results.csv').open() as f:
        results=[{k.strip():float(v) for k,v in r.items()} for r in csv.DictReader(f)]
    selection=json.loads((run/'timeout_free_selection.json').read_text())
    best=next(r for r in results if int(r['epoch'])==selection['selected_epoch'])
    report={'model_path':str(destination.relative_to(ROOT)),'onnx_sha256':sha(destination),'onnx_bytes':destination.stat().st_size,'checkpoint_sha256':sha(checkpoint_path),'plan_sha256':sha(BASE/'detector_EXPERIMENT_PLAN.json'),'selected_epoch_from_csv':int(best['epoch']),'selected_dev_metrics':selection['metrics'],'training_validation_metrics_at_selected_epoch':None if int(best['epoch']) in range(12,20) else best,'training_validation_was_skipped':int(best['epoch']) in range(12,20),'selection_record':{k:v for k,v in selection.items() if k!='candidates'},'selection':'0.1*mAP50+0.9*mAP50-95 on dev only, timeout-free CPU revalidation of preserved epochs8-20','class_names':classes,'coverage':{'ordinary_identities':34,'red_five_distinction':False,'flowers_and_seasons':False,'explicit_unknown_class':False},'input':[1,3,640,640],'output':[1,38,8400],'opset':17,'normalization':'RGB bilinear letterbox pad114 then /255; cxcywh and34classscores; no objectness; no NMS','weights_only':True,'torch_onnx_parity_dev':parity,'parameters':sum(p.numel() for p in model.parameters()),'test_evaluation_status':'Any follow-up on consumed internal_test is diagnostic, not fresh generalization proof'}
    (run/'export_manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    main()
