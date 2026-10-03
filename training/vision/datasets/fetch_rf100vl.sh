#!/usr/bin/env bash
set -euo pipefail
dataset_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
revision=1987e22ed542539fb3d0b8a3456455c2725079a1
mkdir -p "$dataset_dir/sources"
# Public redistribution, without credentials. Preserve the source notices.
archive_path="$dataset_dir/sources/mahjong.tar"
if [[ ! -f "$archive_path" ]] || [[ $(wc -c < "$archive_path") -lt 1911848960 ]]; then
  curl --fail --location --silent --show-error --retry 3 --continue-at - \
    "https://huggingface.co/datasets/LibreYOLO/rf100-vl/resolve/$revision/mahjong.tar" \
    --output "$archive_path"
fi
python_path="${VISION_PYTHON:-$dataset_dir/../../../.venv/bin/python}"
if [[ ! -x "$python_path" ]]; then python_path=python3; fi
exec "$python_path" "$dataset_dir/extract_rf100vl.py"
