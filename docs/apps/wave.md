# Wave

| | |
|---|---|
| bundle ID | `dev.commandline.waveterm` |
| 엔진 | Chromium (Electron) → [engines/chromium.md](engines/chromium.md). terminal 은 xterm.js 다 |
| 확인한 version | 0.14.5 · 2026-09-25 · macOS 27.0 |
| homi 규칙 | ESC → 영문, 한자는 조합 중인 글자만 |

## 특징

- **ESC 는 영문 전환 trigger** — Hammerspoon 규칙에서 옮겼다.
  `2026-09-25 · 주인 요청` ✅
- **terminal 이다** — 보낸 글자는 고칠 수 없다. 한자는 조합 중인 글자만 바꾼다.
- CJK input source 가 켜져 있으면 macOS 의 "space 두 번 → 마침표" 가 xterm.js terminal 에 `. ` 로 샌다고 한다.
  `조사` 🔶 (homi 로는 보지 않았다)

## homi 의 우회

- ESC 영문 trigger, `convertsEnteredText: false` (`AppRules`, `c08572b`·`c884edd`). Chromium 규칙 (`7e4c1fd`).
- 조합 중 Enter·ESC 다시 보내기는 없다 — xterm.js 가 그 key 를 잃는지 아직 모른다 🔶.

## 다시 확인할 것

- 조합 중 ESC·Enter → 확정된 뒤 key 도 terminal 에 간다. 잃으면 다시 보내기 규칙이 필요하다.
- 조합 중인 글자 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 0.14.5 | 원장을 시작함 — 규칙은 Hammerspoon 에서 옮긴 ESC 와 terminal 한자 제한 |
