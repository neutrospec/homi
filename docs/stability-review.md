# 안정적인 입력을 위한 개선 검토 — 2026-10-09

검토한 코드 기준은 `edbf60d` 다. HangulCore·InputSession, IMK lifecycle·client 반영, app 원장·test·도구·설치를 세 subagent 와 나누어 검토하고,
안건마다 AGENTS.md 와 기존 교훈을 다시 대조했다. 아래 **채택은 다음 작업 대상으로 채택했다는 뜻**이다. 이번 검토에서 제품 코드·설치·system 설정은 바꾸지 않았다.

## 판단 기준

주인 결정: **일상적인 두벌식 입력의 안정성이 먼저다.** 글자 유실·중복·엉뚱한 입력칸·첫 key 의 잘못된 모드·입력 중단을 가장 무겁게 본다.
같은 영향이면 평범한 조합·Backspace·homi 내부 한/영·focus 이동을 먼저 검증한다. 발생 빈도를 모르는 안건은 드물다고 가정하지 않는다.
한자·표시 개선과 다른 input source 왕복의 교정은 기본 입력을 악화시키면서까지 하지 않는다.

완전한 입력을 위해 검증 범위를 넓히되, 관측하지 못한 경로를 해결했다고 세지 않는다. 현재 확인한 정상 동작을 보존하고,
좁은 변경 하나마다 재현 test → 실제 app 확인 → 일상 사용의 관측으로 진행한다. 드문 경로의 제한을 명시하고 보류하는 것도 가능한 판단이다.

## 기본 입력을 먼저 보호할 안건

| 안건 | 판단 · 중요도 | 문서·교훈에 비춘 다음 행동 |
|---|---|---|
| 현재 설치본의 입력칸 이동 | **최우선 확인** · 실제 발생했던 회귀 | [Chrome 원장](apps/chrome.md#다음-작업)의 source 전환 없는 경로부터 확인한다. rollback 설치와 model 통과를 실제 복구 확인으로 세지 않는다. |
| activation 과 mode 초기화의 경계 | **재현 test 채택** · 기본 입력에 직접 영향 | 아래 두 counterexample 을 함께 다룬다. [재진입 교훈](lessons.md#client-호출의-재진입으로-abort-하거나-mark-가-다시-남는다-2026-10-09)과 [LaunchBar 요구](apps/launchbar.md)를 모두 지켜야 한다. |
| callback 이 확정한 mark 의 세대 | **검증 채택, 교정 보류** · 유실 위험, 실앱 순서 미관측 | `clientConfirmed` during insert 를 추가로 검증한다. callback 이 old mark 와 new mark 중 무엇을 끝냈는지 가른다. 다음 key 까지 commit 을 미루지 않는다. |
| 비활성·누락의 상태 관측 | **채택** · 입력 자체를 막는 증상, 원인 미확정 | [비활성 관측](macos-input.md#input-menu-의-비활성누락-2026-10-09-미해결)을 한 번에 확보할 읽기 전용 도구를 준비한다. typing 경로는 건드리지 않는다. |
| 제품 설치의 안정적인 서명 | **교정 후보 채택** · 기존 입력의 회귀를 예방하는 작은 변경 | [서명 결정](../AGENTS.md#알려진-함정)의 신원을 지키도록 제품 installer 는 인증서가 없으면 교환·process 종료 전에 실패하게 한다. 기존 설치본의 자체 서명은 확인했으며 인증서 부재를 관측한 것은 아니다. |
| 설치본과 관측의 연결 | **채택** · 검증의 정확성, 낮은 회귀 위험 | 설치 확인·시작 log·사용자 요청 export 에 같은 binary UUID 또는 digest 를 넣는다. key 마다 계산하거나 입력 내용을 더 수집하지 않는다. |
| Enter·ESC·Tab resend 의 순서와 대상 | **검증 채택, 교정 보류** · 명령 유실·잘못된 대상의 위험, 빈도 미상 | own probe 의 두 창·두 app 으로 순서와 focus 변경을 확인한다. [재전송 교훈](lessons.md#terminal-에서-조합-중-escenter-가-사라진다-2026-09-25-m4--apple-입력기-때부터) 때문에 일괄 제거·자동 drop·다른 post API 로의 교체를 바로 적용하지 않는다. |
| 종료 뒤 Caps Lock remap | **검증 채택, 교정 보류** · 기본 key 에 영향, macOS 27 실관측 없음 | [mapping 수명](macos-input.md#homi-process-와-hid-mapping-의-수명)을 근거로 일반 종료·설치 종료와 crash 뒤 상태를 구분한다. snapshot 에 mapping 을 포함한다. guardian daemon 은 추가하지 않는다. |

### activation 의 두 counterexample

[HomiInputController.activateServer](../Sources/homi/HomiInputController.swift)는 client 에 묻지 않고 cached ID 또는 frontmost app 을 사용한다.
이 원칙은 [activate 질의의 교착 교훈](macos-input.md)을 지키므로 유지한다. 그러나 다음 두 경계는 빠져 있다.

1. **같은 event 의 재활성화**: `startsInEnglish` app 에서 한글로 입력하다 mark 중 deactivate → activate 가 끼면,
   [SessionDriver.activate](../Sources/InputSession/SessionDriver.swift)는 조합을 이어 가지만 [ModeMemory.activate](../Sources/InputSession/ModeMemory.swift)는 영문으로 reset 한다.
   model 에서 `ㅎ` mark 가 남은 상태로 mode 가 영문이 되었고, 다음 `ㅏ` key 는 `insert("ㅎ")` 뒤 통과했다. 기대한 `하` 대신 `ㅎa` 경로가 성립한다.
2. **fallback 과 실제 client 가 다름**: activate 는 fallback app 의 시작 규칙을 적용한다. 첫 event 의 `resolveApp` 이 실제 bundle ID 를 알아내도
   그 activation 에 대한 mode 초기화·layout 을 바로잡지 않는다. 실제 client 의 시작 규칙을 놓치거나 다른 app 의 기억을 reset 할 수 있다.

첫째는 독립적인 두 model 실행에서 확인했다. 둘째는 코드상 처리 누락이다. **둘 다 해당 app 의 실제 실패·빈도는 확인하지 않았다.**
LaunchBar 원장의 기존 정상 확인을 취소하거나 현재 비활성의 원인으로 지목하지 않는다.

다음 검증은 실제 client 확인이 늦는 activation, 같은 event 의 재활성화, 실제 새 입력 시작, activation 알림 누락을 함께 다루는 순수 coordinator test 다.
Session·mode·layout·표시가 같은 lifecycle 판단을 따르는지 확인한다. 실제 새 시작의 영문 요구는 유지한다.
매 key 영문으로 reset 하거나 모든 activate reset 을 없애는 수정은 각각 정상 한글 전환과 시작 규칙을 깨므로 기각한다.

### `clientConfirmed` during insert 의 검증 공백

[SessionDriver.clientConfirmed](../Sources/InputSession/SessionDriver.swift)의 `insert:false` 는 event 끝에서 최종 Session 을 비우며 insert 를 생략한다.
현재 [ReentrancyTests](../Tests/InputSessionTests/ReentrancyTests.swift)는 client 확인이 mark 중에 오는 경우와 deactivate 가 insert 중에 오는 경우를 검사한다.

추가 model 은 `한` 뒤 `ㄱ` 의 `insert("한") → mark("ㄱ")` 중 insert 에서 이전 mark 의 확인 callback 을 주입했다.
남은 mark 를 반영한 뒤 Session 은 비었지만 client 에 `ㄱ` mark 가 남았다. **이 callback 순서는 실제 app 에서 미관측**이다.
model 의 callback 의미를 실제 Chromium 의 의미로 가정하지 않고, action 단계·조합 세대·lifecycle 을 입력 내용 없이 대조한다.
callback 의 적용 범위를 확인하기 전에는 insert 생략 정책을 바꾸지 않는다. 무조건 insert 하면 click 중복을 되살리고,
다음 event 에서 판단하면 [입력칸 누출 교훈](lessons.md#보류한-chromium-확정이-다음-입력칸에-들어간다-2026-10-09)을 반복한다.

## 기능·표시와 cold path 의 안건

| 안건 | 판단 | 검토 결과 · 다음 검증 |
|---|---|---|
| 보이지 않는 한자 후보 | **좁은 교정 후보 채택** | [SessionDriver.withEvent](../Sources/InputSession/SessionDriver.swift)는 무변화 flagsChanged 에도 revision 을 올리고 [Client](../Sources/homi/Client.swift)의 show Task 는 옛 revision 을 버린다. `⌥↩ → Option release → show Task` model 은 후보가 열린 채 show 만 취소됐다. 실제 Task 순서는 미관측이다. 후보 내용·선택·종료에 따른 revision 을 검토하되 owner·busy·active 검사는 유지한다. |
| caret 질의의 부작용 | **관측 채택, 교정 보류** | [Chromium 원장](apps/engines/chromium.md)의 firstRect 실패는 click 확정과 다른 경로다. homi 의 attributes 질의와 그 callback 이 실제로 연결되는지 먼저 확인한다. 표시를 위해 입력을 위험하게 하지 않는다. client 질의를 event 밖으로 옮기면 교착 교훈을 깨므로 기각한다. |
| Chromium 최초 판별 | **실패 주입·시간 측정 채택** | [Chromium.hosts](../Sources/homi/Chromium.swift)는 commit callback 에서 처음 app bundle 을 동기 조회하고, 조회 실패도 false 로 영구 cache 한다. 첫 blur 의 오분류는 중복 방지를 건너뛸 수 있다. 실제 실패·지연은 미관측이다. URL 없음·directory 오류·Electron/browser 위치를 주입하고, cache miss 비용을 확인한다. 단순 async 전환은 첫 callback 의 판단 공백을 만들므로 보류한다. |
| ModeHUD·indicator 의 stale Task | **후순위 교정 후보** | [showMode·switchMode](../Sources/homi/HomiInputController.swift)의 Task 에는 후보 창과 같은 owner·현재 mode 확인이 없다. 재진입 activation 뒤 옛 표시가 남을 수 있지만 실제 발생은 미관측이다. mode 표시만 최신 상태를 확인하는 좁은 변경으로 검증한다. 표시 때문에 mode·source 를 다시 바꾸지 않는다. |
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

- 이번 `swift build`·Debug `swift test` 는 138개 모두 통과했다. Release 138개 통과는 앞선 [작업 마감](lessons.md#2026-10-09-작업-마감)의 검증이다.
  proxy 인자·fake client 의 반영을 actual app 완료로 세지 않는다.
- 이번 별도 검사에서는 spec 의 독립 자모 분해표와 Unicode 완성형 정의로 **11,172개 음절**, 자소 Backspace 복원 **41,230 step**,
  받침 뒤 직접 모음의 도깨비불 **150,822 transition**을 검사했고 실패는 0이었다. 물리 key mapping·모든 임의 입력열·IMK 호환성의 증명은 아니다.
- baseline HangulCore/InputSession 을 `/private/tmp` 에 직접 compile 한 model 로 후보 revision, activation mode reset, insert 중 client 확인을 검사했다.
  이 model 들은 다음 regression 의 시작점이며 실제 app 재현을 대신하지 않는다. 두 subagent 의 activation model 을 별도로 실행해 같은 불일치를 확인했다.

다음 작업은 이 순서로 한다.

1. source 왕복을 섞지 않고 현재 설치본의 일반 조합·Backspace·homi 내부 한/영·입력칸 이동부터 확인한다.
   Chrome rollback 확인과 native probe `--check-manual` 의 실제 통과가 아직 남아 있다. 실패하면 새 우회보다 기본 경로를 먼저 복구한다.
2. activation 의 mode 경계와 client 확인의 action 단계부터 재현 test 를 만든다. 한 번에 한 원인만 바꾸고 native text·Chromium 의 해당 경로를 확인한다.
   후보 revision 은 한자 경로를 따로 교정·검증한다.
3. 제품 signing 실패 시 기존 설치본 보존, binary 식별, 비활성 snapshot 은 typing 을 바꾸지 않는 작업으로 준비한다.
   비활성 재발을 기다리는 동안 다른 검토를 멈출 필요는 없다.
4. resend·Caps 종료·caret 질의·cold 판별은 영향과 실제 증거에 따라 조사한다. Chrome source 왕복은 위 기본 경로를 해치지 않는 교정 근거가 있을 때 다시 시작한다.

모든 product 변경의 통과 기준은 재현 test 와 `swift build`·`swift test`, 영향 있는 실제 app 동작이다.
key 전송 권한·native mode 준비 때문에 검사가 막히면 **미검증**으로 남긴다. 설치 중 주인 입력이 실험에 섞이지 않도록 하고,
회귀가 보이면 변경을 철회한다. 며칠 증상이 없었다는 이유만으로 미검증 경로나 원인까지 해결됐다고 기록하지 않는다.
