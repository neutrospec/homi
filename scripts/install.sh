#!/bin/zsh
# install.sh [--register] — homi 를 release build 해서 /Library/Input Methods 에 설치한다.
#
# 설치 위치는 이곳 하나다. macOS 는 보안 입력이 켜진 채 활성화된 문서에서 /System·/Library/Input Methods 의 입력기만 쓴다 —
# ~/Library/Input Methods 의 입력기는 그때마다 ABC 로 밀려난다 (docs/macos-input.md 2026-11-13).
# 교환 한 번에만 sudo 를 쓴다. terminal 에서는 sudo 가 암호를 묻고, terminal 이 아니면 stdin 의 암호를 넘긴다 (install.sh < 암호 file).
# ~/Library/Input Methods 에 옛 설치본이 남아 있으면 교환에 성공한 뒤 그 사본과 등록을 지우고 TIS 에 새 위치를 알린다 —
# 같은 bundle ID 의 사본이 둘이면 LaunchServices 가 둘 다 등록한다 (docs/lessons.md 2026-11-03).
#
# 실행 중인 homi 는 종료한다. 다음 입력 때 system(imklaunchagent)이 새 binary 로 다시 띄운다.
# imklaunchagent 는 절대 죽이지 않는다 — 실행 중인 app 들이 모든 입력기를 잃는다.
#
# --register  처음 한 번, 그리고 설치 위치를 옮긴 뒤: TIS 에 등록하고 input source 목록에 넣는다 (parent 먼저, 그다음 mode).
#             처음 놓은 위치는 logout 뒤에야 모든 app 이 안다 — 그 전까지 새로 뜨는 sandbox app 은 homi 를 찾지 못한다 (docs/macos-input.md 2026-11-16).
set -euo pipefail
cd "${0:A:h}/.."

readonly id=com.unocult.inputmethod.homi
readonly dest="/Library/Input Methods/homi.app"
readonly user_dest="$HOME/Library/Input Methods/homi.app"
readonly lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

register=false
moved=false
for option in "$@"; do
  case $option in
    --register) register=true ;;
    *) echo 'usage: install.sh [--register]' >&2; exit 2 ;;
  esac
done

# sudo 가 읽을 stdin 을 따로 잡아 두고, 그 전의 명령들이 읽지 못하게 뗀다.
exec {password}<&0 </dev/null
if [[ -t $password ]]; then sudo_options=(); else sudo_options=(-S -p ''); fi

swift build -c release --product homi
swift build -c release --product replace-app
bin=$(swift build -c release --show-bin-path)
mkdir -p "${user_dest:h}"
# staging 은 설치본과 같은 volume 의, sudo 없이 쓸 수 있는 곳에 둔다 — ~/Library 와 /Library 는 같은 Data volume 이다.
# 다르면 교환이 실패하고 기존 설치본이 남는다.
# 오래 남는 build/homi.app 사본은 만들지 않는다.
stage=$(mktemp -d "${user_dest:h}/.homi-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
scripts/app.sh "$bin/homi" Sources/homi/Bundle/Info.plist "$stage/homi.app" Sources/homi/Bundle/Resources
codesign --verify --strict "$stage/homi.app"
# UUID 는 서명·검증한 staging executable 의 slice 별 식별자다. 진단 실패는 설치 실패가 아니다.
uuid_report=""
uuid_valid=true
uuid_pattern='^UUID: ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}) \(([A-Za-z0-9_]+)\) .+$'
if uuid_output=$(xcrun dwarfdump --uuid "$stage/homi.app/Contents/MacOS/homi" 2>/dev/null) && [[ -n "$uuid_output" ]]; then
  for line in "${(@f)uuid_output}"; do
    if [[ "$line" =~ $uuid_pattern ]]; then
      uuid_report+="executable UUID (${match[2]}): ${(U)match[1]}"$'\n'
    else
      uuid_valid=false
      break
    fi
  done
else
  uuid_valid=false
fi
# root 로는 교환, 소유자 변경, 교환으로 stage 에 온 옛 설치본의 삭제만 한다. 교환이 실패하면 뒤의 둘은 하지 않는다.
# sudo 를 함수로 감싸지 않는다 — zsh 는 함수 안의 실패로 끝날 때 위의 EXIT trap 을 돌리지 않아 stage 가 남는다.
sudo "${sudo_options[@]}" /bin/sh -c '"$1" "$2" "$3" && /usr/sbin/chown -R root:wheel "$3" && /bin/rm -rf "$2"' \
  sh "$bin/replace-app" "$stage/homi.app" "$dest" <&$password
# 인증서 조회·서명·검증·교환 중 하나라도 실패하면 아래로 오지 않는다 — 옛 사본을 지우거나 실행 중인 입력기를 종료하지 않는다.
if [[ -e $user_dest ]]; then
  # 설치 위치를 옮겼다. user 위치의 사본과 그 LaunchServices 등록을 지우고, 새 위치를 LaunchServices 와 TIS 에 알린다.
  "$lsregister" -u "$user_dest" || true
  rm -rf "$user_dest" || echo "warning: could not remove $user_dest" >&2
  "$lsregister" -f "$dest" || true
  register=true
  moved=true
fi
pkill -x homi || true
echo "installed: $dest"
# 같은 bundle ID 의 다른 사본이 disk 에 남아 있으면 LaunchServices 가 둘 다 등록해 imklaunchagent 의 연결 이름 해석이 흔들린다
# (2026-11-03: 9월의 build/homi.app 사본이 10-29 OS update 때 등록돼 "Refusing connection name" 오류가 났다). 경고만 하고 설치는 막지 않는다.
for copy in "${(@f)$(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null)}"; do
  [[ -z "$copy" || "$copy" == "$dest" || ! -e "$copy" ]] && continue
  echo "warning: another bundle with $id is on disk and may be registered: $copy — unregister with lsregister -u and delete it"
done
if [[ $uuid_valid == true && -n "$uuid_report" ]]; then
  printf '%s' "$uuid_report"
else
  echo "warning: executable UUID unavailable"
  echo "executable UUID: unknown"
fi

if [[ $register == true ]]; then
  swift build --product tis
  tis=$(swift build --show-bin-path)/tis
  "$tis" register "$dest"
  "$tis" enable "$id"
  "$tis" enable "$id.korean"
  "$tis" list --all | grep -F "$id" || echo "homi 가 아직 TIS 목록에 없다 — logout 후 다시 확인"
fi
if [[ $moved == true ]]; then
  echo "설치 위치를 옮겼다 — logout(또는 재시동)해야 sandbox 된 app 이 homi 를 찾는다. 그 전에는 새로 뜬 app 에서 homi 가 동작하지 않는다."
fi
