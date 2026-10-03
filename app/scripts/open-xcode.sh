#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
mode="${1:-phone}"
case "$mode" in
  phone)
    "$script_dir/flutter.sh" build ios --config-only --profile --no-codesign --target lib/main.dart
    printf '%s\n' 'In Xcode: choose "Runner iPhone Test", select your iPhone, choose your signing team, then press Run.'
    ;;
  simulator)
    "$script_dir/flutter.sh" build ios --config-only --simulator --debug --no-codesign --target lib/main.dart
    printf '%s\n' 'In Xcode: choose "Runner", select an iPhone simulator, then press Run. A simulator has no real camera.'
    ;;
  *) printf '%s\n' 'Usage: scripts/open-xcode.sh [phone|simulator] [--prepare-only]' >&2; exit 2 ;;
esac

# Flutter integration tests can rewrite this generated entry point. Always reset
# it via the supported config-only command before handing the workspace to Xcode.
if ! /usr/bin/grep -q '^FLUTTER_TARGET=lib/main.dart$' "$project_root/ios/Flutter/Generated.xcconfig"; then
  printf '%s\n' 'The generated Flutter target is not lib/main.dart; stop and check configuration.' >&2
  exit 1
fi
if [[ "${2:-}" != --prepare-only ]]; then
  developer_path="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  open -a "${developer_path%/Contents/Developer}" "$project_root/ios/Runner.xcworkspace"
fi
