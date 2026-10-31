# Chromium (Electron 포함)

조합은 page(renderer)가 가진다. browser 쪽 view(`RenderWidgetHostViewCocoa`)가 입력기 호출을 받아 renderer 로 넘긴다.

| | |
|---|---|
| app | VS Code, Obsidian, Chrome, Orca, Wave, Claude (이 Mac 에서 판별) |
| 판별 | app bundle 안의 `… Helper (Renderer).app` — Electron 은 `Contents/Frameworks/` 바로 아래, Chrome 은 `… Framework.framework/Helpers/` (`Sources/homi/Chromium.swift`) |
| source | [`render_widget_host_view_cocoa.mm`](https://github.com/chromium/chromium/blob/154.0.8037.98/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm) (`154.0.8037.98` · 2026-10-09 에 읽음, 이전 조사는 `main`) |

## 특징

- **click 때 page 가 조합을 스스로 확정하고, 입력기의 `commitComposition` 을 부른다.**
  click 이면 `mouseEvent:` → `finishComposingText`(`ImeFinishComposingText` + `cancelComposition`) → `discardMarkedText` 로 간다.
  `source` ✅ · `VS Code 1.139.0 · 2026-09-25 · 기록` ✅
- **`cancelComposition` 만으로 renderer 확정까지 보장하지 않는다.** 이 함수는 `discardMarkedText` 뒤 Cocoa mark flag 를 끄며,
  `finishComposingText` 처럼 먼저 `ImeFinishComposingText` 를 보내지 않는다. first responder 이동과 조건부 창 focus 해제에도 cancel 경로가 있다.
  `154.0.8037.98 · 2026-10-09 · source 재검토` ✅ — 모든 blur 를 click 과 같은 renderer 확정으로 일반화하지 않는다.
- **caret 위치 질의 실패도 cancel 경로다.** `firstRectForCharacterRange` 는 `SyncGetFirstRectForRange` 실패 때 `cancelComposition` 후 빈 rect 를 돌려준다.
  `154.0.8037.98 · 2026-10-09 · source` ✅. homi 의 `attributes` 질의가 실제로 이 실패·IMK callback 에 연결됐는지는 미관측이다.
  위치를 묻는 것만으로 항상 조합을 보존한다고 가정하지 않고 [개선 검토](../../stability-review.md)의 별도 검증 대상으로 둔다.
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

## 입력 context 와 source 제한 (2026-10-30)

T3 에 설치된 Electron 44.9.3 의 [DEPS](https://github.com/electron/electron/blob/v44.9.3/DEPS)가 가리키는
Chromium **152.0.7977.167**의 공개 코드를 확인했다. 설치 binary 에서 해당 분기를 실행하는지는 관찰하지 않았다.

- [`RenderWidgetHostViewCocoa.inputContext`](https://github.com/chromium/chromium/blob/152.0.7977.167/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm)는
  편집 불가(`TEXT_INPUT_TYPE_NONE`)·password type·password 이력 flag 에서 nil 을 반환한다.
  AutoFill 지원을 끄고 native context menu 를 여는 조건에서도 nil 이다. 일반 편집칸에서는 상위 AppKit context 를 돌려준다. ✅ source
- [`SetTextInputActive`](https://github.com/chromium/chromium/blob/152.0.7977.167/content/browser/renderer_host/render_widget_host_view_mac.mm)는
  focus·type·password flag 에 따라 password 보호를 켜고 끈다. text input state 변경 때 AppKit 의 context cache 를 갱신하는 경로도 있다. ✅ source
- [`SetPasswordInputEnabled`](https://github.com/chromium/chromium/blob/152.0.7977.167/ui/base/cocoa/secure_password_input.mm)는
  Secure Event Input 과 함께 TSM document 의 허용 source 를 ASCII-capable 목록으로 제한하고, 해제 때 그 property 를 제거한다. ✅ source
  보안 입력 자체와 허용 source 제한은 별도 조작이다. Secure Event Input 의 true/false 하나로 menu 의 상태를 모두 설명하지 않는다.

[T3 의 menu 누락](../t3-code.md#input-menu-에서-homi-누락-2026-10-30-미해결)에 관련될 수 있는 경로지만,
실패 순간 type·flags·context·TSM property 를 확보하지 못했다. 일반 메시지 입력칸이 password 로 잘못 분류됐다고 단정하지 않는다.

### Orca 설치 version 대조 (2026-10-31)

Orca 1.4.244 의 framework 는 Electron **43.8.1**, 공식 [DEPS](https://github.com/electron/electron/blob/v43.8.1/DEPS)의 Chromium 은
**150.0.7871.250**이다. 위 T3 조사 version 과 다르므로 다음 경로를 따로 대조했다.

- [`inputContext`](https://github.com/chromium/chromium/blob/150.0.7871.250/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm)는
  type 이 NONE·PASSWORD 이면 nil, 그 밖에는 상위 AppKit context 를 돌려준다. 위 version 의 password 이력·AutoFill 조건을 이 version 에 그대로 적용하지 않는다.
- [text input state 변경 경로](https://github.com/chromium/chromium/blob/150.0.7871.250/content/browser/renderer_host/render_widget_host_view_mac.mm)는
  AppKit 에 새 input context 를 cache 시키는 `updateWindows`를 기본 설정에서 100ms 뒤에 호출한다.
  focus·활성 상태 변경의 `SetTextInputActive`는 이 timer 를 중단한다. 지연 갱신 경로의 존재는 확인했지만,
  [Orca 의 누락·대기 후 회복](../orca.md#input-menu-의-homi-누락-보고와-회복-2026-10-31-미해결)을 이 100ms timer 탓으로 설명하지 않는다.
- [password 보호](https://github.com/chromium/chromium/blob/150.0.7871.250/ui/base/cocoa/secure_password_input.mm)도
  Secure Event Input 과 TSM 의 ASCII-capable source 제한을 별도로 설정·해제한다.

공개 source 의 후보 기전이며, 실행 중 Orca 의 type·context·TSM 제한·timer 상태는 확보하지 못했다.

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
