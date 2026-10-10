# Windows App

| | |
|---|---|
| bundle ID | `com.microsoft.rdc.macos` |
| 엔진 | — (원격 Windows 화면에 key 를 보낸다, RDP) |
| 확인한 version | 입력 경로: 11.4.2 (3104) · 2026-09-27 · macOS 27.0. key 변환표·Caps Lock 전달: 11.4.3 (3115) · 2026-10-10 · macOS 27.0.1 |
| homi 규칙 | 기본은 한/영 전환 없는 app. 한/영 전환 설정에서 Windows 에 보낼 key 를 오른쪽 Alt·LANG1 중 선택 (현재 Caps Lock 만 지원). 오른쪽 Alt 는 주인 환경에서 정상 확인; LANG1 은 전환 실패 |

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

## Caps Lock 전달 실험 (2026-10-10)

주인 요청: 원격 Windows 가 조합과 한/영 상태를 맡되, homi 의 전환 key 를 원격의 한/영 key 로 전달하고 설정에서 고른다.
우선 **Caps Lock 만**, 기본값 꺼짐으로 준비했다. 오른쪽 ⌘·⌥ 의 단독 tap 은 IMK 밖의 별도 판별이 필요하므로 포함하지 않는다.

- 처음 설치한 시험본은 **Windows App 에서 Caps Lock 으로 한/영 전환** + 일반 Caps Lock 전환을 켠 동안, homi 가 선택된 Windows App 에서만 Caps Lock → LANG1.
  다른 app 은 기존 경로, ABC·옵션 꺼짐·Caps Lock 전환 꺼짐은 원래 mapping 으로 돌아간다. Windows App 안의 길게 누르기 대문자 고정은 없다.
- 이 옵션을 켜면 pass-through 목록에서 Windows App 을 빼도 homi 는 조합하거나 local mode 를 전환하지 않는다. mode 표시는 `–` 이며 원격 상태를 추측하지 않는다.
- [Apple 의 LANG1 정의](https://developer.apple.com/documentation/gamecontroller/gckeycode/lang1)는 Korean keyboard 의 한/영 key 이고 Japanese keyboard 의 Kana key 도 같다.
  **이 정의만으로 RDP 를 거친 103/106 한/영 key 전달을 보장할 수 없다.**
- **11.4.3 의 static 변환표**: Mac keyCode `104` → Scancode `0x70`, 오른쪽 ⌥ `61` → `0xe038`, Caps Lock `57` → `0x3a`.
  `KeycodeToScancodeTranslator.toScancode`·`translationTable`, `Keycode.rawValue`·`Scancode.rawValue` 의 disassemble + static data 대조 ✅.
  설치 당시 실제 원격 동작은 미검증이었다. 이후 주인 시험은 아래에 남겼다. 이 version 의 IMK 입력 경로를 다시 확인한 것은 아니다.
- 적용·복원은 기존 HID mapping 경로를 쓴다. global event tap·비동기 key 재전송·외부 driver 를 추가하지 않는다.
  mapping 의 수명·복원 제한은 [macOS 구조](../macos-input.md#homi-process-와-hid-mapping-의-수명)에 있다.

구현 확인: `swift build`·Debug/Release 전체 **173개 test** 통과. 옵션 범위·옛 설정 읽기·local 조합 억제·mapping 실패·소유 기록·재시작 복원을 검사했다.
2026-10-10 설치본의 CDHash 는 `46ffaf157e255b22d1dce94a5d5b9ae489e8d3b0` (자체 서명 유지).
설치 뒤 homi 선택·하위 ABC layout·옵션 꺼짐·실제 HID 의 Caps Lock → 오른쪽 Control 을 읽어 확인했다.
이것은 물리 key 입력·설정 창 표시·실제 Windows 연결의 통과를 뜻하지 않는다.

### 주인 시험과 target 재검토 (2026-10-10)

- **관측**: 옵션을 켠 뒤 Caps Lock 으로 대문자/소문자가 바뀌지 않지만 한/영도 전환되지 않았다 (주인).
  Caps Lock 의 원래 동작이 막혔다는 단서이며, 원격에 LANG1 이 도착했다는 증거는 아니다.
  이어서 원격 A/가 표시를 mouse 로 누르면 전환·한글·영문 입력이 모두 정상임을 확인했다 (주인).
  사용하는 keyboard 에는 물리 오른쪽 Option 이 없고 그 자리에 Menu key 가 있어, 앞서 요청한 오른쪽 Option 검사는 수행할 수 없다.
  Menu key 의 실제 HID usage 는 관찰하지 않았다. keycap 이나 위치만으로 오른쪽 Option 과 같다고 취급하지 않는다.
- **코드의 불일치**: homi 가 정한 것은 Mac HID 의 LANG1 이다. Windows App 의 위 변환표에는 `0x70` 이 있고,
  전용 한/영에 해당하는 `0x72` 는 없다. `Scancode.rawValue` 의 106개 값에도 `0x72` 가 없다.
  [Chromium 의 platform key 표](https://github.com/chromium/chromium/blob/863ae6f44a6d93d0aaa3674b0554f4a9298d5fd1/ui/events/keycodes/dom/dom_code_data.inc#L318)는
  Windows `0x70` 을 `KanaMode`, `0x72` 를 `Lang1` 로 구분한다. 같은 표에서 Mac LANG1 은 `0x68`(104)다.
  표 기준 commit `863ae6f` (2025-01-03), 2026-10-10 조회. **Mac LANG1 remap 을 Windows 103/106 한/영 key 와 동등하다고 취급할 수 없다.**
- **원인의 범위**: 이 불일치가 전환 실패를 설명할 유력한 근거다 🔶. 실제 원격의 수신 key·Scancode,
  현재 Keyboard Mode·Windows keyboard 종류는 이번 시험에서 관찰하지 못했다. Windows 설정 오류로 단정하지 않는다.
- **목표와 한계**: 목표는 103/106 keyboard 의 **별도 한/영 key** 전달이다 (주인 재확인). 위 static 변환표에는 그 target 이 없어,
  현재 HID → Mac keyCode → Windows App Scancode 경로에서 HID 목적지 번호만 고치는 방법으로 `0x72` 를 고를 수 없다.
  이것을 Windows App 의 모든 입력 경로에서 전용 key 지원이 불가능하다는 결론으로 확대하지 않는다.
- **오른쪽 Alt 후보의 구분**: 물리 오른쪽 Option 이 없어도 Caps Lock 을 HID 오른쪽 Option 으로 remap 하는 후보는 가능하다.
  [Microsoft 문서](https://learn.microsoft.com/en-us/windows-app/input-keyboard-mouse-touch-pen#keyboard-shortcuts-1)는 오른쪽 Option → Alt Gr 를 명시하며,
  [Korean IME 문서](https://learn.microsoft.com/en-us/globalization/input/korean-ime#type-korean-text)는 오른쪽 Alt 전환을 설명한다.
  103/106 전용 key 와 오른쪽 Alt 는 같은 key 가 아니며, 이 문서만으로 주인의 keyboard 종류에서 성공한다고 보장하지 않는다.
  [community 의 Karabiner 설정](https://gist.github.com/mungi/aecbb7a63ca18b3066764debb7eb2747)도 원격 app 에서는 오른쪽 Command → 오른쪽 Option 을 쓴다
  (2026-07-03 작성, 2026-10-10 source 조회). 전용 한/영 key 전달의 recipe 로 세지 않는다.
  이 후보를 전용 key 전달의 교정으로 취급하지 않는다. 기존 LANG1 target 을 조용히 바꾸거나 Windows 설정을 임의로 고치지 않는다.
- **전환 실패가 재발하면**: 원격의 실제 수신 key 와 현재 Korean keyboard 종류를 읽기 전용으로 확인한다.
  mouse 전환 정상은 IME 동작의 기준선이며 key 전달·keyboard 종류까지 증명한 것은 아니다.

### 목적지 선택 (2026-10-10)

주인 요청으로 Windows 에 보낼 key 의 선택을 추가했다. 현재 설정 위치는 **Windows App 의 한/영 전환 → Windows 에 보낼 key** 다.
**한/영 전환 key 를 Windows 에 보내기**를 켜고, **Mac 에서 누를 key**와 Windows 목적지를 나란한 항목으로 확인한다.
현재 지원하는 Mac key 는 Caps Lock 이며, 일반 한/영 전환 설정에서 꺼져 있으면 켜야 한다고 안내한다. 두 목적지를 구분해 고르며,
선택은 즉시 저장되고 다음 app·설정 알림에서 HID mapping 에 반영된다.

| 선택 | Mac HID 목적지 | Windows App 11.4.3 의 static 변환 | 원격 결과 |
|---|---|---|---|
| 오른쪽 Alt | 오른쪽 Option (`0x7000000e6`) | Mac `61` → `0xe038` | 주인 환경에서 한/영 전환·입력 정상 확인 (2026-10-10) |
| 한/영 key (실험) | LANG1 (`0x700000090`) | Mac `104` → `0x70` | 앞선 주인 시험에서 전환 실패. `0x72` 전용 한/영 전달과 같지 않다 |

- 물리 오른쪽 Option 이 없어도 Caps Lock 으로 보낼 수 있다. Menu key 는 바꾸지 않는다.
  homi 선택·일반 Caps Lock 전환·전달 옵션이 모두 켜진 Windows App 에만 적용한다.
- 기본값은 전달 꺼짐이다. 옛 설정의 켜짐과 LANG1 목적지는 유지해 target 을 조용히 바꾸지 않는다.
  새 목적지 값의 읽기에 실패해도 다른 설정을 초기화하지 않는다.
- 목적지 선택은 원격의 IME 상태를 가져오거나 local mode 를 전환하지 않는다. app 이나 ABC 로 나가면 기존 경로로 복원한다.
  Caps Lock 을 누른 채 app 을 옮긴 경우의 양쪽 key 해제는 별도 실관측이 필요하다.
- 검증: 오른쪽 Alt 목적지·쓰기 실패에 관한 2개 test 를 먼저 실패시킨 뒤 교정했다.
  목적지 변경·실패 재시도·wake·기존 LANG1 기록·새 process 복원·다른 도구의 mapping 보존과 설정 round-trip 을 검사했다.
  `swift build`·Debug/Release 전체 **178개 test** 통과. 이 검사는 실제 원격 동작의 증거와 구분한다.
- 실제 설정 view 를 memory 의 test 설정으로 띄워 오른쪽 Alt·한/영 key 선택 상태와 설명을 각각 그려 확인했다
  (`build/windows-settings-right-alt.png`·`windows-settings-hangul.png`). 별도 preview process 이며 실제 homi 의 설정을 바꾸는 검사는 아니다.
- 13:20 KST 에 자체 인증서 `homi code signing` 으로 서명·설치했다. CDHash `309f24f5076b542743e59b94f2ad6334723c0bf9`,
  UUID `D67D8498-DA44-3B56-8C03-069C11D314D4`. 설치 당시 기존 켜짐·LANG1 선택은 유지했다.
  설치 뒤 새 process 실행·homi 선택·일반 app 의 Caps Lock → 오른쪽 Control mapping 을 읽어 확인했다.
- **실제 원격 확인**: 설치 뒤 주인이 오른쪽 Alt 를 선택하고 “완벽하게 동작해”라고 보고했다.
  Caps Lock 으로 원격 한/영 전환·입력이 정상 동작한 사용자 검증이다 ✅. 저장된 설정도 전달 켜짐·`rightAlt` 임을 읽어 확인했다.
  현재 Windows 설정에서의 성공이며, 다른 keyboard 종류나 전용 한/영 key 전달까지 확인한 것은 아니다.
- **설정 문구·배치 정리**: Mac 의 전환 key 와 Windows App 의 전환을 별도 section 으로 나누고, 누를 key·보낼 key 를 명시했다.
  실제 설정 view 의 오른쪽 Alt·한/영 key·옵션 꺼짐·Caps Lock 꺼짐 표시를 preview process 로 확인했다
  (`build/windows-settings-layout-*.png`). `swift build`·Debug 전체 **178개 test** 통과, Release build·서명·설치 완료.
  13:48 KST 설치본의 CDHash `de243ec81f0f85b0d84c6520192e6aa068b62cfa`, UUID `B57B066A-6F98-3122-BF8B-65DA0A7BF3EB`.
  새 process 실행과 저장된 켜짐·`rightAlt` 유지를 확인했다. 이번 변경은 표시만 정리했으며 원격 입력 시험을 다시 수행한 것은 아니다.

남은 실사용 검증: Mac 의 다른 app·ABC 로 나간 뒤 Caps Lock 의 기존 동작, Caps Lock 을 누른 채 app 을 옮겼을 때
양쪽 key 해제, wake·crash 뒤 복원과 장기 사용을 확인한다. 이번 정상 동작 보고를 이 경계들의 통과로 확대하지 않는다.
실패하면 원격의 실제 key·Scancode 를 먼저 관찰한다. `0x70` 을 전용 한/영 key 로 단정하거나 오른쪽 Alt 로 몰래 대체하지 않는다.

### 전환 key 일반화 검토 (2026-10-10)

주인이 의도한 설정은 **Mac 에서 선택한 한/영 전환 key → Windows 에 보낼 key** 다.
Shift+Space 를 전환 key 로 쓰는 경우에도 같은 목적지(예: 오른쪽 Alt)로 보내는 것이 이 의미에 맞는다.
현재 Caps Lock 만 지원하는 것은 구현 범위이며, 다른 전환 key 를 지원할 수 없다는 제약이 아니다. UI 문구 정리만으로 이 요구를 구현한 것은 아니다.

- **현재 경로**: `CapsLockRoute`·`CapsLockMapping` 은 Caps Lock 하나의 HID usage 를 바꾼다.
  `AppRules` 는 Windows 전달 옵션을 켜면 local 조합·전환을 억제한다. IMK 의 `Session` 에 Shift+Space 분기를 더하는 것만으로 Scancode 경로를 처리할 수 없다.
  [Microsoft 문서](https://learn.microsoft.com/en-us/windows-app/input-keyboard-mouse-touch-pen?tabs=macos#keyboard-modes)는
  Scancode 의 key 누름·뗌 전달과 Unicode 의 local IME 사용을 구분한다 (2026-10-10 조회). app 내부 경로를 관측한 version 은 위 특징을 따른다.
- **후보** 🔶: Windows App 이 앞에 있고 homi 와 옵션이 선택된 동안, 입력기 앞의 key event 경로에서 전환 gesture 를 판정해 변환한다.
  [Apple 의 active event tap callback](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback?language=objc)은 event 수정·교체·제거를 지원하며,
  [tapPostEvent](https://developer.apple.com/documentation/coregraphics/cgevent/tappostevent(_:))는 callback 의 event 앞에 새 event 를 넣는다
  (2026-10-10 조회). API 가능성과 실제 Windows App 의 수신·원격 전환 성공은 구분한다. 제품에는 아직 추가하지 않았다.
- **검증 순서**: 별도 probe 로 Shift+Space → 오른쪽 Alt 를 먼저 확인한다. Space 유출·repeat 중 중복 전환·Shift 해제·전환 직후 첫 글자,
  누른 채 app·source 를 옮긴 경우, 변환 경로 사용 불가 시 원래 key 전달을 검사한다.
  오른쪽 ⌘·⌥ 는 단독 tap 과 ⌘C·⌘Tab·⌥+key 를 구분해 기존 단축키를 보존해야 한다. 단순한 전체 key remap 으로 대체하지 않는다.
  기본 입력과 기존 Caps Lock 성공 경로를 회귀시키면서까지 일반화하지 않는다.

## 확인하는 법

- menu bar 표시가 `–` 다. Keyboard Mode 가 Scancode 이면 원격에서 친 한글이 원격의 입력기로 조합된다.
- 전달 옵션을 끄면 Caps Lock 이 원격에 원래 Caps Lock 으로 간다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 11.4.2 | 원장을 시작함 — 늘 영문 규칙만 |
| 2026-09-25 | 11.4.2 | 늘 영문으로 시작 → 한/영 전환 없는 app 으로 (주인, M7) |
| 2026-09-27 | 11.4.2 | Unicode 방식으로 homi 가 조합하는 길을 조사함 — 수식키가 닿지 않고 영문도 나오지 않아 접음. 한/영은 Windows 설정의 일 (주인) |
| 2026-10-10 | 11.4.3 | Caps Lock 전달 옵션 준비·static key 변환표 확인. 실제 원격 동작은 미검증 |
| 2026-10-10 | 11.4.3 | 주인 시험에서 Caps Lock 대문자 고정·한/영 전환 모두 안 됨. LANG1 → KanaMode 와 전용 한/영의 차이를 확인; 실제 수신 key 는 미관측 |
| 2026-10-10 | 11.4.3 | 주인 요청으로 오른쪽 Alt·한/영 key 목적지 선택을 추가·설치. 178개 test·설정 view 확인; 오른쪽 Alt 원격 결과는 미검증 |
| 2026-10-10 | 11.4.3 | 주인이 오른쪽 Alt 를 선택해 원격 한/영 전환·입력 정상 확인. 저장된 전달 켜짐·rightAlt 선택도 확인 |
| 2026-10-10 | 11.4.3 | 설정을 Mac 전환 key 와 Windows App 의 전환으로 나눔. 누를 key·보낼 key 와 현재 Caps Lock 지원 범위를 명시 |
