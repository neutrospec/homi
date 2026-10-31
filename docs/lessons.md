# 결함과 교훈

고친 결함마다 **증상 · 원인 · 증거 · 대응**을 남긴다 (AGENTS.md 작업 규칙). 새 결함은 맨 위에 더한다.
배운 macOS 구조 자체는 `docs/macos-input.md` 에 있다. 여기에는 무엇이 틀렸고 그것을 어떻게 알았는지를 남긴다.

- 간헐 결함의 증거는 homi 의 기록이다 — 이상하면 주인이 곧바로 input menu 의 "최근 key 기록 저장" 을 누르고(`~/Library/Logs/homi/`), 그 file 로 가린다.
- 원인에 🔶 가 붙은 것은 대응이 통했지만 원인은 추정이라는 뜻이다.

## renderer 조회 실패가 영구적인 부재 판정이 된다 (2026-10-31)

- **증상**: 첫 조회에서 app 위치가 없거나 directory 읽기가 실패하면, 다음 callback 에 읽을 수 있어도 기존 renderer 를 찾지 못했다.
  client 자체 확정 우회를 계속 건너뛰는 코드의 반례다. 실제 menu 누락·첫 key 이상과의 인과는 미확인이다.
- **원인**: 기존 `Chromium.hosts`가 조회 실패와 확인된 부재를 모두 false 로 만들고 process 동안 cache 했다.
- **증거**: 기존 판별을 환경 주입 경계로 옮긴 뒤 `rendererUnavailableCanRecover`의 위치 없음·읽기 실패 두 조건에서
  회복 후 판별·종료 방침 기대가 실패했다(`build/renderer-policy-before-20261031.log`). 교정 후 같은 test 와 다른 경계 검사가 통과했다.
- **대응**: `RendererDiscovery`는 미확인·확인한 부재·기존 helper·다른 renderer 이름을 구분하고 미확인만 cache 하지 않는다.
  directory 가 없다는 판단은 부모 목록으로 확인한다. 일부 경로를 못 읽어도 다른 경로에서 찾은 기존 helper 는 유효하다.
  `CommitPolicy`가 별도로 기존 우회 적용을 결정하므로 새로운 renderer 이름의 발견이 곧바로 입력 동작을 바꾸지 않는다.
- **제한**: 조회에 계속 실패하면 callback 마다 동기 조회할 수 있다. 첫 조회의 실패 때는 기존처럼 homi 가 확정한다.
  cold 조회를 비동기로 바꾸는 일과 알려진 source 왕복 실패는 해결하지 않았다. [구조 개선 3번](stability-review.md#3번-renderer-판별과-commit-정책-분리)의 검증 범위를 따른다.

## 늦은 client ID 가 실제 app 의 mode 기억을 덮는다 (2026-10-31)

- **증상**: client ID 가 없는 첫 key 를 영문 fallback app 의 mode 로 넘긴 뒤 실제 ID 를 알면,
  그 app 의 한글 기억까지 영문으로 덮었다. 조합·한/영 전환 없는 Control 단축키에서도 같은 반례가 성립했다.
  [source review](stability-review.md#focus와-source-전환-code-review-2026-10-31)에서 찾은 코드의 결함이며, 실제 Telegram 누락의 원인으로 확인한 것은 아니다.
- **원인**: `ModeActivation.inputStarted`가 모든 keyDown 전에 시작을 소비하고 fallback app 을 저장했다.
  이후 `prepare`는 이어 갈 조합·사용자의 mode 변경이 없어도 그 기억을 실제 app 에 복사했다.
- **증거**: `ActivationTests`에 일반 key·Control 단축키의 regression 두 개를 먼저 추가했고,
  교정 전 각각 실제 app 의 mode·확정 text·mark 기대가 실패했다. 교정 뒤에는 두 반례와 기존 조합·toggle 보존이 통과했다.
  실제 app 의 영문 시작 규칙, 전환 뒤 다른 fallback 의 무변화 key, 한자 질의 중 명시적 새 시작·같은 입력 재활성화도 검사했다.
- **대응**: Session 판단 뒤 조합·후보가 있거나 mode 를 바꾼 입력에만 fallback 이전을 허용한다.
  판단 전의 activation 세대를 잡고 client 반영 전에 확인하여, 질의 중 새로 생긴 시작을 옛 결과가 소비하지 않게 했다.
  mode 의 SOT 는 계속 `ModeMemory`다. 이미 입력한 첫 key 를 재전송하거나 source·layout 을 강제 변경하지 않는다.
- **검증·설치**: `swift build`, Debug·Release 각각 **213개 test 통과**. 12:44:29 KST 에 기존 자체 인증서로 서명·검증·설치했다.
  CDHash `c4fb95bcde22750f1260a0832f71676a287fdcbd`, 새 process PID `27571`과 modifier observer 시작을 확인했다.
  도구가 probe 에 보낸 합성 key 는 client 에 도착했지만 homi event 경로를 확인하지 못해 통과로 세지 않았다.
  주인은 실제 keyboard 로 `한글 → Backspace → ㄹ` 조합·편집과, 다른 app 을 거쳐 ⌘Tab 복귀 뒤 `가` 입력을 확인했고
  **모두 정상이며 `한글가`가 남는다**고 답했다. 도구로는 probe 의 `한`·`글` insert 호출을 별도로 확인했다.
- **제한**: 첫 key 에 실제 ID 가 없을 때 그 key 자체를 어느 app 의 mode 로 해석할지는 여전히 fallback 에 의존한다.
  Telegram 첫 key·menu 누락·source UI 지연의 해결을 뜻하지 않는다. 현재 ChatGPT 의 Chromium 판별·commit 정책과 activation layout 호출은 바꾸지 않았다.

### controller 진단 ID 의 수명 구분

같이 보완한 진단 ID 는 `ObjectIdentifier.hashValue` 대신 **process PID·UUID + 생성 번호**다.
controller 가 사라진 뒤 주소가 재사용돼도 이전 수명의 ID 와 같아지지 않는다. 번호는 Atomic 으로 발급하고 생성 때 한 번 저장한다.
새 process 에서 `/1` Safari, `/2`·`/3` Telegram 의 실제 event·activation 기록을 확인했다.
입력 내용 수집은 늘리지 않았다. 과거 동일 hash 의 log 를 하나의 controller 로 합치지 않는다는 제한은 계속 적용한다.

## 2026-10-09 재검토에서 적용할 교훈

- 주인 결정: 기본 조합·편집·homi 내부 한/영·focus 이동을 우선한다. 드문 source 왕복의 교정이 일상 입력을 악화시키면 철회한다.
  [개선 검토](stability-review.md)에 모든 안건의 채택·보류·기각과 다음 검증을 남겼다. 새 model 의 counterexample 은 실제 app 실패와 구분한다.
- 재진입 경계가 Session 을 보호해도 mode reset·layout·표시까지 같은 판단을 따르는지 별도로 검증해야 한다.
  stale UI 를 막는 세대 검사도 무변화 event 에 필요한 UI 를 버릴 수 있다. 보호 장치 자체의 반례를 검사한다.
- `commitComposition` 의 callback 은 왜 왔는지와 무엇을 끝냈는지를 가른다. old mark·new mark·renderer 확정을 하나로 가정하지 않는다.
  fake client 의 즉시 반영을 실제 app 완료로 세었던 실패를 반복하지 않는다.
- "우리 insert 기록이 없다" 는 app 결함의 확정 증거가 아니다. VS Code 원장의 남은 중복도 원인 미확정으로 바로잡았다.
  한 번에 한 가정을 바꾸고, 설치본의 기본 동작이 복구됐는지 확인한 뒤 다음 실험을 한다.

## 2026-10-09 activation 교정·callback 관측

- 주인은 변경 전에 “한글 입력기는 현재 상태로 잘 동작 하는 것 같다”고 확인했다. 기본 입력의 사용 관측이며,
  Chrome 의 각 입력칸 이동·source 왕복이나 모든 app 의 개별 검사 결과로 확대하지 않는다.
- activation 의 두 counterexample 을 기존 glue 를 재현한 test 에서 먼저 실패시켰다. `ModeActivation` 교정 뒤 통과했고,
  늦은 client ID·첫 modifier·명시적 종료·실제 새 시작을 포함해 14개 regression 을 추가했다(아래 결함).
- 내용 없는 client 호출 관측을 연결했다. helper 9개·실제 `Client` proxy 3개 test 가 계획·호출·반환·cache 의 경계와 질의 횟수를 검사한다.
  token 의 뜻과 한계는 [입력 구조](macos-input.md#client-호출-단계의-관측)에 둔다. commit 정책·range·한글 엔진은 바꾸지 않았다.
- `swift build` 와 Debug·Release 전체 test 통과: 각각 164개(HangulCore 18, InputSession 129, Homi 14, Install 3).
  11:55 KST 에 자체 인증서로 서명·검증·설치했다(CDHash `46e0de87a668649237dff2deeb85a593392ae360`).
  native probe 는 처음 ABC 상태의 준비 단계에서 `BLOCKED` 였다. 12:33 KST 에 실제 `가` 입력·marked text 와 homi 선택은 확인했다.
  그 뒤 준비 글자를 비우는 단계에서 진행이 멈추고 probe 가 SIGSEGV 로 종료됐다. crash stack 은 main thread 의 `AppDelegate.activeChanged` executor 검사에 있다
  (`probe-2026-10-09-123318.ips`). 일반적인 actor isolation 불일치 trap 과는 다르며, stack 에 clear·injection 은 없다. 원인은 미확정이다.
  같은 probe binary(UUID `D29CB4B9-F65F-3092-A8C2-8DF3E49D8665`)의 일반 창에서는 주인이 긴 입력을 정상으로 확인했다.
  실제 insert·mark 의 관측 연결은 [입력 구조](macos-input.md#client-호출-단계의-관측)에 남겼다. insert/mark 중 callback 의 확정 대상·강제 injection·두 입력칸 이동은 아직 검증하지 못했다.
- input menu 의 비활성·누락과 Chrome 의 다른 source 왕복은 **미해결**이다.

## 2026-10-09 작업 마감

- 유지한 변경: 재진입 경계·source 종료 알림 보완·activate 의 client 질의 제거, Caps Lock timer 수명·mapping 실패 처리,
  후보 창의 controller·조합 세대 확인, 완성된 bundle 의 atomic 설치. startup 의 `@main` 전환은 app 을 test target 에서 참조하기 위한 구조 변경이다.
- 최종 rollback 은 09:54 KST 에 자체 인증서 `homi code signing` 으로 서명·검증·설치했다.
  보류한 Chromium 확정과 `replacementRange` 실험은 철회했다. 한글 엔진의 조합 규칙·input mode 구성·설치 위치는 바꾸지 않았다.
- `swift build` 와 Debug·Release test 통과: 각각 138개(HangulCore 18, InputSession 106, Homi 11, Install 3).
  재진입·owner 해제·HID 실패 주입·directory 교환의 검증이다. 후보 창의 실제 표시·모든 app 의 호환성을 증명하지 않는다.
- native probe 자동 검사는 합성 수식키로 한글 모드에 들어가지 못해 `BLOCKED` 였다. 도구의 system keyboard event 전송 권한도 없었다.
  자기 창의 `--check-manual` 경로는 준비했지만 끝까지 `PASS` 를 확인하지 않았다.
- Chrome source 전환·input menu 의 비활성/누락은 **미해결**이다. 당시 rollback 뒤 실제 입력칸 이동의 복구는 주인 확인이 없었다.
  다음 작업의 시작점은 [Chrome 원장](apps/chrome.md#다음-작업)과 [비활성 관측](macos-input.md#input-menu-의-비활성누락-2026-10-09-미해결)에 둔다.

## homi 의 결함

### 정상 Caps tap 을 기존 판정이 거부한다 (2026-10-29)

- **증상**: Caps Lock 단독 시험은 정상이지만 평소 입력을 섞으면 한/영 전환이 빠진다. keyboard 문제를 전제하지 않고 관찰했다.
- **확인한 결함**: `4326e70`은 event 의 timestamp 와 처리 시점의 live counter 를 섞어 tap 을 판정한다.
  물리 release 뒤에 생긴 활동도 release 를 늦게 처리하면 중간 입력으로 오인할 수 있다. 순수 반례는 [code review](stability-review.md#caps-lock-전환-code-review-2026-10-29)에 있다.
- **실제 증거**: 같은 IMK callback 에서 기존 판정과 새 후보를 비교했다. [Orca 29쌍](apps/orca.md#기존-판정과-gesture-후보의-동시-비교-2026-10-29-1320-kst) 중
  4개의 관찰상 단독 tap 을 기존 코드만 거부했다. 어떤 event 가 live counter 를 바꾸었는지는 별도로 남으며 OS update 와의 인과관계도 미확정이다.
- **교정**: 별도 관찰 thread 가 물리 누름·뗌 사이의 활동과 gesture 번호만 기억한다. IMK 에서 유일하게 연결한 gesture 의 snapshot 으로 판단하고
  mode 변경은 계속 IMK 안에서 동기적으로 처리한다. 중복 callback 은 같은 press 를 재사용하고 release 는 한 번만 적용한다.
  권한 부재·모호한 press 에서는 기존 counter 경로를 유지한다. 그 경로의 시간차 한계까지 해결한 것은 아니다.
- **함께 막은 경계**: 짧게 뗀 key 의 늦은 release 가 hold 로 오인되지 않도록 실제 눌림·같은 press·0.5초 경과를 함께 확인한다.
  좌우 modifier 를 구분한다. keyDown 뒤 중복 press 는 다시 arm 하지 않으며, 입력칸 종료로 release 가 안 와도 복귀 후 첫 새 tap 을 막지 않는다.
  마지막 경계는 실패하는 regression 을 먼저 확인했다. timestamp 검색과 metadata 식별 실험은 제품 코드에서 제거했다.
- **검증 범위**: 비교 진단은 새 action 을 실행하지 않았다. 실제 적용 뒤의 입력·hold·focus 이동은 주인 시험으로 확인한다. push 는 그 뒤다.
- **설치**: `swift build`, Debug·Release 전체 201개 test 통과(HangulCore 18, InputSession 149, Homi 31, Install 3).
  13:32 KST 에 설치했고 13:33 에 process 시작·gesture 관찰 준비를 확인했다. 자체 인증서 `homi code signing`,
  CDHash `686f2190b15963148e871777aee4a950064266f7`. 이 설치본은 비교 진단이 아니라 새 판정을 실제 mode 변경에 적용한다.
  일반 조합·Windows App mapping·Telegram 첫 key 의 별도 문제는 수정하지 않았다.
- **사용 확인**: [13:35 시험](apps/orca.md#교정본의-실제-사용-2026-10-29-1335-kst)에서 짧은 전환 34회가 모두 mode 변경으로 이어졌고,
  주인이 누락 개선을 확인했다. 다만 긴 누름 4회는 release 에서 대문자 고정을 처리했다. 이 결과를 hold timer 성공으로 확대하지 않는다.
  remap 된 오른쪽 Control 의 `keyState(.hidSystemState, key: 62)` 를 추가 veto 로 쓰던 hold 경계를 제거하고,
  이미 연결한 같은 press 의 관찰 상태로 판단한다. 직접 조회와 관찰의 차이를 함께 기록해 확인한다.
  이 보완본도 `swift build`, Debug·Release 201개 test 를 통과했다. 13:45 에 시작된 설치본의 CDHash 는
  `cd0baf2767e62f15aceca5a9ad877522ff270b1b`이며 자체 인증서 서명·gesture 관찰 준비를 확인했다.
  13:48 에 긴 누름 4회 모두 release 전에 대문자 고정을 처리했고 release 에서는 다시 처리하지 않았다. 주인도 정상 동작을 확인했다.
  직접 조회는 네 번 모두 `false`, 관찰된 눌림은 `true`였다. [API 관측의 범위](macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29)를 따른다.
  이번 재현 시험의 통과를 모든 app·관찰 불가 환경·일상 사용 기간의 무결함으로 확대하지 않는다.

### event snapshot 실험본이 Caps Lock 전환을 전부 거부한다 (2026-10-29, rollback)

- **증상**: live counter 의 시간차를 교정한 실험본 설치 후 주인이 Caps Lock 전환이 전혀 되지 않는다고 보고했다.
  12:25–12:26 의 실제 IMK log 에 press·release 가 도착했지만 모두 `evidence: missing, action: none` 이었다.
- **확인한 결함**: snapshot 을 찾지 못하면 전환하지 않는 경로를 넣었으나, 실제 IMK 와 Quartz event 의 연결을 설치 전에 검증하지 못했다.
  생성한 CGEvent → NSEvent 의 timestamp test 는 실제 IMK bridge 의 표현을 검증하지 않는다.
  후속 진단에서 [timestamp 불일치·중복 callback·metadata 미보존](macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29)을 확인했다.
- **검증의 한계**: Debug·Release 191개 test 는 모두 통과했다. 순수 판정·합성 event adapter·atomic store 의 통과를 실제 IMK 연결의 증거로 확대했다.
- **대응**: 12:26 에 기존 서명본(CDHash `de243ec81f0f85b0d84c6520192e6aa068b62cfa`)으로 복구했고 주인이 전환 회복을 확인했다.
  원래의 간헐 누락은 여전히 보고됐다. 당시 working tree 의 timestamp snapshot 교정은 실험 코드로 두고 재설치하지 않았다.
  기존 `4326e70` 판정을 유지하고 수식키의 시각·방향만 비교하는 별도 진단본으로 실제 연결부터 확인한다. push 하지 않았다.
  12:35 에 이 진단본을 설치했다. 원본 controller 의 `Activity.now()` 를 먼저 읽고 같은 값으로 판정하며,
  관찰 기록은 비교 log 에만 쓴다(Release 기존 178개 test 통과). 진단 source 위치는 `build/modifier-diagnostic-path.txt` 에 있다.
  13:15 에 gesture 연결을 **비교만 하는** 다음 진단본이 시작됐다. 실제 전환은 `4326e70`의 `ModifierKeys`·`ModifierTap`·adapter·timer 를
  이름만 구분해 유지한다. 새 코드는 전환·대문자 고정을 실행하지 않고 제안 결과만 기록한다. metadata 를 쓰는 실험도 제거했다.
  후보 코드의 Debug·Release 199개 및 별도 진단본의 Release 199개 test 가 통과했다. 실제 IMK 비교는 별도 검증이며 아직 통과로 세지 않는다.
  진단 source 위치는 `build/modifier-shadow-path.txt` 에 있다. 이 분리 설치본을 working tree 전체와 같다고 취급하지 않는다.
  자체 인증서 `homi code signing`, CDHash `c88f80e2defabf06d07a189380ce1159eea91b99`. 시작 log 의
  `legacy decisions, gesture comparison only`와 관찰기 준비를 확인했다. 이후 [13:20 비교](apps/orca.md#기존-판정과-gesture-후보의-동시-비교-2026-10-29-1320-kst)에서 실제 연결을 확인했다.

### Mac LANG1 을 Windows 전용 한/영 전달로 취급한다 (2026-10-10, 미해결)

- **증상**: Windows App 전달 옵션을 켜니 Caps Lock 대문자 고정은 사라졌지만 한/영 전환도 안 됐다 (주인).
- **원인**: Apple 의 LANG1 정의만으로 원격 Windows 의 전용 한/영 key 와 동등한 전달 경로를 확보했다고 볼 수 없었다.
  Windows App 의 변환표와 platform 표의 불일치는 [원장](apps/windows-app.md#주인-시험과-target-재검토-2026-10-10)에 있다.
  실제 원격 수신 key 는 미관측이므로 전환 실패의 전체 원인은 아직 확정하지 않는다.
- **증거**: 주인 시험, 설치된 Windows App 11.4.3 의 static 변환표, Chromium 의 platform key 표 대조.
  unit test 는 homi 의 target 선택·mapping 복원을 검사할 뿐 RDP 이후의 key 의미를 증명하지 않았다.
- **대응**: 성공 여부를 전환 실패로 갱신하고 실제로 통과하는 전환 key 를 먼저 확인한다. Windows 설정 오류로 돌리거나
  다른 target 으로 바꾼 시험본을 근거 없이 설치하지 않는다. 이어진 주인 요청으로 [목적지 선택](apps/windows-app.md#목적지-선택-2026-10-10)을 준비했다.
  오른쪽 Alt 선택은 주인 환경에서 정상 확인했다 ([결과와 범위](apps/windows-app.md#목적지-선택-2026-10-10)). 전용 한/영 key 전달 실패는 남아 있다.

### 재활성화가 mode 를 reset 하고 실제 client 의 시작 규칙을 놓친다 (2026-10-09)

- **증상**: `startsInEnglish` app 의 mark 중 deactivate → activate 를 주입하면 조합은 남고 mode 만 영문이 되어,
  다음 모음이 조합에 붙지 않고 통과했다. activate 의 fallback 과 실제 client 가 다르면 다른 app 의 기억을 reset 하고 실제 시작 규칙은 놓쳤다.
  주인 사용 중의 발생·빈도를 확인한 결함은 아니다.
- **원인**: `SessionDriver` 는 같은 event 의 재활성화를 이어 갔지만 glue 는 모든 activate 에 `ModeMemory.activate` 를 실행했다.
  client ID 를 첫 event 에서 알아낸 뒤 그 시작 intent 를 적용할 경계가 없었다.
- **증거**: 기존 glue 를 재현한 `ActivationTests` 의 첫 두 test 가 수정 전에 실패하고 수정 뒤 통과했다.
  별도 검토에서 fallback A → B → 실제 ID C 의 mode 이동도 잘못된 slot 을 쓰는 반례를 발견해 먼저 실패시킨 뒤 고쳤다.
  실제 IMK 의 재진입 여부는 순수 test 와 구분해 확인한다.
- **대응**: `ModeActivation` 은 시작 intent 와 ID 보정만 맡고 mode 는 `ModeMemory` 하나에 둔다. 실제 ID 또는 그 cache 로
  새 시작의 규칙을 한 번 적용한다. 입력 event 안의 재활성화는 mode·layout 도 이어 가며, 명시적인 commit·종료 flush 는 새 시작과 구분한다.
  activate 의 client 질의는 되살리지 않고 첫 key 중 layout 교정도 넣지 않았다. 늦게 ID 를 얻으면 진행 중 조합·사용자가 고른 mode 를 보존한다.
- **제한**: ID 를 모르고 입력을 시작한 경우 실제 app 의 시작 규칙을 소급해 보장할 수 없다. 같은 controller 의 ID cache 가 정확하다는 전제도 남는다.
  menu bar 표시는 owner·app·현재 mode·pass-through 를 다시 확인하지만 ModeHUD·후보 revision 의 별도 안건까지 해결한 것은 아니다.

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

## 개발 도구에서

- **TIS 를 병렬 test 에서 부르면 process 가 abort 한다** (signal 6) — TIS 는 main thread 에서만. test 에 `@MainActor` (M1).
- **bundle 없이 띄운 창은 앞으로 나오지 않는다** — probe 를 `.app` 으로 조립해 `open` 한다 (M0).
- **app 을 죽이자마자 `open` 하면 LaunchServices 가 -600** — 죽어가는 process 에 붙으려 한다. 종료를 기다린다 (`scripts/probe.sh`).
- **probe 가 무한 재귀했다** — text input context 는 만들어질 때 client 에게 `validAttributesForMarkedText` 를 묻는데, probe 가 그 질문을 기록하며
  context 를 다시 찾았다(`lazy`). 만들어지기 전에는 nil 로 두어 끊었다.
- **Swift Testing 의 `#expect(...)` 안에서는 mutating method 를 부를 수 없다** — 결과를 변수에 먼저 받는다 (세 번 되풀이).
