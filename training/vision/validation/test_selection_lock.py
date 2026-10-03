from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from vision.training.evaluate_classifier import verify_selection_lock, sha256
from vision.validation.manifest import make_lock
from vision.validation.test_manifest import record, manifest


class SelectionLockTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'source').mkdir()
        (self.root / 'source/labels.json').write_text('{"annotations": []}')
        rows, assignments, crops = [], [], []
        for rid, split in [('a', 'train'), ('b', 'dev'), ('c', 'internal_test')]:
            asset = self.root / f'source/{rid}.bin'
            asset.write_bytes(f'original {rid}'.encode())
            source = record(rid, path=f'source/{rid}.bin', sha256=sha256(asset),
                            source_sha256=sha256(asset), split=split,
                            annotation_path='source/labels.json',
                            annotation_sha256=sha256(self.root / 'source/labels.json'))
            rows.append(source)
            assignments.append(source | {'source_id': f'source:{rid}', 'group_id': f'group:{rid}'})
            crops.append({'path':f'{rid}.jpg', 'label':0, 'source_path':f'{rid}.bin',
                          'source_id':f'source:{rid}', 'group_id':f'group:{rid}',
                          'source_sha256':sha256(asset), 'split':split})
        self.source = manifest(*rows)
        self.write('source.json', self.source)
        self.write('source.lock.json', make_lock(self.source))
        self.write('assignments.json', {'records': assignments})
        split_hash = sha256(self.root / 'assignments.json')
        self.config = {'source_split_sha256': split_hash}
        self.crops = {'dataset':str(self.root / 'source'), 'source_split_sha256':split_hash,
                      'classes':['1m'], 'records':crops}
        self.write('crops.json', self.crops)
        (self.root / 'checkpoint.bin').write_bytes(b'frozen checkpoint')
        self.lock = {
            'schema_version':1, 'selected_at':'2026-10-02T15:00:00+00:00',
            'checkpoint_sha256':sha256(self.root / 'checkpoint.bin'),
            'evaluation_manifest_sha256':sha256(self.root / 'crops.json'),
            'source_manifest_path':'source.json', 'source_lock_path':'source.lock.json',
            'source_lock_sha256':sha256(self.root / 'source.lock.json'),
            'source_split_manifest_path':'assignments.json',
            'thresholds':[.5,.8,.95], 'operating_threshold':.8,
        }
        self.write('selection.json', self.lock)

    def write(self, path, value):
        (self.root / path).write_text(json.dumps(value))

    def verify(self):
        return verify_selection_lock(self.root/'selection.json', self.root/'checkpoint.bin',
                                     self.root/'crops.json', self.config, root=self.root)

    def repin_crops(self, crops):
        self.write('crops.json', crops)
        lock = self.lock | {'evaluation_manifest_sha256':sha256(self.root/'crops.json')}
        self.write('selection.json', lock)

    def test_valid_selection_links_checkpoint_crops_originals_labels_and_policy(self):
        lock, report = self.verify()
        self.assertEqual(lock['operating_threshold'], .8)
        self.assertEqual(report['split_records']['internal_test'], 1)

    def test_checkpoint_and_evaluation_manifest_changes_fail_before_evaluation(self):
        (self.root/'checkpoint.bin').write_bytes(b'new checkpoint')
        with self.assertRaisesRegex(ValueError, 'checkpoint mismatch'):
            self.verify()
        (self.root/'checkpoint.bin').write_bytes(b'frozen checkpoint')
        self.write('crops.json', self.crops | {'extra':'edited after selection'})
        with self.assertRaisesRegex(ValueError, 'evaluation manifest mismatch'):
            self.verify()

    def test_original_and_annotation_bytes_checked_not_just_declared_hashes(self):
        image = self.root/'source/c.bin'
        image.write_bytes(b'replaced original')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.verify()
        image.write_bytes(b'original c')
        (self.root/'source/labels.json').write_text('{"annotations": ["changed"]}')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.verify()

    def test_source_lock_and_actual_enriched_split_are_both_verified(self):
        (self.root/'source.lock.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'Source lock file changed'):
            self.verify()
        self.write('source.lock.json', make_lock(self.source, locked_at='2026-10-02T00:00:00Z'))
        self.write('selection.json', self.lock | {'source_lock_sha256':sha256(self.root/'source.lock.json')})
        self.write('assignments.json', {'records': []})
        with self.assertRaisesRegex(ValueError, 'Training source split'):
            self.verify()

    def test_even_a_pinned_crop_manifest_cannot_change_source_split_hash_or_identity(self):
        for key, value in [('split','train'), ('source_sha256','0'*64),
                           ('source_id','invented'), ('group_id','invented'),
                           ('source_path','missing.bin'), ('source_path','../../outside.bin')]:
            changed = deepcopy(self.crops)
            changed['records'][2][key] = value
            self.repin_crops(changed)
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.verify()

    def test_thresholds_and_required_commitment_fields_fail_closed(self):
        for key, value in [('thresholds',[]), ('thresholds',[.8,.5]), ('thresholds',[.8,.8]),
                           ('thresholds',[float('nan')]), ('thresholds',[True]),
                           ('operating_threshold',.7), ('operating_threshold',True),
                           ('selected_at','2026-10-02'), ('schema_version',True),
                           ('source_lock_path','../outside.json')]:
            self.write('selection.json', self.lock | {key:value})
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.verify()
        self.write('selection.json', {'checkpoint_sha256':self.lock['checkpoint_sha256']})
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
