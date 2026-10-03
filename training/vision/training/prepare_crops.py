#!/usr/bin/env python3
"""Build train/dev classifier crops from grouped COCO image partitions.

Image split JSON: {records:[{path,source_id,group_id,split}],...}; path relative
 to dataset root. Never randomly split crops. Entire original image is retained
as the grouping unit. Test images are not opened unless --include-test is used.
"""
from __future__ import annotations
import argparse, hashlib, json, math, random
from collections import Counter, defaultdict
from pathlib import Path
from PIL import Image

CANONICAL = [f'{n}{s}' for s in 'mps' for n in range(1,10)] + [f'{n}z' for n in range(1,8)]
NAMES = {**{f'Character {n}':f'{n}m' for n in range(1,10)},
         **{f'Circle {n}':f'{n}p' for n in range(1,10)},
         **{f'Bamboo {n}':f'{n}s' for n in range(1,10)},
         'East':'1z','South':'2z','West':'3z','North':'4z','White':'5z','Green':'6z','Red':'7z'}


def area_intersection(a, b):
    return max(0, min(a[2], b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))


def pixel_box(coco_box, width, height, margin=.06):
    x,y,w,h = coco_box
    if not all(math.isfinite(v) for v in coco_box) or w <= 0 or h <= 0:
        raise ValueError('Invalid COCO box')
    box = [max(0,min(width,math.floor(x-w*margin))),max(0,min(height,math.floor(y-h*margin))),
           max(0,min(width,math.ceil(x+w*(1+margin)))),max(0,min(height,math.ceil(y+h*(1+margin))))]
    if box[2] <= box[0] or box[3] <= box[1]:raise ValueError('Box outside image')
    return box


def build(dataset, splits, output, include_test=False, negatives=2):
    dataset, output = Path(dataset).resolve(), Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    assignments=json.loads(Path(splits).read_text())
    rows=assignments['records']
    grouped={}; source_splits={}
    for row in rows:
        for key,mapping in [('group_id',grouped),('source_id',source_splits)]:
            if not row.get(key):raise ValueError(f'Missing {key}')
            existing=mapping.setdefault(row[key],row['split'])
            if existing != row['split']:raise ValueError(f'{key} crosses splits')
    # Published image manifests use paths relative to their declared root;
    # minimal local fixtures may use paths relative to the dataset itself.
    source_root=Path(assignments['root']).resolve() if 'root' in assignments else dataset
    by_path={}
    for row in rows:
        source_path=(source_root/row['path']).resolve()
        if not source_path.is_relative_to(dataset):raise ValueError('Source path escapes dataset')
        by_path[str(source_path.relative_to(dataset))]=row
    if len(by_path)!=len(rows):raise ValueError('Repeated image path')
    coco_files=sorted(dataset.glob('*/_annotations.coco.json'))
    if not coco_files:raise ValueError('No COCO annotations')
    records=[]; counts=Counter(); skipped=[]
    for coco_path in coco_files:
        coco=json.loads(coco_path.read_text())
        categories={c['id']:CANONICAL.index(NAMES[c['name']]) for c in coco['categories']}
        annotations=defaultdict(list)
        for a in coco['annotations']:annotations[a['image_id']].append(a)
        for image in coco['images']:
            rel=str((coco_path.parent/image['file_name']).relative_to(dataset))
            if rel not in by_path:raise ValueError(f'Unassigned source {rel}')
            row=by_path[rel]
            if row['split'] in {'holdout','internal_test'} and not include_test:
                continue
            if row['split'] not in {'train','dev','internal_test','holdout'}:raise ValueError('Invalid split')
            with Image.open(dataset/rel) as f:
                # This export is already auto-oriented. COCO coordinates are in
                # these pixels, so applying EXIF orientation again is incorrect.
                photo=f.convert('RGB')
            if photo.size != (image['width'],image['height']):raise ValueError('COCO/image dimension mismatch')
            width,height=photo.size
            source_hash=hashlib.sha256((dataset/rel).read_bytes()).hexdigest()
            if row.get('sha256') and source_hash!=row['sha256']:raise ValueError('Source image hash changed')
            boxes=[]
            def save(box,label,suffix):
                key=hashlib.sha256((rel+'|'+suffix).encode()).hexdigest()[:24]
                path=Path('crops')/row['split']/f'{key}.jpg'
                target=output/path;target.parent.mkdir(parents=True,exist_ok=True)
                crop=photo.crop(box);crop.thumbnail((224,224),Image.Resampling.LANCZOS)
                crop.save(target,quality=95)
                records.append({'path':str(path),'label':label,'split':row['split'],
                    'source_id':row['source_id'],'group_id':row['group_id'],
                    'source_path':rel,'source_sha256':source_hash,'crop_box':box,
                    'annotation_id':suffix,'crop_sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
                counts[(row['split'],label)]+=1
            for a in annotations[image['id']]:
                original=pixel_box(a['bbox'],width,height,0)
                boxes.append(original)
                if a.get('iscrowd',0):
                    skipped.append({'source':rel,'id':a['id'],'reason':'crowd'});continue
                box=pixel_box(a['bbox'],width,height)
                if min(box[2]-box[0],box[3]-box[1])<8:
                    skipped.append({'source':rel,'id':a['id'],'reason':'less than8px'});continue
                save(box,categories[a['category_id']],str(a['id']))
            # Backgrounds train a rejection class. No claim is made that this
            # covers flowers/backs/occluded glyphs or every out-of-domain input.
            rng=random.Random(int(hashlib.sha256(rel.encode()).hexdigest()[:16],16))
            count=0
            for attempt in range(100):
                if count>=negatives:break
                w=rng.randint(max(8,width//20),max(9,width//5));h=min(height,int(w*rng.uniform(1.1,1.7)))
                x=rng.randint(0,width-w);y=rng.randint(0,height-h);box=[x,y,x+w,y+h]
                if any(area_intersection(box,b)>0 for b in boxes):continue
                save(box,len(CANONICAL),'background-'+str(count));count+=1
    manifest={'version':1,'classes':CANONICAL+['background'],'dataset':str(dataset),
              'source_split_sha256':hashlib.sha256(Path(splits).read_bytes()).hexdigest(),
              'crop_policy':'COCO box plus6percent context; preserve aspect; max224px; JPEG95',
              'test_crops_generated':include_test,'notes':['Crop accuracy is not whole-hand detection accuracy.',
                  'Background rejection does not establish rejection of every unsupported tile face.'],
              'counts':{split:{str(c):counts[(split,c)] for c in range(35)} for split in sorted({r['split'] for r in records})},
              'skipped':skipped,'records':records}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'records':len(records),'split_counts':dict(Counter(r['split'] for r in records)),
                      'output':str(output/'manifest.json'),'skipped':len(skipped)}),flush=True)
    return manifest


def main():
    p=argparse.ArgumentParser();p.add_argument('--dataset',required=True);p.add_argument('--splits',required=True);p.add_argument('--output',required=True)
    p.add_argument('--include-test',action='store_true');p.add_argument('--negatives',type=int,default=2);a=p.parse_args()
    build(a.dataset,a.splits,a.output,a.include_test,a.negatives)
if __name__=='__main__':main()
