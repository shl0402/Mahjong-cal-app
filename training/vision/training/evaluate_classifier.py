#!/usr/bin/env python3
"""Evaluate a frozen classifier; never optimize settings on internal_test/holdout.

Ground-truth crop metrics isolate classification. They do not measure locating
missing tiles, complete-camera-row success or physical-device performance.
"""
import argparse, hashlib, json, math, sys, time
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from vision.validation.manifest import audit, verify_files, verify_lock


def sha256(path):
    with Path(path).open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def _inside(root, path):
    if not isinstance(path, str) or not path.strip():
        raise ValueError('Invalid selection/source path')
    result = (root / path).resolve()
    if not result.is_relative_to(root):
        raise ValueError('Selection/source path escapes verification root')
    return result


def verify_selection_lock(lock_path, checkpoint_path, manifest_path, config, *, root=ROOT):
    """Verify lineage and bytes before protected evaluation reads any crops.

    Selection locking records an experiment commitment, not a cryptographic
    authority: preserve the file/hash in the run log before reading predictions.
    """
    root = Path(root).resolve()
    lock = json.loads(Path(lock_path).read_text())
    required = {'schema_version', 'selected_at', 'checkpoint_sha256',
                'evaluation_manifest_sha256', 'source_manifest_path', 'source_lock_path',
                'source_lock_sha256', 'source_split_manifest_path', 'thresholds', 'operating_threshold'}
    if not isinstance(lock, dict) or not required <= set(lock):
        raise ValueError('Incomplete classifier selection lock')
    if type(lock['schema_version']) is not int or lock['schema_version'] != 1:
        raise ValueError('Unknown classifier selection-lock version')
    try:
        selected_at = datetime.fromisoformat(lock['selected_at'])
        if selected_at.tzinfo is None:
            raise ValueError('Timezone required')
    except (TypeError, ValueError) as error:
        raise ValueError('Selection lock needs a timezone-aware timestamp') from error
    if lock['checkpoint_sha256'] != sha256(checkpoint_path):
        raise ValueError('Selection lock/checkpoint mismatch')
    if lock['evaluation_manifest_sha256'] != sha256(manifest_path):
        raise ValueError('Selection lock/evaluation manifest mismatch')
    thresholds = lock['thresholds']
    if (not isinstance(thresholds, list) or not thresholds or
        not all(type(t) in (int, float) and math.isfinite(t) and 0 < t <= 1 for t in thresholds) or
        sorted(set(thresholds)) != thresholds):
        raise ValueError('Thresholds must be predeclared, finite, sorted and unique in (0,1]')
    operating = lock['operating_threshold']
    if type(operating) not in (int, float) or operating not in thresholds:
        raise ValueError('Operating threshold must be one of the predeclared thresholds')
    source_path = _inside(root, lock['source_manifest_path'])
    source_lock_path = _inside(root, lock['source_lock_path'])
    if sha256(source_lock_path) != lock['source_lock_sha256']:
        raise ValueError('Source lock file changed')
    source = json.loads(source_path.read_text())
    source_lock = json.loads(source_lock_path.read_text())
    verify_lock(source, source_lock)
    source_report = audit(source, near_distance=source_lock['near_distance'], require_assigned=True)
    verify_files(source, root)
    source_split_path = _inside(root, lock['source_split_manifest_path'])
    split_hash = sha256(source_split_path)
    crops = json.loads(Path(manifest_path).read_text())
    if not config.get('source_split_sha256') or config['source_split_sha256'] != split_hash:
        raise ValueError('Training source split no longer matches its actual file')
    if crops.get('source_split_sha256') != split_hash:
        raise ValueError('Evaluation crops use a different source split')
    enriched = json.loads(source_split_path.read_text())
    originals = {_inside(root, r['path']): r for r in source['records']}
    assignments = {_inside(root, r['path']): r for r in enriched['records']}
    if len(assignments) != len(enriched['records']) or set(assignments) != set(originals):
        raise ValueError('Enriched source inventory differs from the locked source inventory')
    for path, original in originals.items():
        assignment = assignments[path]
        if assignment['split'] != original['split'] or assignment['sha256'] != original['sha256']:
            raise ValueError('Enriched source split/hash differs from the locked original')
    dataset_root = _inside(root, crops['dataset'])
    for crop in crops['records']:
        path = _inside(dataset_root, crop['source_path'])
        if path not in originals:
            raise ValueError('Crop references an original outside the locked source inventory')
        original, assignment = originals[path], assignments[path]
        if crop['source_sha256'] != original['sha256'] or crop['split'] != original['split']:
            raise ValueError('Crop source hash/split differs from the locked original')
        if any(crop[key] != assignment[key] for key in ('source_id', 'group_id')):
            raise ValueError('Crop source/group identity differs from source assignments')
    return lock, source_report


def wilson(successes,total,z=1.96):
    if not total:return None
    p=successes/total;den=1+z*z/total
    c=(p+z*z/(2*total))/den
    h=z*((p*(1-p)/total+z*z/(4*total*total))**.5)/den
    return [max(0,c-h),min(1,c+h)]


def main():
    import torch
    from torch.utils.data import DataLoader
    from vision.training.train_classifier import CropDataset,classifier,evaluate,load_classifier_checkpoint
    p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--checkpoint',required=True)
    p.add_argument('--split',choices=['dev','internal_test','holdout'],required=True);p.add_argument('--output',required=True)
    p.add_argument('--device',default='mps');p.add_argument('--batch',type=int,default=64)
    p.add_argument('--selection-lock',help='Pinned JSON committing checkpoint before reading a test split');a=p.parse_args()
    output=Path(a.output)
    if output.exists():raise ValueError('Refuse to overwrite an existing evaluation')
    checkpoint_hash=sha256(a.checkpoint)
    state=load_classifier_checkpoint(a.checkpoint)
    config=state['config']
    lock=None;source_report=None
    if a.split!='dev':
        if not a.selection_lock:raise ValueError('Test evaluation needs a saved selection lock')
        lock,source_report=verify_selection_lock(a.selection_lock,a.checkpoint,a.manifest,config)
    dataset=CropDataset(a.manifest,a.split,config['size'])
    if dataset.classes!=config['classes']:raise ValueError('Class map changed')
    if dataset.data.get('source_split_sha256')!=config.get('source_split_sha256'):raise ValueError('Source grouping/splits changed')
    if not len(dataset):raise ValueError('Empty evaluation split')
    model=classifier(len(dataset.classes));model.load_state_dict(state['state_dict']);model.to(a.device).eval();torch.set_num_threads(2)
    loader=DataLoader(dataset,batch_size=a.batch,shuffle=False,num_workers=2)
    t=time.perf_counter();metrics=evaluate(model,loader,a.device,len(dataset.classes))
    per_source=defaultdict(list); predictions=[];at=0
    with torch.inference_mode():
        for images,targets in loader:
            probabilities=model(images.to(a.device)).softmax(1).cpu().numpy()
            for target,prob in zip(targets.tolist(),probabilities):
                row=dataset.rows[at];at+=1
                label=int(prob.argmax());confidence=float(prob[label]);correct=label==target
                pred={'path':row['path'],'source_id':row['source_id'],'group_id':row['group_id'],
                      'target':target,'prediction':label,'confidence':confidence,'correct':correct}
                predictions.append(pred)
                if target<len(dataset.classes)-1:per_source[row['source_id']].append(correct)
    count=len(predictions);correct=sum(r['correct'] for r in predictions)
    selective=[]
    for threshold in lock['thresholds'] if lock else [.5,.7,.8,.9,.95,.99]:
        accepted=[r for r in predictions if r['confidence']>=threshold and dataset.classes[r['prediction']]!='background']
        selective.append({'threshold':threshold,'accepted':len(accepted),'wrong':sum(not r['correct'] for r in accepted),
                          'coverage':len(accepted)/count,'accuracy_among_accepted':sum(r['correct'] for r in accepted)/len(accepted) if accepted else None})
    exact=sum(all(flags) for flags in per_source.values())
    source_splits={r['source_path']:r['split'] for r in dataset.data['records']}
    skipped=dataset.data.get('skipped',[])
    skipped_selected=[r for r in skipped if r.get('split',source_splits.get(r['source']))==a.split]
    skipped_unknown=[r for r in skipped if r.get('split',source_splits.get(r['source'])) is None]
    report={'checkpoint':a.checkpoint,'checkpoint_sha256':checkpoint_hash,'manifest_sha256':sha256(a.manifest),
            'split':a.split,'test_selection_lock':a.selection_lock,'classes':dataset.classes,'metrics':metrics,
            'selection_lock_sha256':sha256(a.selection_lock) if lock else None,
            'source_audit':{k:v for k,v in source_report.items() if k!='components'} if source_report else None,
            'crop_accuracy_wilson95':wilson(correct,count),
            'all_evaluated_foreground_crops_correct_by_source':{'correct':exact,'total':len(per_source),'wilson95':wilson(exact,len(per_source))},
            'skipped_annotations':{'selected_split_count':len(skipped_selected),
                                   'selected_split_reasons':dict(Counter(r['reason'] for r in skipped_selected)),
                                   'unknown_split_count':len(skipped_unknown),
                                   'all_partitions_count':len(skipped)},
            'operating_point':next(r for r in selective if r['threshold']==lock['operating_threshold']) if lock else None,
            'selective_classification':selective,'predictions':predictions,'elapsed_seconds':time.perf_counter()-t,
            'limitations':['Ground-truth boxes supplied; this is not end-to-end tile detection or full-hand accuracy.',
                           'Crops within one source/physical set are correlated; crop-level Wilson interval is descriptive only.',
                           'Unknown physical-set/session IDs prevent an unseen-set claim.',
                           'Threshold table is predeclared/descriptive; do not select a threshold from test results.',
                           'Source-exact result covers only evaluated foreground crops; skipped annotations are reported separately.']}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'split':a.split,'accuracy':metrics['accuracy'],'macro_recall':metrics['macro_recall_present_classes'],
                     'source_exact':report['all_evaluated_foreground_crops_correct_by_source'],'output':str(output)}),flush=True)

if __name__=='__main__':main()
