#!/bin/zsh
# probe.sh [log file] — probe 를 build·bundle 해서 띄운다. log 는 file 로 간다 (기본 build/probe.log).
# log 에는 타이핑한 내용이 그대로 남는다. build/ 는 git 이 무시한다.
set -euo pipefail
cd "${0:A:h}/.."

swift build --product probe
scripts/app.sh .build/debug/probe tools/probe/Info.plist build/probe.app

log=${1:-build/probe.log}
# 옛 probe 가 완전히 끝난 뒤 open 한다 — 곧바로 open 하면 LaunchServices 가 죽어가는 process 에 붙으려다 -600 을 낸다.
pattern='build/probe.app/Contents/MacOS/probe'
pkill -f "$pattern" || true
for _ in {1..20}; do pgrep -f "$pattern" >/dev/null || break; sleep 0.1; done
: > "$log"
open build/probe.app --stdout "$log"
echo "probe log: $log"
