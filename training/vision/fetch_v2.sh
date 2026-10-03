#!/bin/sh
# Fetch a pinned checkpoint. Loading/export is a separate restricted operation.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
model_dir="$project_root/vision/downloads"
mkdir -p "$model_dir"
model_file="$model_dir/mahjong-yolo11n-v2.pt"
model_temporary="$model_file.partial"
trap 'rm -f "$model_temporary"' EXIT
curl --fail --location --silent --show-error \
  'https://raw.githubusercontent.com/nikmomo/Mahjong-YOLO/28ffceed232ad95fd019c47a6c51ae7c78791a0e/trained_models_v2/yolo11n_best.pt' \
  --output "$model_temporary"
model_sha=$(shasum -a 256 "$model_temporary" | cut -d ' ' -f 1)
if [ "$model_sha" != 'ea35d50b9568fc67277538038e7c456b3f29ebd65e1de7bd141e5a1d3a9d0ff1' ]; then
  echo 'Checkpoint checksum mismatch.' >&2
  exit 1
fi
mv "$model_temporary" "$model_file"
echo "Verified checkpoint: $model_file"
