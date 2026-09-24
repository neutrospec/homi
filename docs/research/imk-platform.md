# 조사: IMK platform 구조 (2026-09-25)

조사 agent 가 macOS 입력기 13개의 source·issue 와 주인의 Mac(macOS 27.0 26A428, Swift 6.4)을 직접 확인한 결과를 추렸다.
표기: ✅ source·local 로 확인 / 🔶 불확실. 출처의 약칭은 GitHub repo 다.

**가장 가까운 선행 사례** — "입력기 하나가 안에서 한/영" 을 이미 하는 한국어 입력기 셋:
`hiking90/ongeul` (가장 가깝다. `design/32-hid-capslock-press-duration.md`, `OngeulApp/Sources/*`),
`Meapri/PriType-Swift` (`Docs/UnifiedInputArchitecture.md`), `kiding/SokIM`. 그 밖에 `gureum/gureum`, `rime/squirrel`,
`mtgto/macSKK`, `azooKey/azooKey-Desktop`, `fcitx-contrib/fcitx5-macos`, `vChewing`, `qwertyyb/Fire`, `google/mozc`.

## 1. bundle 과 등록

- `IMKServer(name:bundleIdentifier:)` 가 Info.plist 에서 controller class 이름을 읽는다. Swift class 는
  `"Module.Class"` 로 쓰거나 `@objc(Name)` 으로 이름을 고정한다. 둘 다 쓰인다 (squirrel·fire·ongeul 은 전자, gureum·macskk 는 후자). ✅ local `NSClassFromString`
- `InputMethodServerDelegateClass` 는 생략 가능. ✅ (macskk·azookey·fcitx·SokIM)
- `ComponentInputModeDict` 의 각 mode key 가 `setValue:forTag:`(tag `'imim'`)로 오는 값이고, `selectInputMode:` 의 인자다. ✅ `TextServices.h`, `IMKInputSession.h`
- Apple 의 한국어 입력기는 이제 `.appex`(extension point `com.apple.textinputmethod-services`)로 나온다. 제3자 입력기는 모두 여전히 `.app`. ✅ local
- `LSUIElement` 와 `LSBackgroundOnly` 둘 다 동작한다. ✅
- **ASCII-capable 을 정하는 plist key 는 문서에 없다.** Apple 일본어 입력기의 Roman mode(`com.apple.inputmethod.Roman` key, `en`, `smRoman`)는 true, 한국어 두벌식(`smKorean`)은 false. 우리 mode 는 등록 후 `tis list` 의 A 로 확인한다. 🔶
- **비밀번호 칸**: AppKit 은 칸을 Roman source 로 제한할 수 있다. 영문으로 등록된 mode 는 secure field 에서도 살아서 key 를 받고, ko·zh mode 면 system 이 ABC 로 대체한다 (fcitx PR #46·#254, gureum#893). ✅
  → 영문 mode 를 노출하면 그 mode 는 완전 통과여야 하고 `IsSecureEventInputEnabled()` 를 확인해야 한다.
- `TICapsLockLanguageSwitchCapable` 을 선언하면 system 의 "Caps Lock ↔ ABC" 전환에 끼게 된다. Caps Lock 을 직접 다루려면 선언하지 않는다. ✅

최소 두 mode plist (M0 참고):

```xml
<key>InputMethodConnectionName</key><string>dev.me.inputmethod.Han_Connection</string>
<key>InputMethodServerControllerClass</key><string>HanIME.InputController</string>
<key>TISInputSourceID</key><string>dev.me.inputmethod.Han</string>
<key>TISIntendedLanguage</key><string>ko</string>
<key>tsInputMethodIconFileKey</key><string>icon.tiff</string>
<key>tsInputMethodCharacterRepertoireKey</key><array><string>Hang</string><string>Latn</string></array>
<key>LSUIElement</key><true/>
<key>ComponentInputModeDict</key><dict><key>tsInputModeListKey</key><dict>
 <key>dev.me.inputmethod.Han.Korean</key><dict>
  <key>TISInputSourceID</key><string>dev.me.inputmethod.Han.Korean</string>
  <key>TISIntendedLanguage</key><string>ko</string><key>tsInputModeScriptKey</key><string>smKorean</string>
  <key>tsInputModePrimaryInScriptKey</key><true/><key>tsInputModeIsVisibleKey</key><true/>
  <key>tsInputModeDefaultStateKey</key><true/><key>tsInputModeMenuIconFileKey</key><string>ko.tiff</string>
  <key>TISIconIsTemplate</key><true/></dict>
 <key>com.apple.inputmethod.Roman</key><dict>  <!-- Kotoeri·mozc·azookey 의 관례 -->
  <key>TISInputSourceID</key><string>dev.me.inputmethod.Han.Roman</string>
  <key>TISIntendedLanguage</key><string>en</string><key>tsInputModeScriptKey</key><string>smRoman</string>
  …같은 key…</dict></dict>
 <key>tsVisibleInputModeOrderedArrayKey</key><array><string>dev.me.inputmethod.Han.Korean</string><string>com.apple.inputmethod.Roman</string></array></dict>
```

## 2. 개발 loop

- 재build loop: build → bundle 조립 → `codesign --force --sign -` → bundle 교체 → `killall <exe>`. 다음 입력 때 IMK 가 다시 띄운다. ✅ (gureum `tools/install_debug.sh`, macskk `build_restart.sh`, ongeul `scripts/install.sh`)
- **첫 등록은 logout 없이 믿을 수 없다.** vchewing 은 `TISRegisterInputSource` → `killall TextInputMenuAgent` → 0.5초 → `TISEnableInputSource`. ongeul·PriType·squirrel 은 첫 설치 뒤 logout 을 안내한다. ✅
  - 주인과 같은 build(27.0 26A428)에서 register+enable 이 0 을 돌려줬는데 parent 가 꺼진 채였고 `TISSelectInputSource` 가 -50 (qingjian#209). ✅
  - mode 는 parent input method 가 enable 된 뒤에만 enable 된다 — parent 먼저. ✅ TIS header
  - `ComponentInputModeDict` 를 바꾸면 logout + input source 제거·재추가가 필요할 수 있다 (fcitx PR #46). ✅
  - **`imklaunchagent` 는 절대 죽이지 않는다** — 실행 중인 app 들이 재시작 전까지 모든 입력기를 잃는다 (vchewing). ✅
- ~/Library/Input Methods 의 입력기는 Secure Keyboard Entry 가 켜져 있으면(Terminal·iTerm2) 회색으로 비활성된다 (macOS 15.4.1, macskk#351). /Library/Input Methods 면 괜찮다. ✅
  주인 환경(2026-09-25): Terminal 꺼짐, iTerm2·Ghostty 기본값. Ghostty 는 비밀번호 prompt 를 감지하면 secure input 을 자동으로 켠다.
- 같은 bundle ID·connection 이름의 다른 사본을 지운다 (vchewing, PriType 은 `lsregister -u`). ✅
- **서명과 TCC**: IMK 자체는 TCC 권한이 필요 없다. ad-hoc 서명의 designated requirement 는 cdhash 라, build 마다 손쉬운 사용·입력 모니터링 허가가 풀린다. PriType 은 Apple Development 또는 자체 서명 인증서를 쓴다. ✅ 주인의 Mac 에는 서명 신원이 0개.
- sandbox 는 쓰지 않는다 (mach-register 예외 필요, sandbox 안의 `TISSelectInputSource` 는 icon 만 바꾼다). ✅
- **macOS 26 변경**: 다른 process 가 input source 를 바꿀 때 `deactivateServer` 가 오지 않는다. squirrel#1140 은 `kTISNotifySelectedKeyboardInputSourceChanged` 를 듣는다. ✅
- SwiftPM 만으로 build 하는 입력기가 있다: `yihyunjoon/yido`(한국어, `scripts/package.sh`·`install.sh`), PriType `install.sh`, vchewing `swift package bundle-apps`. ✅
  Swift 6 concurrency: macskk 처럼 `nonisolated override` + `MainActor.assumeIsolated`. ✅

## 3. menu bar 표시 vs 내부 모드

- **우리 NSStatusItem, `selectInputMode` 안 씀**: squirrel(Ａ/中), fcitx, fire(中/英), SokIM. ✅
- **`selectMode` + `setValue:forTag:`**: gureum, macskk, azookey, mozc, ongeul, PriType. ✅
- **`selectInputMode` 의 비용 (ongeul PR #5 측정)**: 호출 직후 IMK 가 key 전달을 멈춰 첫 key 가 ~313–354ms (평소 5–10ms). ✅
  - ongeul 의 대응: key 가 0.6초 없을 때만 호출, `deactivateServer` 에서 flush, `setValue`·`activateServer` 에서 취소.
  - Chromium app 에서는 IMK session 을 부수고 다시 만든다(deactivate→activate). `activateServer` 에서 부르자 ~10Hz loop 와 key 유실. ✅ / 다른 app 🔶
- echo 와 stale: ongeul 은 같은 mode 의 echo 를 무시하고, `tisDirty` flag 로 낡은 system mode 가 새 전환·앱별 기억을 덮지 못하게 한다. ✅
  azookey#340 (macOS 27 beta): 외부에서 mode 를 바꾸자 menu bar 는 바뀌고 입력은 수 초간 옛 mode. ✅
- `setValue` 는 focus 가 바뀔 때도 온다. 거기서 client 를 비동기로 만지면 문제(macskk#112), 동기 HUD 는 rainbow cursor(macskk#336). ✅
- cursor 옆 system 표시는 system input source 를 따라간다 — mode 를 노출해야 뜬다 (ongeul#6). ✅
- "문서의 입력 소스로 자동 전환"(`TextInputGlobalPropertyPerContextInput`)은 주인 Mac 에서 켜져 있다. mode 둘이면 문서마다 mode 를 되돌려 우리 기억과 다툴 것이다. 🔶
- **앱별 기억의 위험**: activate/deactivate 순서가 고정이 아니다(fire), `activateServer` 가 안 올 수 있다(fcitx), fullscreen·Spaces 에서 뒤바뀌거나 빠진다(ongeul PR #20), bundle ID 가 nil 이거나 `com.apple.LocalAuthenticationRemoteService` 같은 원격 service 다(fcitx#422). ✅

## 4. 전환 키 받기

### Caps Lock

- flagsChanged 는 `recognizedEvents` 에 넣어야 온다(기본은 keyDown 만). lock 상태가 바뀔 때만 오고 누른 시간은 모른다. ✅
- system 옵션은 global domain 의 `TISRomanSwitchState` (없으면 켜짐으로 간주, gureum). 주인 Mac 에는 없다. macOS 27 에 `TISSetRomanSwitchState` 가 있으므로 `defaults write` 보다 System Settings 에서 끈다. 🔶
- gureum 방식: IOHIDManager 로 Caps Lock 을 직접 보고(입력 모니터링 권한), 0.5초 안에 떼면 lock 을 원래대로 되돌린다. open issue #745·#760·#570. ✅
- IOKit 으로 lock 되돌리기는 27 에서도 된다 (unsandboxed, TCC 없이 Get 확인. Set 은 ongeul 이 26.3 에서 측정). SokIM 은 Sonoma+ 의 cursor 옆 Caps Lock bubble 을 막으려고 200ms 동안 10번 끈다. ✅

```swift
import IOKit, IOKit.hidsystem
func setCapsLock(_ on: Bool) {
  let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass)); defer { IOObjectRelease(s) }
  var c: io_connect_t = 0
  guard IOServiceOpen(s, mach_task_self_, UInt32(kIOHIDParamConnectType), &c) == KERN_SUCCESS else { return }
  defer { IOServiceClose(c) }
  _ = IOHIDSetModifierLockState(c, Int32(kIOHIDCapsLockState), on) // echo flagsChanged 1번이 온다 — 걸러야 한다
}
```

- Apple keyboard 는 Caps Lock 에 ~100–250ms activation delay 를 두고 짧은 tap 을 무시한다. `CapsLockDelayOverride` (IOHIDProperties.h) 로 끌 수 있으나 재부팅하면 풀린다. ✅
- **(A) flagsChanged + IOKit 되돌리기** 의 실패 양상: delay, echo, LED 깜빡임·bubble, text client 가 없으면 못 받음(저장 dialog·Launchpad), IME 밖에서 lock 이 바뀌면 어긋남.
- **(B) Caps Lock(0x700000039) → F18(0x70000006D) remap**: 입력기는 다음 key 와 같은 흐름에서 평범한 F18 keyDown 을 받는다 — lock·LED·bubble·echo·system 전환이 없다.
  공개 API `IOHIDEventSystemClientCreateSimpleClient` + `IOHIDEventSystemClientSetProperty("UserKeyMapping")` 로 입력기가 직접 걸 수 있다. ✅ SDK
  TN2450 은 특권 불필요·재시작이나 keyboard 제거 시 풀림이라 하지만, 14.2 부터 sudo 가 필요했다·Tahoe 는 hidutil 에 입력 모니터링을 요구한다는 사용자 보고가 있다. 🔶 적용한 입력기는 없다 (한국 사용자들은 Karabiner 로 한다).
  - 시험: `hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'`, 되돌리기는 `[]`.

### 오른쪽 ⌘ 단독 tap

- 판정: keyCode 54 + `NX_DEVICERCMDKEYMASK`(0x10), 다른 수식키 없음, 사이에 key 가 없을 것. timeout 은 fire·vchewing 0.2초, ongeul 0.5초. ✅
- **함정 확인**: ⌘C·⌘V·⌘A 같은 menu 단축키는 입력기가 보기 전에 소비된다 (fcitx `installMainMenu` 주석). ✅ probe run 2 에서도 ⌘Tab 의 Tab 이 오지 않았다.
- 각 project 의 대응: gureum 은 HID 에서 누를 때 전환하고 ⌘ 를 억제하지 않아 단축키와 전환이 같이 일어난다 (#842·#756·#917, 해결 불가로 봄). ongeul·PriType 은 CGEventTap(손쉬운 사용 권한)으로 ⌘ bit 를 지워 전용 한/영 키로 만든다. SokIM 은 오른쪽 ⌘ 가 붙은 keyDown 을 전부 버린다. ✅
- **권한 없는 방법 (전례 없음)**: 누를 때와 뗄 때 `CGEventSourceCounterForEventType` 을 비교한다. 수식키·autorepeat 는 keyDown 으로 세지 않는다. 입력 모니터링·손쉬운 사용이 모두 거부된 상태에서도 값이 온다. ✅ local

```swift
let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
func snap() -> [UInt32] { types.map { CGEventSource.counterForEventType(.hidSystemState, eventType: $0) } }
// 누름 (keyCode 54, NX_DEVICERCMDKEYMASK, .command 만): armed = (snap(), event.timestamp)
// 뗌: if snap() == armed.0 && event.timestamp - armed.1 < 0.35 { 동기적으로 전환 }; armed = nil
```

### Shift+Space / Control+Space

- Control+Space 는 system 단축키 60, Ctrl+Opt+Space 는 61. 주인 Mac 에서 둘 다 켜져 있다 — System Settings 에서 끈다. ✅ local
- **IMK 안의 Shift+Space 는 일부 app 에서 실패한다**: JetBrains·iTerm2 는 space 도 친다 (ongeul 은 event tap 으로 가로챈다). Claude Code 도 Shift+Space 를 쓴다 (gureum#937). ✅
- 전역 hotkey 대안: SokIM 은 `RegisterEventHotKey`(TCC 불필요). macOS 15.0–15.1 은 Shift·Option 만의 hotkey 를 -9868 로 거부했다. 27.0 에서 등록은 됐고 전달은 미시험. 🔶

## 요약 — 새 구현이 설계로 막아야 할 것

1. `selectInputMode` 는 key 를 ~100–350ms 멈추고 Chromium session 을 흔든다 — 우리 status item 을 쓰거나, 불일치일 때만 늦춰서.
2. IMK lifecycle 은 뒤바뀌고 빠진다(26 은 deactivate 도 안 온다) — 앱별 기억은 `handle()`·`client()` 기준, 전환마다 저장, TIS·app 활성화 알림도 본다.
3. 전환은 `handle()` 안에서 동기적으로.
4. 입력기는 ⌘ 단축키의 key 를 못 본다 — event counter 나 event tap. Electron 의 flagsChanged 중복, keyCode 0 합성 event 도 걸러야 한다.
5. Caps Lock — system 전환 끄기, delay·echo·bubble·client 없음 (또는 F18 remap).
6. secure input — 영문 mode 는 완전 통과. /Library/Input Methods 설치 고려.
7. 등록 — parent 먼저, logout 한 번, plist 변경은 logout + 재추가, `imklaunchagent` 금지.
8. 서명·thread — 고정 인증서, `activateServer`·`setValue` 안에서 block 금지.
