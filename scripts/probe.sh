#!/bin/zsh
# probe.sh [log file] — probe 를 build·bundle 해서 띄운다. log 는 file 로 간다 (기본 build/probe.log).
# log 에는 타이핑한 내용이 그대로 남는다. build/ 는 git 이 무시한다.
set -euo pipefail
cd "${0:A:h}/.."

swift build --product probe
scripts/app.sh .build/debug/probe tools/probe/Info.plist build/probe.app

log=${1:-build/probe.log}
pkill -f 'build/probe.app/Contents/MacOS/probe' || true
: > "$log"
open build/probe.app --stdout "$log"
echo "probe log: $log"
