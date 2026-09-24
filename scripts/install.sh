#!/bin/zsh
# install.sh [--register] — homi 를 release build 해서 ~/Library/Input Methods 에 설치한다.
#
# 실행 중인 homi 는 종료한다. 다음 입력 때 system(imklaunchagent)이 새 binary 로 다시 띄운다.
# imklaunchagent 는 절대 죽이지 않는다 — 실행 중인 app 들이 모든 입력기를 잃는다.
#
# --register  처음 한 번: TIS 에 등록하고 input source 목록에 넣는다 (parent 먼저, 그다음 mode).
#             system 이 바로 알아보지 못하면 logout 이 한 번 필요하다.
set -euo pipefail
cd "${0:A:h}/.."

readonly id=com.unocult.inputmethod.homi
readonly dest="$HOME/Library/Input Methods/homi.app"

swift build -c release --product homi
bin=$(swift build -c release --show-bin-path)
scripts/app.sh "$bin/homi" Sources/homi/Bundle/Info.plist build/homi.app Sources/homi/Bundle/Resources

mkdir -p "${dest:h}"
pkill -x homi || true
rm -rf "$dest"
cp -R build/homi.app "$dest"
echo "installed: $dest"

if [[ ${1:-} == --register ]]; then
  swift build --product tis
  tis=$(swift build --show-bin-path)/tis
  "$tis" register "$dest"
  "$tis" enable "$id"
  "$tis" enable "$id.korean"
  "$tis" list --all | grep -F "$id" || echo "homi 가 아직 TIS 목록에 없다 — logout 후 다시 확인"
fi
