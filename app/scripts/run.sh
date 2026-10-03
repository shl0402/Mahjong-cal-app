#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -eq 0 ]]; then
  set -- -d web-server --web-hostname=127.0.0.1 --web-port=8080
fi
exec "$script_dir/flutter.sh" run "$@"
