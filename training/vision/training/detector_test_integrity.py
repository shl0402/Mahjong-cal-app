"""Read-only checks for the detector experiment's data and selection boundary."""
import hashlib
import json
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'vision/training'

class DetectorIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan=json.loads((BASE/'detector_EXPERIMENT_PLAN.json').read_text())
        cls.source=json.loads((ROOT/'vision/datasets/rf100vl_mahjong/image_manifest.json').read_text())
        cls.by_id={r['id']:r for r in cls.source['records']}
        cls.protected=set(json.loads((ROOT/'vision/validation/rf100vl_internal_test_v1.lock.json').read_text())['protected_ids'])

    def test_prepared_images_have_no_test_ids_or_groups(self):
        test_groups={self.by_id[i]['group_id'] for i in self.protected}
        ids={r['id'] for r in self.plan['prepared_records']}
        self.assertFalse(ids & self.protected)
        self.assertFalse(test_groups & {r['group_id'] for r in self.plan['prepared_records']})
        self.assertEqual(len(ids),1979)
        self.assertEqual(ids,{r['id'] for r in self.source['records'] if r['split'] in ('train','dev')})
        self.assertFalse((BASE/'detector_data/images/internal_test').exists())

    def test_source_and_official_checkpoint_are_pinned(self):
        self.assertEqual(hashlib.sha256((ROOT/'vision/datasets/rf100vl_mahjong/image_manifest.json').read_bytes()).hexdigest(),self.plan['source_manifest_sha256'])
        self.assertEqual(hashlib.sha256((BASE/'detector_downloads/yolo11n-coco.pt').read_bytes()).hexdigest(),self.plan['initial_weights']['sha256'])

    def test_all_labels_match_canonical_coco_geometry(self):
        for prepared in self.plan['prepared_records']:
            original=self.by_id[prepared['id']]
            image=ROOT/prepared['prepared_image']
            self.assertEqual(image.resolve(),(ROOT/original['path']).resolve())
            label=Path(str(image).replace('/images/','/labels/')).with_suffix('.txt')
            self.assertEqual(hashlib.sha256(label.read_bytes()).hexdigest(),prepared['label_sha256'])
            values=[line.split() for line in label.read_text().splitlines()]
            self.assertEqual(len(values),len(original['annotations']))
            for encoded,annotation in zip(values,original['annotations']):
                x,y,w,h=annotation['bbox'];iw,ih=original['width'],original['height']
                expected=[(x+w/2)/iw,(y+h/2)/ih,w/iw,h/ih]
                self.assertEqual(self.plan['class_names'][int(encoded[0])],annotation['label'])
                for actual,reference in zip(map(float,encoded[1:]),expected):
                    self.assertAlmostEqual(actual,reference,places=9)
                    self.assertGreaterEqual(actual,0)
                    self.assertLessEqual(actual,1)

    def test_selection_and_augmentation_policy_is_frozen(self):
        config=self.plan['hyperparameters']
        self.assertEqual(config['epochs'],20)
        self.assertEqual(config['seed'],20261002)
        self.assertEqual(config['imgsz'],640)
        self.assertEqual(config['batch'],8)
        self.assertEqual((config['fliplr'],config['flipud']),(0,0))
        self.assertTrue(self.plan['source_test_already_consumed'])
        self.assertIn('no test-based selection',self.plan['selection'])
        self.assertEqual(self.plan['clipped_boxes'],[])

if __name__=='__main__':
    unittest.main()
