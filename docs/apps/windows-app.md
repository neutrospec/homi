# Windows App

| | |
|---|---|
| bundle ID | `com.microsoft.rdc.macos` |
| 엔진 | — (원격 Windows 화면에 key 를 보낸다) |
| 확인한 version | 11.4.2 (3104) · 2026-09-25 · macOS 27.0 — 규칙만 있고 homi 로 본 것은 없다 |
| homi 규칙 | 활성화될 때마다 영문으로 시작 |

## 특징

- **늘 영문으로 시작한다** — Hammerspoon 규칙에서 옮겼다. 원격 Windows 의 입력기가 한/영을 맡으므로 이쪽은 key 를 그대로 넘겨야 할 것이다 🔶.

## homi 의 우회

- `startsInEnglish` (`AppRules`, `c08572b`).

## 다시 확인할 것

- 한글 모드에서 Windows App 으로 → 영문으로 시작하고, 원격 쪽의 한/영 전환 key 가 그대로 간다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 11.4.2 | 원장을 시작함 — 늘 영문 규칙만 |
