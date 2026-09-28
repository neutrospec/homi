# Windows App

| | |
|---|---|
| bundle ID | `com.microsoft.rdc.macos` |
| 엔진 | — (원격 Windows 화면에 key 를 보낸다, RDP) |
| 확인한 version | 11.4.2 (3104) · 2026-09-27 · macOS 27.0 |
| homi 규칙 | 한/영 전환 없는 app (설정의 기본값) — 한/영 전환도 조합도 하지 않고, Caps Lock 도 원래대로 |

## 특징

- **원격 Windows 의 한/영은 Windows 가 맡는다** — homi 는 key 를 그대로 넘기고 원격 Windows 의 입력기가 조합한다. 전환 key 도 Windows 설정에서 정한다.
  `2026-09-27 · 주인` ✅
- **key 를 보내는 방식이 둘이다** (menu Connections → Keyboard Mode). **Scancode** 는 모든 key 를 그대로 보내고 입력기가 끼지 않는다 — 주인은 이것으로 쓴다.
  **Unicode** 는 특수 key 만 그대로 보내고, 나머지는 이 Mac 의 입력기에 넘겨(`inputContext.handleEvent`) 받은 글자를 보낸다 — 원격 화면(`MouseCursorView`)이 text input client 다.
  `11.4.2 · 2026-09-27 · disassemble + 기록` ✅
- **수식키는 어느 방식에서도 입력기에 넘기지 않는다** (`flagsChanged` 에 `handleEvent` 가 없다) — homi 의 Caps Lock·오른쪽 ⌘ 전환이 닿지 않는다.
  `11.4.2 · 2026-09-27 · disassemble + 기록` ✅
- **Unicode 방식에서는 영문도 원격에 나오지 않았다** — homi 는 key 를 넘겼고 Windows App 은 글자를 받아 갔다(key 마다 `commitComposition` 이 따라왔다). 막힌 곳은 모른다 🔶.
  `11.4.2 · 2026-09-27 · 주인 + 기록` ✅
- 이 Mac 의 keyboard layout 으로 원격에 keyboard 언어를 알린다 — `2SetHangul` 이면 한국어(0x0412), ABC 면 영어 (`Resources/Keyboard/LayoutMappings.xml`). homi 아래는 ABC 다.
  `11.4.2 · 2026-09-27 · app 의 resource` ✅ (원격 입력기에 미치는 영향 🔶)

## homi 의 우회

- 한/영 전환 없는 app (`Preferences.passThroughApps`, M7): key·수식키를 그대로 넘기고, 이 app 이 앞에 있는 동안 Caps Lock remap 을 푼다.

## 확인하는 법

- menu bar 표시가 `–` 다. Keyboard Mode 가 Scancode 이면 원격에서 친 한글이 원격의 입력기로 조합된다.
- Caps Lock 이 원격에 원래 Caps Lock 으로 간다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 11.4.2 | 원장을 시작함 — 늘 영문 규칙만 |
| 2026-09-25 | 11.4.2 | 늘 영문으로 시작 → 한/영 전환 없는 app 으로 (주인, M7) |
| 2026-09-27 | 11.4.2 | Unicode 방식으로 homi 가 조합하는 길을 조사함 — 수식키가 닿지 않고 영문도 나오지 않아 접음. 한/영은 Windows 설정의 일 (주인) |
