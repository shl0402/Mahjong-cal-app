#!/usr/bin/env python3
"""Import an existing, hash-verified local research model; never upload images."""
import argparse
import hashlib
import shutil
from pathlib import Path

EXPECTED = '63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    args = parser.parse_args()
    source = args.source.expanduser().resolve(strict=True)
    if hashlib.sha256(source.read_bytes()).hexdigest() != EXPECTED:
        parser.error('Model SHA-256 mismatch; no asset was changed.')
    target = Path(__file__).resolve().parents[1] / 'assets/models/mahjong-ar42-63b683c7.onnx'
    target.parent.mkdir(parents=True, exist_ok=True)
    if source != target.resolve():
        shutil.copy2(source, target)
    print(f'Verified local research model: {target}')

if __name__ == '__main__':
    main()
