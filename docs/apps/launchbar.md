# LaunchBar

| | |
|---|---|
| bundle ID | `at.obdev.LaunchBar` |
| 엔진 | AppKit 🔶 |
| 확인한 version | 6.24 (6297) · 2026-09-25 · macOS 27.0 |
| homi 규칙 | 활성화될 때마다 영문으로 시작 |

## 특징

- **늘 영문으로 시작해야 한다** — app 이름과 명령을 친다. Hammerspoon 규칙에서 옮겼다.
  주인 확인: 늘 영문으로 잘 시작한다.
  `6.24 · 2026-09-25 · 주인` ✅
- 모든 창이 같은 bundle ID 다.
  `조사` ✅

## homi 의 우회

- `startsInEnglish` — 활성화될 때마다 `ModeMemory.activate` 가 영문으로 되돌린다 (`AppRules`, `c08572b`).

## 확인하는 법

- 한글 모드에서 LaunchBar 를 불러 → 영문으로 시작한다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 6.24 | 늘 영문으로 시작 (`c08572b`), 주인 확인 |
