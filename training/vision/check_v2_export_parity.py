#!/usr/bin/env python3
"""Compare restricted PyTorch checkpoint inference with the exported ONNX."""
import ast,importlib,json
import numpy as np
import onnxruntime as ort
import torch
from PIL import Image,ImageOps
from export_v2_weights_only import ROOT,SOURCE,SHA,ALLOWED
from evaluate_online import prepare
from evaluate_baseline import decode
import hashlib

def main():
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SHA
    assert set(torch.serialization.get_unsafe_globals_in_checkpoint(SOURCE)).issubset(set(ALLOWED))
    classes=[getattr(importlib.import_module(name.rsplit('.',1)[0]),name.rsplit('.',1)[1]) for name in ALLOWED]
    with torch.serialization.safe_globals(classes):checkpoint=torch.load(SOURCE,map_location='cpu',weights_only=True)
    model=checkpoint['model'].float().eval();torch.set_num_threads(2)
    from ultralytics.nn.modules.head import Detect
    for module in model.modules():
        if isinstance(module,Detect):module.export=True;module.format='onnx';module.dynamic=False
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    session=ort.InferenceSession(str(ROOT/'vision/downloads/mahjong-yolo11n-v2.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
    names=ast.literal_eval(session.get_modelmeta().custom_metadata_map['names'])
    assert names==model.names
    sources={s['id']:s for s in json.loads((ROOT/'vision/reports/online_sources.json').read_text())['sources']}
    regions=json.loads((ROOT/'vision/reports/online_annotations.json').read_text())['regions'];records=[]
    for region in regions:
        image=ImageOps.exif_transpose(Image.open(ROOT/sources[region['source_id']]['path'])).convert('RGB').crop(region['roi'])
        tensor,geometry=prepare(image)
        with torch.no_grad():expected=model(torch.from_numpy(tensor)).numpy()
        actual=session.run(None,{'images':tensor})[0]
        error=np.abs(expected-actual)
        passed=bool(np.allclose(actual,expected,rtol=1e-4,atol=1e-3))
        relevant=(expected[0,4:].max(axis=0)>=.25)|(actual[0,4:].max(axis=0)>=.25)
        top_classes_equal=bool(np.array_equal(expected[0,4:,relevant].argmax(axis=1),actual[0,4:,relevant].argmax(axis=1)))
        left=sorted(decode(expected,geometry,names),key=lambda p:(p['box'][0]+p['box'][2],p['box'][1]+p['box'][3]))
        right=sorted(decode(actual,geometry,names),key=lambda p:(p['box'][0]+p['box'][2],p['box'][1]+p['box'][3]))
        labels_equal=[p['tile'] for p in left]==[p['tile'] for p in right]
        boxes_equal=len(left)==len(right) and all(np.allclose(a['box'],b['box'],atol=1e-5,rtol=1e-5) for a,b in zip(left,right))
        record={'region':region['id'],'passed':passed and top_classes_equal and labels_equal and boxes_equal,
                'max_coordinate_error_pixels':float(error[:,:4].max()),'max_class_score_error':float(error[:,4:].max()),
                'candidate_top_class_ids_equal':top_classes_equal,'nms_ordered_labels_equal':labels_equal,
                'nms_boxes_equal':boxes_equal,'nms_detections':len(right)}
        records.append(record)
    report={'checkpoint_sha256':SHA,'onnx_sha256':hashlib.sha256((ROOT/'vision/downloads/mahjong-yolo11n-v2.onnx').read_bytes()).hexdigest(),
            'rtol':1e-4,'atol':1e-3,'metadata_class_mapping_equal':True,'all_passed':all(r['passed'] for r in records),'regions':records}
    (ROOT/'vision/reports/v2_export_parity.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    assert report['all_passed']
if __name__=='__main__':main()
