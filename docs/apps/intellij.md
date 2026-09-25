# IntelliJ IDEA

| | |
|---|---|
| bundle ID | `com.jetbrains.intellij` · `com.jetbrains.intellij.ce` (CE 는 지금 설치돼 있지 않다 — 규칙은 같다) |
| 엔진 | JetBrains Runtime → [engines/jbr.md](engines/jbr.md) |
| 확인한 version | 2026.2.3 (IU-262.10968.63) · 2026-09-25 · macOS 27.0 |
| plugin | IdeaVim — 기본 설정 (`~/.ideavimrc` 없음) |
| homi 규칙 | ESC → 영문 |

## 특징

- **ESC 는 영문 전환 trigger** — IdeaVim 에서 Normal 로 갈 때 영문이 되게 (주인 요청).
  `2026.2.3 · 2026-09-25 · 주인` ✅
- **⌥↩ 는 IntelliJ 의 Show Context Actions 다** — homi 는 조합 중이거나 한글을 선택했을 때만 먹고, 그 밖에는 IntelliJ 로 넘긴다.
- **조합 중인 글자의 한자 변환은 된다.**
  `2026.2.3 · 2026-09-25 · 주인` ✅
- **선택 영역의 한자 변환은 글자가 사라진다.** IdeaVim 은 mouse 선택을 Visual mode 로 받고, 조합을 시작하며 선택이 지워지면 Visual 을 나온다.
  Insert 로 돌아가지 않으면 고른 한자는 Normal mode 명령으로 읽혀 버려진다.
  IdeaVim 을 쓰는 동안 선택 영역 변환은 쓸모가 없다 — 끄려면 `convertsEnteredText: false` 로 한다. 그러면 한글을 선택하고 누른 ⌥↩ 도 IntelliJ 로 간다.
  `2026.2.3 · 2026-09-25 · 주인 + source(IdeaVim IdeaSelectionControl)` 🔶
- **editor 는 JBR 이 넘긴 교체 범위를 무시한다** — IntelliJ 의 JBR TextInput listener 는 선택 요청을 speed search 에만 쓴다.
  확정한 단어를 재변환하면 단어가 사라지고 한자도 생기지 않았다.
  `2026.2.3 · 2026-09-25 · source(IdeEventQueue.kt handleSelectTextRangeEvent) + 주인` ✅
- 넘긴 key 마다 입력기에 `commitComposition` 이 곧바로 따라온다 — 조합이 비어 있을 때라 무해하다.
  `2026.2.3 · 2026-09-25 · 기록` ✅
- editor 의 press-and-hold 우회: 입력기가 선택 영역을 물을 때 문자 key(A–Z)가 눌려 있으면, 다음 확정 때 앞 글자를 선택해 덮어쓴다(`myNeedToSelectPreviousChar`).
  homi 로 조합하는 key 는 Java 에 KEY_PRESSED 로 가지 않으니 걸리지 않을 것이다 🔶.
  `source(EditorImpl.java)` ✅
- 조합 중인 글자를 문서가 아니라 inlay 로 그리는 모드가 있다 (registry `editor.input.method.inlay`).
  `source(EditorImpl.java)` ✅

## homi 의 우회

- ESC 영문 trigger (`AppRules`, `c08572b`).
- 고르는 key 는 marked text 가 있는 채로 — Enter 로 골라도 IntelliJ 가 Enter 를 받지 않게 한다 ([engines/jbr.md](engines/jbr.md), `c884edd`).

## 다시 확인할 것

- IdeaVim Insert mode 에서 한글 조합 중 ESC → Normal + 영문.
- 조합 중인 글자 + ⌥↩ → Enter 로 고르기 → 한자로 바뀌고 줄은 바뀌지 않는다.
- 조합도 선택도 없을 때 ⌥↩ → Show Context Actions 가 뜬다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 2026.2.3 | ESC 영문 trigger 추가 (`c08572b`) |
| 2026-09-25 | 2026.2.3 | 한자: 조합 중인 글자는 됨, 선택 영역은 IdeaVim 때문에, 확정한 단어는 editor 가 범위를 무시해서 안 됨 (`c884edd`) |
