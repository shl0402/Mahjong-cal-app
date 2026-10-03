#!/usr/bin/env python3
"""Train a small tile classifier without reading held-out evaluation pixels.

Input manifest: {classes: [canonical labels], records: [{path, label, split,
source_id, group_id}], ...}. Paths are relative to the manifest. Every crop
inherits its original image's split; no crop-level random split is permitted.
Only train/dev records are opened by this program. Test evaluation is separate.
"""
from __future__ import annotations
import argparse, hashlib, io, json, math, random, time
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps
import torch
from torch import nn
from torch.utils.data import Dataset, DataLoader
from torchvision.models import mobilenet_v3_small
from torchvision.transforms import functional as TF

ROOT = Path(__file__).resolve().parents[2]
WEIGHT_SHA256 = '047dcff4addef86ea5bc2eff13c9614dc11f47ab1160d0a71a25e7db994f4e1f'


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def letterbox(image, size):
    image = image.convert('RGB')
    scale = size / max(image.size)
    wh = tuple(max(1, round(x * scale)) for x in image.size)
    image = image.resize(wh, Image.Resampling.BILINEAR)
    out = Image.new('RGB', (size, size), (114, 114, 114))
    out.paste(image, ((size - wh[0]) // 2, (size - wh[1]) // 2))
    return out


def transform(image, size, training=False):
    if training:
        # A physical tile can be upside-down. Mirrored glyphs are deliberately
        # excluded: a horizontal flip is not a normal real-camera variation.
        if random.random() < .25:
            image = image.transpose(Image.Transpose.ROTATE_180)
        image = TF.affine(image, random.uniform(-12, 12), [0, 0],
                          random.uniform(.92, 1.08), [random.uniform(-4, 4), 0],
                          interpolation=TF.InterpolationMode.BILINEAR,
                          fill=[114, 114, 114])
        image = ImageEnhance.Brightness(image).enhance(random.uniform(.72, 1.28))
        image = ImageEnhance.Contrast(image).enhance(random.uniform(.78, 1.22))
        image = ImageEnhance.Color(image).enhance(random.uniform(.8, 1.2))
        if random.random() < .15:
            image = image.filter(ImageFilter.GaussianBlur(random.uniform(.2, .8)))
    tensor = TF.to_tensor(letterbox(image, size))
    return TF.normalize(tensor, [.485, .456, .406], [.229, .224, .225])


def validate_manifest(data):
    classes = data['classes']
    if not classes or len(set(classes)) != len(classes):
        raise ValueError('Classes must be unique and nonempty')
    source_split, group_split, paths = {}, {}, set()
    for row in data['records']:
        if row['split'] not in {'train', 'dev', 'internal_test', 'holdout'}:
            raise ValueError('Unexpected split')
        if not isinstance(row['label'], int) or isinstance(row['label'], bool) or not 0 <= row['label'] < len(classes):
            raise ValueError('Invalid class ID')
        for field, mapping in [('source_id', source_split), ('group_id', group_split)]:
            if not row.get(field):
                raise ValueError(f'Missing {field}')
            key = row[field]
            if key in mapping and mapping[key] != row['split']:
                raise ValueError(f'{field} crosses splits: {key}')
            mapping[key] = row['split']
        if row['path'] in paths:
            raise ValueError('Duplicate crop path')
        paths.add(row['path'])
    if not {'train', 'dev'}.issubset({r['split'] for r in data['records']}):
        raise ValueError('Need train and development partitions')


class CropDataset(Dataset):
    def __init__(self, path, split, size=160):
        self.path = Path(path).resolve()
        self.data = json.loads(self.path.read_text())
        validate_manifest(self.data)
        self.rows = [r for r in self.data['records'] if r['split'] == split]
        self.classes = self.data['classes']
        self.size, self.training = size, split == 'train'

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, index):
        row = self.rows[index]
        path = (self.path.parent / row['path']).resolve()
        if not path.is_relative_to(self.path.parent):
            raise ValueError('Crop path escapes dataset')
        raw = path.read_bytes()
        if row.get('crop_sha256') and hashlib.sha256(raw).hexdigest() != row['crop_sha256']:
            raise ValueError('Crop bytes changed after manifest creation')
        with Image.open(io.BytesIO(raw)) as source:
            image = ImageOps.exif_transpose(source).convert('RGB')
        return transform(image, self.size, self.training), row['label']


def classifier(num_classes, pretrained=None):
    model = mobilenet_v3_small(weights=None)
    if pretrained:
        if sha256(pretrained) != WEIGHT_SHA256:
            raise ValueError('Unexpected ImageNet weight hash')
        model.load_state_dict(torch.load(pretrained, map_location='cpu', weights_only=True))
    model.classifier[-1] = nn.Linear(model.classifier[-1].in_features, num_classes)
    return model


def load_classifier_checkpoint(path):
    # The first locally generated run stored one NumPy float64 loss statistic.
    # Restrict loading to tensor/primitives plus that exact numeric type; do
    # not enable arbitrary pickle execution to recover metadata.
    with torch.serialization.safe_globals([np._core.multiarray.scalar, np.dtype, np.dtypes.Float64DType]):
        return torch.load(path, map_location='cpu', weights_only=True)


@torch.inference_mode()
def evaluate(model, loader, device, num_classes):
    model.eval()
    confusion = np.zeros((num_classes, num_classes), dtype=np.int64)
    total_loss = 0.0
    for images, labels in loader:
        logits = model(images.to(device))
        total_loss += nn.functional.cross_entropy(logits, labels.to(device), reduction='sum').item()
        preds = logits.argmax(1).cpu().numpy()
        for target, pred in zip(labels.numpy(), preds):
            confusion[target, pred] += 1
    support = confusion.sum(1)
    present = support > 0
    recall = np.divide(confusion.diagonal(), support, out=np.zeros(num_classes), where=present)
    return {'accuracy': float(confusion.trace() / max(1, confusion.sum())),
            'macro_recall_present_classes': float(recall[present].mean()),
            'loss': float(total_loss / max(1, confusion.sum())),
            'support': support.tolist(), 'confusion': confusion.tolist(),
            'per_class_recall': recall.tolist(), 'count': int(confusion.sum())}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--pretrained', default=str(ROOT / 'vision/downloads/mobilenet_v3_small-047dcff4.pth'))
    ap.add_argument('--epochs', type=int, default=12)
    ap.add_argument('--batch', type=int, default=64)
    ap.add_argument('--size', type=int, default=160)
    ap.add_argument('--lr', type=float, default=.0005)
    ap.add_argument('--seed', type=int, default=20261002)
    ap.add_argument('--workers', type=int, default=2)
    ap.add_argument('--device', default='mps')
    args = ap.parse_args()
    if args.epochs < 1 or args.batch < 1 or args.size < 64:
        raise ValueError('Invalid experiment configuration')
    output = Path(args.output); output.mkdir(parents=True, exist_ok=False)
    random.seed(args.seed); np.random.seed(args.seed); torch.manual_seed(args.seed)
    torch.set_num_threads(2)
    if args.device == 'mps' and not torch.backends.mps.is_available():
        raise RuntimeError('MPS unavailable; explicitly select cpu instead of silently changing the experiment')
    device = torch.device(args.device)
    train = CropDataset(args.manifest, 'train', args.size)
    dev = CropDataset(args.manifest, 'dev', args.size)
    train_counts = Counter(r['label'] for r in train.rows)
    missing = set(range(len(train.classes))) - train_counts.keys()
    if missing:
        raise ValueError(f'Training split lacks classes: {missing}')
    # Training-only inverse-frequency weights; never inspect test class counts.
    class_weights = torch.tensor([1 / math.sqrt(train_counts[i]) for i in range(len(train.classes))], dtype=torch.float32)
    class_weights /= class_weights.mean()
    model = classifier(len(train.classes), args.pretrained).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=.0001)
    schedule = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, args.epochs, eta_min=args.lr / 20)
    loader = DataLoader(train, batch_size=args.batch, shuffle=True, num_workers=args.workers,
                        persistent_workers=args.workers > 0, generator=torch.Generator().manual_seed(args.seed))
    dev_loader = DataLoader(dev, batch_size=args.batch, shuffle=False, num_workers=args.workers,
                           persistent_workers=args.workers > 0)
    criterion = nn.CrossEntropyLoss(weight=class_weights.to(device), label_smoothing=.03)
    config = {**vars(args), 'architecture': 'torchvision mobilenet_v3_small', 'torch': str(torch.__version__),
              'manifest_sha256': sha256(args.manifest), 'pretrained_sha256': sha256(args.pretrained),
              'train_count': len(train), 'dev_count': len(dev), 'classes': train.classes,
              'source_split_sha256': train.data.get('source_split_sha256'),
              'selection': 'maximum development macro recall; tie broken by development accuracy',
              'test_pixels_read': False, 'augmentation': 'rotation +-12deg/180deg; brightness/contrast/color; mild scale/shear/blur; no mirroring',
              'normalization': 'RGB /255; ImageNet mean/std; aspect-preserving gray-114 letterbox',
              'parameters': sum(p.numel() for p in model.parameters())}
    (output / 'config.json').write_text(json.dumps(config, indent=2) + '\n')
    print(json.dumps(config), flush=True)
    history, best = [], (-1., -1.)
    started = time.perf_counter()
    for epoch in range(args.epochs):
        model.train(); loss_sum = 0.; seen = 0; epoch_start = time.perf_counter()
        for step, (images, labels) in enumerate(loader):
            optimizer.zero_grad(set_to_none=True)
            loss = criterion(model(images.to(device)), labels.to(device))
            loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 5.)
            optimizer.step()
            loss_sum += loss.item() * len(labels); seen += len(labels)
            if step % 50 == 0:
                print(f'epoch={epoch+1} step={step}/{len(loader)} loss={loss.item():.4f}', flush=True)
        metrics = evaluate(model, dev_loader, device, len(train.classes))
        score = (metrics['macro_recall_present_classes'], metrics['accuracy'])
        record = {'epoch': epoch + 1, 'train_loss': loss_sum / seen, 'dev': metrics,
                  'seconds': time.perf_counter() - epoch_start, 'lr': optimizer.param_groups[0]['lr']}
        history.append(record)
        if score > best:
            best = score
            state = {key: value.detach().cpu() for key, value in model.state_dict().items()}
            torch.save({'state_dict': state, 'epoch': epoch + 1, 'config': config, 'development': metrics}, output / 'best.pt.tmp')
            (output / 'best.pt.tmp').replace(output / 'best.pt')
        schedule.step()
        (output / 'history.json').write_text(json.dumps(history, indent=2) + '\n')
        print(json.dumps({k:v for k,v in record.items() if k != 'dev'} | {'dev_accuracy':metrics['accuracy'], 'dev_macro_recall':score[0]}), flush=True)
    result = {'best_checkpoint_sha256': sha256(output / 'best.pt'), 'best_development_macro_recall': best[0],
              'best_development_accuracy': best[1], 'total_seconds': time.perf_counter() - started,
              'epochs_completed': args.epochs, 'test_evaluation_performed': False}
    (output / 'training_result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)

if __name__ == '__main__':
    main()
