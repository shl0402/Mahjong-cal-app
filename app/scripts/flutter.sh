#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$project_root/.tools/flutter/bin/flutter" ]]; then
  flutter_bin="$project_root/.tools/flutter/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
else
  printf '%s\n' 'Install Flutter 3.47.6 (Dart 3.13.5) or place its SDK at .tools/flutter.' >&2
  exit 1
fi

# Process-local settings: leave the Mac's global Xcode/Java selection alone.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
if [[ -x '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java' ]]; then
  export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
fi
if [[ -d "$HOME/Library/Android/sdk" ]]; then
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
fi
cd "$project_root"
exec "$flutter_bin" "$@"
