# Emacs

| | |
|---|---|
| bundle ID | `org.gnu.Emacs` |
| 엔진 | — (Emacs 자체의 입력기를 쓴다) |
| 확인한 version | GNU Emacs 31.1 · NS · Spacemacs · macOS 27.2 · 2026-10-29 |
| homi 규칙 | 한/영 전환 없는 app (설정의 기본값). 조합·모드는 Emacs 가 맡고, 선택하면 Caps Lock 을 F18 로 전달 |

## 특징

- **Emacs 에는 자체 한글 입력기가 있고 품질이 아주 좋다** — homi 는 한/영 전환도 조합도 하지 않고 key 를 그대로 넘긴다.
  Emacs 의 한/영 전환(`toggle-input-method` 등)도 그대로 Emacs 에 간다.
  `2026-09-25 · 주인` ✅
- terminal 안의 `emacs -nw` 는 그 terminal 의 bundle ID 라서 여기에 해당하지 않는다.

## homi 의 우회

- 한/영 전환 없는 app (`Preferences.passThroughApps`, M7).

## Caps Lock 전달 (2026-10-29)

주인 요청: Emacs 의 `korean-hangul`과 기존 Shift+Space 전환을 유지하고, Caps Lock 도 **전환 전용**으로 쓴다.
처음 고른 Ctrl 겸용은 철회했다. homi 가 Emacs 의 조합·한/영 상태를 소유하지 않는다.

- homi 설정의 `Emacs 자체 입력기에 Caps Lock 사용`은 **기본 꺼짐**이다. 옛 설정에 항목이 없어도 켜지지 않는다.
  이 옵션·일반 Caps Lock 전환·homi 선택이 모두 켜져 있을 때만 Caps Lock → HID F18 (`0x70000006d`).
  Emacs 는 이 key 를 `toggle-input-method`에 연결한다. ABC·일반 Caps Lock 해제에서는 원래 mapping 이다.
- 옵션을 켜면 pass-through 목록에서 Emacs 를 빼도 homi 가 조합하지 않는다. 끄면 목록의 기존 선택을 따른다:
  기본 목록에서는 원래 Caps Lock 으로 돌아가고, 목록에서도 뺀 경우는 다른 일반 app 처럼 homi 가 처리한다.
- 기존 HID mapping 경로만 사용한다. key 재전송·새 event tap·Ctrl tap 판정을 추가하지 않았다.
  Windows App 의 오른쪽 Alt·일반 app 의 Caps Lock 경로를 유지한다.
  소유 기록·재시작 복원은 [mapping 수명](../macos-input.md#homi-process-와-hid-mapping-의-수명)을 따른다.
- 주인의 `~/.config/spacemacs/init.el`에 있는 `dotspacemacs/user-config`에 F18 binding 을 추가했다.
  다른 설정에서 사용하려면 다음을 연결한다:

```elisp
(setq default-input-method "korean-hangul")
(global-set-key (kbd "S-SPC") #'toggle-input-method)
(global-set-key (kbd "<f18>") #'toggle-input-method)
```

**검증**:

- `swift build`·Debug/Release **206개 test** 통과. app·source·설정 범위, F18·Shift+Space·자모의 pass-through,
  Emacs ↔ Windows App ↔ 일반 app ↔ 원래 mapping, 쓰기 실패·wake·새 process 복원을 확인했다.
- 설치된 Emacs 31.1 의 별도 batch process 에서 사용자 `user-config` 정의를 읽어 3개 ERT 검사 통과.
  F18·Shift+Space binding, `한글` 조합 뒤 어느 key 로도 영문 전환해 `한글a`가 남는 경로, 두 번 전환과 Ctrl-A 보존을 검사했다.
  이것은 물리 Caps Lock 입력의 증거와 다르다.
- release build·자체 서명·재설치했고, 실행 중인 Emacs 에 F18 binding 과 별도 `*homi Caps Lock 확인*` buffer 를 준비했다.
  19:34:52 KST 설치본 CDHash 는 `b3d786df3690eee12116adee4bf9b1da1b512c90`이다.
  검사 buffer 는 전환 횟수·mode 만 기록하며 입력 내용은 기록하지 않는다. 잠금 화면 때문에 자동 key 검사는 중단했다.
  Emacs 는 재설치 직후 IMK 를 호출하지 않을 수 있어 이번에는 설치본을 직접 실행했다. 시작·로그인 경로의 자동 실행까지 검증한 것은 아니다.
- **주인 확인**: 설치 뒤 Caps Lock·Shift+Space 전환 시험을 요청했고, 주인이 "매우 좋아. 잘 동작 해."라고 보고했다 ✅.
  시험 buffer 에서는 `toggle-input-method` 실행 17회를 확인했다. 물리 누름별 대응·긴 누름의 repeat 여부를 따로 기록한 것은 아니므로,
  이 수를 17개의 물리 Caps Lock 누름으로 세거나 다른 app 복귀·wake·crash 경계까지 통과한 것으로 확대하지 않는다.
  확인 뒤 시험용 `post-command-hook` 1개를 제거하고 남은 관찰 hook 이 0개임을 확인했다. buffer 의 글자·mode·binding 은 유지했다.
- **선택 옵션 추가**: 주인이 특수 동작의 on/off 를 요청해 `emacsCapsLock`을 추가했다. `swift build`·Debug/Release **207개 test** 통과.
  옛 설정의 기본 꺼짐·저장 복원·Windows 오른쪽 Alt 와의 독립성을 검사했고, 실제 설정 view 도 확인했다.
  20:19:32 KST 재설치본 CDHash 는 `39e0a7603bf12ded5c6f648ee98e323780144eed`이다.
  실제 설정 창에서 끔 → 켬 → 끔 → 켬을 조작한 뒤 Emacs 를 활성화해 HID mapping 의 F18 → 없음 → F18 을 확인했다.
  Safari 복귀 시 일반 homi 의 오른쪽 Control mapping 으로 돌아왔다. 최종 저장값은 `emacsCapsLock=true`이며,
  기존 `toggleKeys=[capsLock]`·Windows 전달 켜짐·`rightAlt`는 유지됐다. 이 설치본에서 물리 key 입력 시험을 반복한 것은 아니다.

## 확인하는 법

- menu bar 표시가 `–` 다. Emacs 의 한글 입력기로 조합되고, Emacs 의 한/영 전환 key 가 먹힌다.
- Caps Lock 과 Shift+Space 가 Emacs 안의 mode 만 전환하고, 일반 Mac app 으로 돌아가면 homi 의 기존 Caps Lock 전환이 동작한다.
- bundle ID 가 `org.gnu.Emacs` 가 아니면(배포판마다 다를 수 있다) pass-through 목록에 더해 homi 의 조합을 끌 수 있다.
  Caps Lock 전달 옵션은 `org.gnu.Emacs`에만 적용된다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | — | "한/영 전환 없는 app" 기본 목록에 넣음 (주인, M7) |
| 2026-10-29 | 31.1 | 자체 입력기·Shift+Space 를 유지하며 Caps Lock → F18 전달과 binding 을 설치. 206개 Swift test·3개 ERT 통과, 주인이 실제 전환 정상 확인 |
| 2026-10-29 | 31.1 | 전달 옵션을 기본 꺼짐으로 추가. 207개 Swift test·실제 설정 on/off 와 app 복귀 mapping 확인, 주인 환경은 켜짐으로 저장 |
