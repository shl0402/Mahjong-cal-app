#!/usr/bin/env python3
"""Export a pinned checkpoint with PyTorch's restricted weights-only unpickler.
No checkpoint-defined Python functions/classes are permitted.
"""
import hashlib,importlib,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.environ['YOLO_AUTOINSTALL']='False'
os.environ['YOLO_CONFIG_DIR']=str(ROOT/'vision/downloads/ultralytics-config')
import torch
import onnx

SOURCE=ROOT/'vision/downloads/mahjong-yolo11n-v2.pt'
SHA='ea35d50b9568fc67277538038e7c456b3f29ebd65e1de7bd141e5a1d3a9d0ff1'
# Explicitly reviewed library classes. Never dynamically allow all names in a checkpoint.
ALLOWED='''ultralytics.nn.modules.conv.Concat
ultralytics.nn.modules.block.DFL
ultralytics.nn.modules.conv.Conv
ultralytics.nn.modules.block.C2PSA
ultralytics.nn.modules.head.Detect
torch.nn.modules.linear.Identity
torch.nn.modules.container.ModuleList
torch.nn.modules.upsampling.Upsample
ultralytics.nn.modules.block.SPPF
torch.nn.modules.activation.SiLU
ultralytics.nn.modules.block.Bottleneck
torch.nn.modules.container.Sequential
torch.nn.modules.batchnorm.BatchNorm2d
ultralytics.nn.modules.block.Attention
ultralytics.nn.modules.block.PSABlock
ultralytics.nn.modules.conv.DWConv
torch.nn.modules.conv.Conv2d
ultralytics.nn.tasks.DetectionModel
ultralytics.nn.modules.block.C3k
ultralytics.nn.modules.block.C3k2
torch.nn.modules.pooling.MaxPool2d'''.splitlines()

def main():
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SHA
    globals_found=set(torch.serialization.get_unsafe_globals_in_checkpoint(SOURCE))
    if not globals_found.issubset(set(ALLOWED)):
        raise ValueError(f'Unapproved pickle globals: {globals_found-set(ALLOWED)}')
    classes=[]
    for name in ALLOWED:
        module,attribute=name.rsplit('.',1);classes.append(getattr(importlib.import_module(module),attribute))
    with torch.serialization.safe_globals(classes):
        checkpoint=torch.load(SOURCE,map_location='cpu',weights_only=True)
    model=checkpoint['model'].float().eval()
    torch.set_num_threads(2)
    from ultralytics.nn.modules.head import Detect
    for module in model.modules():
        if isinstance(module,Detect):
            module.export=True;module.format='onnx';module.dynamic=False
    sample=torch.zeros(1,3,640,640)
    with torch.no_grad():
        y=model(sample)
    print('names',model.names,'output',tuple(y.shape),flush=True)
    if tuple(y.shape)!=(1,42,8400) or model.names.get(34)!='UNKNOWN':raise ValueError('Unexpected newer model output')
    destination=ROOT/'vision/downloads/mahjong-yolo11n-v2.onnx'
    torch.onnx.export(model,sample,str(destination),opset_version=17,input_names=['images'],output_names=['output0'],dynamo=False)
    exported=onnx.load(destination)
    onnx.helper.set_model_props(exported,{'names':repr(model.names),'task':'detect','license':'AGPL-3.0 (Ultralytics-derived model)',
                                         'source_checkpoint_sha256':SHA,'export':'torch restricted weights_only=True; explicit trusted class allowlist'})
    onnx.checker.check_model(exported)
    onnx.save(exported,destination)
    print(destination,hashlib.sha256(destination.read_bytes()).hexdigest(),destination.stat().st_size,flush=True)
    (ROOT/'vision/reports/v2_export.json').write_text(json.dumps({'checkpoint_sha256':SHA,'onnx_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
        'onnx_bytes':destination.stat().st_size,'checkpoint_training_version':checkpoint.get('version'),'torch':torch.__version__,
        'allowed_classes':ALLOWED,'weights_only':True,'opset':17},indent=2)+'\n')

if __name__=='__main__':main()
