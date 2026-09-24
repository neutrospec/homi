#!/bin/zsh
# app.sh <executable> <Info.plist> <out.app>
# SwiftPM 이 만든 executable 을 .app bundle 로 조립하고 ad-hoc 서명한다.
# macOS 는 bundle 이 있어야 app 으로 대접한다 — bundle ID, 창 활성화, input method 등록 모두 bundle 기준이다.
set -euo pipefail

exe=$1 plist=$2 app=$3
name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$exe" "$app/Contents/MacOS/$name"
cp "$plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
