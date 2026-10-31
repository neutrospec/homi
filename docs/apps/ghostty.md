# Ghostty

| | |
|---|---|
| bundle ID | `com.mitchellh.ghostty` |
| 엔진 | 자체 (`SurfaceView_AppKit.swift`) |
| 확인한 version | 조합·한자: 1.3.1 (15212) · 2026-09-25 · macOS 27.0. Caps 진단: 1.4.0 (18457) · 2026-10-29 · macOS 27.2 |
| homi 규칙 | ESC·Ctrl-B·Ctrl-A(Ctrl 단독) → 영문, 조합 중 Return·keypad Enter·ESC·Tab 다시 보내기, 한자는 조합 중인 글자만 |

## 특징

- **입력기의 YES 를 보지 않는다.** key 를 스스로 처리하지 않는 경우는 셋이다 —
  ① 이 key 전에 조합 중이었다 ② 입력기가 비지 않은 글자를 `insertText` 했다 ③ key 처리 중에 keyboard layout 이 바뀌었다.
  ①이면 확정 글자만 보내고 화살표 말고는 key 를 버린다 — 조합 중 ESC·Enter 가 사라지는 까닭이다.
  `source(SurfaceView_AppKit.keyDown, String.keyEventText)` ✅
- **key 처리 중에 input source 가 바뀌면 그 key 를 버린다** — homi 가 key 처리 중에 TIS 를 건드리지 않는 까닭이다 (결정 4).
  `source` ✅
- **글자 없이 먹은 key 가 샌다** — Caps Lock 을 F18 로 받았을 때 F18 의 문자 U+F715 가 들어갔다. marked text 를 세웠다 지우는 신호도 통하지 않았다.
  `2026-09-25 · 주인` ✅
- **terminal 의 선택을 입력기에 선택 영역으로 알려 준다** — `selectedRange` 는 화면의 선택이고, `attributedSubstring` 은 요청한 범위와 상관없이 선택된 글자를 돌려준다.
  `source` ✅
- **`markedRange` 는 `{0, 글자 수}`(위치는 늘 0)이고 `validAttributesForMarkedText` 는 빈 목록이다.**
  `source` ✅
- 조합 중에 수식키(Caps Lock·오른쪽 ⌘)로 전환하면, 확정된 마지막 글자가 선택된 것처럼 보이다가 다음 key 에 사라진다. 글자는 맞게 들어간다(`한a`).
  `2026-09-25 · 주인` ✅ (까닭 🔶 — flagsChanged 처리 중에 확정한 것을 다시 그리는 문제로 본다)

## homi 의 우회

- ESC·Ctrl-B·Ctrl-A(tmux prefix) 영문 trigger, 조합 중 Return·keypad Enter·ESC·Tab 다시 보내기, `convertsEnteredText: false`
  (`AppRules`, `c08572b`·`c884edd`).
- 전환 key 는 수식키다 (`c08572b`).

## 확인하는 법

2026-10-31 15:23 homi 교정본은 [resend 를 원래 process 로 전달](../macos-input.md#key-다시-보내기)한다.
설치된 Ghostty 는 **1.4.0**, macOS **27.2**다. 주인은 Telegram 과 terminal 쪽 모두 정상이라고 답했다.
질문이 Ghostty/iTerm2 를 함께 다뤘으므로 개별 terminal 의 통과로 확대하지 않는다. 범위는 [공통 기록](../macos-input.md#key-다시-보내기)을 따른다.

- vim 에서 조합 중 ESC 한 번 → Normal + 영문. tmux 에서 Ctrl-B → 영문.
- Caps Lock·오른쪽 ⌘ 전환 때 글자가 새지 않는다.
- 조합 중 전환의 화면 문제가 아직 있는가.
- 한글 출력을 선택하고 ⌥↩ → 아무것도 바뀌지 않는다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 1.3.1 | F18 이 샘 → 수식키 전환, 조합 중 Enter·ESC·Tab 다시 보내기 (`c08572b`) |
| 2026-09-25 | 1.3.1 | 선택 영역을 한자 변환에서 뺌 — 선택은 출력이다 (`c884edd`) |
| 2026-10-29 | 1.4.0 | Caps 단독 비교에서 Quartz 와 IMK 의 timestamp 불일치 확인. [전달 구조 관측](../macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29). app 우회 추가 없음 |
