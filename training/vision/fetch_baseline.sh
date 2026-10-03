#!/bin/sh
# Download the exact reviewed ONNX artifact, not a moving branch or pickle file.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
model_dir="$project_root/vision/downloads"
mkdir -p "$model_dir"
model_file="$model_dir/mahjong-yolo11n.onnx"
model_temporary="$model_file.partial"
trap 'rm -f "$model_temporary"' EXIT
curl --fail --location --silent --show-error \
  'https://raw.githubusercontent.com/nikmomo/Mahjong-YOLO/28ffceed232ad95fd019c47a6c51ae7c78791a0e/models/nano/mahjong-yolon-best.onnx' \
  --output "$model_temporary"
model_sha=$(shasum -a 256 "$model_temporary" | cut -d ' ' -f 1)
if [ "$model_sha" != '3c7732c022d41c1a3f48cea931ce626416d92486ab5b86692312941d0cc22226' ]; then
  echo 'The downloaded model does not match the reviewed checksum.' >&2
  exit 1
fi
mv "$model_temporary" "$model_file"
curl --fail --location --silent --show-error \
  'https://raw.githubusercontent.com/nikmomo/Mahjong-YOLO/28ffceed232ad95fd019c47a6c51ae7c78791a0e/LICENSE' \
  --output "$model_dir/LICENSE.upstream"
echo "Verified model: $model_file"
