#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

"$script_dir/open-xcode.sh" phone --prepare-only
# This invokes the same workspace, scheme and profile configuration used by
# Xcode's Run action. It checks device compilation but intentionally does not
# create a signing profile, install on a phone, or change the developer team.
exec xcodebuild \
  -workspace "$project_root/ios/Runner.xcworkspace" \
  -scheme 'Runner iPhone Test' \
  -configuration Profile \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$project_root/build/xcode-phone-test" \
  CODE_SIGNING_ALLOWED=NO \
  FLUTTER_TARGET=lib/main.dart \
  build
