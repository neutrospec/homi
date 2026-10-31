# 안정적인 입력을 위한 개선 검토 — 2026-10-09

검토한 코드 기준은 `edbf60d` 다. HangulCore·InputSession, IMK lifecycle·client 반영, app 원장·test·도구·설치를 세 subagent 와 나누어 검토하고,
안건마다 AGENTS.md 와 기존 교훈을 다시 대조했다. 아래 **채택은 작업 대상으로 채택했다는 뜻**이다.
조사 당시에는 제품 코드를 바꾸지 않았다. 이후 주인이 승인한 activation 교정·callback 관측의 구현과 검증은 [후속 기록](lessons.md#2026-10-09-activation-교정callback-관측)에 있다.

## 판단 기준

주인 결정: **일상적인 두벌식 입력의 안정성이 먼저다.** 글자 유실·중복·엉뚱한 입력칸·첫 key 의 잘못된 모드·입력 중단을 가장 무겁게 본다.
같은 영향이면 평범한 조합·Backspace·homi 내부 한/영·focus 이동을 먼저 검증한다. 발생 빈도를 모르는 안건은 드물다고 가정하지 않는다.
한자·표시 개선과 다른 input source 왕복의 교정은 기본 입력을 악화시키면서까지 하지 않는다.

완전한 입력을 위해 검증 범위를 넓히되, 관측하지 못한 경로를 해결했다고 세지 않는다. 현재 확인한 정상 동작을 보존하고,
좁은 변경 하나마다 재현 test → 실제 app 확인 → 일상 사용의 관측으로 진행한다. 드문 경로의 제한을 명시하고 보류하는 것도 가능한 판단이다.

## 기본 입력을 먼저 보호할 안건

| 안건 | 판단 · 중요도 | 문서·교훈에 비춘 다음 행동 |
|---|---|---|
| Caps Lock 전환 누락 | **2026-10-29 교정·주인 시험 통과** · 기본 한/영 전환에 직접 영향 | [code review 의 반례](#caps-lock-전환-code-review-2026-10-29)와 실제 동시 비교에서 정상 tap 의 거짓 거부를 확인했다. gesture 교정 뒤 짧은 전환 34회·hold 4회 및 주인의 정상 동작 확인을 얻었다. [fallback·일상 사용의 남은 범위](lessons.md#정상-caps-tap-을-기존-판정이-거부한다-2026-10-29)는 계속 확인한다. |
| system 의 문서별 input source 복원 | **2026-10-31 켜짐 발견·주인 승인 후 해제, 초성 누락은 재발** | [현재 설정 확인](macos-input.md#문서별-input-source-복원-재확인-2026-10-31). homi 내부 한/영과 ABC ↔ homi 선택을 분리한다. 해제만으로 초성 누락은 해결되지 않았고 Orca 의 menu 누락 보고도 나왔다. 첫 key 영문·T3 menu 누락의 해제 후 경과는 별도로 확인한다. |
| Telegram 복귀 뒤 첫 key 의 영문 | **2026-10-29 주인 보고, 기본 입력의 우선 조사** | [원장](apps/telegram.md#창-전환-뒤-첫-key-가-영문-2026-10-29-미해결). Caps 를 누르지 않고 다음 key 부터 한글로 회복한다는 조건 때문에 tap 취소와 분리한다. 첫 key 의 IMK 도착·app 식별·mode·client 반영을 가르며, 주입한 activation model 을 실제 원인으로 단정하지 않는다. |
| Telegram 복귀 뒤 초성 누락 | **2026-10-30·31 주인 보고, 기본 입력의 글자 유실로 우선 조사** | Caps 없이 `당 → ㅏㅇ`, 다음 날 자동 복원 해제 후 ⌘Tab 뒤에도 재발. [합성 조건 비교와 controller 교체 관측](apps/telegram.md#창-전환-뒤-초성-누락-2026-10-30-미해결). 첫 mark 의 표시 누락만으로는 설명되지 않는다. 첫 key 전달·modifier·조합 상태·client 전환을 가르며, 첫 key 영문과 동일 원인으로 단정하지 않는다. |
| 현재 설치본의 입력칸 이동 | **최우선 확인** · 실제 발생했던 회귀 | 주인의 변경 전 기본 입력 정상 보고는 [후속 기록](lessons.md#2026-10-09-activation-교정callback-관측)에 있다. Chrome 의 개별 경로 확인과 model 통과는 구분한다. |
| activation 과 mode 초기화의 경계 | **재현 test 후 교정·설치** · 기본 입력에 직접 영향 | 아래 두 counterexample 의 mode 경계를 `ModeActivation` 으로 교정했다. [검증·제한](lessons.md#재활성화가-mode-를-reset-하고-실제-client-의-시작-규칙을-놓친다-2026-10-09)과 [LaunchBar 요구](apps/launchbar.md)를 함께 확인한다. |
| 늦은 client ID 와 fallback mode 이전 | **2026-10-31 교정·설치·probe 실제 입력 주인 확인** | [교정과 검증 범위](lessons.md#늦은-client-id-가-실제-app-의-mode-기억을-덮는다-2026-10-31). 무변화 key 는 이전하지 않으며 조합·toggle 보존과 새 activation 경계를 test 했다. 실제 Telegram 원인으로 확인한 것은 아니다. |
| callback 이 확정한 mark 의 세대 | **2026-10-31 적용 범위 교정·설치·주인 확인** · 유실 위험 | [교훈](lessons.md#이전-mark-의-확인이-다음-조합을-지운다-2026-10-31). client 확정의 기존 판단은 유지하되 아직 보내지 않았던 mark 까지 확인한 것으로 처리하지 않는다. 다음 key 까지 commit 을 미루지 않는다. |
| 비활성·누락의 상태 관측 | **채택·2026-10-31 실패 보고 중 snapshot 확보** · 입력 자체를 막는 증상, 원인 미확정 | [Orca 관측](apps/orca.md#input-menu-의-homi-누락-보고와-회복-2026-10-31-미해결): 등록·process 유지, Secure Event Input=false, 같은 창에서 기다린 뒤 회복 보고. menu 전체·focus 와 context 제한을 다음에 대조하며, 보기 착오도 배제하지 않는다. typing 경로는 건드리지 않는다. |
| ChatGPT 복귀 뒤 source 전환 UI 지연 | **2026-10-31 11:56 전후 주인 보고, 미해결** | [보고 순서·log 범위](apps/chatgpt.md#복귀-뒤-source-전환-지연-보고-2026-10-31-미해결). 같은 `⌃Space`에 무표시 → 이름 popup → 커서 옆 표시. UI 와 실제 source 선택을 분리하고, activation 을 전환 완료로 세지 않는다. 개별 시도의 source·focus 대응이 다음 관측이다. |
| ChatGPT renderer helper 판별 | **실제 판별 함수의 false 확인·commit 정책은 검증 후보** | [현재 bundle 의 이름 불일치](apps/chatgpt.md#별도-code-review-renderer-helper-이름-판별). 판별식 확대 전에 실제 commit·click·focus 경로를 확인한다. source 전환 UI 지연의 원인으로 채택하지 않는다. |
| controller 진단 ID | **2026-10-31 교정·새 process 기록 확인** | [수명 구분](lessons.md#controller-진단-id-의-수명-구분). process PID·UUID 와 생성 번호를 쓴다. 과거 동일 hash log 는 한 controller 로 합치지 않는다. |
| 제품 설치의 안정적인 서명 | **2026-10-31 chore 교정·검증 완료** | [서명 실패 보호](lessons.md#인증서가-없으면-제품-설치가-ad-hoc-서명으로-계속된다-2026-10-31). 인증서 조회·서명·검증 실패를 주입해 교환·process 종료가 없음을 확인했고 실제 인증서의 임시 bundle 검증도 통과했다. 현재 입력기는 재설치하지 않았다. |
| 설치본과 관측의 연결 | **채택** · 검증의 정확성, 낮은 회귀 위험 | 설치 확인·시작 log·사용자 요청 export 에 같은 binary UUID 또는 digest 를 넣는다. key 마다 계산하거나 입력 내용을 더 수집하지 않는다. |
| Enter·ESC·Tab resend 의 순서와 대상 | **2026-10-31 준비·목적지 교정·설치·주인 확인** · 명령 유실·잘못된 대상의 위험, 빈도 미상 | [준비 실패·목적지 교정](lessons.md#resend-가-준비되지-않은-key-를-먹고-목적지를-잃는다-2026-10-31). 새 event 의 process 지정 전달은 Telegram·terminal 에서 주인이 정상 보고했다. OS queue 의 다음 key 순서·같은 app 안의 입력칸은 미해결이다. |
| 종료 뒤 Caps Lock remap | **검증 채택, 교정 보류** · 기본 key 에 영향, macOS 27 실관측 없음 | [mapping 수명](macos-input.md#homi-process-와-hid-mapping-의-수명)을 근거로 일반 종료·설치 종료와 crash 뒤 상태를 구분한다. snapshot 에 mapping 을 포함한다. guardian daemon 은 추가하지 않는다. |
| Windows App 의 한/영 key 전달 | **2026-10-10 Caps Lock → 오른쪽 Alt 는 주인 확인, LANG1 은 전환 실패** · 기본값 꺼짐 | [원장](apps/windows-app.md#목적지-선택-2026-10-10)의 목적지 선택과 검증 범위를 따른다. [선택한 전환 key 의 일반화](apps/windows-app.md#전환-key-일반화-검토-2026-10-10)는 검증 채택: Shift+Space 의 별도 probe 부터, 오른쪽 ⌘·⌥ 는 단축키 보존까지 확인한다. 원격 Windows 설정·일반 조합 경로·local mode 소유는 바꾸지 않는다. |

### Caps Lock 전환 code review (2026-10-29)

**후속 실험**: event snapshot 교정은 Debug·Release 191개 test 를 통과했으나 실제 IMK 에서 모두 `missing` 이 되어
Caps 전환이 막혔다. 기존 설치본으로 복구했으며 [실패·다음 진단](lessons.md#event-snapshot-실험본이-caps-lock-전환을-전부-거부한다-2026-10-29-rollback)을 따른다.
실제 IMK 는 [timestamp·metadata 를 보존하지 않았고 중복 callback 도 보냈다](macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29).
timestamp 검색은 철회했다. gesture 연결 후보는 기존 판정을 유지한 별도 설치본에서 [실제 29쌍을 연결](apps/orca.md#기존-판정과-gesture-후보의-동시-비교-2026-10-29-1320-kst)했다.
기존 코드만 거부한 4개 tap 을 확인한 뒤 종료 경계 regression 을 보완했다. Debug·Release 201개 test 를 통과한
[교정본을 설치](lessons.md#정상-caps-tap-을-기존-판정이-거부한다-2026-10-29)했고 실제 짧은 전환 34회와 주인의 누락 개선 확인을 얻었다.
같은 시험의 긴 누름은 release 에서 처리돼 보완했고, 이후 네 번 모두 누른 채 처리됨을 관측했다. 주인도 긴 누름의 정상 동작을 확인했다.
unit test·비교 action 을 실제 입력 성공으로 확대하지 않는다.

제품 코드 기준은 `4326e70` 다. 읽기 전용 관찰 뒤 `ModifierTap`·`ModifierKeys`·IMK adapter·hold timer·mapping·기존 test 를 검토했다.
현재 source 를 `/private/tmp` 에 compile 한 model 에서 아래 반례를 확인했다. **시간·counter·mapping 소실은 주입한 조건**이며,
실제 IMK 가 오늘 그 순서로 처리했다는 증명은 아니다. 이 code review 당시에는 제품 코드·설치본·system 설정을 바꾸지 않았다.

1. **우선 교정 검토 — tap 의 시간 구간과 counter 의 시간 구간이 다르다.**
   [HomiInputController](../Sources/homi/HomiInputController.swift)의 `Activity.now()` 는 처리할 때의 누적 횟수이고,
   [ModifierEvent adapter](../Sources/homi/Client.swift)는 원래 event timestamp 를 붙인다.
   [ModifierTap.release](../Sources/InputSession/ModifierTap.swift)는 counter 차이를 무조건 누르는 동안의 활동으로 해석한다.
   model 의 물리 시각은 press `10.0`, release `10.1`, 다음 key `10.3` 이다. press 처리 `10.01` 은 같게 두고
   release 처리를 `10.11 → 10.4` 로 옮기자 결과가 `toggle → none` 으로 바뀌었다. **event 전달 순서가 맞아도 정상 tap 을 버린다.**
   반대로 ⌘C 처럼 IMK 에 오지 않는 key 가 `10.05` 에 발생하고 press 를 `10.06` 에 처리하면,
   두 sample 에 이미 같은 횟수가 들어가 단축키를 tap 으로 인정한다. 시간 구간이 잘못된 하나의 원인에서 거짓 거부·거짓 허용이 모두 나온다.
   이 code review 당시에는 실제 homi 의 snapshot 이 없었다. 이후 [동시 비교](apps/orca.md#기존-판정과-gesture-후보의-동시-비교-2026-10-29-1320-kst)로 거짓 거부를 포착했다.
2. **별도 교정 후보 — hold timer 가 release 미도착을 계속 누름으로 취급한다.**
   [HomiInputController.capsLockHeld](../Sources/homi/HomiInputController.swift)는 현재 key 의 누름 상태를 확인하지 않고,
   `ModifierTap.holdReached` 는 armed·counter 일치만 본다. 물리 release `10.1` 의 전달이 `10.6` 으로 늦고 timer 가 `10.5` 에 먼저 실행되면,
   model 은 대문자 고정 action 을 내고, 뒤늦은 release 는 `held` 때문에 버렸다. 짧은 tap 의 timestamp 로 재판정하지 않는다.
   이 순서의 실제 발생은 미관측이다. timer 수명 교정은 유지하며, 떼기 전 대문자 고정 요구를 없애는 변경으로 대신하지 않는다.
3. **별도 교정 후보 — 좌우 modifier 를 합친 flag 로 오른쪽 key 의 누름·뗌을 판정한다.**
   `KeyEvent` adapter 는 좌우 정보를 버리고, [ModifierKeys.track](../Sources/InputSession/ModifierKeys.swift)는 `.control` 이 남아 있으면 press 로 본다.
   왼쪽 Control 을 누른 채 Caps Lock 을 눌렀다 떼면, Caps release 뒤에도 `.control` 이 남아 timer 를 다시 건다.
   model 은 이 상태에서 Caps 를 누르고 있지 않은데 대문자 고정 action 을 냈다. `.command`·`.option` 도 같은 판정 방식이다.
   양쪽 key 의 상태를 구분할 검증이 필요하며, 이번 단독 Caps 누락의 원인으로 지목하지 않는다.
4. **별도 교정 후보 — 같은 remap 경로이면 실제 mapping 을 확인하지 않는다.**
   [CapsLockMapping.apply](../Sources/homi/CapsLockMapping.swift)는 `applied == route` 일 때 read 전에 성공을 반환한다.
   model 은 적용 후 mapping 을 비운 다음 같은 `.homi` 를 요청해도 성공을 반환했고 mapping 은 비어 있었다.
   [mapping 수명](macos-input.md#homi-process-와-hid-mapping-의-수명)과 cache 의 수명이 다르지만, `SourceWatcher` 의 invalidate 는 wake 에만 있다.
   이번 관측에는 오른쪽 Control 신호가 있었으므로 이 경로를 누락의 우선 원인으로 삼지 않는다. 다른 도구의 mapping 을 보존하는 기존 교훈도 지킨다.

**검증 공백**: `ToggleTests` 의 첫 key 검사는 이미 인정된 `.toggle` 을 직접 넣고, `ModifierKeysTests` 는 counter 증가가 누르는 동안의 입력이라고 전제한다.
`HoldTimerTests` 는 owner 수명을 검사한다. 이 test 들의 통과는 위 시간 구간·전달 지연·좌우 구분의 반례를 배제하지 않는다.
거부된 modifier 는 `guard let action` 에서 기록 없이 반환하므로, 기존 ring buffer 만으로 counter 불일치·cancel·hold 를 구분할 수도 없다.

다음 교정의 기준은 **같은 물리 event 순서에서 전달 지연만 달라져도 tap·chord 의 뜻은 같아야 한다**는 것이다.
정상 tap → 다음 key, 보이지 않는 Ctrl·⌘ 단축키, 짧은 tap 의 늦은 release, 실제 hold, lifecycle 취소를 함께 검증한다.
단순 counter 제거·tap 을 press 에서 확정·임의 유예 시간은 단축키·대문자 고정 요구를 보존하지 못하므로 바로 적용하지 않는다.

### activation 의 두 counterexample

[HomiInputController.activateServer](../Sources/homi/HomiInputController.swift)는 client 에 묻지 않고 cached ID 또는 frontmost app 을 사용한다.
이 원칙은 [activate 질의의 교착 교훈](macos-input.md)을 지키므로 유지한다. 교정 전에는 다음 두 경계가 빠져 있었다.

1. **같은 event 의 재활성화**: `startsInEnglish` app 에서 한글로 입력하다 mark 중 deactivate → activate 가 끼면,
   [SessionDriver.activate](../Sources/InputSession/SessionDriver.swift)는 조합을 이어 가지만 [ModeMemory.activate](../Sources/InputSession/ModeMemory.swift)는 영문으로 reset 한다.
   model 에서 `ㅎ` mark 가 남은 상태로 mode 가 영문이 되었고, 다음 `ㅏ` key 는 `insert("ㅎ")` 뒤 통과했다. 기대한 `하` 대신 `ㅎa` 경로가 성립한다.
2. **fallback 과 실제 client 가 다름**: activate 는 fallback app 의 시작 규칙을 적용한다. 첫 event 의 `resolveApp` 이 실제 bundle ID 를 알아내도
   그 activation 에 대한 mode 초기화·layout 을 바로잡지 않는다. 실제 client 의 시작 규칙을 놓치거나 다른 app 의 기억을 reset 할 수 있다.

첫째는 독립적인 두 model 실행에서 확인했다. 둘째는 코드상 처리 누락이다. **둘 다 해당 app 의 실제 실패·빈도는 확인하지 않았다.**
LaunchBar 원장의 기존 정상 확인을 취소하거나 현재 비활성의 원인으로 지목하지 않는다.

후속 교정은 늦은 ID·같은 event 의 재활성화·실제 새 시작·activation 알림 누락을 순수 coordinator test 로 고정했다.
같은 event 의 재활성화에서는 mode·layout 을 이어 간다. 실제 ID 를 알아내기 전의 layout 보정은 넣지 않았다 — key 중 system 변경의 위험을 피하고 별도 관측으로 남긴다.
실제 새 시작의 영문 요구와 fallback 의 제한은 [교훈](lessons.md#재활성화가-mode-를-reset-하고-실제-client-의-시작-규칙을-놓친다-2026-10-09)에 있다.
매 key 영문으로 reset 하거나 모든 activate reset 을 없애는 수정은 각각 정상 한글 전환과 시작 규칙을 깨므로 기각한다.

### insert 중 client 확인의 적용 범위

초기 model 은 `insert("한") → mark("ㄱ")`의 insert 에서 이전 mark 의 확인 callback 을 주입해
Session 은 비고 client 에 `ㄱ` mark 만 남는 반례를 확인했다. **이 callback 순서는 실제 app 에서 미관측**이다.
2026-10-31 주인이 논리적 결함도 교정하도록 요청해, 기존 client 확정 판단의 적용 범위를 그때까지 보낸 mark 에 한정했다.
아직 보내지 않은 mark 는 확인 대상이 될 수 없다는 계약이며, renderer 의 실제 확정을 관측했다고 주장하지 않는다.
실패 test·대응·제한은 [교훈](lessons.md#이전-mark-의-확인이-다음-조합을-지운다-2026-10-31)에 둔다.

### 구조 개선 뒤 남은 세 경계 (2026-10-31)

앞선 구조 개선 네 단계와 구분한다. 새 1번은 위 client 확인 범위, 2번은 resend 준비·대상, 3번은 busy 중 후보 UI 유실이다.
세 항목을 교정해 15:23 에 설치했고 주인이 probe 의 기본 입력·후보·app 왕복을 확인했다.
1번의 재활성화 경계를 추가 보완해 Debug·Release 각각 260개 test 뒤 15:32 에 재설치했다. 최종본의 Chrome 입력칸 이동도 주인이 정상 확인했고 AX·DOM event 를 대조했다. Telegram·terminal 재전송도 정상 보고했으며 개별 범위는 각 기록을 따른다.
1번의 다음 key 보류와 2번의 전체 keyboard 가로채기는 추가하지 않았다. 3번은 후보 뜻 표시 누락과 별개다.

## 구조 개선 계획 (2026-10-31)

`c461b75` 기준 review 뒤 주인이 네 항목 모두의 개선을 목표로 정했고, **1번부터 차례로 진행**한다.
일반 조합·Backspace·내부 한/영·focus 이동의 안정성이 우선이다. 구조 추출과 호환 정책 변경을 한 번에 섞지 않는다.

| 순서 | 개선 | 범위·통과 기준 | 상태 |
|---|---|---|---|
| 1 | 제품의 입력 순서를 test 에서 직접 실행 | app 식별 → mode 준비 → Session 판단 → client 반영을 `InputCoordinator`로 모은다. test 는 client·환경만 대체한다. ID 질의부터 끝나는 동기 경계와 실제 입력/종료 flush 구분을 보존하고, 설치 후 기본 입력을 확인한다. | 완료 — 설치·주인 확인 |
| 2 | app 식별 근거와 종료 의도를 type 으로 표현 | 실제 client ID·fallback, client 자체 확정·homi 확정의 뜻을 명확히 한다. `String`·`trusted`·`insert: false`의 조합으로 잘못된 상태를 만들 가능성을 줄인다. 현재 종료 정책은 먼저 test 로 고정하며 callback token 을 입력칸 소유권으로 취급하지 않는다. | 완료 — 설치·주인 확인 |
| 3 | app 판별과 호환 정책 분리 | Chromium 발견 결과와 commit 정책을 분리하고, 미확인·확인된 부재를 구별한다. cold 판별을 옮길 때 첫 callback 의 행동을 먼저 검사한다. ChatGPT 에 우회를 적용할지는 실제 app 검증 후 따로 결정한다. | 완료 — 설치·주인 확인. cold 조회 이동은 보류 |
| 4 | 입력 revision 과 UI revision 분리 | 무변화 modifier event 가 필요한 후보 표시를 취소하지 않도록 한다. 실제 후보 변경·확정·focus 종료 뒤에는 오래된 UI 가 뜨지 않는지 검사한다. | 완료 — 설치·주인 확인. 뜻 표시 누락은 별도 미해결 |

### 1번: 입력 coordinator 추출

[InputCoordinator](../Sources/InputSession/InputCoordinator.swift)가 app cache·시작 intent·실제 입력 depth 를 소유한다.
`InputClient`는 ID·한자 질의·Action 반영, `ModeStore`는 기존 shared mode memory 와 저장의 경계다.
memory 접근을 끝낸 뒤에만 client 를 호출하며 별도 mode cache 는 추가하지 않는다.
`HomiInputController`에는 NSEvent 해석·modifier 관찰·표시·IMK lifecycle 의 기존 종료 정책이 남는다.
coordinator 생성 중에는 환경 callback 을 호출하지 않으며, Session·사전은 기존처럼 controller 생성 때 준비한다.
activation 의 layout 호출 위치와 Chromium commit 정책도 이번 추출 범위 밖이다.

[ActivationTests](../Tests/InputSessionTests/ActivationTests.swift)의 app 판별·mode 준비 복제 코드를 제거했다.
기존 재활성화·늦은 ID 반례는 제품 coordinator 를 통과하고, ID 질의 재진입·mode 저장 순서·후속 질의의 종료 보류·bound client 확정·
modifier 한자 질의·resend 권한·두 controller 의 mode 공유를 추가로 검사한다.
[ClientTests](../Tests/HomiTests/ClientTests.swift)는 실제 `Client` adapter 와 fake IMK proxy 를 연결해 ID 질의·insert callback 도 검사한다.
이는 실제 app 의 callback 의미·조합 완료를 증명하지 않는다. 설치 뒤 검증과 최근 간헐 증상의 원인 확정은 구분한다.

검증: `swift build`와 Debug·Release 각각 **223개 test** 통과(기존 213개 유지, 새 경계 검사 10개).
2026-10-31 **13:39:26 KST** 에 자체 서명본을 설치했다(CDHash `a856f69785c9cc548667c0455a1dec67e0a9ce9d`).
새 PID `30602`의 시작과 modifier observer 준비를 확인했다. 주인이 요청한 probe 실제 keyboard 시험이 정상 동작했다고 보고했다.
시험 범위는 `한글` 조합·Backspace 뒤 `ㄹ` 재입력, Caps Lock 으로 영문 `a`·한글 `가` 전환 입력,
다른 app 에 갔다가 `⌘Tab`으로 돌아와 `가` 입력이다. 정상 여부는 주인 보고이며 도구의 합성 key 결과가 아니다.
근거는 `build/coordinator-{build,debug-tests,release-tests,install,startup}-20261031.log`다.

### 2번: app 식별 근거와 조합 종료 방침

`709002f` 기준 동작을 유지하면서 두 경계를 type 으로 표현했다.

- [InputApp](../Sources/InputSession/InputApp.swift)은 `client(ClientAppID)`와 `fallback(String)`을 구분한다.
  `ClientAppID`는 nil·빈 답으로는 생성되지 않고 coordinator 는 이 type 만 cache 한다. `ModeActivation`에는 app 과 근거가 함께 전달되므로
  별도의 `trusted` 값과 엇갈리지 않는다. 늦은 ID 보정을 위한 token 도 fallback 에서만 만드는 `FallbackInput`으로 명시했다.
  ID 를 모를 때 첫 key 를 fallback 으로 해석하는 한계는 남으며, app ID 는 개별 입력칸의 identity 가 아니다.
- [CompositionEnd](../Sources/InputSession/SessionDriver.swift)는 `commitToClient`와 `alreadyCommittedByClient`를 구분한다.
  `insert: false` 대신 방침을 명시하며, 겹친 명시적 종료 중 재삽입 금지와 마지막 callback 대상을 유지한다.
  deactivate 는 같은 event 의 재활성화로 취소할 수 있어 명시적 종료와 별도로 둔다. bound client 선택·flush 시점도 유지한다.
  이 type 은 caller 의 방침이며 실제 client 의 확정 증거가 아니다. Chromium 판별·commit 정책은 3번의 별도 검토 대상이다.

변경 전에 추가한 세 test 로 **같은 ID 문자열의 fallback/client 구분(nil·빈 답), 종료 순서와 무관한 재삽입 방지·후보 정리,
명시적 commit 대상의 우선순위**를 고정했다. 변경 전 세 test 와 변경 후 관련 58개 test 가 통과했다.
근거는 `build/typed-boundaries-{before,after}-20261031.log`다. 새 간헐 결함을 재현·해결했다는 뜻은 아니다.

`swift build`와 Debug·Release 각각 **226개 test**가 통과했다. 2026-10-31 **14:06:34 KST** 에 자체 서명본을 설치했고
(CDHash `94e3ad6b19d4f49503e15a4e1a5c058cb6029050`), 새 PID `3115`의 시작·modifier observer 준비·probe 입력 수신을 확인했다.
주인은 `한` 조합 → 다른 app 으로 `⌘Tab` → probe 복귀 → `글` → Caps Lock·영문 `a` → Caps Lock·한글 `가`의
결과가 **`한글a가`**로 정상임을 확인했다. 도구에서도 probe 의 최종 text 와 한/영 mode 왕복을 관측했다.
기록은 `build/typed-boundaries-{build,debug-tests,release-tests,install,runtime}-20261031.log`다.
이 확인을 다른 app 이나 알려진 source 왕복 문제의 해결로 확대하지 않는다.

### 3번: renderer 판별과 commit 정책 분리

`826719c`의 판별·종료 분기를 [RendererDiscovery](../Sources/homi/RendererDiscovery.swift)와
[CommitPolicy](../Sources/InputSession/CommitPolicy.swift)로 나눴다. 판별은 bundle 의 근거만 돌려주고,
정책은 기존 `… Helper (Renderer).app`에서만 그 callback 의 TIS 선택을 읽는다. bound client 반영·SessionDriver 의 종료 합치기는 유지한다.
[조회 실패의 부재 cache 결함](lessons.md#renderer-조회-실패가-영구적인-부재-판정이-된다-2026-10-31)을 실패 test 뒤 교정했다.
확인된 판별은 기존처럼 process 동안 app 별로 cache 하고, TIS 선택은 cache 하지 않는다.

새 검사 11개는 cold 첫 callback·warm cache 뒤 source 변경, ID 없음, 정상 부재·읽기 실패·부분 실패와 회복,
기존 helper 우선순위·다른 renderer 이름의 정책 미적용을 다룬다. `build/renderer-policy-{before,after}-20261031.log`가 근거다.
설치 bundle 을 제품 판별 코드로 읽은 결과는 [Chrome](apps/chrome.md#판별정책-분리-검증-2026-10-31),
[Orca](apps/orca.md#renderer-판별-재확인-2026-10-31), [ChatGPT](apps/chatgpt.md#판별정책-분리-2026-10-31),
[TextEdit](apps/textedit.md#renderer-부재-확인-2026-10-31)에 둔다. 별도 실행의 정책 비교는 source=true 를 주입한 model 이며 실제 app callback 검사가 아니다.

**cold 조회 시점은 유지한다.** cache 준비 전에 첫 Chrome callback 이 오면 기본 확정으로 중복할 수 있어 단순 async 이동은 하지 않았다.
별도 process 의 한 차례 측정은 첫 Chrome 조사 21.382ms, 이후 다른 세 app 의 각 cold 조사 0.609–1.595ms였다.
NSWorkspace 초기화를 포함할 수 있고 실제 IMK callback 지연·상한을 측정한 것은 아니다.
`build/RendererPolicyReview20261031.swift`·`build/renderer-policy-installed-bundles-20261031.log`에 실행 근거가 있다.
typing 경로의 file I/O 제거는 첫 판별을 미리 확보할 근거가 필요하므로 남긴다.

`swift build`와 Debug·Release 각각 **237개 test**가 통과했다. 2026-10-31 **14:29:08 KST** 에 자체 서명본을 설치했고
(CDHash `f62d321ce294ee5595f66cb282c62eed879ea508`), 새 PID `38121`의 시작·modifier observer 준비를 확인했다.
주인이 [Chrome 의 조합 중 입력칸 이동](apps/chrome.md#판별정책-분리-검증-2026-10-31)을 정상 확인했다.
근거는 `build/renderer-policy-{build,debug-tests,release-tests,install,runtime}-20261031.log`다.
이 확인을 다른 app·source 왕복이나 간헐 첫 key 문제의 해결로 확대하지 않는다.

### 4번: 입력 revision과 후보 UI revision 분리

`6170865` 기준 [무변화 event 의 후보 표시 취소](lessons.md#무변화-event-가-한자-후보-표시를-취소한다-2026-10-31)를 실패 test 로 고정한 뒤 교정했다.
Session 은 후보 상태를 할당할 때만 `candidateRevision`을 바꾼다(같은 선택의 재표시 포함). 후보가 없는 일반 조합·반복 commit 은 이 값을 바꾸지 않는다.
기존 event·종료 세대는 `inputRevision`으로 남기고 UI 판정에는 쓰지 않는다. 후보 표시·닫기를 맡는
[CandidatePresentation](../Sources/homi/CandidatePresentation.swift)은 owner·busy·active 조건을 유지하며, Task 에서는 client 질의·Session 변경을 하지 않는다.
caret 위치는 기존처럼 동기 event 안에서 읽고 재진입한 종료의 flush 가 끝난 뒤에만 Task 를 예약한다.

[새 test 10개](../Tests/HomiTests/CandidatePresentationTests.swift)는 제품 coordinator·Session·Client·표시 guard 를 연결하고
client proxy·owner·mode 저장소·panel·UI queue 환경을 대체한다. 무변화 event, 한자 key·modifier tap, 선택·목록 변경, 취소·확정·모드·focus·source 종료,
같은 글자로 재시작, 다른 owner, caret 질의 재진입·Session mutation 중 UI 실행을 검사한다.
보이는 창의 hide 와 일반 조합·Backspace·확정의 후보 UI/위치 질의 0도 확인한다. UI 작업 전후 문서·Session·mode·질의 횟수는 같다.
`swift build`와 Debug·Release 각각 **247개 test**가 통과했다. 2026-10-31 **14:41:46 KST** 에 자체 서명본을 설치했고
(CDHash `aad69015f59140ad2e481f1d0b4f6fdbb2f74a20`), 새 PID `49052`의 시작·modifier observer 준비·probe 입력 수신을 확인했다.
주인이 [probe 의 기본 입력·후보 선택·app 왕복](apps/engines/appkit.md#probe-의-후보-ui-검증-2026-10-31)을 정상 확인했다.
근거는 `build/candidate-revision-{before,after,build,debug-tests,release-tests,install,runtime}-20261031.log`다.
[첫 목록의 후보 뜻 누락 보고](apps/engines/appkit.md#후보-뜻의-첫-표시-누락-보고-2026-10-31-미해결)는 별도 미해결이며, 이 통과를 모든 표시·app 호환성의 완성으로 확대하지 않는다.

## focus와 source 전환 code review (2026-10-31)

제품 source 기준은 `623adcb`다. 최근 Telegram 첫 key·Orca menu 누락·ChatGPT source 전환 지연 보고에 맞춰
`handle → app 식별 → mode 준비 → Session → client 반영`, activation·source 종료와 관찰 경로를 검토했다.
**코드의 반례와 실제 증상의 원인은 다르다.** review 단계에서는 제품을 변경하지 않았다.
이후 주인 승인으로 1·3번을 교정·설치했다. [후속 검증과 제한](lessons.md#늦은-client-id-가-실제-app-의-mode-기억을-덮는다-2026-10-31)을 따르며, 아래 반례는 교정 전 기준이다.

### 1. 조합·전환 없는 첫 key 도 다른 app 의 mode 를 복사한다 — 교정·설치

검토 당시 [HomiInputController.handle](../Sources/homi/HomiInputController.swift)는 모든 keyDown 에서 결과를 알기 전에
`ModeActivation.inputStarted`를 호출했다. client ID 가 비면 fallback app 을 저장하고, 뒤늦게 실제 ID 를 알게 된
[ModeActivation.prepare](../Sources/InputSession/ModeActivation.swift)는 fallback 의 현재 mode 를 실제 app 의 기억에 복사했다.

반례: 실제 app 은 한글로 기억하고 fallback app 은 영문인 상태에서, 첫 key 의 client ID 가 없다고 가정한다.
일반 key 나 Control 단축키를 **처리하지 않고 그대로 넘겨도** 입력 시작을 소비한다. 조합은 비어 있고 mode 를 바꾸지도 않았지만,
다음 event 에 실제 ID 를 알면 그 app 의 한글 기억까지 영문으로 덮는다. controller 의 `prepareMode`는 이 변경을 저장한다.
이는 앞선 Telegram model 의 늦은 ID 결과를, **이어 갈 조합·전환이 없는 조건**으로 좁혀 확인한 것이다.

제품 `InputSession` module 을 직접 실행한 `build/ActivationReview20261031.swift`에서 두 반례와 세 대조 조건을 확인했다.

| 합성 조건 | 교정 전 결과 |
|---|---|
| 실제 ID 없음 → 영문 fallback 으로 일반 key 통과 → 실제 ID 확인 | 실제 app 의 한글 기억이 영문으로 바뀜 |
| 같은 조건에서 Control 단축키 통과, 조합·mode 변화 없음 | 역시 영문으로 바뀜 |
| 첫 event 부터 실제 ID 를 앎 | 실제 app 의 한글 기억 유지 |
| ID 를 모르는 동안 실제 한글 조합을 시작함 | 늦은 ID 확인 뒤에도 조합의 한글 mode 유지 |
| ID 를 모르는 동안 명시적으로 영문 → 한글 전환 | 늦은 ID 확인 뒤에도 새 mode 유지 |

교정 기준은 **명시적 mode 변경·진행 중 조합의 연속성과, 아무 변화 없이 넘긴 key 를 구분**하는 것이다.
모든 fallback 이전을 없애면 기존 `ActivationTests`의 조합·toggle 보존 요구가 깨진다.
후속 수정에서 두 반례를 실패하는 regression test 로 먼저 고정했고 기존 조합·toggle 보존도 확인했다.
실제 실패 때 ID 가 비고 fallback 이 다른 app 이었다는 증거는 아직 없다. 이 경로만으로는
Telegram 의 “첫 key 만 영문, 곧바로 한글 복구”나 초성 유실, source 목록 누락 전체를 설명하지 못한다.

### 2. ChatGPT renderer 판별과 commit 정책 — 판별 누락 확인, 정책 변경 전 app 검증

[설치 bundle·실제 판별 함수의 결과](apps/chatgpt.md#별도-code-review-renderer-helper-이름-판별)를 확인했다.
이 분류는 `commitComposition`에서 client 자체 확정으로 볼지 `insertText`를 보낼지 바꾼다.
누락은 명확하지만, renderer helper 가 있다는 사실만으로 기존 Chromium 우회가 이 app 에도 맞는다고 정하지 않는다.
일반 조합 뒤 click·focus 이동의 callback 과 실제 글자 수를 먼저 검증한다. 다른 source 왕복은 그 다음이다.

### 3. controller hash 는 수명을 넘는 진단 ID 가 아니다 — 교정·실행 확인

[HomiInputController.traceID](../Sources/homi/HomiInputController.swift)는 검토 당시 `ObjectIdentifier(self).hashValue`였다.
객체 해제 뒤 주소 재사용과 hash 충돌을 구별하지 못하므로, 서로 다른 수명의 controller 를 같은 것으로 읽을 수 있다.
[Orca 회복 log](apps/orca.md#input-menu-의-homi-누락-보고와-회복-2026-10-31-미해결)에도 동일 값 아래 mark 이력의 초기화·최초 event 기록이 다시 나타났다.
process 내 생성 번호를 각 controller 에 한 번 부여하고 process 식별과 함께 기록하는 변경을 채택한다.
이는 입력 내용을 더 모으거나 입력 판단을 바꾸는 일이 아니다. 과거 log 만으로 같은 객체의 mode reset·조합 소실을 확정하지 않는다.

### 4. activation의 layout 호출 — 검증 공백, 확인된 장애는 아님

`activateServer`의 재활성화 판정은 `inputDepth > 0 && !session.hasExplicitEnd`다.
평범한 activation 의 `Client.apply(.layout)`는 `SessionDriver.withEvent` 밖에서 실행한다.
만일 `overrideKeyboard` 안에서 같은 controller 의 activation 이 중첩되면 `inputDepth == 0`이므로 layout 호출을 다시 허용한다.
기존 activation model 은 이 IPC 를 실행하지 않고, `ClientTests`의 `overrideKeyboard`도 빈 구현이라 이 경계를 검사하지 않는다.

**해당 중첩이 실제로 일어났다는 log·재현은 없다.** [macSKK #292](https://github.com/mtgto/macSKK/pull/292)도
activate 의 override 제거 사례이지만 작성자가 원인 미확정·local 미재현이라고 명시했다. 그 변경을 homi 의 해법으로 복사하지 않는다.
우리 경계의 callback 주입 검사를 먼저 하고, 실제 client 관측에서 호출의 시작·반환·중첩 여부를 대조한다.
ABC layout 지정은 TIS source 를 ABC 로 선택하는 것과 다르다. 호출을 없애거나 key 처리 안으로 옮기면 문장부호·원격 layout 요구를 훼손할 수 있다.

### 원인에서 배제한 범위와 다음 순서

- 현재 제품 source 에 source disable·재등록·`TISSelectInputSource` 호출은 없다. `Info.plist`의 한국어 mode 는 visible/enabled 이다.
  menu 누락의 직접 원인을 찾은 것은 아니며, homi 의 IPC 지연이나 app/system 과의 상호작용이 무해하다는 증명도 아니다.
- 일반 key 의 modifier 는 그 `NSEvent`에서 읽고 observer 는 원본 event 를 반환한다.
  “⌘Tab release 를 homi 가 못 봐서 이후 일반 key 에 Command 가 계속 붙는다”는 내부 cache 경로는 없다.
- [insert 중 client 확인 범위](#insert-중-client-확인의-적용-범위)는 2026-10-31 후속 교정했다. 실제 callback 의미·순서와 단일 `ActiveInputSession`의 한계는 별도다.
  callback 세대와 실제 입력칸 소유권을 확인하지 않은 일괄 commit·무조건 insert 는 과거 유실·누출 교훈과 충돌한다.

1·3번의 교정 후 probe 실제 입력은 주인이 확인했다. 일상 사용과 2번의 실제 commit 검증, 4번의 callback 주입 검사를 이어 간다. 새 사용자 관측만 무기한 기다리는 대신
소유권·event 순서의 경계를 검사하되, 이 네 작업을 최근 증상 전체의 해결로 약속하지 않는다.

검증: `swift build`와 Debug `swift test` **207개 통과**, 별도 module 검사에서 위 두 반례·세 대조 조건 확인,
제품 Chromium 판별 함수의 실제 bundle 조회 확인. 기존 suite 의 통과는 새 반례를 검사한다는 뜻이 아니다.
build·test 결과는 `build/source-review-build-20261031.log`·`build/source-review-tests-20261031.log`에 있다.

## 기능·표시와 cold path 의 안건

| 안건 | 판단 | 검토 결과 · 다음 검증 |
|---|---|---|
| 보이지 않는 한자 후보 | **반례 교정·설치·주인 확인** | [4번 구현·검증](#4번-입력-revision과-후보-ui-revision-분리)을 따른다. event 횟수와 후보 변경을 분리하고 owner·busy·active 조건은 유지한다. 실제 간헐 증상의 원인 확정은 아니다. |
| 첫 후보 목록의 뜻 표시 누락 | **주인 결정: 재발 때 재검토** | [probe 보고](apps/engines/appkit.md#후보-뜻의-첫-표시-누락-보고-2026-10-31-미해결). 같은 한 글자의 다음 목록에는 뜻이 보였다. 첫 쪽 사전 값은 비어 있지 않다. 재발하면 첫 show 와 다음 show 의 데이터·label 가시성을 대조한다. |
| caret 질의의 부작용 | **관측 채택, 교정 보류** | [Chromium 원장](apps/engines/chromium.md)의 firstRect 실패는 click 확정과 다른 경로다. homi 의 attributes 질의와 그 callback 이 실제로 연결되는지 먼저 확인한다. 표시를 위해 입력을 위험하게 하지 않는다. client 질의를 event 밖으로 옮기면 교착 교훈을 깨므로 기각한다. |
| Chromium 최초 판별 | **cache 실패 교정·판별과 정책 분리** | [3번 구현·검증](#3번-renderer-판별과-commit-정책-분리)을 따른다. 미확인을 부재로 고정하지 않고 첫 callback 의 기존 판단을 검사했다. 실제 간헐 증상의 원인으로 확인한 것은 아니다. cold 조회의 단순 async 이동은 여전히 보류한다. |
| ModeHUD·indicator 의 stale Task | **indicator 는 activation 교정에 포함, ModeHUD 는 후순위** | indicator 는 owner·app·현재 mode·pass-through 를 확인한다. ModeHUD 의 Task guard 는 별도 안건이며 실제 실패는 미관측이다. 표시 때문에 mode·source 를 다시 바꾸지 않는다. |
| ModeHUD 의 hide animation | **후순위 관측** | [ModeHUD](../Sources/homi/ModeHUD.swift)는 예약 작업을 취소하지만 이미 시작한 fade 까지 끝내는 보장은 없다. 새 말풍선과 겹친 animation 의 실제 표시부터 확인한다. 조합·client 반영을 고칠 이유는 없다. |
| `UserDefaults` 저장의 비동기화 | **근거 없는 성능 교정은 보류** | [저장 계약](macos-input.md#mode-저장과-key-처리)을 확인하니 key 경로의 `Memory.save` 만으로 동기 disk stall 이라고 단정할 수 없다. 지연이 관측되면 측정 후 판단하며 mode 의 SOT 는 계속 동기 memory 다. |
| 진단·resource 의 작은 개선 | **후순위** | [saveRecord](../Sources/homi/Record.swift)의 초 단위 이름은 같은 초의 export 를 덮어쓸 수 있다. 한자 사전의 parse 실패도 `try?` 로 사라진다([Memory](../Sources/homi/Memory.swift)). export 이름의 충돌 방지·내용 없는 오류 사유 표시는 가능하지만 기본 조합보다 먼저 할 일은 아니다. |

후보 문제의 model 결과는 `showSuppressed=true, candidatesStillOpen=true` 였다. 보이지 않는 후보가 숫자·Enter 를 후보 선택으로 처리할 수 있다는 점에서
표시만의 장식 문제와 다르다. 다만 한자 경로의 문제이므로 기본 조합·focus 이동의 검증을 건너뛰고 설치하지 않는다.

## 유지·보류·기각하는 제안

| 제안 | 판단 · 이유 |
|---|---|
| HangulCore rewrite | **기각**. spec 와 추가 검사에서 새 결함이 없다. 기본 조합을 넓게 바꿀 근거가 없다. |
| 순수 엔진·Action 목록·동기 재진입 경계·bound client·weak timer·atomic 설치 | **유지**. 기존 재현과 교훈이 지지한다. 다만 bound client 는 DOM 입력칸 소유권의 증명이 아니며 재진입 경계가 모든 mode·callback 의미를 해결한 것도 아니다. |
| Chrome homi → ABC → homi 교정 | **후순위 보류**. 주인에게 드문 경로다. [Chrome](apps/chrome.md)에 실패와 실험 기준을 보존한다. 필요할 때 조합을 먼저 끝낸 뒤 바꾸는 운용은 가능한 임시 타협이며 해결 완료는 아니다. |
| `replacementRange` 의 SDK 계약 교정 | **단독 실험으로 보류**. [range 실험 교훈](lessons.md#imk-현재-selection-의-range-계약이-구현과-다르다-2026-10-09-교정-보류)대로 계약 차이는 남지만 앞선 실험의 인과를 분리하지 못했다. 다른 commit 정책과 함께 바꾸지 않는다. |
| `composedString` 추가·attributed mark 로 변경 | **원인 교정으로는 보류**. 누락이나 plain String 이 이번 실패를 만들었다는 증거가 없다. 직접 marked text 를 보내는 방식 자체를 결함으로 보지 않는다. |
| SourceWatcher 대상 확대 | **검증만 채택**. [현재 단일 owner 의 한계](macos-input.md#client-호출은-imk-lifecycle-을-재진입시킬-수-있다)는 인정한다. 두 controller model 을 검증하되, 모든 controller 일괄 commit 은 stale client·새 입력칸 누출 위험 때문에 기각한다. |
| TIS 선택·늦은 markedRange·client identity 로 종료 원인/이전 입력칸 판정 | **기각**. 실제 실패한 근거다. 같은 event 안의 lifecycle 합치기와 다음 key 까지 commit 을 보류하는 것은 구분한다. |
| timer retry·source 강제 복원·비활성 때 자동 enable/재등록 | **기각**. 입력 순서·등록 상태를 추측으로 바꾸며 원인 증거를 지운다. state snapshot 이 먼저다. |
| `/Library` 이동·daemon 재시작·guardian 추가 | **현재 대안으로 기각**. 주인의 두 설치 위치 관측과 맞지 않고 기본 입력의 새 위험·복잡도를 만든다. `imklaunchagent` 는 종료하지 않는다. |
| app 별 추측 우회·새 옵션·추가 dependency | **기각**. 재현과 원장 없이 늘리지 않는다. Froala·extension·VS Code 를 원인으로 단정하지 않는다. |
| 모든 app·옵션을 매번 전수 manual 검사 | **기각**. 변경의 영향을 받는 대표 engine·app 경로를 실제로 확인하고 일상 관측으로 보완한다. Office 외부 source/report 를 현재 homi 의 app 검증으로 승격하지 않는다. |

## 검증 근거와 다음 순서

일본어 입력기의 최신 공개 코드도 [recipe 검토](research/japanese-ime-recipes.md)로 대조했다. activation intent 를 실제 client event 와 함께 적용하는 방식,
client 반영 단계·질의 횟수를 검사하는 bridge test, 현재 상태로 늦은 UI 를 검증하는 presenter test 를 다음 검증에 채택한다.
외부 source 는 homi 의 callback 의미·입력칸 소유권을 증명하지 못했다. 비동기 commit·system mode 동기화·가짜 mark 우회는 가져오지 않으며 기본 입력의 우선순위는 유지한다.

- 조사 단계의 `swift build`·Debug `swift test` 는 138개 모두 통과했다. Release 138개 통과는 앞선 [작업 마감](lessons.md#2026-10-09-작업-마감)의 검증이다.
  proxy 인자·fake client 의 반영을 actual app 완료로 세지 않는다.
- activation·관측 연결 후 전체 test 와 실제 검사 결과는 [후속 기록](lessons.md#2026-10-09-activation-교정callback-관측)에 둔다.
- 이번 별도 검사에서는 spec 의 독립 자모 분해표와 Unicode 완성형 정의로 **11,172개 음절**, 자소 Backspace 복원 **41,230 step**,
  받침 뒤 직접 모음의 도깨비불 **150,822 transition**을 검사했고 실패는 0이었다. 물리 key mapping·모든 임의 입력열·IMK 호환성의 증명은 아니다.
- baseline HangulCore/InputSession 을 `/private/tmp` 에 직접 compile 한 model 로 후보 revision, activation mode reset, insert 중 client 확인을 검사했다.
  이 model 들은 다음 regression 의 시작점이며 실제 app 재현을 대신하지 않는다. 두 subagent 의 activation model 을 별도로 실행해 같은 불일치를 확인했다.

다음 작업은 이 순서로 한다.

1. source 왕복을 섞지 않고 현재 설치본의 일반 조합·Backspace·homi 내부 한/영·입력칸 이동부터 확인한다.
   주인의 기본 입력 정상 보고를 개별 Chrome·native 경로의 통과로 확대하지 않는다. 실패하면 새 우회보다 기본 경로를 먼저 복구한다.
2. activation 교정본의 native text·LaunchBar·Chromium 경로를 확인한다. client 확인의 action 단계는 관측하고 적용 대상을 확인한 뒤 정책을 결정한다.
   후보 revision 은 한자 경로를 따로 교정·검증한다.
3. 제품 signing 실패 때 기존 설치본 보존은 [교정·검증을 마쳤다](lessons.md#인증서가-없으면-제품-설치가-ad-hoc-서명으로-계속된다-2026-10-31). binary 식별·비활성 snapshot 은 typing 을 바꾸지 않는 작업으로 준비한다.
   비활성 재발을 기다리는 동안 다른 검토를 멈출 필요는 없다.
4. resend·Caps 종료·caret 질의·cold 판별은 영향과 실제 증거에 따라 조사한다. Chrome source 왕복은 위 기본 경로를 해치지 않는 교정 근거가 있을 때 다시 시작한다.

모든 product 변경의 통과 기준은 재현 test 와 `swift build`·`swift test`, 영향 있는 실제 app 동작이다.
key 전송 권한·native mode 준비 때문에 검사가 막히면 **미검증**으로 남긴다. 설치 중 주인 입력이 실험에 섞이지 않도록 하고,
회귀가 보이면 변경을 철회한다. 며칠 증상이 없었다는 이유만으로 미검증 경로나 원인까지 해결됐다고 기록하지 않는다.
