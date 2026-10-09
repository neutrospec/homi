# 결함과 교훈

고친 결함마다 **증상 · 원인 · 증거 · 대응**을 남긴다 (AGENTS.md 작업 규칙). 새 결함은 맨 위에 더한다.
배운 macOS 구조 자체는 `docs/macos-input.md` 에 있다. 여기에는 무엇이 틀렸고 그것을 어떻게 알았는지를 남긴다.

- 간헐 결함의 증거는 homi 의 기록이다 — 이상하면 주인이 곧바로 input menu 의 "최근 key 기록 저장" 을 누르고(`~/Library/Logs/homi/`), 그 file 로 가린다.
- 원인에 🔶 가 붙은 것은 대응이 통했지만 원인은 추정이라는 뜻이다.

## 2026-10-09 재검토에서 적용할 교훈

- 주인 결정: 기본 조합·편집·homi 내부 한/영·focus 이동을 우선한다. 드문 source 왕복의 교정이 일상 입력을 악화시키면 철회한다.
  [개선 검토](stability-review.md)에 모든 안건의 채택·보류·기각과 다음 검증을 남겼다. 새 model 의 counterexample 은 실제 app 실패와 구분한다.
- 재진입 경계가 Session 을 보호해도 mode reset·layout·표시까지 같은 판단을 따르는지 별도로 검증해야 한다.
  stale UI 를 막는 세대 검사도 무변화 event 에 필요한 UI 를 버릴 수 있다. 보호 장치 자체의 반례를 검사한다.
- `commitComposition` 의 callback 은 왜 왔는지와 무엇을 끝냈는지를 가른다. old mark·new mark·renderer 확정을 하나로 가정하지 않는다.
  fake client 의 즉시 반영을 실제 app 완료로 세었던 실패를 반복하지 않는다.
- "우리 insert 기록이 없다" 는 app 결함의 확정 증거가 아니다. VS Code 원장의 남은 중복도 원인 미확정으로 바로잡았다.
  한 번에 한 가정을 바꾸고, 설치본의 기본 동작이 복구됐는지 확인한 뒤 다음 실험을 한다.

## 2026-10-09 작업 마감

- 유지한 변경: 재진입 경계·source 종료 알림 보완·activate 의 client 질의 제거, Caps Lock timer 수명·mapping 실패 처리,
  후보 창의 controller·조합 세대 확인, 완성된 bundle 의 atomic 설치. startup 의 `@main` 전환은 app 을 test target 에서 참조하기 위한 구조 변경이다.
- 최종 rollback 은 09:54 KST 에 자체 인증서 `homi code signing` 으로 서명·검증·설치했다.
  보류한 Chromium 확정과 `replacementRange` 실험은 철회했다. 한글 엔진의 조합 규칙·input mode 구성·설치 위치는 바꾸지 않았다.
- `swift build` 와 Debug·Release test 통과: 각각 138개(HangulCore 18, InputSession 106, Homi 11, Install 3).
  재진입·owner 해제·HID 실패 주입·directory 교환의 검증이다. 후보 창의 실제 표시·모든 app 의 호환성을 증명하지 않는다.
- native probe 자동 검사는 합성 수식키로 한글 모드에 들어가지 못해 `BLOCKED` 였다. 도구의 system keyboard event 전송 권한도 없었다.
  자기 창의 `--check-manual` 경로는 준비했지만 끝까지 `PASS` 를 확인하지 않았다.
- Chrome source 전환·input menu 의 비활성/누락은 **미해결**이다. rollback 뒤 실제 입력칸 이동의 복구도 주인 확인이 아직 없다.
  다음 작업의 시작점은 [Chrome 원장](apps/chrome.md#다음-작업)과 [비활성 관측](macos-input.md#input-menu-의-비활성누락-2026-10-09-미해결)에 둔다.

## homi 의 결함

### 보류한 Chromium 확정이 다음 입력칸에 들어간다 (2026-10-09)

- **증상**: source 전환 교정본에서 조합 중인 `글` 을 둔 채 다른 입력칸을 click 하고 `한` 을 치면 새 칸에 `글한` 이 들어갔다.
- **원인**: `commitComposition` 에서 Session 을 남기고 다음 event 의 `markedRange` 답으로 확정했다.
  proxy 하나를 여러 DOM 입력칸이 공유하며, 그 답은 이전 칸의 mark 가 남았다는 증거가 아니었다.
- **증거**: 실제 Chrome lifecycle·DOM 순서와 주인 관측은 [Chrome 원장](apps/chrome.md)에 있다.
  같은 proxy 의 focus 를 바꾸는 regression 도 수정 전에 Session 잔류·`글한` 으로 실패했다.
- **대응**: 다음 event 에서 확정하는 경로를 제거하고 기존 Chromium 우회로 복귀했다.
  client 가 확정한 Session 은 callback 반환 전에 끝낸다. key 처리 중의 재진입만 같은 event 끝에서 처리한다.
  source 전환의 기존 실패는 남는다 — rollback 을 그 문제의 해결로 세지 않는다.

### IMK 현재 selection 의 range 계약이 구현과 다르다 (2026-10-09, 교정 보류)

- **증상·원인**: `insertText` 의 `replacementRange` 를 `{NSNotFound, 0}` 으로 보냈다.
  IMK 의 현재 selection 지정은 `{NSNotFound, NSNotFound}` 다 — `setMarkedText` 의 위치만 지정하는 설명과 혼동했다.
- **증거**: macOS 27 SDK `IMKInputSession.h`, 실제 `Client.apply` 의 proxy 인자를 검사한 `ClientTests` 실패.
- **실험·현재 처리**: 길이도 `NSNotFound` 로 바꿔 설치했지만 Chrome 의 대체·입력칸 누출은 계속됐고 주인은 더 나쁘다고 보고했다.
  인과관계는 가르지 못했다. 입력칸 이동의 실패를 먼저 제거하면서 range 도 기존 `{NSNotFound, 0}` 으로 되돌렸다.
  SDK 계약과 실제 IMK 전달의 차이는 미해결이며, proxy 인자 test 만으로 app 동작을 증명할 수 없다.

### Chrome 에서 ABC 를 거쳐 돌아오면 조합하던 글자를 덮어쓴다 (2026-10-09, 미해결)

- **증상**: 주인 — 조합 중 input menu 를 mouse 로 ABC → homi 전환하고 바로 `한글` 을 치면 이전 글자가 대체됐다.
  mouse 로 입력 위치를 옮기는 경로는 정상이었다. ⌃Space 전환은 별도 확인하지 않았다.
- **기존 처리의 결함**: `commitComposition` 때 TIS 가 아직 homi 라는 이유로 client 가 이미 확정했다고 판단해 Session 만 비웠다.
  source 종료 알림이 와도 이미 비었으므로 client 에 남은 mark 를 확정할 수 없었다.
- **증거**: Chrome 154.0.8037.98·macOS 27.0.1 의 lifecycle log — 07:51:23.347 commit 의 선택은 homi,
  07:51:23.357 source 알림에서는 ABC. 이미 ABC 인 commit 도 관측됐다.
- **실패한 대응**: callback 뒤의 다음 event·종료 경계에서 Cocoa mark cache 를 확인했다.
  실제 입력칸 이동에서는 보류한 글자가 새 칸에 들어가 이 처리를 제거했다(위의 결함).
  현재는 기존 TIS 기반 우회로 돌아왔으며 source 전환의 구분은 불완전하다. 실제 관측은 [Chrome 원장](apps/chrome.md)에 둔다.
- **test 의 한계**: 초기 fake client 는 insert 가 곧바로 문서와 mark 에 반영된다고 가정해 실제 실패를 놓쳤다.
  현재 `explicitSourceCommitBeforeSourceNotification` 은 명시적 확정·source 알림·deactivate 의 중복 방지만 검사한다.
  TIS 로 종료 원인을 가리는 것과 IMK 호출이 renderer 에 전달되는 것은 검증하지 않는다.

### client 호출의 재진입으로 abort 하거나 mark 가 다시 남는다 (2026-10-09)

- **증상**: 한자 질의 중 commit 이 끼면 process 가 abort 했다. `한` 다음 `ㄱ` 을 처리하는 `insert → mark` 중 deactivate 가 끼면,
  Session 은 비었는데 client 에 `ㄱ` 의 mark 가 남았다.
- **원인**: mutating `Session.handle` 이 client 질의를 실행하는 동안 다시 `Session.commit` 에 접근했다.
  상태 변경 뒤 목록을 반영해도, 목록 중간에 lifecycle 이 들어오는 것은 막지 못했다.
- **증거**: lifecycle 을 주입한 `ReentrancyTests` — 수정 전 mark 불일치와 Swift exclusive access abort, Debug·Release 에서 확인.
  실제 macOS 관측의 근거는 [입력 구조](macos-input.md#client-호출은-imk-lifecycle-을-재진입시킬-수-있다)에 있다.
- **대응**: `SessionDriver` 에서 질의부터 client 반영까지 감싸고 재진입한 종료를 마지막에 처리한다.
  deactivate 누락은 source 알림으로 보완한다. 지연된 후보 표시는 끝난 조합이나 다른 controller 의 창을 건드리지 않는다.
  client 가 이미 확정한 callback 은 뒤의 deactivate·source 종료가 다시 넣지 않도록 같은 경계에서 합친다.
  deactivate·source 알림 두 regression 으로 중복 방지를 확인한다.
  실제 Chrome 의 source 전환은 [Chrome 원장](apps/chrome.md)에 별도로 검증한다 — 주입 test 만으로 app 호환성을 확정하지 않는다.

### Caps Lock timer 가 controller 를 붙잡는다 (2026-10-09)

- **증상**: timer 를 취소하거나 실행을 마친 뒤에도 owner 가 해제되지 않았다.
- **원인**: controller → `DispatchWorkItem` → controller 의 strong reference 순환.
- **증거**: `HoldTimerTests` 의 weak owner 검사 — 기존 구조는 해제 실패, 수정 뒤 취소·대기·완료 경로 모두 해제.
- **대응**: timer 는 owner 를 weak 로 들고, 취소·실행 때 작업을 비운다. 이것이 IMK 내부나 system 의 모든 누수를 해결한다는 뜻은 아니다.

### Caps Lock mapping 실패를 성공으로 기억하고 다른 mapping 을 지운다 (2026-10-09)

- **증상**: HID 쓰기가 실패해도 다음 알림에서 재시도하지 않았다. homi 를 떠날 때 다른 도구의 Caps Lock mapping 도 사라질 수 있었다.
- **원인**: setter 결과를 무시하고 적용 상태를 cache 했다. 해제 때 source 가 Caps Lock 인 항목을 모두 지웠다.
- **증거**: 실제 keyboard 를 바꾸지 않는 `CapsLockMappingTests` — setter 실패·다른 도구의 변경·wake 를 주입.
- **대응**: 성공만 cache 하고, homi 의 Caps Lock → 오른쪽 Control 항목만 해제한다. 덮기 전 mapping 은 복원하며 다른 도구가 새로 바꾼 값은 보존한다.
  source·destination 이 homi 와 정확히 같은 항목은 소유자를 구분할 수 없다 — 모든 도구와의 동시 제어를 보장한 것은 아니다.

### 설치 실패 때 입력기가 없는 구간이 생긴다 (2026-10-09)

- **증상**: 기존 app 을 지운 뒤 복사에 실패하면 설치 위치에 homi 가 없다. 복사 중에도 불완전한 app 이 노출될 수 있었다.
- **원인**: process 종료 → 설치본 삭제 → 복사 순서였다. 완성된 bundle 을 교환하지 않았다.
- **증거**: 설치 script 검토, `AtomicInstallTests` 의 실패·첫 설치·교환 검사. 수정한 script 로 서명·설치 성공.
- **대응**: 같은 volume 에서 조립·서명·검증한 뒤 `renamex_np(RENAME_SWAP)` 으로 교환하고 process 를 종료한다.
  지속적인 `build/homi.app` 사본도 새로 만들지 않는다. 과거 사본이 등록돼 있었다는 것만으로 비활성의 원인이라고 단정하지 않는다.

### Remote Desktop 에서 원격에 한글이 가지 않는다 (2026-09-26, M7 중)
- **증상**: homi 로 한/영을 바꿔도 원격 입력칸에는 영문만 들어갔다. Apple 입력기로는 됐다 (주인).
- **원인**: 화면 공유는 입력기의 글자를 받지 않고, key 를 이 Mac 의 keyboard layout 으로 글자로 바꿔 보낸다. homi 아래 layout 은 늘 ABC 였다.
- **증거**: framework 에 입력기의 글자를 받는 method 가 없다(symbol). keysym 을 layout 으로 만든다(disassemble). Remote Desktop log 의 `KeyLayoutData size` 와
  주인의 ⌃Space 관측 — 이 Mac 만 바뀌고 원격은 그대로인데 한/영이 됐다.
  처음 세운 "입력 소스 ID 동기화 덕" 이라는 설명은 틀렸다 — 그 동기화는 Remote Desktop 에서 켤 수 없다.
- **대응**: Remote Desktop 에서는 homi 가 모드에 따라 layout 을 바꾼다 (한 → `2SetHangul`, `d226abe`). 원격은 두벌식에 둔다.
- **교훈**: binary 에서 찾은 기능이 UI 에도 있다고 가정하지 않는다. 주인의 관측이 설명과 어긋나면 관측이 맞다 — 다시 판다.

### 설정 창이 보이지 않는다 (2026-09-25, M7)
- **증상**: input menu 의 "설정…" 을 눌러도 창이 보이지 않았다 (주인).
- **원인** 🔶: homi 는 background app 이라 `NSApp.activate()` 가 받아들여지지 않을 수 있고, 그러면 창이 다른 app 의 창 뒤에 뜬다.
- **증거**: 주인 관측. 아래 대응 뒤로 주인이 설정을 바꿔 쓰고 있다.
- **대응**: 활성화와 상관없이 `orderFrontRegardless` 로 맨 앞에, mouse 가 있는 화면 가운데에 띄운다 (`44e27e7`).

### Chromium 에서 조합 중에 click 하면 음절이 두 번 들어간다 (2026-09-25, M6 중)
- **증상**: VS Code 에서 `자`를 조합하던 중 mouse 로 click·선택하면, 그 음절이 누른 자리에 한 번 더 들어갔다 (주인).
- **원인**: Chromium 은 click·blur 때 page 가 조합을 스스로 확정한 뒤 `discardMarkedText` 로 입력기의 `commitComposition` 을 부른다.
  homi 는 그때 조합을 또 `insertText` 했다. 조사에서 알던 함정(AGENTS.md 함정 3)인데 막지 않았었다.
- **증거**: source — `render_widget_host_view_cocoa.mm` `mouseEvent:` → `finishComposingText` → `cancelComposition`.
  homi 기록 — click 때 `commitComposition` 다음에 `insert "자"`.
  첫 대응("client 에 marked text 가 남았을 때만 넣기")이 통하지 않은 것도 기록으로 알았다: 입력기를 부르는 동안 Chromium 은 아직 "있다" 고 답했다.
- **대응**: Chromium 계열 app(bundle 안의 `… Helper (Renderer).app`)의 `commitComposition` 은 homi 가 선택된 동안 넣지 않는다 (`7e4c1fd`).
- **교훈**: app 이 부르는 IMK 호출의 뜻은 app 마다 다르다 — "조합을 끝내 달라" 일 수도, "이미 끝냈다" 일 수도 있다. 가설은 기록으로 확인한다.

### 확정한 단어를 한자로 바꾸면 app 마다 틀어진다 (2026-09-25, M6)
- **증상**: `나는한자` + ⌥↩ 가 TextEdit·Telegram 에서는 맞았다. VS Code·Orca 는 `나는한자漢字`, IntelliJ 는 단어가 사라지고 한자도 없었다 (주인).
- **원인**: 확정한 글자를 marked text 로 되돌리려면 `replacementRange` 를 줘야 하는데, 이 교체를 app 마다 다르게 다룬다.
  IntelliJ editor 는 범위를 무시하고, VS Code 같은 JS editor 는 자기가 모르는 범위에서 시작한 조합을 커서 자리의 새 입력으로 다룬다 🔶.
- **증거**: 주인 관측(app 별 표는 docs/macos-input.md). source — IntelliJ `IdeEventQueue.kt` 는 JBR 의 선택 요청을 speed search 에만 쓴다.
  client 가 알리는 `validAttributesForMarkedText` 가 된 곳(NSTextView)과 안 된 곳(Chromium·JBR)을 가른다.
- **대응**: 방금 친 단어는 NSTextView 수준을 알리는 client(교체 범위 + `NSTextAlternatives`)에서만 바꾼다. terminal·Office 는 app 규칙으로 뺀다.
  고르는 key 는 늘 marked text 가 있는 채로 오게 한다 — 선택 영역도 ⌥↩ 때 marked text 로 만든다 (`c884edd`).
- **교훈**: 결정 5(확정한 글자를 고쳐 쓰지 않는다)의 이유가 실제로 드러났다. 예외는 client 가 스스로 밝힌 능력으로만 연다.

### menu bar 표시가 생기지 않는다 (2026-09-25, M4)
- **증상**: homi 를 골라도 menu bar 에 한/A 가 나타나지 않았다 (주인).
- **원인**: `NSStatusItem` 을 앱 객체(`NSApplication.shared`)보다 먼저 만들었다 — 오류 없이 아무것도 생기지 않는다.
- **증거**: homi process 가 창을 하나도 갖지 않았다 (`CGWindowListCopyWindowInfo`).
- **대응**: `main.swift` 에서 앱 객체를 먼저 만든다 (`b9e220a`).

### 대문자 고정이 뗄 때 켜진다 (2026-09-25, M4)
- **증상**: Caps Lock 을 길게 눌러도 macOS 와 달리 떼야 대문자 고정이 켜졌다 (주인).
- **원인**: 길게 누름을 뗄 때 판정했다.
- **증거**: 주인 관측.
- **대응**: 0.5초가 되는 순간 timer 로 켠다 (`ModifierTap.holdReached`, `b9e220a`).

### 대문자 고정 표시가 둘 뜬다 (2026-09-25, M4)
- **증상**: 대문자 고정을 바꿀 때 homi 의 ⇪ 말풍선과 macOS 자신의 대문자 고정 표시가 함께 떴다 (주인).
- **원인**: homi 가 IOKit 으로 lock 상태를 바꾸면 macOS 가 자기 표시를 띄운다. homi 가 따로 그릴 까닭이 없었다.
- **증거**: 주인 관측.
- **대응**: homi 의 대문자 고정 표시를 없애고 macOS 에 맡긴다 (`b9e220a`).

### 다시 보낸 Enter 가 Telegram 에 닿지 않는다 (2026-09-25, M4)
- **증상**: 조합 중 Enter 를 먹고 다시 보냈더니 Telegram 에서 "틱" 소리만 나고 Enter 가 사라졌다 (주인).
- **원인** 🔶: 원래 event 의 복사본(`NSEvent.cgEvent.copy()`)을 key 처리 도중에 보냈다. 복사본에 딸린 창·시각 정보 때문인지 보낸 시점 때문인지는 가르지 않았다.
- **증거**: homi 기록으로 다시 보낸 것은 확인했다. Telegram 의 전송 조건(`flags == 0` + 입력칸에 글자)은 맞았다 (source) → event 가 입력칸에 닿지 않았다.
- **대응**: 새 event(`CGEvent(keyboardEventSource:virtualKey:keyDown:)`)를 원래 key 처리가 끝난 뒤 HID 경로로 보낸다 (`c08572b`).

### Telegram 에서 조합 중 Enter 가 전송이 아니라 줄바꿈이 된다 (2026-09-25, M4 — Apple 입력기 때부터)
- **증상**: 한글을 조합하다 Enter 를 누르면 전송되지 않고 줄이 바뀌었다 (주인).
- **원인**: Telegram 은 marked text 가 없을 때만 Enter 로 보낸다 — 조합 중이면 입력기에 넘기고, 입력기가 확정한 뒤 줄바꿈이 된다.
- **증거**: source — TelegramSwift `ChatInputTextView.keyDown`.
- **대응**: 조합 중 Enter 는 확정하고 먹은 뒤 다시 보낸다 (`AppRules` 의 `resendWhileComposing`, `c08572b`).

### terminal 에서 조합 중 ESC·Enter 가 사라진다 (2026-09-25, M4 — Apple 입력기 때부터)
- **증상**: vim 에서 한글을 치다 ESC 를 두 번 눌러야 했다.
- **원인**: Ghostty·iTerm2 는 조합 중에 온 key 를 음절 확정에만 쓰고 key 자체는 버린다.
- **증거**: source — Ghostty `SurfaceView_AppKit.keyDown`, iTerm2 `iTermKeyboardHandler.m`. 조사(gt#1663, gureum#1).
- **대응**: 조합 중 Enter·ESC·Tab 은 확정하고 먹은 뒤 다시 보낸다 (`c08572b`). 주인 확인 — vim 의 ESC 한 번.

### 전환 key 가 terminal 에 새어 나간다 (2026-09-25, M3→M4)
- **증상**: Caps Lock 을 F18 로 받았을 때 Ghostty 에 F18 의 문자(U+F715)가, Shift+Space 로 전환하면 space 가 들어갔다 (주인).
- **원인**: Ghostty·iTerm2 는 입력기의 YES(먹었다)를 보지 않는다. 조합도 글자도 없이 먹은 key 는 스스로 보낸다.
  marked text 를 세웠다 지우는 신호(macSKK 방식)도 통하지 않았다.
- **증거**: source — Ghostty `keyDown`(markedTextBefore·insertText·layout 변화 세 조건), iTerm2 `shouldPassPostCocoaEventToDelegate`.
- **대응**: 전환 key 는 글자를 만들지 않는 수식키로 — Caps Lock 은 homi 가 선택된 동안 오른쪽 Control 로 remap, Shift+Space 전환은 없앴다 (주인 결정, `c08572b`). Shift+Space 는 M7 에서 알고 고르는 선택지로 되살렸다.
- **교훈**: "입력기가 key 를 먹었다" 의 판정은 app 이 한다 (docs/macos-input.md 의 표).

### system 이 homi 를 밀어낸다 (2026-09-25, M0·M4)
- **증상**: homi 를 고른 채 다른 창에 갔다 오면 ABC 로 돌아가 있었다. menu bar 표시가 켜졌다 꺼졌다 했다.
- **원인**: "문서의 입력 소스로 자동 전환" 이 문서마다 input source 를 되살린다.
- **증거**: probe — homi 를 고른 채 돌아오자 system 이 ABC 를 되살렸다. `SourceWatcher` 의 선택 알림이 오락가락했다.
- **대응**: 주인이 그 설정을 껐다 (`TextInputGlobalPropertyPerContextInput = 0`, `633c572`). app 별 한/영은 homi 가 기억한다.

## 원인이 아직 확정되지 않은 관측

- **VS Code 에서 가끔, click 한 자리에 조합 중이던 음절이 한 번 더** (`자한자`) — 해당 homi 기록에 insert 가 없다.
  Chromium 의 타이밍으로 추정했지만, 지연된 lifecycle·mark 반영까지 배제한 증거는 아니다. homi 의 결함이 아니라고 확정하지 않는다.

## homi 의 결함이 아니었던 것

같은 증상을 다시 보면 먼저 여기를 본다.

- **IntelliJ 에서 선택 영역을 한자로 바꾸면 글자가 사라진다** — IdeaVim 은 mouse 선택을 Visual mode 로 받고, 조합을 시작하며 선택이 지워지면 Visual 을 나온다.
  Insert 로 돌아가지 않으면 고른 한자는 Normal mode 명령으로 읽혀 버려진다 (source: IdeaVim `IdeaSelectionControl` — 주인 관측과 맞다 🔶). 조합 중인 글자는 된다.
- **Word 에서 선택만 있을 때 ⌥↩ 가 무시된다** — homi 기록에 그 key 가 없다. marked text 가 없으면 Word 가 key 를 먼저 가져가는 듯하다 🔶.
- **Telegram 에서 첫 초성이 사라진다**(`아` → `ㅏ`) — Apple 입력기에서만 났다. homi 로는 재현되지 않았다.

## 개발 도구에서

- **TIS 를 병렬 test 에서 부르면 process 가 abort 한다** (signal 6) — TIS 는 main thread 에서만. test 에 `@MainActor` (M1).
- **bundle 없이 띄운 창은 앞으로 나오지 않는다** — probe 를 `.app` 으로 조립해 `open` 한다 (M0).
- **app 을 죽이자마자 `open` 하면 LaunchServices 가 -600** — 죽어가는 process 에 붙으려 한다. 종료를 기다린다 (`scripts/probe.sh`).
- **probe 가 무한 재귀했다** — text input context 는 만들어질 때 client 에게 `validAttributesForMarkedText` 를 묻는데, probe 가 그 질문을 기록하며
  context 를 다시 찾았다(`lazy`). 만들어지기 전에는 nil 로 두어 끊었다.
- **Swift Testing 의 `#expect(...)` 안에서는 mutating method 를 부를 수 없다** — 결과를 변수에 먼저 받는다 (세 번 되풀이).
