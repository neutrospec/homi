# AGENTS.md — hangul

**homi** (`com.unocult.inputmethod.homi`) — macOS 한글 입력기. 주인 한 사람이 매일 쓰는 도구이고,
목표는 **두벌식 한글 입력이 완벽하게 동작하는 것** 하나다. 기능을 늘리는 프로젝트가 아니다 — 잡다한 기능·옵션·변죽은 만들지 않는다.

> **현재 (2026-09-27)**: M0–M4·M6·M7 을 주인이 확인했다. 지금은 M5 — 일상 사용과 app 호환성.
> 이상하면 주인이 곧바로 "최근 key 기록 저장" 을 누른다 → [진행 단계](#진행-단계)

## 문서

| 문서 | 내용 |
|---|---|
| `AGENTS.md` | 목적·결정·규칙. 이 file 이 SOT 다 |
| `docs/spec.md` | 두벌식 조합 규칙 — 엔진 test 가 그대로 고정한다 |
| `docs/macos-input.md` | 배운 macOS 입력 구조와 그 증거 (✅ 확인 / 🔶 추정) |
| `docs/apps/` | app 원장 — app 마다 확인한 사실·homi 의 우회·version. 같은 엔진의 공통 사실은 `engines/` |
| `docs/lessons.md` | 고친 결함의 증상·원인·증거·대응, homi 의 결함이 아니었던 것 |
| `docs/research/` | 구현 전의 조사 (2026-09-25). 그 뒤 확인한 것은 위 문서가 우선한다 |

문서는 가치로 쓴다 — 같은 뜻이면 짧게, 단 친절함은 지킨다. 문서를 위한 문서는 쓰지 않는다 (2026-09-27 주인).
사실은 한 곳에 둔다: macOS 의 구조는 macos-input, app 에 딸린 것은 원장, 고친 결함은 lessons — 다른 곳에서는 가리키기만 한다.

## 왜 만드는가

macOS 기본 한국어 입력기(`com.apple.inputmethod.Korean.2SetKorean`)에서 주인이 겪는 결함:

| 증상 — 늘이 아니라 **가끔** 나타난다 | 알게 된 원인 | 이 입력기의 답 |
|---|---|---|
| 조합이 깨져 자모가 풀려 입력된다 (`한글` → `ㅎㅏㄴㄱㅡㄹ`) | Apple 입력기는 marked text 없이 확정한 뒤 바꿔치기하고 app 의 text 를 cache 한다 ✅. 문서 위치 답이 비동기인 app 과 어긋나면 조합이 끊긴다 🔶 | 결정 5 |
| 한글 모드인데 첫 자음이 영문으로 찍힌다 | Caps Lock 전환은 key 를 뗀 뒤 43–106ms 에 확정되어 key event 와 다른 통로로 온다 ✅ (probe). 다른 process 의 `TISSelectInputSource` 전환은 실패가 잦다 ✅ | 결정 1·4 |
| 앱별 한/영 기억을 믿을 수 없다 | system 의 기억은 app 이 아니라 문서 단위이고, 복원 자체가 input source 전환이라 위 문제에 노출된다 🔶 | 입력기가 client bundle ID 별로 직접 기억한다 |

가끔 나타난다는 것은 timing 이나 누적 상태에 달린 결함이라는 신호다. 그래서 **"재현이 안 된다"는 해결의 증거가 아니다.**
결함이 생길 수 없는 구조로 만들고(핵심 설계 결정), 그 구조를 test 로 고정하고, 일상 사용 기간의 관측으로 확인한다.

이 결함을 메우던 Hammerspoon 입력 전환기도 대체한다. 그 설정의 역사는 eventtap timeout·stale cache·비동기 전환 race 와의 싸움이다
(`~/.hammerspoon/HAMMERSPOON_ARCHITECTURE.md`). 입력기는 key event 를 입력 흐름 안에서 순서대로 받으므로 그 싸움 자체가 없다.

## 핵심 설계 결정

1. **입력기 하나가 한글과 영문을 모두 처리한다.** 영문 모드는 key event 를 그대로 통과시킨다.
   한/영 전환은 TIS input source 를 바꾸지 않고 입력기 내부 모드만 바꾼다.
   - 왜: 전환 키가 타이핑 키와 같은 event 흐름에 있으면 "전환 → 다음 키" 순서가 구조적으로 보장된다.
2. **모드의 SOT 는 입력기 내부 상태 하나다.** menu bar 표시·system input source 는 이 상태를 비추는 출력일 뿐,
   거꾸로 system 을 읽어 모드를 판단하지 않는다.
   - Hammerspoon 설정의 원칙("system 이 SOT, cache 금지")과 반대인 이유: 그쪽은 상태를 소유하지 못했고, 여기는 소유한다.
3. **판단은 key event 처리 안에서 동기적으로 끝낸다.** timer·지연·비동기 재시도로 상태를 맞추지 않는다 — race 의 원천이다.
4. **key 처리 중에 system input source 를 건드리지 않는다.** typing 경로에서 `TISSelectInputSource`·`selectInputMode` 를 부르지 않는다.
   - 왜: Ghostty 는 key 처리 중 input source 가 바뀌면 그 key 를 버리고, `selectInputMode` 직후에는 key 전달이 ~300ms 멈춘다.
     system 에 모드를 알리는 일(menu bar)은 key 처리 밖에서 한다.
5. **조합 중인 글자는 marked text 로 보인다.** 이미 확정한 text 를 `replacementRange` 로 고쳐 쓰지 않고, `replacementRange` 는 NSNotFound 로 둔다.
   - 왜: Chromium·Electron·terminal·Office 는 문서 위치 질의에 비동기로 또는 틀리게 답한다. 교과서 경로(marked text)는 CJK 입력 때문에 모든 app 이 구현한다.
   - 한자 변환도 marked text 를 바꾼다 — 조합 중인 글자, 또는 ⌥↩ 때 선택 영역에서 시작한 조합.
   - 예외 하나 — 선택 없이 방금 친 단어를 바꿀 때(Apple 식): macOS text 엔진 수준을 알리는 client(`validAttributesForMarkedText` 에
     교체 범위와 `NSTextAlternatives`)에서만, 그 자리 글자를 확인한 뒤 marked text 로 되돌린다. 다른 app 은 app 마다 다르게 깨졌다 (docs/macos-input.md).
6. **조합 엔진은 순수하다.** AppKit/IMK 를 모르는 결정적 state machine. 한글 조합의 정확성은 여기서 test 로 증명한다.
7. **IMK 층은 얇다.** NSEvent 해석 → 판단(`Session`·`ModifierKeys`) → client 반영. 앱별 우회는 재현 증거가 있을 때만, 사유와 함께.

## 요구사항 (확정 2026-09-25)

### 한글 입력

- **두벌식 표준만.** 세벌식·옛한글·모아치기·자동 순서 교정 없음.
- 조합 규칙의 SOT 는 `docs/spec.md` 와 엔진 test. 그중 주인이 정한 것:
  - 같은 자음을 연달아 쳐도 합치지 않는다 — `ㄱㄱ` 은 `ㄱㄱ`, 된소리는 Shift 로만. Apple 은 초성에서 합친다고 보고됐다.
  - Backspace 는 자소 단위 (`닭 → 달 → 다 → ㄷ`), 모음 없는 겹자음은 합치지 않는다 (`ㄱㅅ`) — Apple 과 같다.
  - ⌥+key 는 한글 모드에서도 영문일 때와 같다 — 조합을 확정하고 key 를 넘긴다 (`⌥a → å`). Apple 은 `⌥a → a`.
  - `` ` `` 는 한글 모드에서도 `` ` `` 다 (Apple 두벌식은 `₩`).
- **한자 변환** (M6): ⌥↩ 가 방금 친 단어, 없으면 조합 중인 글자, 그것도 없으면 선택한 한글을 바꾼다.
  - 변환 key(⌥↩ 기본, 오른쪽 ⌥·⌘ 짧게 — 한/영 전환 key 와 겹치면 ⌥↩)와 "방금 친 단어" 를 쓸지는 설정에서 고른다 (M7).
  - 방금 친 단어는 macOS text 엔진 client 에서만 (결정 5 의 예외). 단어는 homi 가 이어서 친 한글 + 조합 중인 글자의 끝부분 중 사전에 있는 가장 긴 것
    (`나는한자` → `한자`), ⌥↩ 를 다시 누르면 더 짧게. 한글이 아닌 key·수식키 조합·click·입력칸 이동·전환이 끼면 끊긴다 — app 의 문서를 뒤지지 않는다.
  - 후보 창: 1–9 고르기, ↑↓ 옮기기, ←→ 쪽 넘기기, Enter·Space 확정, ESC 취소(한글 그대로), 다른 key 는 한글 그대로 두고 평소처럼.
  - terminal·Office 는 조합 중인 글자만 (`AppRules` 의 `convertsEnteredText`). app 마다의 사정은 원장에 있다.
  - 사전: libhangul `data/hanja/hanja.txt` (BSD 3-clause, Choe Hwanjin — 저작권 표시가 file 머리에 있다). bundle 에 넣고 map 해서 이진 탐색한다.

### 한/영 전환

- 전환 key 는 설정에서 고른다 (여럿 함께, 하나는 남긴다) — **Caps Lock**, **오른쪽 ⌘**, **오른쪽 ⌥** 의 단독 tap, **Shift+Space**. 기본은 Caps Lock·오른쪽 ⌘.
  - Caps Lock: 전환 key 일 때만, homi 가 선택된 동안 오른쪽 Control 로 remap 해 tap 으로 받는다. **짧게 = 전환, 길게(0.5초) = 대문자 고정** —
    macOS 처럼 누르고 있는 채로 켜진다. 다른 input source 와 한/영 전환 없는 app 에서는 원래대로다.
  - 오른쪽 ⌘·⌥: 짧게 = 전환. 사이에 다른 key·mouse 가 있었으면(⌘C·⌘Tab) 아니다 — system 의 누름 횟수로 판정, 권한 불필요.
    전환에 쓰지 않는 쪽은 한자 key 로 고를 수 있다.
  - Shift+Space: terminal(Ghostty·iTerm2)에서는 영문 → 한글 전환 때 space 가 샌다 — 주인이 알고 고르는 선택지다.
  - 수식키 tap 은 어느 app 에도 새지 않는다 — 전환 key 의 기본이 수식키인 이유 (함정 10).
- 전환은 즉시 — 다음 key 부터 새 모드. 조합 중이면 먼저 확정한다. 오른쪽 ⌘·⌥·Caps Lock 을 다른 key 와 함께 쓰면 평소의 ⌘·⌥·Ctrl 이다.
- 모드 표시: menu bar 의 한/A + 모드가 바뀔 때 커서 옆 말풍선(Apple 입력기처럼). system input menu 의 icon("호")은 고정이다.
  대문자 고정 표시는 macOS 에 맡긴다 — 겹치면 불편하다.

### 앱별 상태

- 앱(client bundle ID)마다 마지막 모드를 기억해 돌아오면 복원한다 (`ModeMemory`, UserDefaults — 재시작해도 유지).
  key 마다 그 입력칸의 app 으로 읽어서 activate 알림이 늦거나 빠져도 틀리지 않는다. 처음 보는 app 은 **영문**으로 시작.
- 주인이 설정 창(input menu 의 "설정…"·menu bar 의 한/A)에서 고르는 것 — 바꾸는 즉시 저장되고 다음 key 부터 쓰인다:
  - **시작할 때 영문인 app** — 기본 LaunchBar.
  - **ESC 로 영문인 app** — 조합 중이면 확정 → 영문 → ESC 는 app 으로 간다. 기본 VS Code(·Insiders)·Obsidian·iTerm2·Wave·Ghostty·IntelliJ(·CE).
  - **한/영 전환 없는 app** — 한/영 전환도 조합도 하지 않고 key 를 넘긴다. Caps Lock 도 원래대로(remap 을 푼다), 표시는 `–`.
    원격 컴퓨터나 app 자체의 입력기가 한/영을 맡는다. 기본 Windows App·Emacs (Emacs 의 입력기가 좋다).
- app 의 결함에 맞춘 우회는 주인이 고를 것이 아니라 `Sources/InputSession/AppRules.swift` 에 둔다 — 바꾸면 다시 build·설치한다. 까닭은 원장에:
  - 조합 중 Enter·ESC 를 app 이 잃거나 다르게 쓰는 곳(Telegram 의 Enter, terminal 의 Enter·ESC·Tab)은 확정한 뒤 그 key 를 먹고 **새 event 로 다시 보낸다**.
    손쉬운 사용 권한이 없으면 먹지 않고 넘긴다 — key 를 잃지 않는다.
  - Ghostty 는 tmux prefix Ctrl-B·Ctrl-A(Ctrl 단독일 때만)도 영문 trigger 다.
  - Remote Desktop 은 입력기의 글자를 받지 않고 key 를 이 Mac 의 keyboard layout 으로 글자로 바꿔 보낸다 — homi 가 한/영을 layout 으로 알린다
    (한 → 두벌식 layout `2SetHangul`, A → ABC). 조합은 원격 입력기가 하므로 **원격 Mac 은 두벌식에 둔다**.

### 하지 않는 것

세벌식 등 다른 자판, 옛한글, 자동완성·예측, 특수문자 palette, App Store 배포와 sandbox.
명시적 요청 없이 옵션이나 기능을 늘리지 않는다. 설정 창도 주인이 고르겠다고 한 것만 둔다.

## 구조

SwiftPM package 하나. `.xcodeproj` 는 두지 않는다 — build·test·설치가 CLI 로 끝나야 agent 가 스스로 검증할 수 있다.

| module | 역할 | 의존 |
|---|---|---|
| `HangulCore` | 두벌식 자판 mapping + 조합 state machine. 입력: 자모·편집 명령 / 출력: commit 문자열 + 조합 중 문자열 | 없음 |
| `InputSession` | key 해석(자모·Backspace·넘길 key·trigger), 수식키 tap 의 뜻(`ModifierKeys`), 모드, 앱별 기억과 규칙, 주인의 설정(`Preferences`), 최근 기록(`Recorder`) | `HangulCore` |
| `homi` (app, `Sources/homi`) | IMK glue — `IMKServer`, `HomiInputController`, NSEvent 변환, menu bar 표시, 설정 창(SwiftUI). `Bundle/` 에 `Info.plist`·resource | 위 둘 + AppKit·InputMethodKit |

- 위 두 module 은 AppKit·IMK 를 모른다 — "key 순서 → client 에게 할 일" 대부분을 `swift test` 로 검증한다. IMK 층에 남는 것이 적을수록 좋다.
- `Session` 은 client 를 직접 부르지 않고 할 일(`Action`) 목록을 돌려준다. IMK 층은 상태 변경이 끝난 뒤에 적용한다 —
  IMK 는 우리의 `insertText` 도중에 deactivate 를 끼워 부를 수 있어서, 상태를 바꾸는 중에 client 를 부르면 재진입이 겹친다.
- `Info.plist` 는 한국어 mode 하나(`com.unocult.inputmethod.homi.korean`, `smKorean`)만 둔다 — 한/영은 homi 안의 모드라 system 에 알릴 일이 없다 (결정 4).
  비밀번호 칸에서는 system 이 ABC 로 바꾼다 (함정 7). mode 구성을 바꾸면 logout + input source 재추가가 필요하다.
- 자판 mapping 은 `keyCode`(물리 위치) 기준이다 — `NSEvent.characters` 는 homi 아래의 keyboard layout 에 따라 바뀐다.
- 문장부호 등 한글이 아닌 key 는 조합을 확정한 뒤 넘겨 layout 이 문자를 만들게 한다 — `insertText` 로 직접 넣으면 key event 를 읽는
  xterm.js·Ink(Claude Code)가 못 본다. homi 아래 layout 은 늘 ABC 로 둔다 (Remote Desktop 의 한글 모드만 두벌식).
- IMK override 는 `nonisolated override` + `MainActor.assumeIsolated` — macOS 27 SDK 의 IMK header 에는 actor 표시가 없다.
- 간헐 결함은 사후에 재현하기 어렵다 — 최근 key event·상태 전이를 memory ring buffer 에만 들고 있다가 주인이 요청할 때 저장한다 (입력 내용 보호).

## 알려진 함정

설계·구현 전에 읽는다. 근거는 docs/ 의 해당 문서에 있다.

1. **IMK lifecycle 은 뒤바뀌고 빠진다.** activate/deactivate 순서 보장이 없고 중첩되며, macOS 26 부터 다른 process 의 전환에는 `deactivateServer` 가 오지 않는다.
   상태는 controller·client 단위로, 확정은 두 번 불려도 안전하게, 앱별 규칙은 key 마다 다시 읽는다.
2. **확정이 엉뚱한 client 로 간다.** 새 session 이 먼저 key 를 받고 옛 session 의 확정이 뒤늦게 온다 — init 때 묶인 client 로 넣는다.
3. **Chromium 은 click·blur 때 스스로 확정한 뒤 `commitComposition` 을 부른다** — 그대로 넣으면 음절이 두 번. homi 가 선택된 동안 Chromium 계열의 것은 넣지 않는다.
4. **입력기는 ⌘ 단축키의 key 를 못 본다** — menu 가 먼저 가져가고, ⌘Tab 의 Tab 은 system 이 가져간다. 수식키 tap 은 system 의 누름 횟수로 판정한다.
5. **Caps Lock** 은 그대로 받으면 system 전환 옵션·activation delay·lock echo·LED·bubble 과 얽힌다 — 그래서 remap 해서 tap 으로 받는다.
6. **`activateServer`·`setValue` 안에서 client 에게 묻거나 기다리지 않는다** — Chrome deadlock, Spotlight 멈춤 사례.
   homi 아래 layout 을 정하는 `overrideKeyboard` 만 activate 때 부른다 (선행 입력기들도 activate·`setValue` 에서 부른다).
7. **영문 mode 를 system 에 노출하면 비밀번호 칸에서도 그 mode 가 살아 key 를 받는다.** 한국어 mode 만 두면 system 이 ABC 로 대체한다.
8. **등록** — parent input method 를 먼저 enable, 첫 등록엔 logout 을 각오, `ComponentInputModeDict` 를 바꾸면 logout + 재추가.
   **`imklaunchagent` 는 절대 죽이지 않는다** (실행 중인 app 들이 모든 입력기를 잃는다).
9. **ad-hoc 서명은 build 마다 신원이 바뀌어** 손쉬운 사용 허가가 풀린다 — login keychain 의 자체 서명 인증서 "homi code signing" 으로 서명한다 (2036 만료).
10. **app 마다 "입력기가 먹었다" 판정이 다르다.** Ghostty·iTerm2 는 입력기의 YES 를 보지 않고, 조합도 글자도 없이 먹은 key 를 스스로 보낸다 — 전환 key 가 수식키인 이유.
11. **다시 보낸 key 는 event 대기열의 끝에 붙는다** — 조합 중 Enter·ESC 를 누르고 수 ms 안에 다음 key 를 이미 눌렀다면 순서가 바뀔 수 있다. 일상 사용에서 지켜본다.
12. **입력기가 먹는 key 는 marked text 가 있는 채로 와야 한다** — 그래야 app 이 그 key 를 입력기의 것으로 본다 (JBR·Chromium, 10 과 같은 이야기).
    그래서 선택 영역도 ⌥↩ 때 marked text 로 만든다.
13. **확정한 글자를 되돌리는 재변환(`replacementRange`)은 app 마다 다르게 깨진다** — 결정 5 의 예외가 좁은 이유.

## 열린 결정

| 결정 | 선택지 | 근거 · 할 실험 | 때 |
|---|---|---|---|
| 설치 위치 | `~/Library/Input Methods` · `/Library/Input Methods` | Secure Keyboard Entry 가 켜지면 전자는 비활성된다 (macOS 15.4.1, 조사). 지금은 전자 — sudo 가 필요 없고, Secure Keyboard Entry 를 늘 켜 둔 곳이 없다. iTerm2 에서 켜 보면 27 에서도 그런지 안다 | M5 |

## 선행 사례

"입력기 하나가 안에서 한/영" 을 이미 하는 한국어 입력기가 있다. 설계 문서와 issue tracker 가 교과서다.

- `hiking90/ongeul` — 가장 가깝다. `design/` 의 문서들 (Caps Lock 은 `design/32-hid-capslock-press-duration.md`)
- `Meapri/PriType-Swift` (활발한 fork: `ghostface2232/PriType-Swift`) — `Docs/UnifiedInputArchitecture.md`
- `kiding/SokIM`, 고전으로 `gureum/gureum`

## Build · 설치 · 검증

- `swift build`, `swift test` — 모든 변경의 최소 관문. HangulCore(spec 의 예, Apple `2SetHangul` layout 대조, 무작위 불변식)와 InputSession(key 순서 → 할 일).
  TIS 를 부르는 test 는 `@MainActor` 여야 한다 (병렬 test 에서 다른 thread 로 부르면 abort).
  Swift Testing 의 `#expect(...)` 안에서는 mutating method 를 부를 수 없다 — 결과를 변수에 먼저 받는다.
- `scripts/install.sh [--register]` — release build → bundle 조립·서명(`scripts/app.sh`) → `~/Library/Input Methods/homi.app` → 실행 중인 homi 종료.
  다음 입력 때 system 이 새 binary 로 띄운다. `--register` 는 처음 한 번 (TIS 등록 + enable).
- 개발 도구 (`tools/`, 제품 아님):
  - `swift run tis list|current|watch|register|enable|disable|select` — input source 조회·관찰·조작.
  - `scripts/probe.sh` — test client 창 (log: `build/probe.log`). key event, handled 여부, 입력기가 묻는 것·시키는 것, input source 변화를 시간순으로 보여준다.
    입력기가 client 에게 무엇을 하는지는 추측하지 말고 여기서 본다.
- `swift scripts/make-icon.swift 호 Sources/homi/Bundle/Resources/homi.tiff` — menu bar icon.
- log: `/usr/bin/log stream --level debug --predicate 'subsystem == "com.unocult.inputmethod.homi"'` (zsh 에서는 `log` 가 builtin 이다).
- 직접 확인할 app (주인이 쓰는 것): VS Code · Obsidian · Ghostty · iTerm2 · Wave · Terminal · Chrome · Safari · Firefox · KakaoTalk · Telegram · Word ·
  Excel · PowerPoint · Pages · Xcode · IntelliJ · LaunchBar · Spotlight · ChatGPT · Claude · Codex · TextEdit · Notes · Windows App · Remote Desktop

**개발 중 안전장치**

- 입력기가 고장나면 타이핑 자체가 막힌다. `ABC` 를 input source 에 남겨 menu bar 로 탈출할 수 있게 한다.
- key event 처리 안에서 block 하지 않는다 — IPC·file I/O·lock 대기 금지. 입력기가 멈추면 client 앱의 입력이 멈춘다.

## 주인 환경

입력기가 한/영의 유일한 주인이 되려면 system 쪽 전환 경로를 정리한다. **agent 가 임의로 바꾸지 않는다 — 주인에게 확인받는다.**

- ✅ "문서의 입력 소스로 자동 전환" 끄기 (2026-09-25) — 켜 두면 system 이 문서마다 input source 를 되돌려 homi 를 밀어낸다.
- ✅ 손쉬운 사용에서 homi 허가 (2026-09-25) — 조합 중 Enter·ESC 다시 보내기에 필요하다.
- ✅ Hammerspoon 입력 전환 코드 제거 — 주인이 직접 (2026-09-25).
- ✅ Apple 한국어 입력기를 입력 소스에서 뺐다 (2026-09-26 확인). `ABC` 는 남긴다 (비밀번호 칸, 비상용).
- "Caps Lock 키로 ABC 입력 소스 전환" 은 켜도 꺼도 된다 — homi 가 선택된 동안에는 homi 가 Caps Lock 을 remap 해서 system 이 보지 못한다.
  켜 두면 homi 밖(ABC)에서 homi 로 돌아오는 길이 된다. 지금은 꺼 두었다 (2026-09-26 주인).
- `⌃Space`·`⌃⌥Space` input source 단축키는 선택 — 켜 두면 비상 탈출구이고, 끄면 IntelliJ 등이 `⌃Space` 를 쓸 수 있다.

## 작업 규칙

- **조합 버그는 재현 test 부터.** 실패하는 test 를 먼저 쓰고 고친다.
- **글자를 잃지 않는다.** 조합 중인 글자는 focus 이동·앱 전환·mouse click·모드 전환·trigger 키 어느 경로로도
  사라지거나 엉뚱한 곳에 들어가면 안 된다. 이 경로들은 test 로 관리한다.
- **macOS 동작을 추측으로 코딩하지 않는다.** IMK·TIS 는 문서가 얇고 app 마다 다르게 군다 — 실험으로 확인하고 `docs/macos-input.md` 에 남긴다.
  결함을 고쳤다면 `docs/lessons.md` 에 증상·원인·증거·대응으로.
- **입력 내용을 log·file 에 남기지 않는다.** 상태 전이·bundle ID 까지만 — key code 도 모이면 입력 내용이다 (key 는 memory 의 ring buffer 에만).
  타이핑은 곧 비밀번호이고 대화다. (예외: `probe` 는 test 창에 친 것만 `build/` 에 남긴다.)
- IMK 층을 바꿨으면 설치해서 해당 app 에서 직접 확인하고, 무엇을 확인했는지 보고한다. `swift test` 통과만으로 "된다" 고 하지 않는다.
- app 에 관해 알게 된 것은 그 app 의 원장(`docs/apps/<app>.md`)에 version·날짜·근거와 함께 적는다. `AppRules.swift` 를 바꾸기 전에 읽고, 바꾼 뒤에 갱신한다.
  app 이 update 됐다고 따로 확인하지 않는다 — 문제가 생겨 분석할 때 원장의 version 과 견주어 무엇이 바뀌었는지 본다 (2026-09-27 주인).
- system 설정 변경(`defaults write`, `hidutil`, input source 추가·제거, 인증서)은 주인에게 먼저 확인받는다.
- runtime 외부 dependency 없음. test 용이라도 추가하려면 먼저 묻는다.

## 학습 동반

주인은 이 프로젝트를 하며 macOS 입력 구조를 배운다. 입력기만이 아니라 주인의 이해도 산물이다.

- TIS input source, IMK, `NSTextInputClient`, marked text, key event 경로 같은 개념은 처음 다룰 때 한 단계 풀어 설명한다.
  결정·실험에는 "왜"를 함께 놓는다.
- 배운 구조는 `docs/macos-input.md` 에 쌓는다. 확인된 사실과 추정을 구분하고, 확인한 방법(실험·source·문서)을 붙인다.
- 실험 도구(`tools/`)는 관찰 가능하게 만든다 — 무엇이 어떤 순서로 일어났는지 log 로 보이게.

## 글말

**주인과의 대화는 한국어로 한다** — 주인의 모국어다. 설명·진행 보고·질문·요약 모두.

본문은 한국어, **기술 용어는 영어 원문 그대로** — `commit`, `client`, `event`, `marked text`, `bundle ID`.
조사는 한국어로 붙인다 ("client 가", "event 를"). 한글 조합의 도메인 용어(조합, 초성·중성·종성, 겹받침, 도깨비불)는
한국어가 표준이므로 그대로 쓴다. 대화·문서·주석·commit message 모두에 적용한다.

- commit message: `scope: 요약 — 이유`
- runtime log 는 영어 문장.

## 진행 단계

| | 내용 | 완료 기준 |
|---|---|---|
| M0 ✅ | 준비 — SwiftPM package, 개발 도구 `tis`·`probe`, 선행 조사, 이름 homi·bundle ID, 설치 script, 빈 입력기 등록 | 빈 입력기가 System Settings 에 보이고 선택된다 (2026-09-25) |
| M1 ✅ | `HangulCore` — 두벌식 조합, `docs/spec.md`, test | 조합 규칙 전부가 test 로 고정된다 (2026-09-25) |
| M2 ✅ | 최소 입력기 — 한글 조합(marked text), commit 경로, 최근 기록(ring buffer) | 주요 앱에서 한글이 쳐진다 (2026-09-25) |
| M3 ✅ | 전환 키 셋 + menu bar 표시 | "전환 → 다음 키" 순서가 test 로 고정된다 (2026-09-25) |
| M4 ✅ | 앱별 기억 + 앱 규칙 + 조합 중 Enter·ESC 다시 보내기 + 수식키 전환 | 주인 확인 (2026-09-25) |
| M5 | 앱 호환성 검증 → 일상 사용 | 일상 사용 기간 동안 세 증상이 한 번도 없다 (Apple 한국어 입력기는 이미 뺐다) |
| M6 ✅ | 한자 변환 — `⌥↩`: 방금 친 단어(macOS text 엔진 app)·조합 중인 글자·선택한 한글, libhangul 사전 | 주인 확인 (2026-09-25) |
| M7 ✅ | 설정 창 — 전환 key, 한자 key·방식, app 목록(시작할 때 영문·ESC 로 영문·한/영 전환 없는 app) | 주인이 설정을 바꿔 쓰고 있다 (2026-09-26) |
