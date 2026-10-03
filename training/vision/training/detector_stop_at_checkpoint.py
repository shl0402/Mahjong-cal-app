#!/usr/bin/env python3
"""Interrupt only our identified training process after a complete saved epoch."""
import argparse
import datetime
import hashlib
import json
import os
import signal
import subprocess
import time
from pathlib import Path

BASE=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--pid',type=int,required=True)
    parser.add_argument('--epoch',type=int,required=True)
    parser.add_argument('--adjustment',choices=['batch4','workers0'],default='batch4')
    args=parser.parse_args()
    run=BASE/'detector_runs/full20'
    for _ in range(300):
        command=subprocess.check_output(['ps','-p',str(args.pid),'-o','command='],text=True).strip()
        if 'Python vision/training/detector_train.py' not in command:
            raise RuntimeError('PID is not the known detector training command')
        try:
            progress=json.loads((run/'progress.json').read_text())
        except (FileNotFoundError,json.JSONDecodeError):
            time.sleep(2);continue
        if progress[-1]['epoch']>=args.epoch:
            last=run/'weights/last.pt'
            event={'stopped_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pid':args.pid,'command':command,'completed_epoch':progress[-1]['epoch'],'checkpoint_sha256':hashlib.sha256(last.read_bytes()).hexdigest(),'reason':'Persistent active memory compression and lower throughput after task-owned emulators closed','resource_adjustment':args.adjustment}
            history_path=run/'checkpoint_interruption_history.json'
            history=json.loads(history_path.read_text()) if history_path.exists() else ([json.loads((run/'checkpoint_interruption.json').read_text())] if (run/'checkpoint_interruption.json').exists() else [])
            history.append(event)
            history_path.write_text(json.dumps(history,indent=2)+'\n')
            (run/'checkpoint_interruption.json').write_text(json.dumps(event,indent=2)+'\n')
            os.kill(args.pid,signal.SIGINT)
            print(json.dumps(event,indent=2),flush=True)
            return
        time.sleep(2)
    raise RuntimeError('No safe checkpoint boundary appeared in ten minutes; no signal sent')

if __name__=='__main__':
    main()
