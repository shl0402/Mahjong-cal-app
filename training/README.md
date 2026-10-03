# Mahjong training and evaluation

This workspace contains:

- `vision/`: current research code, dataset download/audit tools, grouped split manifests, classifier and detector training, export/parity checks, benchmark predictions and source provenance.
- `train/`: original legacy training code/configuration retained for reference. Its images and generated labels remain local. Do not use its whole-image boxes as proper row-detector annotations.
- `docs/`: data audit, evaluation protocol, comparison reports and measured limitations.

Run research commands **from this folder** so `vision/...` paths and the recorded manifests retain their original meaning. Frozen manifests have not been rewritten or relabeled as fresh tests. Historical absolute paths in run metadata identify the original machine, not portable setup paths.

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r vision/requirements.txt
# Extra evaluation/export/training dependencies:
pip install -r requirements-training.txt
```

Dataset download and reconstruction scripts: `vision/datasets/fetch_rf100vl.sh`, `extract_rf100vl.py`, and `audit_rf100vl.py`. Review [data provenance](docs/VISION_DATA_AUDIT.md) before downloading. The 156-image internal test is already consumed for development; do not report another adaptive evaluation on it as a fresh holdout.

Completed runs:

- `vision/runs/mobilenetv3_rf100_v1/`: 12-epoch classifier reports. Good same-source crop results did not translate to complete different-source hands.
- `vision/training/detector_runs/full20/`: 20-epoch detector reports and timeout-free checkpoint selection. 0/7 different-source photo hands and 0/20 video rows; excluded from the app.
- [Full detector report](vision/training/detector_REPORT.md).

Model checkpoints, ONNX files, raw datasets, extracted crop pixels, downloaded third-party packages and videos are excluded from Git. Their hashes, configurations, download sources and result reports are retained. All original artifacts remain in the original local workspace; this GitHub repository is a source/report handoff, not a binary backup.

Future training should use a new experiment name and a genuinely separate physical-set/session evaluation. Do not resume or overwrite the completed run as if it were an unfinished experiment.
