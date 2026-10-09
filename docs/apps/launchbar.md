# LaunchBar

| | |
|---|---|
| bundle ID | `at.obdev.LaunchBar` |
| 엔진 | AppKit 🔶 |
| 확인한 version | 6.24 (6297) · 2026-09-25 · macOS 27.0 |
| homi 규칙 | 새 입력 시작마다 영문. 같은 입력 event 의 재활성화는 mode 유지 |

## 특징

- **늘 영문으로 시작해야 한다** — app 이름과 명령을 친다. Hammerspoon 규칙에서 옮겼다.
  주인 확인: 늘 영문으로 잘 시작한다.
  `6.24 · 2026-09-25 · 주인` ✅
- 모든 창이 같은 bundle ID 다.
  `조사` ✅

## homi 의 우회

- `startsInEnglish` — `ModeActivation` 이 실제 client ID 또는 그 cache 로 새 시작을 판정한 경계에서 `ModeMemory.activate` 를 한 번 적용한다.
  같은 event 의 재활성화는 조합·mode 를 유지한다. client ID 가 늦는 경우와 명시적 종료의 제한은 [교훈](../lessons.md#재활성화가-mode-를-reset-하고-실제-client-의-시작-규칙을-놓친다-2026-10-09)에 있다.
  순수 coordinator test 는 통과했으며 이번 수정본의 실제 LaunchBar 재호출 확인은 아직 남아 있다(2026-10-09).

## 확인하는 법

- 한글 모드에서 LaunchBar 를 불러 → 영문으로 시작한다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 6.24 | 늘 영문으로 시작 (`c08572b`), 주인 확인 |
