#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-web}" in
  web) exec "$script_dir/flutter.sh" build web --release --no-web-resources-cdn --target lib/main.dart ;;
  android) exec "$script_dir/flutter.sh" build apk --debug --target lib/main.dart ;;
  android-test-release) exec "$script_dir/flutter.sh" build apk --release --split-per-abi --target lib/main.dart ;;
  ios-simulator) exec "$script_dir/flutter.sh" build ios --simulator --debug --no-codesign --target lib/main.dart ;;
  ios-device) exec "$script_dir/flutter.sh" build ios --profile --no-codesign --target lib/main.dart ;;
  *) printf '%s\n' 'Usage: scripts/build.sh [web|android|android-test-release|ios-simulator|ios-device]' >&2; exit 2 ;;
esac
