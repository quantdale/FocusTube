#!/usr/bin/env bash
set -euo pipefail

preferred="/Applications/Xcode_26.6.app/Contents/Developer"
if [[ -d "$preferred" ]]; then
  sudo xcode-select -s "$preferred"
fi

xcodebuild -version
swift --version

version="$(xcodebuild -version | awk '/Xcode/{print $2}')"
if [[ "$version" != 26.* ]]; then
  echo "FocusTube CI requires an accepted stable Xcode 26.x toolchain; found $version" >&2
  exit 1
fi
