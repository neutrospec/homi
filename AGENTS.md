# AGENTS.md — hangul

**homi** (`com.unocult.inputmethod.homi`) — macOS 한글 입력기. 주인 한 사람이 매일 쓰는 도구이고,
목표는 **두벌식 한글 입력이 완벽하게 동작하는 것** 하나다. 기능을 늘리는 프로젝트가 아니다 — 잡다한 기능·옵션·변죽은 만들지 않는다.

> **현재 (2026-09-25)**: M0–M4 와 M6(한자 변환 `⌥↩`)을 주인이 확인했다 (Hammerspoon 입력 전환 코드는 주인이 직접 정리). M7 설정 창을 주인이 확인하는 중이다.
> 지금은 M5 — 일상 사용과 app 호환성. 이상하면 주인이 곧바로 "최근 key 기록 저장" 을 누른다 → [진행 단계](#진행-단계)

## 문서

| 문서 | 내용 |
|---|---|
| `AGENTS.md` | 목적·결정·규칙. 이 file 이 SOT 다 |
| `docs/macos-input.md` | 배운 macOS 입력 구조와 실험 기록 (✅ 확인 / 🔶 추정) |
| `docs/lessons.md` | 고친 결함의 증상·원인·증거·대응, homi 의 결함이 아니었던 것 |
| `docs/apps/` | app 원장 — app 마다 입력 구현·특징·homi 의 우회와 확인한 version. 같은 엔진의 공통 사실은 `docs/apps/engines/` |
| `docs/research/imk-platform.md` | 조사 — bundle·등록·menu bar 표시·전환 키 받기 |
| `docs/research/app-compat-and-hangul.md` | 조사 — IMK lifecycle·앱별 호환성·Apple 입력기 결함의 원인·두벌식 규칙 |

## 왜 만드는가

macOS 기본 한국어 입력기(`com.apple.inputmethod.Korean.2SetKorean`)에서 주인이 겪는 결함:

| 증상 — 늘이 아니라 **가끔** 나타난다 | 알게 된 원인 | 이 입력기의 답 |
|---|---|---|
| 조합이 깨져 자모가 풀려 입력된다 (`한글` → `ㅎㅏㄴㄱㅡㄹ`) | Apple 입력기는 marked text 없이 확정한 뒤 바꿔치기하고 app 의 text 를 cache 한다 ✅. 문서 위치 답이 비동기인 app 과 어긋나면 조합이 끊긴다 🔶 | 결정 5 |
| 한글 모드인데 첫 자음이 영문으로 찍힌다 | Caps Lock 전환은 key 를 뗀 뒤 43–106ms 에 확정되어 key event 와 다른 통로로 온다 ✅ (probe). 다른 process 의 `TISSelectInputSource` 전환은 실패가 잦다 ✅ | 결정 1·4 |
| 앱별 한/영 기억을 믿을 수 없다 | system 의 기억은 app 이 아니라 문서 단위이고, 복원 자체가 input source 전환이라 위 문제에 노출된다 🔶 | 입력기가 client bundle ID 별로 직접 기억한다 |

가끔 나타난다는 것은 timing 이나 누적 상태에 달린 결함이라는 신호다. 그래서 **"재현이 안 된다"는 해결의 증거가 아니다.**
결함이 생길 수 없는 구조로 만들고(핵심 설계 결정), 그 구조를 test 로 고정하고, 일상 사용 기간의 관측으로 확인한다.

이 결함을 메우던 Hammerspoon 입력 전환기(`~/.hammerspoon/init.lua`)도 대체한다. 그 설정의 역사는
eventtap timeout·stale cache·비동기 전환 race 와의 싸움이다 (`~/.hammerspoon/HAMMERSPOON_ARCHITECTURE.md`).
입력기는 key event 를 입력 흐름 안에서 순서대로 받으므로 그 싸움 자체가 없다.

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
   - 예외 하나 — Apple 식(선택 없이 커서 앞 단어): 교체를 제대로 받는 client 에서만, homi 가 기억한 글자를 그 자리에서 확인하고
     `replacementRange` 로 marked text 로 되돌린다. 제대로 받는 client = macOS text 엔진(NSTextView) 수준을 알리는 것 —
     `validAttributesForMarkedText` 에 교체 범위와 `NSTextAlternatives` 가 함께 있다. 다른 app 에서는 app 마다 다르게 깨졌다 (2026-09-25, docs/macos-input.md).
6. **조합 엔진은 순수하다.** AppKit/IMK 를 모르는 결정적 state machine. 한글 조합의 정확성은 여기서 test 로 증명한다.
7. **IMK 층은 얇다.** NSEvent 해석 → 엔진 → client 반영. 앱별 우회는 재현 증거가 있을 때만, 사유와 함께.

## 요구사항 (확정 2026-09-25)

### 한글 입력

- **두벌식 표준만.** 세벌식·옛한글·모아치기·자동 순서 교정 없음.
- 조합 규칙의 SOT 는 `docs/spec.md` 와 엔진 test. 그중 주인이 정한 것:
  - 같은 자음을 연달아 쳐도 합치지 않는다 — `ㄱㄱ` 은 `ㄱㄱ`. 된소리는 Shift 로만 (2026-09-25). Apple 은 초성에서 합친다고 보고됐다.
  - Backspace 는 자소 단위 (`닭 → 달 → 다 → ㄷ`), 모음 없는 겹자음은 합치지 않는다 (`ㄱㅅ` 은 `ㄱㅅ`) — Apple 과 같고, 주인이 지금 쓰는 그대로.
  - ⌥(Option)+key 는 한글 모드에서도 영문일 때와 같다 — 조합을 확정하고 key 를 넘긴다 (`⌥a → å`, 2026-09-25). Apple 은 `⌥a → a`.
- 한글 모드에서도 `` ` `` 키는 `` ` `` 를 입력한다 (Apple 두벌식은 `₩`).
- **한자 변환** `⌥↩` (M6) — 방금 친 단어, 없으면 조합 중인 글자, 그것도 없으면 선택한 한글.
  - 변환 key(⌥↩ 기본, 오른쪽 ⌥·⌘ 짧게 — 한/영 전환 key 와 겹치면 ⌥↩)와 "방금 친 단어" 를 쓸지는 설정에서 고른다 (M7, 2026-09-25 주인).
  - **방금 친 단어**(Apple 입력기처럼 선택 없이)는 macOS text 엔진을 쓰는 app(TextEdit·Telegram 등)에서만 — 되는 조건에서는 살린다 (2026-09-25 주인).
    판별은 app 목록이 아니라 client 가 알리는 입력 지원이다 (결정 5 의 예외). VS Code·Orca·IntelliJ·Word 에서는 틀어졌다.
    단어는 homi 가 이어서 친 한글 + 조합 중인 글자의 끝부분 중 사전에 있는 가장 긴 것 (`나는한자` → `한자`), `⌥↩` 를 다시 누르면 더 짧은 단어로.
    한글이 아닌 key·수식키 조합·click·입력칸 이동·전환이 끼면 거기서 끊긴다 — app 의 문서를 뒤지지 않는다.
  - 후보 창: 1–9 고르기, ↑↓ 옮기기, ←→ 쪽 넘기기, Enter·Space 확정, ESC 취소(한글 그대로), 다른 key 는 한글 그대로 두고 평소처럼.
  - terminal(iTerm2·Ghostty·Wave·Terminal)과 Office(Word·Excel·PowerPoint)에서는 조합 중인 글자만 (`AppRules` 의 `convertsEnteredText`) —
    terminal 의 선택 영역은 출력이고 보낸 글자는 고칠 수 없다. Office 는 위치를 준 교체에 깨진다.
  - 선택 영역이 안 되는 곳 (2026-09-25 주인 확인): Word 는 선택만 있을 때 ⌥↩ 를 입력기에 주지 않는다(homi 기록에 key 가 없다).
    IntelliJ + IdeaVim 은 mouse 선택이 Visual mode 라 고른 한자가 명령으로 읽힌다. 둘 다 조합 중인 글자는 된다.
  - 사전: libhangul `data/hanja/hanja.txt` (BSD 3-clause, Choe Hwanjin — 저작권 표시가 file 머리에 있다). bundle 에 넣고 map 해서 이진 탐색한다.

### 한/영 전환

- 전환 키는 설정에서 고른다 (여럿 함께, 하나는 남긴다) — **Caps Lock**, **오른쪽 ⌘**, **오른쪽 ⌥** 의 단독 tap, **Shift+Space**. 기본은 Caps Lock·오른쪽 ⌘ (2026-09-25). 받는 방법:
  - Caps Lock: 전환 key 로 쓸 때만, homi 가 선택된 동안 오른쪽 Control 로 remap 해 flagsChanged 로 받는다. **짧게 = 전환, 길게(0.5초 이상) = 대문자 고정** — macOS 와 같다.
    대문자 고정은 누르고 있는 채로 0.5초가 되는 순간 켜진다 (뗄 때가 아니라).
    다른 input source 와 한/영 전환 없는 app 에서는 원래대로다.
  - 오른쪽 ⌘·⌥: 짧게 = 전환. 사이에 다른 key·mouse 가 있었으면(⌘C·⌘Tab) 아니다 — system 의 누름 횟수로 판정, 권한 불필요.
    전환에 쓰지 않는 쪽은 한자 key 로 고를 수 있다.
  - Shift+Space: keyDown 으로 받는다. terminal(Ghostty·iTerm2)은 입력기가 글자 없이 먹은 key 를 스스로 보내서 영문 → 한글 전환 때 space 가 샌다
    (docs/macos-input.md). 그래서 한때 없앴다가, 주인이 알고 고를 수 있게 설정에 두었다 (2026-09-25).
  - 수식키 tap 은 어느 app 에도 새지 않는다 — 전환 key 의 기본이 수식키인 이유.
- 모드 표시: homi 의 menu bar 표시(한/A) + 모드가 바뀔 때 **커서 옆 말풍선**(한/A, Apple 입력기처럼 — 주인 요청).
  system input menu 의 icon("호")은 고정이다. 대문자 고정 표시는 macOS 에 맡긴다 — 겹치면 불편하다 (2026-09-25 주인 결정).
- 전환은 즉시 — 다음 키부터 새 모드. 조합 중이면 먼저 commit 하고 전환한다.
- 오른쪽 ⌘·⌥·Caps Lock 을 다른 키와 함께 쓰면 평소의 ⌘·⌥·Ctrl 이다.

### 앱별 상태

- 앱(client bundle ID)마다 마지막 모드를 기억해 그 앱으로 돌아오면 복원한다. 입력기가 재시작해도 유지.
- 처음 보는 앱은 **영문**으로 시작.
- 활성화될 때마다 영문으로 시작하는 앱 (설정, 기본값): `at.obdev.LaunchBar`
- **한/영 전환 없는 app** (설정, 기본값): `com.apple.RemoteDesktop` · `com.microsoft.rdc.macos`(Windows App) · `org.gnu.Emacs` (2026-09-25 주인).
  한/영 전환도 조합도 하지 않고 key 를 그대로 넘긴다 — 원격 컴퓨터의 입력기나 app 자체의 입력기(Emacs 의 것이 좋다)가 한/영을 맡는다.
  Caps Lock 도 원래대로 — 그 app 이 앞에 있는 동안 remap 을 푼다. menu bar 표시는 `–`.
- 영문 전환 trigger 키 — 조합 중이면 commit → 영문으로 전환 → **키는 앱에 그대로 전달**. ESC 의 app 목록은 설정에서 고친다 (아래는 기본값):

  | 앱 | bundle ID | trigger |
  |---|---|---|
  | VS Code | `com.microsoft.VSCode` | ESC |
  | VS Code Insiders | `com.microsoft.VSCodeInsiders` | ESC |
  | Obsidian | `md.obsidian` | ESC |
  | iTerm2 | `com.googlecode.iterm2` | ESC |
  | Wave | `dev.commandline.waveterm` | ESC |
  | Ghostty | `com.mitchellh.ghostty` | ESC, Ctrl-B, Ctrl-A |

  수식키 조건은 Hammerspoon 규칙 그대로: ESC 는 수식키 무관, Ctrl-B·Ctrl-A 는 Ctrl **단독**일 때만 (Ctrl-Shift-B 는 아님).
  - ⚠️ terminal(Ghostty·iTerm2)은 조합 중에 누른 ESC 를 음절 확정에 쓰고 key 자체는 버린다 — Apple 입력기에서 vim 에 ESC 를 두 번 누르게 되는 이유다. 정책은 [열린 결정](#열린-결정).
  - iTerm2 는 조합 중이 아니면 Ctrl 키를 입력기에 보여주지 않는다. Ctrl-B·Ctrl-A 규칙이 Ghostty 전용인 것과 맞는다.
- 주인이 고르는 것(전환 key, 한자 key·방식, 시작할 때 영문·ESC 로 영문·한/영 전환 없는 app)은 **설정 창**에 둔다 — input menu 의 "설정…"·menu bar 의 한/A.
  바꾸는 즉시 저장되고(UserDefaults 의 `preferences`) 다음 key 부터 쓰인다. app 의 결함에 맞춘 우회(다시 보내기, 한자 제한, Ghostty 의 Ctrl-B·Ctrl-A)는
  주인이 고를 것이 아니라서 source 의 `Sources/InputSession/AppRules.swift` 에 둔다 — 바꾸면 다시 build·설치한다.
- 모드는 key 마다 그 입력칸의 app 으로 읽는다 (`ModeMemory`) — activate 알림이 늦거나 빠져도 틀리지 않는다. UserDefaults 에 남아 재시작해도 유지.
- 조합 중 Enter·ESC 를 app 이 잃거나 다르게 쓰는 곳(Telegram 의 Enter, terminal 의 Enter·ESC·Tab)에서는 확정한 뒤 그 key 를 먹고 **다시 보낸다**.
  손쉬운 사용 권한이 없으면 먹지 않고 예전처럼 넘긴다 — key 를 잃지 않는다.
  다시 보낼 때는 **새 event** 를 만들어 원래 key 처리가 끝난 뒤 HID 경로로 보낸다 — 원래 event 를 복사해 보내면 app 에 닿지 않았다 (docs/macos-input.md).

### 하지 않는 것

세벌식 등 다른 자판, 옛한글, 자동완성·예측, 특수문자 palette, App Store 배포와 sandbox.
명시적 요청 없이 옵션이나 기능을 늘리지 않는다. 설정 창도 주인이 고르겠다고 한 것만 둔다 (2026-09-25).

## 구조

SwiftPM package 하나. `.xcodeproj` 는 두지 않는다 — build·test·설치가 CLI 로 끝나야 agent 가 스스로 검증할 수 있다.

| module | 역할 | 의존 |
|---|---|---|
| `HangulCore` (M1) | 두벌식 자판 mapping + 조합 state machine. 입력: 자모·편집 명령 / 출력: commit 문자열 + 조합 중 문자열 | 없음 |
| `InputSession` | key 해석(자모·Backspace·넘길 key, M3 부터 전환 키·trigger), 모드, 앱별 기억과 규칙, 주인의 설정(`Preferences`), 최근 기록(`Recorder`) | `HangulCore` |
| `homi` (app, `Sources/homi`) | IMK glue — `IMKServer`, `HomiInputController`, NSEvent 변환, menu bar 표시, 설정 창(SwiftUI). `Bundle/` 에 `Info.plist`·resource | 위 둘 + AppKit·InputMethodKit |

- `Info.plist` 는 한국어 mode 하나(`com.unocult.inputmethod.homi.korean`, `smKorean`)만 둔다 — 한/영은 homi 안의 모드이고
  표시도 homi 가 하므로 system 에 mode 를 알릴 일이 없다 (결정 4). 비밀번호 칸에서는 system 이 ABC 로 바꾼다.
  mode 구성을 바꾸면 logout + input source 재추가가 필요하다.

- 아래 두 module 은 AppKit·IMK 를 import 하지 않는다. 그래서 "key 순서 → client 에게 할 일" 대부분을 `swift test` 에서 검증한다.
  IMK 층에 남는 것이 적을수록 좋다.
- `Session` 은 client 를 직접 부르지 않고 할 일(`Action`: mark·insert) 목록을 돌려준다. IMK 층은 상태 변경이 끝난 뒤에 적용한다 —
  IMK 는 우리의 `insertText` 도중에 deactivate 를 끼워 부를 수 있어서, 상태를 바꾸는 중에 client 를 부르면 재진입이 겹친다.
- 자판 mapping 은 `keyCode`(물리 위치) 기준이다. `NSEvent.characters` 는 layout 에 따라 바뀐다 (`kc=5` 가 `g`/`ㅎ`).
- 문장부호·`` ` `` 등 한글이 아닌 key 는 조합을 확정한 뒤 통과시켜 layout 이 문자를 만들게 한다. `insertText` 로 직접 넣으면 key event 를 읽는 xterm.js·Ink(Claude Code) 가 못 본다.
- IMK override 는 `nonisolated override` + `MainActor.assumeIsolated` — macOS 27 SDK 의 IMK header 에는 actor 표시가 없다.
- app bundle 은 script 가 조립한다: executable + `Info.plist` + icon → codesign → 설치 (`scripts/app.sh` 가 뼈대).
- 간헐 결함은 사후에 재현하기 어렵다. 입력기는 최근 key event·상태 전이를 memory ring buffer 에만 들고 있다가
  주인이 요청할 때 dump 한다 — file 에 상시 기록하지 않는다 (입력 내용 보호). 설계는 M2.

## 알려진 함정

조사와 실험에서 나온 것. 설계·구현 전에 읽는다. 근거와 출처는 `docs/research/`.

1. **IMK lifecycle 은 뒤바뀌고 빠진다.** activate/deactivate 순서 보장이 없고, 중첩되어 오기도 하며, macOS 26 부터는 다른 process 의 전환에 `deactivateServer` 가 오지 않는다.
   상태는 controller·client 단위로 두고, 확정은 두 번 불려도 안전하게, 앱별 규칙은 첫 `handle()` 에서 다시 적용한다.
2. **확정이 엉뚱한 client 로 간다.** 새 session 이 먼저 key 를 받고 옛 session 의 확정이 뒤늦게 온다. init 때 묶인 client 로 넣는다.
3. **Chromium 은 click·blur 때 스스로 확정한 뒤 `commitComposition` 을 부른다.** 그대로 넣으면 음절이 두 번 들어간다 (VS Code 에서 `자자`, 주인 관측).
   Chromium 은 입력기를 부른 뒤에야 자기 상태를 바꾸므로 `markedRange` 로는 가릴 수 없다 (homi 기록). 그래서 Chromium 계열 app(bundle 안의
   renderer helper 로 판별)의 `commitComposition` 은, homi 가 아직 선택된 입력기라면 넣지 않는다 — 입력 소스 전환 때 system 이 부르는 것만 넣는다.
   그 뒤에도 VS Code 에서 가끔 click 한 자리에 한 번 더 들어가는 것은 VS Code 쪽이다 (homi 기록에 넣은 것이 없다).
4. **입력기는 ⌘ 단축키의 key 를 못 본다.** menu 가 먼저 가져가고, ⌘Tab 의 Tab 은 system 이 가져간다 (probe run 2). 되돌아올 때 `flagsChanged kc=0` 같은 합성 event 도 온다.
5. **Caps Lock** — system 전환 옵션, Apple keyboard 의 activation delay, lock 상태 echo·LED·cursor 옆 bubble, text client 가 없으면 못 받는 문제가 있다.
6. **`activateServer`·`setValue` 안에서 client 호출·block 금지.** Chrome 과 deadlock, Spotlight 멈춤 사례. `setValue` 는 focus 가 바뀔 때마다 같은 값으로 다시 온다 — echo 로 무시.
7. **영문 mode 를 system 에 노출하면 비밀번호 칸에서도 그 mode 가 살아 key 를 받는다.** 완전 통과여야 한다. 한국어 mode 만 있으면 system 이 ABC 로 대체한다.
8. **등록** — parent input method 를 먼저 enable, 첫 등록엔 logout 을 각오, `ComponentInputModeDict` 를 바꾸면 logout + 재추가. **`imklaunchagent` 는 절대 죽이지 않는다** (실행 중인 app 들이 모든 입력기를 잃는다).
9. **ad-hoc 서명은 build 마다 신원이 바뀐다** — 손쉬운 사용·입력 모니터링 허가가 매번 풀린다. 그래서 login keychain 의 자체 서명 인증서
   "homi code signing" 으로 서명한다 (`scripts/app.sh`, 2026-09-25 생성, 2036 만료). 신원 조건 = bundle ID + 이 인증서.
10. **app 마다 "입력기가 먹었다" 판정이 다르다.** Ghostty·iTerm2 는 입력기의 YES 를 보지 않고, 조합도 글자도 없이 먹은 key 를 스스로 보낸다.
    그래서 전환 key 는 글자를 만들지 않는 수식키여야 한다 — 규칙표는 docs/macos-input.md.
11. **다시 보낸 key 는 event 대기열의 끝에 붙는다.** 조합 중 Enter·ESC 를 누르고 수 ms 안에 다음 key 를 이미 눌렀다면 둘의 순서가 바뀔 수 있다.
    일상 사용에서 지켜본다.
12. **입력기가 먹는 key 는 marked text 가 있는 채로 와야 한다.** app 은 key 앞에 marked text 가 있었을 때만 그 key 를 입력기의 것으로 본다 —
    JetBrains Runtime 은 marked text 없이 온 `insertText` 를 누른 key 의 입력으로 Java 에 보내고(Enter 로 골랐다면 Enter 동작까지),
    Chromium 은 한 글자면 원래 keydown 을 page 에 보낸다. 10 의 terminal 규칙과 같은 이야기다. 그래서 선택 영역도 ⌥↩ 때 marked text 로 만든다.
13. **확정한 글자를 marked text 로 되돌리는 재변환(`replacementRange`)은 app 마다 다르게 깨진다.** VS Code·Orca 는 조합을 커서에 따로 만들고,
    IntelliJ editor 는 범위를 무시하고(source), Office 는 위치를 준 교체에 깨진다. Chromium 처럼 지원한다고 알려도 그 위의 JS editor 가 모른다 —
    그래서 macOS text 엔진 수준을 알리는 client 에서만 한다 — 결정 5 의 예외가 좁은 이유다 (docs/macos-input.md).

## 열린 결정

| 결정 | 선택지 | 근거 · 할 실험 | 때 |
|---|---|---|---|
| 설치 위치 | `~/Library/Input Methods` · `/Library/Input Methods` | Secure Keyboard Entry 가 켜지면 전자는 비활성된다 (macOS 15.4.1). **M0 는 전자** — sudo 가 필요 없고, 지금 Secure Keyboard Entry 가 늘 켜진 곳이 없다 | M5 |

## 선행 사례

"입력기 하나가 안에서 한/영" 을 이미 하는 한국어 입력기가 있다. 설계 문서와 issue tracker 가 교과서다.

- `hiking90/ongeul` — 가장 가깝다. `design/` 의 문서들 (Caps Lock 은 `design/32-hid-capslock-press-duration.md`)
- `Meapri/PriType-Swift` (활발한 fork: `ghostface2232/PriType-Swift`) — `Docs/UnifiedInputArchitecture.md`
- `kiding/SokIM`, 고전으로 `gureum/gureum`

## Build · 설치 · 검증

- `swift build` — 전부 build. `swift test` — 모든 변경의 최소 관문. 지금은 `HangulCore`: spec 의 예 전부, Apple `2SetHangul` layout 과의 대조, 무작위 입력 불변식.
  TIS 를 부르는 test 는 `@MainActor` 여야 한다 (병렬 test 에서 다른 thread 로 부르면 abort).
  Swift Testing 의 `#expect(...)` 안에서는 mutating method 를 부를 수 없다 — 결과를 변수에 먼저 받는다 (세 번 되풀이한 실수).
- 개발 도구 (`tools/`, 제품 아님):
  - `swift run tis list|current|watch|register|enable|disable|select` — input source 조회·관찰·조작
  - `scripts/probe.sh` — test client 창을 띄운다 (log: `build/probe.log`). key event, `handleEvent` 의 handled 여부,
    입력기가 client 에게 묻는 것(`? selectedRange`…)과 시키는 것(`setMarkedText`·`insertText`…), input source 변화를 시간순·중첩으로 보여준다.
    입력기가 client 에게 무엇을 하는지는 추측하지 말고 여기서 본다.
- `scripts/install.sh [--register]` — release build → bundle 조립 → ad-hoc 서명 → `~/Library/Input Methods/homi.app` → 실행 중인 homi 종료.
  다음 입력 때 system 이 새 binary 로 띄운다. `--register` 는 처음 한 번 (TIS 등록 + enable; 안 잡히면 System Settings 에서 추가하거나 logout).
- `scripts/app.sh <exe> <Info.plist> <out.app> [resources]` — bundle 조립 + ad-hoc 서명. bundle 이 없으면 macOS 는 app 으로 대접하지 않는다 (창이 앞으로 안 나온다).
- `swift scripts/make-icon.swift 호 Sources/homi/Bundle/Resources/homi.tiff` — menu bar template icon (16pt @1x·@2x)
- log: `log stream --level debug --predicate 'subsystem == "com.unocult.inputmethod.homi"'`
- 직접 확인할 앱 (주인이 쓰는 것): VS Code · Obsidian · Ghostty · iTerm2 · Wave · Terminal · Chrome · Safari · Firefox ·
  KakaoTalk · Telegram · Word · Excel · PowerPoint · Pages · Xcode · IntelliJ · LaunchBar · Spotlight ·
  ChatGPT · Claude · Codex · TextEdit · Notes · Windows App

**개발 중 안전장치**

- 입력기가 고장나면 타이핑 자체가 막힌다. 개발 중에는 `ABC` 를 input source 에 남겨 menu bar 로 탈출할 수 있게 한다.
- key event 처리 안에서 block 하지 않는다 — IPC·file I/O·lock 대기 금지. 입력기가 멈추면 client 앱의 입력이 멈춘다.

## 주인 환경 (일상 사용으로 넘어갈 때)

입력기가 한/영의 유일한 주인이 되려면 system 쪽 전환 경로를 정리한다. **agent 가 임의로 바꾸지 않는다 — 주인에게 확인받는다.**

- ✅ "문서의 입력 소스로 자동 전환" 끄기 (2026-09-25 완료, `TextInputGlobalPropertyPerContextInput = 0`) — 켜 두면 system 이 문서마다 input source 를 되돌려 homi 를 밀어낸다.
- ✅ 손쉬운 사용에서 homi 허가 (2026-09-25) — 조합 중 Enter·ESC 다시 보내기에 필요.
- Hammerspoon 입력 전환 코드 제거 — 주인이 직접 (2026-09-25). 남겨 두면 ESC 마다 `com.apple.keylayout.ABC` 로 전환해 homi 를 벗어난다.
- Apple 한국어 입력기 제거 — 일상 사용에서 세 증상이 없음을 확인한 뒤 (M5). `ABC` 는 남긴다 (비밀번호 칸, 비상용).
- "Caps Lock 키로 ABC 입력 소스 전환" 은 **켜 둬도 된다.** homi 가 선택된 동안에는 homi 가 Caps Lock 을 remap 해서 system 이 보지 못하고,
  homi 밖(ABC)에서는 이 옵션이 homi 로 돌아오는 길이 된다.
- `⌃Space`·`⌃⌥Space` input source 단축키(symbolic hotkey 60·61)는 선택. 켜 두면 비상 탈출구이고, 끄면 IntelliJ 등이 `⌃Space` 를 쓸 수 있다.

## 작업 규칙

- **조합 버그는 재현 test 부터.** 실패하는 test 를 먼저 쓰고 고친다.
- **글자를 잃지 않는다.** 조합 중인 글자는 focus 이동·앱 전환·마우스 click·모드 전환·trigger 키 어느 경로로도
  사라지거나 엉뚱한 곳에 들어가면 안 된다. 이 경로들은 test 목록으로 관리한다.
- **macOS 동작을 추측으로 코딩하지 않는다.** IMK·TIS 는 문서가 얇고 앱마다 다르게 군다. 실험으로 확인하고
  `docs/macos-input.md` 에 남긴다. 결함을 고쳤다면 `docs/lessons.md` 에 증상 · 원인 · 증거 · 대응으로.
- **입력 내용을 log·file 에 남기지 않는다.** 상태 전이·bundle ID 까지만 — key code 도 모이면 입력 내용이다 (key 는 memory 의 ring buffer 에만).
  타이핑은 곧 비밀번호이고 대화다. (예외: `probe` 는 test 창에 친 것만 `build/` 에 남긴다.)
- IMK 층을 바꿨으면 설치해서 해당 앱에서 직접 확인하고, 무엇을 확인했는지 보고한다. `swift test` 통과만으로 "된다"고 하지 않는다.
- app 에 관해 알게 된 것(특징·우회·재현 절차)은 그 app 의 원장 `docs/apps/<app>.md` 에 version·날짜·근거와 함께 적는다.
  `AppRules.swift` 를 바꾸기 전에 그 원장을 읽고, 바꾼 뒤에 갱신한다. app 이 update 되면 원장의 "다시 확인할 것" 을 해 본다.
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
| M4 ✅ | 앱별 기억 + 앱 규칙 + 조합 중 Enter·ESC 다시 보내기 + 수식키 전환 | 주인 확인 (2026-09-25). Hammerspoon 입력 전환 코드는 주인이 직접 정리 |
| M5 | 앱 호환성 검증 → 일상 사용 | 일상 사용 기간 동안 세 증상이 한 번도 없다 → Apple 한국어 입력기를 지운다 |
| M6 ✅ | 한자 변환 — `⌥↩`: 방금 친 단어(macOS text 엔진 app)·조합 중인 글자·선택한 한글, libhangul 사전 | 주인 확인 (2026-09-25) |
| M7 | 설정 창 — 전환 key(Caps Lock·오른쪽 ⌘·⌥·Shift+Space), 한자 key·방식, app 목록(시작할 때 영문·ESC 로 영문·한/영 전환 없는 app) | 주인 확인 |
