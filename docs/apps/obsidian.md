# Obsidian

| | |
|---|---|
| bundle ID | `md.obsidian` |
| 엔진 | Chromium (Electron) → [engines/chromium.md](engines/chromium.md). editor 는 CodeMirror 6 이다 🔶 |
| 확인한 version | 1.13.7 · 2026-09-25 · macOS 27.0 |
| homi 규칙 | ESC → 영문 |

## 특징

- **ESC 는 영문 전환 trigger** — Hammerspoon 규칙에서 옮겼다.
  `2026-09-25 · 주인 요청` ✅
- Obsidian 에만 있는 관측은 아직 없다. 엔진의 사실(click 확정, Apple 방식 한자 없음)을 따른다.

## homi 의 우회

- ESC 영문 trigger (`AppRules`, `c08572b`). Chromium 규칙 (`7e4c1fd`).

## 확인하는 법

- 조합 중 ESC → 확정 + 영문.
- 조합 중 click → 음절이 한 번만 남는다.
- 조합 중인 글자·선택한 한글 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 1.13.7 | 원장을 시작함 — 규칙만 있고 고유한 관측은 없다 |
