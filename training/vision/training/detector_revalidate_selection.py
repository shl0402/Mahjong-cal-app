#!/usr/bin/env python3
"""Repair validation timeouts using saved candidates and development data only."""
import gc
import hashlib
import importlib
import json
import os
import shutil
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'vision/training'
RUN=BASE/'detector_runs/full20'
os.environ['YOLO_AUTOINSTALL']='False'
os.environ['YOLO_CONFIG_DIR']=str(BASE/'detector_downloads/config')
os.environ['OMP_NUM_THREADS']='2'
sys.path.insert(0,str(ROOT/'vision'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    import numpy as np
    import torch
    from export_v2_weights_only import ALLOWED
    os.environ['YOLO_CONFIG_DIR']=str(BASE/'detector_downloads/config')
    from ultralytics.models.yolo.detect import DetectionValidator
    from ultralytics.utils import ops
    torch.set_num_threads(2)
    assert (RUN/'run_summary.json').exists(), 'Training must finish before selection repair'
    policy_path=BASE/'detector_SELECTION_REPAIR.json'
    policy=json.loads(policy_path.read_text())
    # Locally trained checkpoints also retain the standard loss/assignment modules.
    allowed=list(ALLOWED)+['numpy.core.multiarray.scalar','numpy._core.multiarray.scalar','numpy.dtype',
        'ultralytics.utils.loss.BboxLoss','ultralytics.utils.loss.DFLoss',
        'ultralytics.utils.loss.v8DetectionLoss','ultralytics.utils.tal.TaskAlignedAssigner',
        'ultralytics.utils.IterableSimpleNamespace','torch.nn.modules.loss.BCEWithLogitsLoss']
    trusted=[(getattr(importlib.import_module(n.rsplit('.',1)[0]),n.rsplit('.',1)[1]),n) for n in allowed]
    trusted += [type(np.dtype(np.float64)),type(np.dtype(np.float32))]
    class NoTimeoutValidator(DetectionValidator):
        def postprocess(self,preds):
            outputs=ops.non_max_suppression(preds,self.args.conf,self.args.iou,nc=0 if self.args.task=='detect' else self.nc,multi_label=True,agnostic=self.args.single_cls or self.args.agnostic_nms,max_det=self.args.max_det,end2end=self.end2end,rotated=self.args.task=='obb',max_time_img=float('inf'))
            return [{'bboxes':x[:,:4],'conf':x[:,4],'cls':x[:,5],'extra':x[:,6:]} for x in outputs]
    results=[]
    for path in sorted((RUN/'weights').glob('candidate_epoch*.pt')):
        epoch=int(path.stem.removeprefix('candidate_epoch'))
        assert epoch in policy['eligible_epochs']
        found=set(torch.serialization.get_unsafe_globals_in_checkpoint(path))
        assert found.issubset(set(allowed)),found-set(allowed)
        with torch.serialization.safe_globals(trusted):
            checkpoint=torch.load(path,map_location='cpu',weights_only=True)
        assert checkpoint['epoch']==epoch-1, (path, checkpoint['epoch'], epoch)
        model=(checkpoint.get('ema') or checkpoint['model']).float().eval()
        start=time.monotonic()
        validator=NoTimeoutValidator(args={'data':str(BASE/'detector_data/dataset.yaml'),'split':'val','imgsz':640,'batch':8,'device':'cpu','workers':0,'conf':.001,'iou':.7,'max_det':300,'half':False,'plots':False,'save_json':False,'save_txt':False,'verbose':False,'project':str(RUN/'dev_revalidation'),'name':f'epoch{epoch:02d}','exist_ok':True,'rect':True})
        metrics=validator(model=model)
        expected_count=json.loads((BASE/'detector_EXPERIMENT_PLAN.json').read_text())['counts']['dev_images']
        assert validator.seen==expected_count, (validator.seen,expected_count)
        assert len(validator.metrics.maps)==34
        metric_values={k:float(v) for k,v in metrics.items()}
        # Use the unchanged standard Ultralytics fitness; later epoch wins a tie.
        fitness=float(validator.metrics.fitness)
        result={'epoch':epoch,'checkpoint_path':str(path.relative_to(ROOT)),'checkpoint_sha256':sha(path),'fitness':fitness,'metrics':metric_values,'elapsed_seconds':time.monotonic()-start,'images':validator.seen,'per_class_map50_95':list(map(float,validator.metrics.maps))}
        results.append(result)
        (RUN/'dev_revalidation_progress.json').write_text(json.dumps(results,indent=2)+'\n')
        print('REVALIDATED '+json.dumps(result),flush=True)
        del model,checkpoint,validator
        gc.collect()
    assert {r['epoch'] for r in results}==set(policy['eligible_epochs'])
    selected=max(results,key=lambda r:(r['fitness'],r['epoch']))
    destination=RUN/'weights/selected_dev.pt'
    shutil.copyfile(ROOT/selected['checkpoint_path'],destination)
    report={'selected_epoch':selected['epoch'],'fitness':selected['fitness'],'metrics':selected['metrics'],'checkpoint_path':str(destination.relative_to(ROOT)),'checkpoint_sha256':sha(destination),'criterion':'0.1 * development mAP50 + 0.9 * development mAP50-95; timeout-free CPU validation; later epoch wins ties','policy_sha256':sha(policy_path),'candidates':results,'unavailable_early_epochs':list(range(1,8)),'test_images_used_for_selection':False}
    (RUN/'timeout_free_selection.json').write_text(json.dumps(report,indent=2)+'\n')
    print('SELECTED '+json.dumps({k:v for k,v in report.items() if k!='candidates'}),flush=True)

if __name__=='__main__':
    main()
