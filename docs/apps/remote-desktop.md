# Remote Desktop

| | |
|---|---|
| bundle ID | `com.apple.RemoteDesktop` |
| 엔진 | — (원격 화면에 key 를 보낸다, `ScreenSharing.framework`) |
| 확인한 version | 3.10 (650.9.1) · 2026-09-26 · macOS 27.0 |
| homi 규칙 | `keyboardLayoutFollowsMode` — homi 의 한/영을 homi 아래의 keyboard layout 으로 알린다 (한 → `2SetHangul`, A → ABC). 원격은 두벌식에 둔다 |

## 특징

- **화면은 입력기가 만든 글자를 받지 않는다.** 화면(`SSFrameBufferView`)은 `keyDown:` 으로 key 를 직접 받아
  key code(`SSKeyboardEvent`)나 X11 keysym(`stSendX11Keysym:`)으로 원격에 보낸다. framework 에 `insertText`·`setMarkedText`·`interpretKeyEvents` 가 없다 —
  그래서 homi 가 조합해도 원격에는 영문 key 가 갔다.
  `3.10 · 2026-09-26 · 실험(ScreenSharing.framework 의 symbol 조사) + 주인` ✅
- **보낼 글자는 이 Mac 의 keyboard layout 이 정한다.** keysym 은 key code 를 지금의 keyboard layout(`TISCopyCurrentKeyboardLayoutInputSource`)으로 바꿔 만든다
  (`ConvertKeycodeToX11Keysym`, log 의 `KeyLayoutData size` — ABC 5032 byte, `2SetHangul` 2964 byte). `2SetHangul` 은 key 마다 자모를 하나 낸다(g → ㅎ).
  `3.10 · macOS 27.0 · 2026-09-26 · 실험(UCKeyTranslate + log)` ✅
- **key code 와 keysym:** 이 Mac 과 원격의 입력 소스 ID 가 같으면 key code, 다르면 keysym. homi 가 선택되어 있으면 원격에 homi 가 없으니 늘 keysym 이다.
  원격은 자기 입력 소스가 바뀔 때마다 ID 를 알려 온다 — log 는 ID 를 가리지만 길이는 남긴다(ABC 23, 두벌식 39).
  `3.10 · macOS 27.0 · 2026-09-25 · 실험(disassemble + Remote Desktop 의 log)` ✅
- **원격은 받은 글자를 자기 layout 에서 key 로 되돌려 치고, 없으면 글자 그대로 넣는다.** 원격의 `ScreensharingAgent` 는 keysym 을 지금의 layout 으로
  key code 로 되돌려 key event 를 만들고(`KeyMap.c` — `KeyMapDictionary_ConvertKeysym`, `CGEventCreateKeyboardEvent`), 그 layout 에 없는 글자는
  Unicode 글자로 넣는다(`CGEventKeyboardSetUnicodeString`). 그래서 원격이 **두벌식이면** 자모가 두벌식 key 로 되돌아가 원격 입력기가 한글로 조합하고,
  원격이 **ABC 면** 자모가 그대로 들어간다(풀어쓰기). 영문 글자는 원격이 두벌식이어도 영문으로 들어간다.
  `3.10 · macOS 27.0 · 2026-09-26 · 주인 + 받는 쪽 binary 의 import·문자열` ✅
- **"키보드 언어 동기화"(Sync Keyboard Language)는 이 Mac 의 입력 소스 ID 를 원격에 보내 원격이 정확히 그 ID 를 고르게 한다 — 하지만 Remote Desktop 에서는 켤 수 없다.**
  보내는 쪽 `RFBShareKeyboardSourceID` → `UpdateKeyboardInputSourceInfo`, 받는 쪽 `TISCopyInputSourceRefForInputSourceID` → `TISEnableInputSource` → `TISSelectInputSource`.
  이 flag 가 꺼져 있으면 log 에 `do not set keyboard source` 만 남는다. 원격 창의 nib 에 `키보드` 단추(설명 "키보드 언어 동기화")가 있지만
  toolbar delegate 의 기본·허용 목록에 없고 사용자화도 꺼져 있어, 늘 꺼져 있다.
  `3.10 · macOS 27.0 · 2026-09-26 · 실험(lldb disassemble, nib 해독) + 주인` ✅
- **Apple 입력기로 된 것도 layout 덕이다.** 이 Mac 을 ⌃Space 로 ABC ↔ 두벌식으로 바꾸면 원격의 입력 소스는 그대로인데 한/영이 바뀌었다 — 두벌식의 layout 이 자모를 보낸다.
  `3.10 · macOS 27.0 · 2026-09-26 · 주인 + Remote Desktop 의 log` ✅
- **homi 가 layout 만 바꿔도 Remote Desktop 은 곧바로 다시 읽는다.** `overrideKeyboardWithKeyboardNamed:` 로 바꾸면 선택된 입력 소스 변경 알림이 가서
  `local keyboard changed` → 새 `KeyLayoutData` (전환마다 ms 안). 창을 떠나면 ABC, 돌아오면 모드의 layout.
  `3.10 · macOS 27.0 · 2026-09-26 · Remote Desktop 의 log + 주인` ✅
- **이 Mac 의 Apple 한국어 입력기는 필요 없다.** `2SetHangul` layout 은 켜져 있지 않아도 `overrideKeyboardWithKeyboardNamed:` 로 쓸 수 있다 —
  Apple 한국어 입력기를 다시 끈 뒤에도 그대로 됐다.
  `3.10 · macOS 27.0 · 2026-09-26 · 주인` ✅
- 한글 모드(`2SetHangul`)에서 ABC 와 다른 글자: `` ` `` → ₩, ⌥+글자 → 평범한 글자 (Apple 두벌식과 같다). ⌘·⌃ 단축키는 같다.
  `2026-09-26 · 실험(UCKeyTranslate 로 두 layout 비교)` ✅

## homi 의 우회

- `AppProfile.keyboardLayoutFollowsMode` (`AppRules.swift`): activate 때와 모드가 바뀔 때 homi 아래의 layout 을 한 → `com.apple.keylayout.2SetHangul`,
  A → ABC 로 둔다 (`HomiInputController.followLayout`). 다른 app 은 activate 마다 ABC. 입력 소스는 바꾸지 않는다 (결정 1·4).
- **원격 Mac 은 두벌식에 둔다** — 한/영은 이쪽 homi 가 한다. 원격이 ABC 면 한글이 풀어쓰기로 들어간다: 한글은 원격 입력기만 조합할 수 있고,
  원격 입력기가 한글 key 를 받는 것은 원격이 두벌식일 때뿐이다. 이 Mac 에서 원격의 입력 소스를 바꿀 길은 없다(동기화를 켤 수 없다).
- 주인이 Remote Desktop 을 한/영 전환 없는 app 에 넣으면 homi 는 비켜서고 layout 도 ABC 다.

## 확인하는 법

- 원격을 두벌식에 두고: 한 → 한글 조합, A → 영문, 전환 즉시 (log 의 `KeyLayoutData size` 가 2964 ↔ 5032).
- Remote Desktop 을 떠나면 다른 app 의 영문·문장부호가 정상 (layout 이 새지 않는다).
- 원격을 ABC 로 두면 한글이 풀어쓰기 — 그대로면 "원격은 두벌식" 도 그대로.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 3.10 | 원장을 시작함 — 늘 영문 규칙만 |
| 2026-09-25 | 3.10 | 늘 영문으로 시작 → 한/영 전환 없는 app 으로 (주인, M7). 그때의 설명: "원격 Mac 의 한/영 상태가 중요할 뿐" |
| 2026-09-25 | 3.10 | homi 로 조합해도 원격은 영문 — 화면이 입력기 글자를 받지 않는다. "Sync Keyboard Language" 가 입력 소스 ID 를 원격에 맞춘다고 보고, Apple 입력기로 된 것도 그 덕이라 적었다 (틀림 — 아래) |
| 2026-09-25 | 3.10 | 이 Mac 에 Apple 두벌식을 다시 켜고 입력 소스를 두벌식 → ABC 로 바꿔 봄 — 동기화가 꺼져 있어 원격에 보내지 않았다 |
| 2026-09-26 | 3.10 | 동기화 단추가 Remote Desktop 에는 나오지 않는다 (주인 + nib·code 확인). 원격의 한/영은 원격 입력 소스가 아니라 이 Mac 의 layout 이 정한다 (주인 + log) |
| 2026-09-26 | 3.10 | 한/영 전환 없는 app → `keyboardLayoutFollowsMode`: homi 가 layout 을 모드대로 둔다. 주인 확인 — 원격이 두벌식이면 한/영 모두 되고, ABC 면 한글이 풀어쓰기 |
