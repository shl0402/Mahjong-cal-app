#!/usr/bin/env python3
"""Train from externally restricted-loaded COCO weights; only local outputs reload normally."""
import argparse
import hashlib
import importlib
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'vision/training'
os.environ['YOLO_AUTOINSTALL'] = 'False'
os.environ['YOLO_CONFIG_DIR'] = str(BASE / 'detector_downloads/config')
os.environ['WANDB_MODE'] = 'disabled'
os.environ['OMP_NUM_THREADS'] = '2'
os.environ['OPENBLAS_NUM_THREADS'] = '2'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--probe', action='store_true')
    parser.add_argument('--resume', action='store_true', help='Resume this script\'s own full20/weights/last.pt after an interruption')
    parser.add_argument('--batch-override',type=int,choices=[4],help='Recorded resource-only reduction when resuming; other frozen settings stay unchanged')
    parser.add_argument('--workers-override',type=int,choices=[0],help='Recorded resource-only removal of loader subprocesses when resuming')
    parser.add_argument('--skip-intermediate-validation',action='store_true',help='Documented compute repair: final validation plus later timeout-free CPU checkpoint selection')
    args = parser.parse_args()
    if args.probe and args.resume:
        parser.error('The discarded timing probe cannot be resumed')
    if args.batch_override is not None and not args.resume:
        parser.error('Resource batch reduction requires --resume')
    if args.workers_override is not None and not args.resume:
        parser.error('Resource worker reduction requires --resume')
    if args.skip_intermediate_validation and not args.resume:
        parser.error('Validation compute repair requires --resume')
    import torch
    torch.set_num_threads(2)
    from ultralytics import YOLO, settings
    from ultralytics.models.yolo.detect import DetectionTrainer
    from ultralytics.utils import checks
    checks.check_pip_update_available = lambda: None
    settings.update({k:False for k in ('sync','wandb','mlflow','comet','clearml','dvc','neptune','raytune','tensorboard') if k in settings})
    # Statically reviewed library classes only. External checkpoint code is never executed.
    allowed = '''ultralytics.nn.modules.conv.Concat
ultralytics.nn.modules.block.DFL
ultralytics.nn.modules.conv.Conv
ultralytics.nn.modules.block.C2PSA
ultralytics.nn.modules.head.Detect
torch.nn.modules.linear.Identity
torch.nn.modules.container.ModuleList
torch.nn.modules.upsampling.Upsample
ultralytics.nn.modules.block.SPPF
torch.nn.modules.activation.SiLU
ultralytics.nn.modules.block.Bottleneck
torch.nn.modules.container.Sequential
torch.nn.modules.batchnorm.BatchNorm2d
ultralytics.nn.modules.block.Attention
ultralytics.nn.modules.block.PSABlock
ultralytics.nn.modules.conv.DWConv
torch.nn.modules.conv.Conv2d
ultralytics.nn.tasks.DetectionModel
ultralytics.nn.modules.block.C3k
ultralytics.nn.modules.block.C3k2
torch.nn.modules.pooling.MaxPool2d'''.splitlines()
    plan_path = BASE / 'detector_EXPERIMENT_PLAN.json'
    plan = json.loads(plan_path.read_text())
    weights = BASE / 'detector_downloads/yolo11n-coco.pt'
    assert hashlib.sha256(weights.read_bytes()).hexdigest() == plan['initial_weights']['sha256']
    found = set(torch.serialization.get_unsafe_globals_in_checkpoint(weights))
    assert found.issubset(set(allowed)), found - set(allowed)
    classes = [getattr(importlib.import_module(n.rsplit('.',1)[0]),n.rsplit('.',1)[1]) for n in allowed]
    with torch.serialization.safe_globals(classes):
        checkpoint = torch.load(weights, map_location='cpu', weights_only=True)
    assert torch.backends.mps.is_available(), 'MPS unavailable; this experiment must run on MPS'
    memory = {'recommended_max_bytes':torch.mps.recommended_max_memory(), 'current_bytes':torch.mps.current_allocated_memory(), 'driver_bytes':torch.mps.driver_allocated_memory()}
    model = YOLO('yolo11n.yaml')
    source = checkpoint['model'].float()
    model.load(source)
    model.ckpt = checkpoint  # Model.train retains our safely loaded pretrained module.
    assert torch.equal(model.model.model[0].conv.weight,source.model[0].conv.weight)
    class TwoWorkerTrainer(DetectionTrainer):
        def __init__(self,*a,**kw):
            super().__init__(*a,**kw)
            self.args.workers = args.workers_override if args.workers_override is not None else 2
            # check_resume only accepts four override keys; enforce these after
            # it has restored the checkpoint's settings, before loader creation.
            if args.skip_intermediate_validation:
                assert self.args.epochs==20 and self.args.patience==100 and self.args.time is None
                self.args.val=False
    name = 'probe' if args.probe else 'full20'
    run_dir = BASE / 'detector_runs' / name
    if run_dir.exists() and not args.resume:
        raise RuntimeError(f'Refusing to overwrite an existing run: {run_dir}')
    if args.resume:
        if (run_dir/'run_summary.json').exists():
            raise RuntimeError('Completed experiments cannot be resumed')
        last = run_dir/'weights/last.pt'
        if not last.is_file():
            raise RuntimeError('No locally generated recovery checkpoint exists')
        # This file is an output of this script, never a downloaded checkpoint.
        model = YOLO(str(last))
    start = time.monotonic()
    events = json.loads((run_dir/'progress.json').read_text()) if args.resume and (run_dir/'progress.json').exists() else []
    previous_elapsed = events[-1]['elapsed_seconds'] if events else 0
    def record_epoch(trainer):
        measured=bool(trainer.args.val or trainer.epoch+1>=trainer.epochs)
        repeated_final=trainer.epoch+1==trainer.epochs and any(e['epoch']==trainer.epochs for e in events)
        entry = {'epoch':trainer.epoch+1,'elapsed_seconds':previous_elapsed+time.monotonic()-start,'metrics':{k:float(v) for k,v in trainer.metrics.items()} if measured else {},'validation_performed':measured,'validation_stage':'final_best_checkpoint' if repeated_final else ('epoch_validation' if measured else 'skipped_for_timeout_free_cpu_revalidation'),'best_fitness':float(trainer.best_fitness),'best_fitness_is_fresh':measured,'mps_current_bytes':torch.mps.current_allocated_memory(),'mps_driver_bytes':torch.mps.driver_allocated_memory()}
        events.append(entry)
        (run_dir/'progress.json').write_text(json.dumps(events,indent=2)+'\n')
        if measured and not repeated_final and trainer.fitness == trainer.best_fitness:
            selection={'selected_epoch':trainer.epoch+1,'fitness':float(trainer.fitness),'metrics':entry['metrics'],'criterion':'Ultralytics dev fitness; same equality/tie behavior as save_model'}
            (run_dir/'selection_record.json').write_text(json.dumps(selection,indent=2)+'\n')
        print('DETECTOR_PROGRESS '+json.dumps(entry),flush=True)
    model.add_callback('on_fit_epoch_end',record_epoch)
    def record_runtime(trainer):
        runtime={'start_epoch':trainer.start_epoch+1,'total_epochs':trainer.epochs,'batch':trainer.batch_size,'train_workers':trainer.train_loader.num_workers,'val_workers':trainer.test_loader.num_workers,'intermediate_validation':trainer.args.val,'patience':trainer.args.patience,'time_budget':trainer.args.time,'scheduler':'LambdaLR driven by epoch, not validation metrics','optimizer_state_entries':len(trainer.optimizer.state),'training_gradient_code':'unchanged BaseTrainer backward and optimizer_step','save_every_epoch':trainer.args.save}
        if args.workers_override==0:
            assert runtime['train_workers']==runtime['val_workers']==0
        if args.skip_intermediate_validation:
            assert trainer.start_epoch>=11 and runtime['intermediate_validation'] is False and runtime['save_every_epoch'] is True and runtime['patience']==100
        (run_dir/f"runtime_epoch{runtime['start_epoch']:02d}.json").write_text(json.dumps(runtime,indent=2)+'\n')
        print('DETECTOR_RUNTIME '+json.dumps(runtime),flush=True)
    model.add_callback('on_train_start',record_runtime)
    config = dict(plan['hyperparameters'])
    if args.probe:
        config['epochs'] = 1
    if args.resume:
        config['resume'] = str(run_dir/'weights/last.pt')
    if args.batch_override is not None:
        config['batch']=args.batch_override
    if args.workers_override is not None:
        config['workers']=args.workers_override
    if args.skip_intermediate_validation:
        config['val']=False
        repair={'recorded_at':datetime.now(timezone.utc).isoformat(),'skipped_validation_epochs':list(range(events[-1]['epoch']+1,20)),'reason':'Avoid repeated truncated MPS validation; all preserved epochs8-20 receive timeout-free CPU development validation after training','final_epoch_validation':True,'raw_results_csv_warning':'Skipped epoch validation columns are stale/default library bookkeeping, not measured validation results; progress.json explicitly marks them unavailable','verified_in_local_trainer':'Scheduler uses epoch LambdaLR; backward/optimizer_step unaffected; patience100 cannot early-stop a20-epoch run; save=True retains every checkpoint','selection_policy':'detector_SELECTION_REPAIR.json'}
        (run_dir/'validation_compute_repair.json').write_text(json.dumps(repair,indent=2)+'\n')
    if args.batch_override is not None or args.workers_override is not None:
        previous_config=model.ckpt.get('train_args',{})
        adjustment={'recorded_at':datetime.now(timezone.utc).isoformat(),'from_batch':previous_config.get('batch'),'to_batch':config['batch'],'from_requested_workers':previous_config.get('workers'),'to_requested_workers':config['workers'],'loader_note':'Ultralytics uses requested workers for train and twice that number for val; workers0 removes both pools','reason':'Resource exception: active macOS memory pressure, not validation/test results','resuming_after_epoch':events[-1]['epoch'] if events else None,'checkpoint_sha256':hashlib.sha256((run_dir/'weights/last.pt').read_bytes()).hexdigest(),'unchanged_plan_sha256':hashlib.sha256(plan_path.read_bytes()).hexdigest()}
        history_path=run_dir/'resource_adjustment_history.json'
        history=json.loads(history_path.read_text()) if history_path.exists() else ([json.loads((run_dir/'resource_adjustment.json').read_text())] if (run_dir/'resource_adjustment.json').exists() else [])
        history.append(adjustment)
        history_path.write_text(json.dumps(history,indent=2)+'\n')
        (run_dir/'resource_adjustment.json').write_text(json.dumps(adjustment,indent=2)+'\n')
    model.train(trainer=TwoWorkerTrainer, data=str(BASE/'detector_data/dataset.yaml'), project=str(BASE/'detector_runs'), name=name, exist_ok=args.resume, save=True, **config)
    elapsed = previous_elapsed+time.monotonic()-start
    result = {'probe':args.probe,'resumed':args.resume,'elapsed_seconds':elapsed,'estimated_20_epoch_seconds_from_probe':elapsed*20 if args.probe else None,'initial_memory':memory,'plan_sha256':hashlib.sha256(plan_path.read_bytes()).hexdigest(),'external_load_weights_only':True,'local_output_reload':'Ultralytics reloads locally generated checkpoints only','events':events}
    (run_dir/'run_summary.json').write_text(json.dumps(result,indent=2)+'\n')
    print('DETECTOR_FINISHED '+json.dumps(result),flush=True)

if __name__ == '__main__':
    main()
