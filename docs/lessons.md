# 결함과 교훈

고친 결함마다 **증상 · 원인 · 증거 · 대응**을 남긴다 (AGENTS.md 작업 규칙). 새 결함은 맨 위에 더한다.
배운 macOS 구조 자체는 `docs/macos-input.md` 에 있다. 여기에는 무엇이 틀렸고 그것을 어떻게 알았는지를 남긴다.

- 간헐 결함의 증거는 homi 의 기록이다 — 이상하면 주인이 곧바로 input menu 의 "최근 key 기록 저장" 을 누르고(`~/Library/Logs/homi/`), 그 file 로 가린다.
- 원인에 🔶 가 붙은 것은 대응이 통했지만 원인은 추정이라는 뜻이다.

## homi 의 결함

### Chromium 에서 조합 중에 click 하면 음절이 두 번 들어간다 (2026-09-25, M6 중)
- **증상**: VS Code 에서 `자`를 조합하던 중 mouse 로 click·선택하면, 그 음절이 누른 자리에 한 번 더 들어갔다 (주인).
- **원인**: Chromium 은 click·blur 때 page 가 조합을 스스로 확정한 뒤 `discardMarkedText` 로 입력기의 `commitComposition` 을 부른다.
  homi 는 그때 조합을 또 `insertText` 했다. 조사에서 알던 함정(AGENTS.md 함정 3)인데 막지 않았었다.
- **증거**: source — `render_widget_host_view_cocoa.mm` `mouseEvent:` → `finishComposingText` → `cancelComposition`.
  homi 기록 — click 때 `commitComposition` 다음에 `insert "자"`.
  첫 대응("client 에 marked text 가 남았을 때만 넣기")이 통하지 않은 것도 기록으로 알았다: 입력기를 부르는 동안 Chromium 은 아직 "있다" 고 답했다.
- **대응**: Chromium 계열 app(bundle 안의 `… Helper (Renderer).app`)의 `commitComposition` 은 homi 가 선택된 동안 넣지 않는다 (`7e4c1fd`).
- **교훈**: app 이 부르는 IMK 호출의 뜻은 app 마다 다르다 — "조합을 끝내 달라" 일 수도, "이미 끝냈다" 일 수도 있다. 가설은 기록으로 확인한다.

### 확정한 단어를 한자로 바꾸면 app 마다 틀어진다 (2026-09-25, M6)
- **증상**: `나는한자` + ⌥↩ 가 TextEdit·Telegram 에서는 맞았다. VS Code·Orca 는 `나는한자漢字`, IntelliJ 는 단어가 사라지고 한자도 없었다 (주인).
- **원인**: 확정한 글자를 marked text 로 되돌리려면 `replacementRange` 를 줘야 하는데, 이 교체를 app 마다 다르게 다룬다.
  IntelliJ editor 는 범위를 무시하고, VS Code 같은 JS editor 는 자기가 모르는 범위에서 시작한 조합을 커서 자리의 새 입력으로 다룬다 🔶.
- **증거**: 주인 관측(app 별 표는 docs/macos-input.md). source — IntelliJ `IdeEventQueue.kt` 는 JBR 의 선택 요청을 speed search 에만 쓴다.
  client 가 알리는 `validAttributesForMarkedText` 가 된 곳(NSTextView)과 안 된 곳(Chromium·JBR)을 가른다.
- **대응**: 방금 친 단어는 NSTextView 수준을 알리는 client(교체 범위 + `NSTextAlternatives`)에서만 바꾼다. terminal·Office 는 app 규칙으로 뺀다.
  고르는 key 는 늘 marked text 가 있는 채로 오게 한다 — 선택 영역도 ⌥↩ 때 marked text 로 만든다 (`c884edd`).
- **교훈**: 결정 5(확정한 글자를 고쳐 쓰지 않는다)의 이유가 실제로 드러났다. 예외는 client 가 스스로 밝힌 능력으로만 연다.

### menu bar 표시가 생기지 않는다 (2026-09-25, M4)
- **증상**: homi 를 골라도 menu bar 에 한/A 가 나타나지 않았다 (주인).
- **원인**: `NSStatusItem` 을 앱 객체(`NSApplication.shared`)보다 먼저 만들었다 — 오류 없이 아무것도 생기지 않는다.
- **증거**: homi process 가 창을 하나도 갖지 않았다 (`CGWindowListCopyWindowInfo`).
- **대응**: `main.swift` 에서 앱 객체를 먼저 만든다 (`b9e220a`).

### 대문자 고정이 뗄 때 켜진다 (2026-09-25, M4)
- **증상**: Caps Lock 을 길게 눌러도 macOS 와 달리 떼야 대문자 고정이 켜졌다 (주인).
- **원인**: 길게 누름을 뗄 때 판정했다.
- **증거**: 주인 관측.
- **대응**: 0.5초가 되는 순간 timer 로 켠다 (`ModifierTap.holdReached`, `b9e220a`).

### 대문자 고정 표시가 둘 뜬다 (2026-09-25, M4)
- **증상**: 대문자 고정을 바꿀 때 homi 의 ⇪ 말풍선과 macOS 자신의 대문자 고정 표시가 함께 떴다 (주인).
- **원인**: homi 가 IOKit 으로 lock 상태를 바꾸면 macOS 가 자기 표시를 띄운다. homi 가 따로 그릴 까닭이 없었다.
- **증거**: 주인 관측.
- **대응**: homi 의 대문자 고정 표시를 없애고 macOS 에 맡긴다 (`b9e220a`).

### 다시 보낸 Enter 가 Telegram 에 닿지 않는다 (2026-09-25, M4)
- **증상**: 조합 중 Enter 를 먹고 다시 보냈더니 Telegram 에서 "틱" 소리만 나고 Enter 가 사라졌다 (주인).
- **원인** 🔶: 원래 event 의 복사본(`NSEvent.cgEvent.copy()`)을 key 처리 도중에 보냈다. 복사본에 딸린 창·시각 정보 때문인지 보낸 시점 때문인지는 가르지 않았다.
- **증거**: homi 기록으로 다시 보낸 것은 확인했다. Telegram 의 전송 조건(`flags == 0` + 입력칸에 글자)은 맞았다 (source) → event 가 입력칸에 닿지 않았다.
- **대응**: 새 event(`CGEvent(keyboardEventSource:virtualKey:keyDown:)`)를 원래 key 처리가 끝난 뒤 HID 경로로 보낸다 (`c08572b`).

### Telegram 에서 조합 중 Enter 가 전송이 아니라 줄바꿈이 된다 (2026-09-25, M4 — Apple 입력기 때부터)
- **증상**: 한글을 조합하다 Enter 를 누르면 전송되지 않고 줄이 바뀌었다 (주인).
- **원인**: Telegram 은 marked text 가 없을 때만 Enter 로 보낸다 — 조합 중이면 입력기에 넘기고, 입력기가 확정한 뒤 줄바꿈이 된다.
- **증거**: source — TelegramSwift `ChatInputTextView.keyDown`.
- **대응**: 조합 중 Enter 는 확정하고 먹은 뒤 다시 보낸다 (`AppRules` 의 `resendWhileComposing`, `c08572b`).

### terminal 에서 조합 중 ESC·Enter 가 사라진다 (2026-09-25, M4 — Apple 입력기 때부터)
- **증상**: vim 에서 한글을 치다 ESC 를 두 번 눌러야 했다.
- **원인**: Ghostty·iTerm2 는 조합 중에 온 key 를 음절 확정에만 쓰고 key 자체는 버린다.
- **증거**: source — Ghostty `SurfaceView_AppKit.keyDown`, iTerm2 `iTermKeyboardHandler.m`. 조사(gt#1663, gureum#1).
- **대응**: 조합 중 Enter·ESC·Tab 은 확정하고 먹은 뒤 다시 보낸다 (`c08572b`). 주인 확인 — vim 의 ESC 한 번.

### 전환 key 가 terminal 에 새어 나간다 (2026-09-25, M3→M4)
- **증상**: Caps Lock 을 F18 로 받았을 때 Ghostty 에 F18 의 문자(U+F715)가, Shift+Space 로 전환하면 space 가 들어갔다 (주인).
- **원인**: Ghostty·iTerm2 는 입력기의 YES(먹었다)를 보지 않는다. 조합도 글자도 없이 먹은 key 는 스스로 보낸다.
  marked text 를 세웠다 지우는 신호(macSKK 방식)도 통하지 않았다.
- **증거**: source — Ghostty `keyDown`(markedTextBefore·insertText·layout 변화 세 조건), iTerm2 `shouldPassPostCocoaEventToDelegate`.
- **대응**: 전환 key 는 글자를 만들지 않는 수식키로 — Caps Lock 은 homi 가 선택된 동안 오른쪽 Control 로 remap, Shift+Space 전환은 없앴다 (주인 결정, `c08572b`).
- **교훈**: "입력기가 key 를 먹었다" 의 판정은 app 이 한다 (docs/macos-input.md 의 표).

### system 이 homi 를 밀어낸다 (2026-09-25, M0·M4)
- **증상**: homi 를 고른 채 다른 창에 갔다 오면 ABC 로 돌아가 있었다. menu bar 표시가 켜졌다 꺼졌다 했다.
- **원인**: "문서의 입력 소스로 자동 전환" 이 문서마다 input source 를 되살린다.
- **증거**: probe — homi 를 고른 채 돌아오자 system 이 ABC 를 되살렸다. `SourceWatcher` 의 선택 알림이 오락가락했다.
- **대응**: 주인이 그 설정을 껐다 (`TextInputGlobalPropertyPerContextInput = 0`, `633c572`). app 별 한/영은 homi 가 기억한다.

## homi 의 결함이 아니었던 것

같은 증상을 다시 보면 먼저 여기를 본다.

- **VS Code 에서 가끔, click 한 자리에 조합 중이던 음절이 한 번 더** (`자한자`) — homi 기록에 넣은 것이 없다. VS Code(Chromium) 안의 타이밍 🔶.
- **IntelliJ 에서 선택 영역을 한자로 바꾸면 글자가 사라진다** — IdeaVim 은 mouse 선택을 Visual mode 로 받고, 조합을 시작하며 선택이 지워지면 Visual 을 나온다.
  Insert 로 돌아가지 않으면 고른 한자는 Normal mode 명령으로 읽혀 버려진다 (source: IdeaVim `IdeaSelectionControl` — 주인 관측과 맞다 🔶). 조합 중인 글자는 된다.
- **Word 에서 선택만 있을 때 ⌥↩ 가 무시된다** — homi 기록에 그 key 가 없다. marked text 가 없으면 Word 가 key 를 먼저 가져가는 듯하다 🔶.
- **Telegram 에서 첫 초성이 사라진다**(`아` → `ㅏ`) — Apple 입력기에서만 났다. homi 로는 재현되지 않았다.

## 개발 도구에서

- **TIS 를 병렬 test 에서 부르면 process 가 abort 한다** (signal 6) — TIS 는 main thread 에서만. test 에 `@MainActor` (M1).
- **bundle 없이 띄운 창은 앞으로 나오지 않는다** — probe 를 `.app` 으로 조립해 `open` 한다 (M0).
- **app 을 죽이자마자 `open` 하면 LaunchServices 가 -600** — 죽어가는 process 에 붙으려 한다. 종료를 기다린다 (`scripts/probe.sh`).
- **probe 가 무한 재귀했다** — text input context 는 만들어질 때 client 에게 `validAttributesForMarkedText` 를 묻는데, probe 가 그 질문을 기록하며
  context 를 다시 찾았다(`lazy`). 만들어지기 전에는 nil 로 두어 끊었다.
- **Swift Testing 의 `#expect(...)` 안에서는 mutating method 를 부를 수 없다** — 결과를 변수에 먼저 받는다 (세 번 되풀이).
