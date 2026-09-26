# Windows App

| | |
|---|---|
| bundle ID | `com.microsoft.rdc.macos` |
| 엔진 | — (원격 Windows 화면에 key 를 보낸다) |
| 확인한 version | 11.4.2 (3104) · 2026-09-25 · macOS 27.0 — 규칙만 있고 homi 로 본 것은 없다 |
| homi 규칙 | 한/영 전환 없는 app (설정의 기본값) — 한/영 전환도 조합도 하지 않고, Caps Lock 도 원래대로 |

## 특징

- **원격 Windows 의 한/영 상태가 중요할 뿐, 이쪽의 한/영 전환은 필요 없다** — homi 는 한/영 전환도 조합도 하지 않고 key 를 그대로 넘기고, 원격 Windows 의 입력기가 한/영을 맡는다.
  `2026-09-25 · 주인` ✅
- 처음에는 Hammerspoon 규칙대로 "늘 영문으로 시작" 이었다.

## homi 의 우회

- 한/영 전환 없는 app (`Preferences.passThroughApps`, M7): key·수식키를 그대로 넘기고, 이 app 이 앞에 있는 동안 Caps Lock remap 을 푼다.

## 확인하는 법

- 이 app 에서 menu bar 표시가 `–` 다. 원격 쪽에서 친 한글이 원격의 입력기로 조합된다.
- Caps Lock 이 원격 쪽에서 원래 Caps Lock 으로 동작한다. 오른쪽 ⌘·⌥ 와 Shift+Space 가 원격으로 그대로 간다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 11.4.2 | 원장을 시작함 — 늘 영문 규칙만 |
| 2026-09-25 | 11.4.2 | 늘 영문으로 시작 → 한/영 전환 없는 app 으로 (주인, M7) |
