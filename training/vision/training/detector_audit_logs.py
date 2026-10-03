#!/usr/bin/env python3
"""Report standard-validator timeouts without treating skipped metrics as fresh."""
import collections
import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent
RUN = BASE / 'detector_runs/full20'


def main():
    reports = []
    for name in ('detector_full20.log', 'detector_resume_batch4.log',
                 'detector_resume_workers0.log'):
        current = 'startup'
        counts = collections.Counter()
        for line in re.split(r'[\r\n]', (BASE / name).read_text(errors='replace')):
            epoch = re.match(r'\s+(\d+)/20\s+', line)
            if epoch:
                current = 'epoch_' + epoch.group(1)
            if line.startswith('Validating ') and 'best.pt' in line:
                current = 'final_library_best_checkpoint'
            if 'NMS time limit' in line:
                counts[current] += 1
        reports.append({'log': name, 'nms_timeout_warning_count': sum(counts.values()),
                        'nms_timeout_warnings_by_stage': dict(counts)})
    progress = json.loads((RUN / 'progress.json').read_text())
    report = {
        'logs': reports,
        'validation_explicitly_skipped_epochs': sorted({r['epoch'] for r in progress
            if r.get('validation_performed') is False}),
        'selection_source': 'timeout_free_selection.json',
        'warning': 'A timeout can truncate batch predictions. Standard MPS validation '
                   'and raw results.csv are not the final selection or accuracy evidence. '
                   'Skipped validation metrics are unavailable, not measured zeros.',
    }
    (RUN / 'validation_log_audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
