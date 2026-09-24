# 조사: IMK lifecycle · 앱별 호환성 · Apple 입력기 결함 · 두벌식 (2026-09-25)

조사 agent 가 입력기 source·issue, app source(Chromium·Ghostty·iTerm2), 주인의 Mac(macOS 27)을 확인한 결과를 추렸다.
표기: ✅ 확인 / 🔶 불확실. 약칭: gureum, sq=squirrel, skk=macSKK, vc=vChewing, az=azooKey, fx=fcitx5-macos,
gt=ghostty, PT=`ghostface2232/PriType-Swift`(`Meapri/PriType-Swift` 의 fork, 2026-09-24 갱신. 같은 단일 입력기 설계의 한국어 입력기 — 가까운 선행 사례지만 주장의 출처가 하나뿐), Cr=Chromium.

## 1. IMK lifecycle

- **`commitComposition`**: client 가 "조합을 지금 끝내길" 원할 때. 보통 `insertText` 로 답한다. ✅ header
  - input source 전환 때 `deactivateServer` 보다 먼저 온다(az#216). Caps Lock 전환 때도 온다(vc#109). ✅
  - Chromium 은 mouse-down·blur·tab 전환 때 renderer 에서 먼저 확정한 뒤 `discardMarkedText` 를 부르고, 그게 `commitComposition` 으로 온다.
    그대로 `insertText` 하면 **두 번 들어간다** (gureum#87, Chrome 에서 click 후 음절 중복 — 미해결). ✅
- **안 올 때도 있다**: macOS 26 에서 다른 process 가 `TISSelectInputSource` 로 전환하면 `deactivateServer` 가 없다. TIS notification 은 온다 (sq#1142). ✅
- **순서는 "옛 것 deactivate → 새 것 activate" 가 아니다**: 새 session 이 먼저 activate 되어 key 를 받고 옛 것이 ~0.5초 뒤 deactivate 되기도 한다(vc#177·#259).
  옛 app 의 deactivate-commit 이 Spotlight 의 첫 key 에 떨어진 사례(vc#255). `handle()` 안의 `insertText` 도중에 deactivate/activate 가 중첩되어 오기도 한다(PT#15, macOS 27).
  `activateServer` 가 아예 안 와도 `handle()` 은 온다(fx). ✅
- **엉뚱한 client 에 확정하지 않으려면**: gureum 은 controller 마다 composer 를 두고 init 때 묶인 `controller.client()` 로 넣는다. macSKK 도 init 때의 client 를 잡는다.
  vChewing 은 현재 session 이 아니면 deactivate 때 버리고, `deactivateServer` 안에서 `setMarkedText` 를 부르지 않는다(Safari 새 tab 이 멈춤, vc#226).
  Chromium 창 하나의 모든 web 입력칸은 client 하나를 공유한다(PT#15). ✅
- **`handle` vs `inputText`**: 하나만 구현. `handle` 은 NSEvent(flagsChanged·mouse 포함, `recognizedEvents` 대로). YES = 먹음, NO = AppKit 이 이어서 `insertText:`/`doCommandBySelector:`. ✅
  - 한국어 확정 관례: `insertText(음절)` 후 NO. Apple 과 gureum 모두 (gt PR#14272). ✅
  - iTerm2(기본 설정)·Ghostty 는 text 를 넣지 않은 YES 를 무시한다 — key 가 pty 로 간다 (gureum#96). ✅
- **`activateServer`·`setValue` 는 최소로**: 거기서 client 를 동기 호출하면 Chrome 과 deadlock(az#317), 느리면 Spotlight 가 멈춤(vc#255). `setValue` 는 focus 가 바뀔 때마다 같은 값으로 다시 온다 — echo 로 무시. ✅
- **`bundleIdentifier()`** = text input client 를 가진 process: Chrome web 도 `com.google.Chrome`, Electron 은 자기 ID(`com.microsoft.VSCode`, `md.obsidian`, `dev.commandline.waveterm`),
  LaunchBar 의 모든 창 `at.obdev.LaunchBar`, `com.microsoft.rdc.macos`, `com.apple.RemoteDesktop`, `com.mitchellh.ghostty`, `com.googlecode.iterm2`, `com.kakao.KakaoTalkMac`, Spotlight `com.apple.Spotlight`. ✅
  nil 일 수 있다 — frontmost app 으로 대체(skk, PT). ✅ Safari 🔶
- **Swift 6**: macOS 27 SDK 의 IMK header 에는 MainActor·nullability 표시가 없다. `@MainActor` override 는 error. `nonisolated override` + `MainActor.assumeIsolated`(macSKK) 또는 vChewing 의 ObjC overlay header. ✅

## 2. app 계열별

- **Chromium/Electron** (Chrome, VS Code, Obsidian, Wave):
  - 확정 후 key 를 통과시키면 page 는 keydown(229) → compositionend → keyup(229) → 진짜 keydown 을 본다. `isComposing || keyCode === 229` 를 안 보는 web handler 가 두 번 동작한다 — **"Enter 에 마지막 음절 중복"**. Chromium 구조라 Apple 입력기에서도 난다. ✅
  - 한국어는 음절마다 조합이 끝나며, app 이 조합 중에 입력칸을 다시 focus 하면 음절이 자모로 쪼개진다 (vscode PR#320898, VSCodeVim gureum#884). ✅
  - `selectedRange`·`attributedSubstring` 답이 비동기이거나 틀리다 — **이미 확정한 text 를 다시 쓰지 말 것** (PT). ✅
  - Wave 는 Electron + xterm.js. CJK input source 가 켜져 있으면 macOS 의 "space 두 번 → 마침표" 가 xterm.js terminal 에 ". " 로 샌다 (orca#11504). ✅
- **native terminal** (Ghostty, iTerm2, Terminal):
  - **조합 중에 누른 Enter·Esc·Tab 은 음절만 확정하고 key 자체는 사라진다** — Apple 두벌식에서도 vim 은 Esc 를 두 번 눌러야 한다 (gt#1663, gureum#1; Ghostty 는 화살표만 재전송, 수정 PR#14272 미병합). ✅
  - **Ghostty 는 key 처리 중에 input source ID 가 바뀌면 그 keyDown 을 버린다** — 동기 `selectMode` 로 모드를 바꾸는 Esc·Ctrl-B 는 먹힌다 (gt 7a27af8). iTerm2 도 같은 검사가 있으나 기본 꺼짐. ✅
  - **iTerm2 는 조합 중이 아니면 Ctrl+글자를 입력기에 묻지 않고 pty 로 보낸다.** ✅
  - `handle()` 안에서 marked text 를 동기적으로 설정해야 한다 — 아니면 iTerm2 가 raw key 도 보낸다 (az#357). ✅
  - Ghostty 는 새 tab 을 연 직후 첫 입력이 조합되지 않을 수 있다 (gt#13235). ✅
- **JetBrains**: 조합이 안 바뀌면 IDE 가 key 를 스스로 넣어서 한글 뒤 Space·Enter 가 사라졌다 (gureum#92). ✅
- **MS Office**: Excel 새 cell 의 첫 자음이 영문으로(MS Q&A). cell 편집마다 새 client(vc#446). `replacementRange` 는 항상 NSNotFound — 아니면 Office 가 깨진다(vc). ✅
- **Safari/Spotlight**: WebKit 이 확정 keydown 보다 compositionend 를 먼저 쐈다(2026 수정). gureum 에서 화살표 뒤 밑줄이 남고 다음 key 가 마지막 글자를 지웠다(gureum#421). ✅
- **KakaoTalk**: 입력기가 확정하고 Return 을 통과시키면 제대로 전송된다(Telegram·WeChat 은 줄바꿈이 됨, gureum#892). 비밀번호 칸은 입력기가 영문을 직접 넣으면 막힌다(gureum#893). ✅
- **marked text 지원이 없거나 약한 app**: Steam, LINE, ChatGPT desktop(vc), Finder 바탕화면 type-to-select(PT), 비밀번호 칸(`setMarkedText` 가 beep). ✅

## 3. Apple 입력기 결함의 원인

- **(a) 풀어쓰기 — app 때문** (어떤 입력기든 겪는다): 미리 알림이 음절마다 조합을 끝냄(gureum#682), 네이버 검색창이 JS 로 focus 를 뺏음 → 'ㅇㅏㄴ녕'(gureum#733), VS Code 찾기 창·VSCodeVim·Evernote·Discord·Karabiner 규칙. ✅
- **(a) 풀어쓰기 — Apple 입력기 때문**:
  - focus·input source 가 바뀐 직후의 첫 key 가 조합되지 않는다. Qt 개발자: Apple 입력기가 "내부적으로" 조합하지 않기로 결정(QTBUG-136128, FB17460926). Ghostty 1.3.x 에서는 매번 재현(gt#12541). gureum 은 영향 없음. ✅
  - macOS 27 의 Apple 한국어 입력기(KIM_Extension)는 비공개 IMK class `IMKTextDocumentTextInputAdaptor` 위의 `KIMController` 다. 그 class 는 **app 의 text 를 cache 하고**
    `showsComposingTextAsMarkedText`, `unreliableApps`, `recomposeCharacters:`, `modelessUnsupportedApps` 같은 member 를 가진다. ✅ (strings·runtime dump)
    text 질의에 비동기로 답하는 app 과 cache 가 어긋난다는 것은 추론. 🔶 → probe run 1·2 에서 본 "marked text 없이 바꿔치기" 와 맞아떨어진다.
  - 별개 결함: 조합이 선택 영역을 대체한 뒤 Backspace 가 U+0008 을 넣는다 (vscode#148356). ✅
- **(b) 첫 key 가 이전 언어로 — 확인. 원인은 느림이 아니라 활성화 실패**:
  - 다른 process 의 `TISSelectInputSource` 로 keyboard layout → 입력기 전환이 82% 실패(Apple 병음도 36%), 2초 기다려도 소용없음. native 단축키는 50번 중 0번 실패 (sq#1162, az#340 macOS 27). ✅
    — Hammerspoon 의 영문 전환도 다른 process 의 `TISSelectInputSource` 다.
  - Caps Lock 은 key-up 에서 hold delay 뒤에 전환 — Caps Lock 을 떼기 전에 누른 key 는 이전 source 로 간다 (clien, ny64). ✅ probe run 1·2 의 timing 과 맞다.
  - 입력기 안의 전환은 key 처리 중에 `TISSelectInputSource`·`selectInputMode` 를 전혀 부르지 않을 때만 이 문제를 고친다 (PT 2.7.x 가 바로 이 버그). ✅
- **(c) "문서의 입력 소스로 자동 전환"**: app 단위가 아니라 문서 단위, 문서를 닫을 때까지 (Apple 지원 문서). 새 창·cell 은 새로 시작하고, 복원 자체가 전환이라 (b) 에 노출된다. 🔶

## 4. 두벌식 규칙

- **자판**: Shift 로 ㄲㄸㅃㅆㅉㅒㅖ. 겹모음은 정확히 ㅘㅙㅚㅝㅞㅟㅢ. 겹받침은 ㄳㄵㄶㄺㄻㄼㄽㄾㄿㅀㅄ. ✅ libhangul
- **도깨비불**: key 하나로 친 받침은 통째로 넘어가고(벘+ㅡ → 버|쓰), 두 key 로 만든 겹받침은 갈라진다(맑+ㅗ → 말|고, 갃+ㅏ → 각|사). ㅉ 은 받침이 될 수 없다(가+ㅉ → 가|ㅉ). ✅ libhangul test
- **같은 key 반복으로 된소리 (ㄱ+ㄱ)**: 표준은 Shift. libhangul 기본은 안 합침. **Apple 은 초성만 합친다 (ㅅㅅㅏ → 싸), 받침은 아니다** (gureum#767). 정확히 어느 쌍인지 🔶
- **홀로 선 ㄳ**: libhangul 은 조합(rtk → ㄱ|사), Apple 은 안 함, MS IME 는 함. ✅
- **Backspace**: libhangul 은 keystroke 하나를 되돌린다(ㅞ → ㅜ, ㄺ → ㄹ, Shift 로 친 ㅆ 은 통째로). Apple 은 "자소 단위/글자 단위 삭제" 설정이 있다. ✅
  마지막 자모는 확정한 뒤 app 이 지우게 한다 — probe run 2 에서 확인 (`insertText "ㄷ"` → `deleteBackward:`). ✅
- **홀로 선 모음 뒤 자음**: libhangul 은 모음을 확정하고 새 음절 (AUTO_REORDER=false). Apple 도 같을 것. 🔶
- **다른 key**: 문장부호·Cmd/Ctrl/Option 조합·화살표는 확정 후 통과, mouse-down 은 확정 (gureum). ✅
- **libhangul 을 test oracle 로**: 표준에 대해선 좋다. Apple 에 맞추려면 NON_CHOSEONG_COMBI=false + 초성만 반복 합침(기본 옵션은 받침도 합쳐 버린다). "2" 자판엔 문장부호 mapping 이 없다. 🔶 Apple 과의 일치
- **₩ 와 layout 차이**: `2SetHangul` 에서 ` → ₩(U+20A9), Shift+` → ~, Option+` → `.
  **Option(또는 Option+Shift)+아무 key → 평범한 ASCII** (Option+a → a, ABC 는 å). Caps Lock 은 자모에 무시. 숫자·문장부호는 ABC 와 같다. ✅ local `UCKeyTranslate`
  - 문자를 layout 대신 `insertText` 로 직접 넣으면 xterm.js·Ink(Claude Code 의 UI) 는 key event 를 읽으므로 그 문자를 못 본다 (gureum#919). ✅ → 문장부호·` 는 통과시켜 layout 이 만들게 한다.

## 주인의 사용 기준 상위 함정

1. **terminal 에서 Esc·Enter 유실** — 조합 중 Esc 는 음절만 확정되고 사라진다. vim 에 Esc 두 번. 정책 필요 (예: 확정 → key 를 먹고 다시 보냄). 🔶 해결책
2. **Ghostty 는 mode 변경 중의 key 를 버린다** — 내부 상태만 바꾸고 system 보고는 key 처리 뒤 비동기로.
3. **iTerm2 는 Ctrl 키를 입력기에 안 보여준다** — Ctrl-B/Ctrl-A 규칙은 Ghostty 에서만 된다(주인 규칙도 Ghostty 전용이라 맞다). 한/영 키는 단독 수식키이거나 event tap 이어야 한다.
4. **엉뚱한 client 로 가는 확정** — 상태는 controller·client 단위, 확정은 두 번 불려도 안전하게.
5. **Chromium 이 이미 확정한 뒤의 중복** — `commitComposition` 때 client 에 아직 marked text 가 있을 때만 넣는다. 🔶 설계
6. **Enter 는 Apple 과 똑같이** — `insertText`(NSNotFound) 한 번, NO 반환, 빈 `setMarkedText`·취소 없음.
7. **앱별 기억·강제 영문** — 활성화를 믿지 말고 첫 `handle()` 에서 규칙을 다시 적용, bundle ID 로, 반복 `setValue` 무시.
8. **`TISSelectInputSource`·`selectInputMode` 로 전환하지 않는다.**
9. **활성화는 최소로, 영문 mode 는 순수 통과.**
10. **경계 의미론** — 자모 단위 Backspace, 제어 문자 금지, 선택 영역 대체, 주인 손버릇(ㅅㅅ → ㅆ 등)과 맞는 규칙, ₩ 는 layout 경유.

재현 도구 (session 임시 폴더, 보존 안 됨): `kltest.swift`(layout 별 `UCKeyTranslate` 비교), `dumpimk.m`(IMK class·method runtime dump).
