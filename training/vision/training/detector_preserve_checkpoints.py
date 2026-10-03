#!/usr/bin/env python3
"""Preserve completed local checkpoints for timeout-free dev-only validation."""
import hashlib
import json
import shutil
import time
from pathlib import Path

RUN=Path(__file__).resolve().parent/'detector_runs/full20'

def main():
    for _ in range(7200):
        try:
            progress=json.loads((RUN/'progress.json').read_text())
        except (FileNotFoundError,json.JSONDecodeError):
            time.sleep(2);continue
        epoch=progress[-1]['epoch']
        source=RUN/'weights/last.pt'
        destination=RUN/'weights'/f'candidate_epoch{epoch:02d}.pt'
        if source.exists() and not destination.exists():
            before=source.stat()
            temporary=destination.with_suffix('.temporary')
            shutil.copyfile(source,temporary)
            after=source.stat()
            if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):
                temporary.unlink();time.sleep(2);continue
            temporary.replace(destination)
            record={'epoch':epoch,'bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'progress_elapsed_seconds':progress[-1]['elapsed_seconds']}
            (destination.with_suffix('.json')).write_text(json.dumps(record,indent=2)+'\n')
            print(json.dumps(record),flush=True)
        if (RUN/'run_summary.json').exists():
            return
        time.sleep(2)
    raise RuntimeError('Checkpoint observer reached four-hour limit')

if __name__=='__main__':
    main()
