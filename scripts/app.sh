#!/bin/zsh
# app.sh <executable> <Info.plist> <out.app> [resources dir]
# SwiftPM 이 만든 executable 을 .app bundle 로 조립하고 서명한다.
# macOS 는 bundle 이 있어야 app 으로 대접한다 — bundle ID, 창 활성화, input method 등록 모두 bundle 기준이다.
#
# 서명은 login keychain 의 자체 서명 인증서 "homi code signing" 으로 한다 (2026-09-25 생성, 2036 만료).
# ad-hoc 서명은 build 마다 신원(cdhash)이 바뀌어 손쉬운 사용 허가가 매번 풀린다. 인증서가 없으면 ad-hoc 으로 한다.
set -euo pipefail

readonly identity="homi code signing"

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
if security find-identity -v -p codesigning | grep -qF "\"$identity\""; then
  codesign --force --sign "$identity" "$app"
else
  echo "warning: \"$identity\" 인증서가 없어 ad-hoc 서명 — 손쉬운 사용 허가가 build 마다 풀린다" >&2
  codesign --force --sign - "$app"
fi
