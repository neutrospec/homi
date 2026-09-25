# Chromium (Electron 포함)

조합은 page(renderer)가 가진다. browser 쪽 view(`RenderWidgetHostViewCocoa`)가 입력기 호출을 받아 renderer 로 넘긴다.

| | |
|---|---|
| app | VS Code, Obsidian, Chrome, Orca, Wave, Claude (이 Mac 에서 판별) |
| 판별 | app bundle 안의 `… Helper (Renderer).app` — Electron 은 `Contents/Frameworks/` 바로 아래, Chrome 은 `… Framework.framework/Helpers/` (`Sources/homi/Chromium.swift`) |
| source | `render_widget_host_view_cocoa.mm` (2026-09-25 에 읽음) |

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
- 창 하나의 모든 web 입력칸이 client 하나를 공유한다. `조사(PriType#15)` ✅
- web page 의 handler 가 `isComposing`·keyCode 229 를 보지 않으면 조합 중 Enter 에 마지막 음절이 두 번 처리된다 — Chromium 구조라 Apple 입력기에서도 난다. `조사` ✅

## homi 의 우회

- Chromium 계열의 `commitComposition` 은, homi 가 아직 선택된 입력기라면 넣지 않고 조합만 버린다. 입력 소스 전환 때 system 이 부르는 것만 넣는다
  (`HomiInputController.commitComposition`, `7e4c1fd`). 전환 순간에 TIS 가 이미 새 입력 소스를 가리키는지는 아직 확인하지 않았다 🔶.
- Apple 방식 한자는 쓰지 않는다 — `NSTextAlternatives` 를 알리지 않는다 (`Client.replacesLikeTextView`, `c884edd`).

## 다시 확인할 것 (Chromium·Electron 이 바뀌면)

- 조합 중(`자`)에 click → 음절이 한 번만 남는다. homi 기록에 `finished by client — not inserting`.
- `validAttributesForMarkedText` 에 `NSTextAlternatives` 가 생겼는가 — 생기면 Apple 방식 한자가 켜진다. 그 app 에서 `나는한자` + ⌥↩ 가 맞는지 본다.
- renderer helper 의 위치가 그대로인가 — 판별이 여기에 기댄다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | VS Code 1.139.0 | click 때 음절 중복 — 첫 대응(marked text 확인)이 통하지 않음을 기록으로 확인 → Chromium 규칙 (`7e4c1fd`) |
| 2026-09-25 | VS Code 1.139.0, Orca 1.4.210, Chrome 154 | 확정한 단어의 재변환이 틀어짐 → Apple 방식 한자에서 뺌 (`c884edd`) |
