#!/usr/bin/env python3
"""Preserve final optimizer/EMA state and omit redundant post-training MPS validation."""
import argparse
import datetime
import hashlib
import importlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
RUN = BASE / 'detector_runs/full20'
sys.path.insert(0, str(ROOT / 'vision'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import numpy as np
    import torch
    from export_v2_weights_only import ALLOWED
    torch.set_num_threads(2)
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int, required=True)
    args = parser.parse_args()
    allowed = list(ALLOWED) + ['numpy.core.multiarray.scalar', 'numpy._core.multiarray.scalar',
        'numpy.dtype', 'ultralytics.utils.loss.BboxLoss', 'ultralytics.utils.loss.DFLoss',
        'ultralytics.utils.loss.v8DetectionLoss', 'ultralytics.utils.tal.TaskAlignedAssigner',
        'ultralytics.utils.IterableSimpleNamespace', 'torch.nn.modules.loss.BCEWithLogitsLoss']
    trusted = [(getattr(importlib.import_module(n.rsplit('.', 1)[0]), n.rsplit('.', 1)[1]), n)
               for n in allowed] + [type(np.dtype(np.float64)), type(np.dtype(np.float32))]
    source = RUN / 'weights/last.pt'
    initial = source.stat().st_mtime_ns
    temporary = RUN / 'weights/final_snapshot.temporary'
    started = time.monotonic()
    while time.monotonic() - started < 900:
        if source.stat().st_mtime_ns == initial:
            time.sleep(.03)
            continue
        before = source.stat()
        shutil.copyfile(source, temporary)
        after = source.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            time.sleep(.03)
            continue
        try:
            found = set(torch.serialization.get_unsafe_globals_in_checkpoint(temporary))
            assert found.issubset(set(allowed)), found - set(allowed)
            with torch.serialization.safe_globals(trusted):
                checkpoint = torch.load(temporary, map_location='cpu', weights_only=True)
        except (EOFError, RuntimeError):
            time.sleep(.03)
            continue
        if checkpoint.get('epoch') != 19 or not checkpoint.get('optimizer', {}).get('state'):
            raise RuntimeError('Final full checkpoint was not captured; no signal sent')
        command = subprocess.check_output(['ps', '-p', str(args.pid), '-o', 'command='], text=True).strip()
        assert 'Python vision/training/detector_train.py --resume --batch-override 4 --workers-override 0' in command
        destination = RUN / 'weights/candidate_epoch20.pt'
        temporary.replace(destination)
        optimizer_path = RUN / 'weights/final_optimizer_snapshot.pt'
        torch.save(checkpoint['optimizer'], optimizer_path)
        record = {'epoch': 20, 'checkpoint_sha256': sha(destination),
                  'optimizer_snapshot_sha256': sha(optimizer_path),
                  'optimizer_state_entries': len(checkpoint['optimizer']['state']),
                  'checkpoint_internal_epoch': checkpoint['epoch'],
                  'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'pid': args.pid, 'command': command,
                  'reason': 'All20 training epochs and final in-loop validation completed; '
                            'omit redundant library best.pt MPS validation, replaced by '
                            'precommitted timeout-free CPU dev selection',
                  'normal_training_function_return': False, 'termination_signal': 'SIGINT'}
        (RUN / 'post_training_validation_omission.json').write_text(json.dumps(record, indent=2) + '\n')
        (destination.with_suffix('.json')).write_text(json.dumps(record, indent=2) + '\n')
        os.kill(args.pid, signal.SIGINT)
        print(json.dumps(record), flush=True)
        for _ in range(300):
            check = subprocess.run(['ps', '-p', str(args.pid), '-o', 'command='], capture_output=True, text=True)
            if not check.stdout.strip():
                progress = json.loads((RUN / 'progress.json').read_text())
                assert progress[-1]['epoch'] == 20
                summary = {'probe': False, 'resumed': True, 'completed_training_epochs': 20,
                    'elapsed_seconds': progress[-1]['elapsed_seconds'], 'events': progress,
                    'plan_sha256': sha(BASE / 'detector_EXPERIMENT_PLAN.json'),
                    'normal_training_function_return': False,
                    'post_training_mps_validation_omitted': True,
                    'training_process_exited': True, 'termination_signal': 'SIGINT',
                    'final_checkpoint': record,
                    'external_load_weights_only': True,
                    'local_output_reload': 'Ultralytics reloads locally generated checkpoints only'}
                (RUN / 'run_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
                print('Training process exited; checkpoint20 and optimizer preserved.', flush=True)
                return
            time.sleep(.2)
        raise RuntimeError('Process has not exited; summary not finalized')
    raise RuntimeError('Final checkpoint did not appear; no signal sent')


if __name__ == '__main__':
    main()
