#!/usr/bin/env python3
"""Download pinned public research candidates; verify every artifact before use."""
import argparse,hashlib,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ARTIFACTS={
 'small':('yolo11s-v2.pt','https://raw.githubusercontent.com/nikmomo/Mahjong-YOLO/28ffceed232ad95fd019c47a6c51ae7c78791a0e/trained_models_v2/yolo11s_best.pt','1b755721c3b581fe550d9568c85a6c5cf12558c6232453943b73dc669eafd6fd'),
 'medium':('yolo11m-v2.pt','https://raw.githubusercontent.com/nikmomo/Mahjong-YOLO/28ffceed232ad95fd019c47a6c51ae7c78791a0e/trained_models_v2/yolo11m_best.pt','a00a03dd9229f5809d4de3c9474b9bcdd74b7b42a5a507e92a803755e268d372'),
 'ar42':('ar-yolov8-42.onnx','https://raw.githubusercontent.com/LYiHub/AR-Mahjong-Assistant-preview/e6bc06cbdbc22ab53f40b1ef5ebeca6dc49f8299/server/models/yolo/weights.onnx','63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a'),
 'vit':('mahjong-vit.safetensors','https://huggingface.co/s-seow/mahjong-tile-classifier-vit/resolve/997e76ef44835b4f582226c4f2826f6335af42d9/model.safetensors','6ce2fa4fb1cc052ebdfb181e34e35ea341dbe471bc5b9090f5dbd84ab1e5c796'),
}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('candidates',nargs='*',default=list(ARTIFACTS));args=parser.parse_args()
    dest=HERE/'downloads';dest.mkdir(exist_ok=True)
    for name in args.candidates:
        filename,url,expected=ARTIFACTS[name];target=dest/filename
        if not target.exists():
            partial=target.with_suffix(target.suffix+'.partial')
            subprocess.run(['curl','-fLsS','--max-time','180',url,'-o',str(partial)],check=True)
            if hashlib.sha256(partial.read_bytes()).hexdigest()!=expected:raise ValueError(f'Checksum mismatch: {name}')
            partial.replace(target)
        if hashlib.sha256(target.read_bytes()).hexdigest()!=expected:raise ValueError(f'Existing checksum mismatch: {name}')
        print('Verified',name,target.stat().st_size,flush=True)
if __name__=='__main__':main()
