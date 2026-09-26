# iTerm2

| | |
|---|---|
| bundle ID | `com.googlecode.iterm2` |
| 엔진 | 자체 (`PTYTextView`, `iTermKeyboardHandler`) |
| 확인한 version | 3.6.10 · 2026-09-25 · macOS 27.0 |
| homi 규칙 | ESC → 영문, 조합 중 Return·keypad Enter·ESC·Tab 다시 보내기, 한자는 조합 중인 글자만 |

## 특징

- **입력기의 YES(먹었다)를 보지 않는다** (기본 설정). key 를 스스로 처리하지 않는 경우는 셋뿐이다 —
  ① 이 key 전에 조합 중이었다 ② 입력기가 1글자 이상 `insertText` 했다 ③ 처리 뒤에 marked text 가 남았다.
  조합도 글자도 없이 먹은 key 는 terminal 로 간다. 입력기의 YES 는 실험 설정(`experimentalKeyHandling`)에서만 본다.
  `source(iTermKeyboardHandler.m shouldPassPostCocoaEventToDelegate, insertText)` ✅
- **조합 중에 누른 Enter·ESC 는 음절 확정에 쓰이고 key 는 사라진다** — vim 에 ESC 를 두 번 눌러야 했다 (Apple 입력기 때부터).
  `조사(gureum#1)` ✅ · 다시 보내기로 ESC 한 번: `3.6.10 · 2026-09-25 · 주인` ✅
- **조합 중이 아니면 Ctrl key 를 입력기에 보여주지 않는다** — Ctrl-B·Ctrl-A trigger 가 Ghostty 에만 있는 까닭이다.
  `조사` ✅
- **`insertText("")` 는 "글자 없음" 으로 다룬다** — 빈 확정으로는 key 를 먹을 수 없다.
  `source` ✅

## homi 의 우회

- terminal 규칙: ESC 영문 trigger, 조합 중 Return·keypad Enter·ESC·Tab 은 확정 → 먹고 → 다시 보낸다, `convertsEnteredText: false`
  (`AppRules`, `c08572b`·`c884edd`).
- 전환 key 는 수식키(Caps Lock → 오른쪽 Control, 오른쪽 ⌘)다 — 글자 없이 먹은 key 가 새지 않게 (`c08572b`).

## 확인하는 법

- vim insert mode 에서 한글 조합 중 ESC 한 번 → Normal + 영문.
- 조합 중 Enter → 확정 + 명령 실행.
- Caps Lock·오른쪽 ⌘ 전환 때 terminal 에 아무 글자도 새지 않는다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 3.6.10 | 조합 중 Enter·ESC·Tab 다시 보내기, 수식키 전환 (`c08572b`) |
