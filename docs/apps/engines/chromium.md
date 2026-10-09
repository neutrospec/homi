# Chromium (Electron 포함)

조합은 page(renderer)가 가진다. browser 쪽 view(`RenderWidgetHostViewCocoa`)가 입력기 호출을 받아 renderer 로 넘긴다.

| | |
|---|---|
| app | VS Code, Obsidian, Chrome, Orca, Wave, Claude (이 Mac 에서 판별) |
| 판별 | app bundle 안의 `… Helper (Renderer).app` — Electron 은 `Contents/Frameworks/` 바로 아래, Chrome 은 `… Framework.framework/Helpers/` (`Sources/homi/Chromium.swift`) |
| source | [`render_widget_host_view_cocoa.mm`](https://github.com/chromium/chromium/blob/154.0.8037.98/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm) (`154.0.8037.98` · 2026-10-09 에 읽음, 이전 조사는 `main`) |

## 특징

- **click·blur 때 page 가 조합을 스스로 확정하고, 입력기의 `commitComposition` 을 부른다.**
  click 이면 `mouseEvent:` → `finishComposingText`(`ImeFinishComposingText` + `cancelComposition`) → `discardMarkedText` 로 간다.
  first responder 를 넘길 때, 창이 key 를 잃을 때도 `cancelComposition` 한다.
  `source` ✅ · `VS Code 1.139.0 · 2026-09-25 · 기록` ✅
- **그 호출은 입력기를 기다리고, 끝난 뒤에야 `_hasMarkedText` 를 끈다** — 그동안 `markedRange` 는 아직 "있다" 고 답한다.
  `VS Code 1.139.0 · 2026-09-25 · 기록` ✅
- **mouse event 를 입력기에 넘기지 않는다** — 입력기의 mouse-down 처리가 불리지 않는다.
  `source` ✅
- **key 처리 중의 호출은 모아 두었다가 key 처리 뒤에 보낸다.** `insertText(NSNotFound)` 의 글자를 먼저 보내고, `setMarkedText` 는 마지막 것 하나만 보낸다.
  `replacementRange` 를 준 `insertText` 는 곧바로 보낸다.
  `source` ✅
- **key 앞에 marked text 가 없었고 넣는 글자가 한 글자면 원래 keydown 을 page 에 보낸다.**
  marked text 가 있었으면 keyCode 229(PROCESSKEY)를 보낸다 — 입력기가 먹은 key 로 다뤄진다.
  `source` ✅
- **`validAttributesForMarkedText`**: `NSUnderline` `NSUnderlineColor` `NSMarkedClauseSegment` `NSTextInputReplacementRangeAttributeName` — WebKit 것을 옮겼다.
  `NSTextAlternatives` 는 없다.
  `source` ✅
- **교체 범위는 Blink 까지는 가지만, 그 위의 JS editor 는 모른다.** 확정한 단어를 marked text 로 되돌리면 VS Code·Orca 는 `나는한자漢字` 가 됐고,
  Chrome 은 입력칸에 따라 달랐다.
  `VS Code 1.139.0, Orca 1.4.210, Chrome 154 · 2026-09-25 · 주인` ✅ (까닭 🔶)
- 조합이 있으면 `replacementRange` 를 준 확정도 조합 자리에 들어간다고 기억한다 (Blink `InputMethodController::CommitText`). `source 기억` 🔶
- 같은 view 안의 여러 DOM 입력칸이 client 하나를 공유할 수 있다. controller 를 고정해도 DOM focus 는 바뀐다.
  `조사(PriType#15)·Chrome 비교 page 의 같은 controller 기록` ✅
- web page 의 handler 가 `isComposing`·keyCode 229 를 보지 않으면 조합 중 Enter 에 마지막 음절이 두 번 처리된다 — Chromium 구조라 Apple 입력기에서도 난다. `조사` ✅

## homi 의 우회

- `commitComposition` 에서 homi 가 선택돼 있으면 Session 만 끝내는 기존 우회로 복귀했다.
  **불완전함**: source 전환에도 TIS 가 아직 homi 를 가리킬 수 있어 그 경로는 계속 실패한다.
  callback 뒤 mark 를 확인하는 교정은 새 입력칸에 글자를 넣어 제거했다. 다음 event 로 확정을 넘기지 않는다.
  구조와 근거는 [입력 구조](../../macos-input.md#chromium-은-click-때-조합을-스스로-확정한다), 실제 검증 범위는 [Chrome 원장](../chrome.md)에 있다.
- Apple 방식 한자는 쓰지 않는다 — `NSTextAlternatives` 를 알리지 않는다 (`Client.replacesLikeTextView`, `c884edd`).

## 확인하는 법

- 조합 중(`자`)에 click → 음절이 한 번만 남는다. 새 입력칸에 이전 조합이 따라오지 않는다.
- 조합 중(`한`)에 input menu 로 ABC → homi → `한글` → `한한글` 이 남아야 한다. 현재 미해결 경로다.
- `validAttributesForMarkedText` 에 `NSTextAlternatives` 가 생겼는가 — 생기면 Apple 방식 한자가 켜진다. 그 app 에서 `나는한자` + ⌥↩ 가 맞는지 본다.
- renderer helper 의 위치가 그대로인가 — 판별이 여기에 기댄다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | VS Code 1.139.0 | click 때 음절 중복 — 첫 대응(marked text 확인)이 통하지 않음을 기록으로 확인 → Chromium 규칙 (`7e4c1fd`) |
| 2026-09-25 | VS Code 1.139.0, Orca 1.4.210, Chrome 154 | 확정한 단어의 재변환이 틀어짐 → Apple 방식 한자에서 뺌 (`c884edd`) |
| 2026-10-09 | Chrome 154.0.8037.98 · macOS 27.0.1 | source commit 때 TIS 의 선택이 아직 homi 인 순서 확인. callback 뒤 mark 확인은 새 입력칸 누출을 일으켜 제거하고 기존 우회로 복귀. source 전환 실패는 남음 |
