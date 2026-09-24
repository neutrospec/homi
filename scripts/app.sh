#!/bin/zsh
# app.sh <executable> <Info.plist> <out.app> [resources dir]
# SwiftPM 이 만든 executable 을 .app bundle 로 조립하고 ad-hoc 서명한다.
# macOS 는 bundle 이 있어야 app 으로 대접한다 — bundle ID, 창 활성화, input method 등록 모두 bundle 기준이다.
set -euo pipefail

exe=$1 plist=$2 app=$3 resources=${4:-}
name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")

plutil -lint -s "$plist"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$exe" "$app/Contents/MacOS/$name"
cp "$plist" "$app/Contents/Info.plist"
if [[ -n $resources ]]; then
  mkdir -p "$app/Contents/Resources"
  cp -R "$resources/" "$app/Contents/Resources/"
  find "$app/Contents/Resources" -name '*.strings' -exec plutil -lint -s {} +
fi
codesign --force --sign - "$app"
