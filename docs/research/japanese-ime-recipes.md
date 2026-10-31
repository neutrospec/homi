# 일본어 입력기의 공개 코드에서 가져올 recipe — 2026-10-09

목적은 homi 의 [안정성 안건](../stability-review.md)을 검증할 처리 방식과 test 를 찾는 것이다.
세 subagent 와 macSKK·azooKey·Mozc 를 나누어 읽고 AquaSKK 를 함께 대조했다. 공개 source·test·issue 를 검토했으며 외부 입력기를 실행하거나 설치하지 않았다.
**아래 채택은 다음 test·검토 대상으로 채택했다는 뜻이다. 제품 코드를 교정하거나 homi 의 비활성·Chrome source 왕복을 해결한 것은 아니다.**

## 조사 기준

2026-10-09 GitHub API 로 확인한 branch HEAD 를 고정했다. 날짜는 commit 의 UTC 날짜이며, 배포본·macOS 27 실앱 검증 날짜가 아니다.
homi 의 runtime 비교 기준은 `edbf60d` 다. 선행 구현의 동작은 source 에서 확인한 것과 작성자가 보고한 실험을 구분한다.

| 프로젝트 | 고정한 commit · 날짜 | 읽은 영역 · license |
|---|---|---|
| macSKK | [`a1136581eca60212ba3ff5a8040f62b963bd9566`](https://github.com/mtgto/macSKK/commit/a1136581eca60212ba3ff5a8040f62b963bd9566) · 2026-10-04 | controller·state machine·completion presenter·tests. GPL-3.0-or-later |
| azooKey-Desktop | [`bd90b7bdc8f38069987b36426b990ef3129edf62`](https://github.com/azooKey/azooKey-Desktop/commit/bd90b7bdc8f38069987b36426b990ef3129edf62) · 2026-09-27 | controller·ConverterServer·activation contract·후보 UI tests. MIT |
| Mozc | [`921b8cc99904c8d31b771e395513da0a5d55182a`](https://github.com/google/mozc/commit/921b8cc99904c8d31b771e395513da0a5d55182a) · 2026-10-07 | macOS controller·bridge/renderer tests·client IPC·설치 issue. Google source 는 BSD 3-Clause, third-party 자료는 별도 |
| AquaSKK | [`e90a04b15b15a82a0651a63aeb72dcd22d0d8c94`](https://github.com/codefirst/aquaskk/commit/e90a04b15b15a82a0651a63aeb72dcd22d0d8c94) · 2026-09-28 | controller·front end·session·data-driven tests·app 우회. 검토한 source header 는 GPL-2.0-or-later |

Mozc 는 Google Japanese Input 의 공개 subset 이며 공식 제품과 같은 QA 를 약속하지 않는다([README](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/README.md), [branding](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/docs/about_branding.md)).
Mozc macOS controller 의 마지막 변경은 2026-04-28 include 추가, controller test 는 2025-11-25 API 이름 변경이었다. 최신 repo 날짜만으로 최신 app 호환성을 인정하지 않는다.
이번에 가져오는 것은 검증 방식이다. 외부 source 를 homi 코드나 dependency 로 복사하지 않았다.

## 1. activation 의 준비와 실제 입력 시작을 구분한다 — 기본 입력 test 채택

azooKey 의 [activateServer](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/azooKeyMac/InputController/azooKeyMacInputController.swift#L147)는 pending activation 을 저장한다.
첫 server-bound key request 에 이를 동봉하고 비우며, [server](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/Core/Sources/ConverterServer/ConverterServer%2BKeyEvent.swift#L23)는 key 해석 전에 적용한다.
그 [contract test](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/Core/Tests/CoreTests/XPCTests/ConverterServerContractTests.swift#L20)는 request serialization 을 검사한다. 실제 client 판별·nested activation 을 검증한 test 는 아니다.

homi 에서는 **activate 때 불확실한 fallback app 의 기억을 reset 하지 않고, 실제 client 를 아는 첫 event 에서 초기화와 key 판단을 함께 하는** 설계를 검증한다.
비동기 server 는 필요 없다. flagsChanged 가 한/영 전환을 맡으므로 keyDown 만 기다려서는 안 된다.
[현재 두 counterexample](../stability-review.md#activation-의-두-counterexample)을 고칠 coordinator 는 다음 경우를 함께 만족해야 한다.

1. fallback app 과 실제 client 가 다르면 실제 app 의 시작 규칙을 한 번 적용하고 fallback app 의 기억은 건드리지 않는다.
2. intent 를 소비한 event 의 mark 중 deactivate → activate 가 끼고 조합을 이어 가기로 했다면 mode·layout 도 이어 간다.
3. event 밖의 실제 새 입력 시작에서는 `startsInEnglish` 를 적용한다.
4. cold controller 가 activate 없이 첫 event 를 받아도 실제 app 의 규칙을 적용하며 이후 매 key 를 영문으로 reset 하지 않는다.

azooKey 는 이미 intent 를 소비했어도 다음 activate 에서 조건 없이 새 intent·generation 을 만든다.
**이 부분을 그대로 옮기면 homi 의 nested activation reset 결함이 남는다.** 실제 새 시작과 같은 event 의 재활성화 구분은 homi 의 동기 coordinator 가 맡아야 한다.
Mozc 의 [SwitchMode test](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller_test.mm#L529)처럼 중복 요청이 상태를 다시 초기화하지 않는지도 검사한다.

## 2. bridge 는 호출 여부뿐 아니라 반영 상태와 순서를 검사한다 — 기본 입력 test 채택

Mozc controller 는 [test client 초기화](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm#L206)와
[converter·renderer 교체 setter](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm#L192)를 제공한다.
AquaSKK 의 [TestResult](https://github.com/codefirst/aquaskk/blob/e90a04b15b15a82a0651a63aeb72dcd22d0d8c94/src/engine/tests/TestResult.h)는 확정 문자열·mark·mode·cursor·handled 를 함께 비교한다.
homi 의 기존 순수 Session·Action 과 ClientTests 를 유지하며 다음 검증을 독립 구현한다.

- fake client 에 engine 의 다음 조합과 client 의 현재 mark 를 별도로 둔다. `insert → mark` 각 호출의 시작·반환에 lifecycle callback 을 주입하고 순서·최종 상태를 검사한다.
- 반복 commit, `commit → deactivate`, insert 중 callback, mark 중 callback 을 분리한다. pending 종료가 사라지거나 새 mark 를 부당하게 비우지 않는지 본다.
- typing 결과와 key 의 consumed/pass 여부를 함께 검사한다. 한자 UI 가 없는데 숫자·Enter 만 후보로 처리되는 상태도 실패로 센다.

이는 [insert 중 client 확인 범위](../stability-review.md#insert-중-client-확인의-적용-범위)의 test recipe 다.
model 에서 callback 을 old mark 의 확인이라고 지정했다고 실제 Chromium 에서 그 의미가 증명되는 것은 아니다.
실앱에서는 입력 내용 없이 insert·mark 의 시작/반환, local 조합 세대·마지막 반영 세대·callback 순서를 관찰해야 한다.
같은 proxy 의 여러 DOM field 를 fake 로 나누어도 실제 입력칸 소유권을 알아낸 증거로 세지 않는다.

**선행 test 의 한계도 가져온다.** Mozc 의 [setMarkedText mock](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller_test.mm#L165)은 no-op 이고 [activate/deactivate](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm#L282)는 test client 가 있으면 건너뛴다.
[#1327](https://github.com/google/mozc/issues/1327)은 test crash 가 Bazel PASS 로 보였던 보고와 실제 IMK 에서 test 를 격리한 경위다.
AquaSKK 의 [runner](https://github.com/codefirst/aquaskk/blob/e90a04b15b15a82a0651a63aeb72dcd22d0d8c94/src/engine/tests/SKKInputSession_TEST.cpp#L41)는 불일치를 출력하지만 main 의 실패 exit 로 전달하지 않는다.
homi 는 test failure 를 실제 실패로 전파하고 bridge mock·native probe·실앱 확인을 별도 결과로 보고한다.

## 3. 표시를 위한 client 질의의 범위·횟수를 고정한다 — test 채택, 위치 정책은 보류

azooKey [#317](https://github.com/azooKey/azooKey-Desktop/pull/317)은 2026-04-21 병합됐고 init·activate 의 caret 질의를 제거했다.
작성자는 Chrome 의 claude.ai/chatgpt.com freeze 해소와 TextEdit·Safari·VSCode 의 후보 표시를 확인했다고 보고했다.
동봉한 test 는 빈 후보의 geometry 를 검사하며 실제 deadlock 재현 test 는 아니다.
최신 activate 에는 [menu 상태 갱신](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/azooKeyMac/InputController/azooKeyMacInputControllerHelper.swift#L68)을 통한 selection query 가,
[setValue](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/azooKeyMac/InputController/azooKeyMacInputController.swift#L206)에는 composing/selecting 상태의 UI refresh 를 통한 caret query 가 남는다.
#317 을 lifecycle 전체의 client query 제거로 넓히지 않는다.

homi 의 spy client 로 **우리 구현의 init·activate·setValue 에서 caret/selection/substring 질의 0**, 표시 변화 없는 일반 조합·Backspace 의 UI 용 caret 질의 0 을 고정한다.
간접 UI refresh 도 같은 검사에 들어간다. 실제 필요한 mode HUD·한자 시작 질의는 동기 event 경계 안에서 받고 UI 에 값만 넘긴다.
macSKK [#394](https://github.com/mtgto/macSKK/pull/394)도 background 의 위치 질의를 key 처리 때로 되돌린 사례다.

Mozc 의 [UpdateCandidates test](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller_test.mm#L431)는 첫 표시 때 위치 질의 1회, 표시 중 갱신·종료 때 추가 0회를 검사한다.
이 budget 을 검사하는 방식은 채택한다. 후보 session 동안 위치를 고정하는 정책은 client 창 이동을 따라가지 못하는 타협이므로 필요할 때 좁게 실험한다.
Mozc 의 [next run loop 질의](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm#L790)는 homi 의 교착 교훈과 충돌하므로 timing 을 옮기지 않는다.

## 4. 늦은 UI 는 event 횟수 대신 의미 있는 상태로 검증한다 — 후보 test 채택

macSKK 의 비동기 **completion** [CompletionPresenter.apply](https://github.com/mtgto/macSKK/blob/a1136581eca60212ba3ff5a8040f62b963bd9566/macSKK/CompletionPresenter.swift#L172)는 현재 조합 상태와 검색 때 상태가 맞을 때만 표시한다.
[testApplyDiscardsResultWhenYomiChanged/WhenNotComposing](https://github.com/mtgto/macSKK/blob/a1136581eca60212ba3ff5a8040f62b963bd9566/macSKKTests/CompletionPresenterTests.swift#L257)는 옛 결과를 버리고 현재 표시·선택을 보존하는지 검사한다.
[#399](https://github.com/mtgto/macSKK/pull/399)는 검색 지연을 주입해 재현했고, [#487](https://github.com/mtgto/macSKK/pull/487)은 2026-06-27 늦은 결과가 다른 조합 상태에서 표시되는 회귀를 고쳤다.
일반 conversion 후보는 controller 의 동기 sink 로 표시한다. 두 UI 경로를 같은 구현으로 설명하지 않는다.

homi 의 [후보 revision 안건](../stability-review.md#기능표시와-cold-path-의-안건)은 작은 panel protocol 과 직접 실행 순서를 고를 수 있는 fake UI scheduler 로 검증한다.

| 끼워 넣을 순서 | 기대 결과 |
|---|---|
| `⌥↩ → Option release → 예약한 show 실행` | 무변화 event 는 유효한 show 를 취소하지 않는다. 후보 상태와 실제 panel 이 함께 열린다. |
| `show 예약 → cancel/commit → 옛 show 실행` | panel 이 다시 열리지 않고 현재 Session 도 바뀌지 않는다. |
| `show 예약 → 후보 내용/selection 변경 → 옛 show 실행` | 옛 snapshot 이 최신 후보·선택을 덮지 않는다. |
| `owner A 의 show 예약 → owner B 활성화 → A 의 show 실행` | B 의 panel·입력 상태를 건드리지 않는다. |
| `조합 종료 → 같은 글자로 재조합 → 옛 show 실행` | 문자열이 같아도 옛 session 의 결과는 버린다. |

후보 내용·선택·종료의 revision 과 activation 을 구분하는 세대(epoch)를 별도로 유지하며 owner·busy·active 검사는 유지한다.
macSKK 의 문자열 equality 와 Task cancellation 만으로 homi 의 owner/generation 을 대체하지 않는다.
azooKey 의 [CandidateSelectionFeedbackTests](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/azooKeyMacTests/CandidateSelectionFeedbackTests.swift#L18)는 snapshot 을 그릴 때 선택 delegate 를 다시 부르지 않는지 검사한다.
같은 원칙으로 후보·mode 의 표시가 Session·ModeMemory·TIS 를 다시 변경하지 않는 불변식을 고정한다. 새 UI 기능은 추가하지 않는다.

## 5. 설치 중 bundle 경로의 연속성을 지킨다 — 기존 설치 검증 보강

Mozc [#1439](https://github.com/google/mozc/issues/1439)는 macOS 26.3 의 GYP → Bazel package upgrade 뒤 menu icon 이상과 logout/login 복구를 보고했다.
maintainer 는 옛 bundle 삭제와 새 설치 사이의 경로 공백을 분석하고 installer 수정 뒤 해결을 보고했다.
상세 분석은 AI 작성으로 명시되어 있다. 관측·maintainer 의 수정 확인과 cache race 의 분석을 구분한다.

homi 는 이미 `RENAME_SWAP` 으로 경로 공백 없이 교환한다([설치 교훈](../lessons.md#설치-실패-때-입력기가-없는-구간이-생긴다-2026-10-09)).
삭제 후 복사나 덮어쓰기 방식으로 돌아갈 근거가 아니다. 실패 주입 시 기존 bundle·서명 보존, 교환 중 경로 연속성, 실제 설치 전후 TIS 상태를 검증하는 자료로 쓴다.
**이 upgrade 사례가 주인의 평상시 gray 증상 원인이라는 증거는 없다.** [비활성 snapshot](../macos-input.md#input-menu-의-비활성누락-2026-10-09-미해결)을 먼저 확보한다.

## 좁은 관측이 필요하거나 가져오지 않을 방식

| 선행 방식 · 근거 | homi 의 판단 |
|---|---|
| macSKK [#292](https://github.com/mtgto/macSKK/pull/292)의 activate `overrideKeyboard` 제거 | **관측만**. Safari·Mail·Notes crash 보고에 대한 대응이며 작성자도 원인 미확정·local 미재현이라고 했다. homi 의 문장부호·Remote Desktop layout 을 바꾸는 근거가 아니다. |
| macSKK [#116](https://github.com/mtgto/macSKK/pull/116)의 panel accessibility 변경 | **증상이 있을 때 관측**. Full Keyboard Access 에서 후보가 사라진 보고다. 후보 revision 취소와 panel 자체의 focus 간섭을 구분하고 system 설정은 임의로 바꾸지 않는다. |
| AquaSKK [inEvent guard](https://github.com/codefirst/aquaskk/blob/e90a04b15b15a82a0651a63aeb72dcd22d0d8c94/src/engine/session/SKKInputSession.cpp#L70), macSKK 의 즉시 commit 발행 | **SessionDriver 대체 기각**. AquaSKK 는 재진입 event/clear 를 무시한다. macSKK 의 동기 sink 도 전체 client 반영의 재진입 안전성을 증명하지 않는다. homi 는 종료 요청을 보존하고 같은 event 끝에 합치는 경계를 유지한다. |
| azooKey [commit generation guard](https://github.com/azooKey/azooKey-Desktop/blob/bd90b7bdc8f38069987b36426b990ef3129edf62/azooKeyMac/InputController/azooKeyMacInputController.swift#L190) | **text 처리에는 기각**. commit 요청 뒤 deactivate 가 generation 을 올리면 insert effect 까지 버리는 순서가 성립한다. 실앱 발생은 미검증이며 old/new mark 확인 해법도 아니다. |
| Mozc [commit callback 의 즉시 insert](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm#L690) | **일괄 적용 기각**. callback sender 에 조합을 넣는 방식이 homi 의 Chromium self-confirm 중복·입력칸 누출을 해결했다는 증거가 없다. bound client 와 전체 반영 경계는 유지한다. |
| 여러 system mode·key 중 `selectInputMode`·외부 TIS 를 내부 mode 에 반영 | **기각**. 내부 한/영 SOT·key 순서 보장과 충돌한다. azooKey [#340](https://github.com/azooKey/azooKey-Desktop/issues/340)은 2026-10-09 API 에서도 open 이며 외부 전환 불일치 해결 자료가 아니다. |
| AquaSKK [app 우회](https://github.com/codefirst/aquaskk/wiki/Workaround)의 form-feed mark·확정 직전 재-mark | **일괄 적용 기각**. wiki 는 2016-11-04 자료다. homi 는 가짜 mark 신호가 통하지 않은 [terminal 교훈](../lessons.md)을 이미 가지고 있다. 현 app 재현 없이 우회를 늘리지 않는다. |
| AquaSKK·macSKK 의 `{NSNotFound, NSNotFound}` | **단독 실험 보류**. 선행 구현에 있다는 사실은 [homi 의 실패한 range 실험](../lessons.md#imk-현재-selection-의-range-계약이-구현과-다르다-2026-10-09-교정-보류)을 해결한 증거가 아니다. commit 정책과 묶어 다시 바꾸지 않는다. |
| Mozc 의 [attributed mark·composedString](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm#L654) | **원인 교정으로는 보류**. homi 에서 plain String·getter 누락이 실패 원인이라는 증거가 없다. 필요하면 각각 단독 실험한다. |
| converter IPC/XPC·timeout/retry·history replay/dump·surrounding text 수집 | **기각**. Mozc [client](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/client/client.cc#L82)의 release timeout 은 30초다. 빠른 순수 한글 엔진에 필요 없고 homi 의 typing 무대기·입력 내용 비기록 원칙과 충돌한다. |
| main 밖 callback 을 `DispatchQueue.main.sync` 로 보정 | **관측 전 기각**. macSKK 의 방어 코드가 homi 의 non-main callback 발생 증거는 아니다. 동기 대기 경로를 새로 만들지 않는다. |

## 다음 작업에 반영할 순서

기본 입력·Chrome rollback 의 실제 확인을 먼저 한다. 이어서 activation coordinator 와 단계별 client 반영 test 를 준비하고,
client 질의 budget·후보 UI scheduler test·설치 실패 검증을 각각 분리한다. 이 자료 때문에 다른 source 왕복 교정의 우선순위를 올리지 않는다.
구현 때는 [안정성 검토의 통과 기준](../stability-review.md#검증-근거와-다음-순서)을 따른다.
외부 project 의 PR 병합·test 통과·작성자 실앱 확인은 homi 의 test·실앱 확인을 대신하지 않는다.

문서 변경 뒤 homi 의 `swift build`·Debug `swift test` 138개가 통과했다. local link 경로·heading 과 diff 공백도 검사했다.
새 regression test 를 추가하거나 실제 app 동작을 새로 확인한 것은 아니다.
