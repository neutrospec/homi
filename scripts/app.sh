#!/bin/zsh
# app.sh [--allow-ad-hoc] <executable> <Info.plist> <out.app> [resources dir]
# SwiftPM 이 만든 executable 을 .app bundle 로 조립하고 서명한다.
# macOS 는 bundle 이 있어야 app 으로 대접한다 — bundle ID, 창 활성화, input method 등록 모두 bundle 기준이다.
#
# 서명은 login keychain 의 자체 서명 인증서 "homi code signing" 으로 한다 (2026-09-25 생성, 2036 만료).
# 인증서가 없으면 bundle 을 조립하기 전에 실패한다. 제품 설치에서 ad-hoc 으로 조용히 바뀌지 않는다.
# probe 같은 개발 도구만 --allow-ad-hoc 으로 인증서 부재 때의 대체 서명을 명시한다.
set -euo pipefail

readonly identity="homi code signing"

allow_ad_hoc=false
if [[ ${1:-} == --allow-ad-hoc ]]; then
  allow_ad_hoc=true
  shift
fi
if (( $# < 3 || $# > 4 )); then
  echo 'usage: app.sh [--allow-ad-hoc] <executable> <Info.plist> <out.app> [resources dir]' >&2
  exit 2
fi

exe=$1 plist=$2 app=$3 resources=${4:-}
# 먼저 조회를 끝내고 검사한다. grep -q 의 조기 종료가 security 의 pipe 실패로 해석되지 않게 한다.
if identity_report=$(security find-identity -v -p codesigning) && grep -qF "\"$identity\"" <<< "$identity_report"; then
  signing_identity=$identity
elif [[ $allow_ad_hoc == true ]]; then
  echo "warning: \"$identity\" unavailable; using explicitly allowed ad-hoc signing for this development bundle" >&2
  signing_identity=-
else
  echo "error: code signing identity \"$identity\" is required; bundle assembly stopped" >&2
  exit 1
fi
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
codesign --force --sign "$signing_identity" "$app"
