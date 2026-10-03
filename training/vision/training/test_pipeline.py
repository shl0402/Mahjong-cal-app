import json,tempfile,unittest
from pathlib import Path
import numpy as np
from PIL import Image
from prepare_crops import pixel_box,build
from train_classifier import validate_manifest,transform,CropDataset

class PipelineTests(unittest.TestCase):
 def test_no_crop_level_source_split(self):
  rows=[dict(path='a',label=0,source_id='same',group_id='g1',split='train'),dict(path='b',label=0,source_id='same',group_id='g2',split='dev')]
  with self.assertRaises(ValueError):validate_manifest(dict(classes=['1m'],records=rows))
 def test_no_group_crossing(self):
  rows=[dict(path='a',label=0,source_id='a',group_id='same',split='train'),dict(path='b',label=0,source_id='b',group_id='same',split='dev')]
  with self.assertRaises(ValueError):validate_manifest(dict(classes=['1m'],records=rows))
 def test_clips_context_to_image(self):
  self.assertEqual(pixel_box([0,0,20,30],20,30),[0,0,20,30])
  with self.assertRaises(ValueError):pixel_box([0,0,float('nan'),4],20,30)
  with self.assertRaises(ValueError):pixel_box([100,100,4,4],20,30)
 def test_changed_crop_bytes_rejected(self):
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory)
   Image.new('RGB',(10,10)).save(root/'tile.png')
   rows=[dict(path='tile.png',label=0,source_id='a',group_id='a',split='dev',crop_sha256='0'*64),
         dict(path='unused.png',label=0,source_id='b',group_id='b',split='train')]
   (root/'manifest.json').write_text(json.dumps(dict(classes=['1m'],records=rows)))
   with self.assertRaisesRegex(ValueError,'Crop bytes changed'):CropDataset(root/'manifest.json','dev')[0]
 def test_crowd_regions_cannot_be_sampled_as_background(self):
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);data=root/'data';data.mkdir();records=[]
   for role in ['train','dev']:
    d=data/role;d.mkdir();Image.new('RGB',(80,100),'white').save(d/'tile.jpg')
    coco={'categories':[{'id':0,'name':'Character 1'}], 'images':[{'id':0,'file_name':'tile.jpg','width':80,'height':100}], 'annotations':[{'id':0,'image_id':0,'category_id':0,'bbox':[0,0,80,100],'iscrowd':1}]}
    (d/'_annotations.coco.json').write_text(json.dumps(coco))
    records.append(dict(path=role+'/tile.jpg',source_id=role,group_id=role,split=role))
   (root/'split.json').write_text(json.dumps({'records':records}))
   report=build(data,root/'split.json',root/'crops')
   self.assertEqual(report['records'],[]);self.assertEqual(len(report['skipped']),2)
 def test_no_test_pixels_opened_during_preparation(self):
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);data=root/'data';data.mkdir();split=root/'split.json';records=[]
   for role in ['train','dev','internal_test']:
    d=data/role;d.mkdir()
    if role!='internal_test':Image.new('RGB',(80,100),'white').save(d/'tile.jpg')
    # Deliberately absent test image: even opening it would fail the build.
    coco={'categories':[{'id':0,'name':'Character 1'}], 'images':[{'id':0,'file_name':'tile.jpg','width':80,'height':100}], 'annotations':[{'id':0,'image_id':0,'category_id':0,'bbox':[10,10,30,50]}]}
    (d/'_annotations.coco.json').write_text(json.dumps(coco))
    records.append(dict(path=role+'/tile.jpg',source_id=role,group_id=role,split=role))
   split.write_text(json.dumps({'records':records}))
   report=build(data,split,root/'crops',negatives=0)
   self.assertEqual({r['split'] for r in report['records']},{'train','dev'})
   self.assertFalse(report['test_crops_generated'])
 def test_transform_is_finite_and_normalized_rgb(self):
  x=transform(Image.new('RGB',(20,40),(255,0,0)),160)
  self.assertEqual(tuple(x.shape),(3,160,160));self.assertTrue(np.isfinite(x.numpy()).all())
  self.assertAlmostEqual(x[0,80,80].item(),(1-.485)/.229,places=5)
  self.assertAlmostEqual(x[1,80,80].item(),(0-.456)/.224,places=5)
if __name__=='__main__':unittest.main()
