# JetBrains Runtime (JBR)

JetBrains 의 Java runtime 이다. native 의 `AWTView` 가 입력기 호출을 받아 Java 의 `CInputMethod` 로 넘긴다.
Java 쪽에서 marked text 는 문서 밖의 "composed text" 다.

| | |
|---|---|
| app | IntelliJ IDEA (Rider 같은 다른 JetBrains IDE 도 같을 것이다 🔶) |
| source | JetBrainsRuntime `main` — `AWTView.m`, `CInputMethod.java`, `CPlatformResponder.java` (2026-09-25 에 읽음) |

## 특징

- **누른 key 를 Java 에 보내는 조건: key 처리 뒤에 marked text 가 없고 `fKeyEventsNeeded` 가 참일 때** (`keyDown:`).
  `source` ✅
- **`setMarkedText("")` 는 `fKeyEventsNeeded` 를 끈다** — 빈 marked text 를 세우면 그 key 는 Java 에 가지 않는다.
  `source` ✅
- **`insertText` 는 marked text 가 있거나 key 처리 밖일 때만 입력기 글자(InputMethodEvent)로 받는다.**
  그 밖에는 누른 key 의 입력으로 보낸다 — 누른 key 의 KEY_PRESSED 다음에 글자마다 KEY_TYPED. Enter 로 고른 글자라면 Enter 동작까지 일어날 것이다 🔶.
  `source` ✅
- **`insertText` 끝에 `abandonInput`**(`markedTextAbandoned` + `unmarkText`)을 한다. IntelliJ 에서는 넘긴 key 마다 입력기에 `commitComposition` 이 곧바로 따라왔다.
  `source` ✅ · `IntelliJ 2026.2.3 · 2026-09-25 · 기록` ✅
- **`replacementRange` 는 `selectRange` 로 간다** — `JTextComponent` 는 그 범위를 선택하고, 그 밖의 component 는 JBR TextInput API 의 listener 에 맡긴다.
  IntelliJ 의 listener 는 [intellij.md](../intellij.md) 에 있다.
  `source` ✅
- **`markedRange` 는 Java 의 입력 위치(`getInsertPositionOffset`)를 빌린다** — 문서 위치와 같다는 보장이 없다.
  `source` ✅
- **`validAttributesForMarkedText` 는 빈 목록이다.**
  `source` ✅
- **press-and-hold 는 `event.willBeHandledByComplexInputMethod` 로 가린다.** `doCommandBySelector` 가 `insertNewline:`·`insertTab:`·`deleteBackward:` 면 key 를 Java 에 보낸다.
  `source` ✅

## homi 의 우회

- 고르는 key 는 marked text 가 있는 채로 오게 한다 — 선택 영역도 ⌥↩ 때 marked text 로 만든다 (`c884edd`).
- Apple 방식 한자는 쓰지 않는다 — 아무 attribute 도 알리지 않는다.

## 확인하는 법

- 조합 중 ESC → 영문 전환, IdeaVim 은 ESC 를 받는다 (Normal).
- 조합 중인 글자 + ⌥↩ → Enter 로 고르기 → 한자로 바뀌고 줄은 바뀌지 않는다.
- `validAttributesForMarkedText` 가 여전히 비었는가.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | IntelliJ 2026.2.3 | source 로 key 전달 규칙 확인 (M6) |
