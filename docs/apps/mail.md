# Apple Mail

| | |
|---|---|
| bundle ID | `com.apple.mail` |
| 입력 구현 | recipient의 정적 선언 type은 `MUIAddressField` · 재현 당시 실제 class·field editor는 미확인 |
| 조사 환경 | 16.0 (3901.200.71.1.16) · 2026-11-01 · macOS 27.2 (26B123), 설치 bundle `Info.plist` 확인 |
| homi 설치본 | 2026-11-01 09:18 source ID 판정 교정본 (`aa4e74e`) |
| homi 규칙 | Mail 전용 우회 없음 |

## recipient 자동완성 뒤 중간 음절 누락 (2026-11-01, 미해결)

주인이 재현하기 쉬운 조건을 보고했다. 실제 이름 대신 한글 음절을 **S1·S2·S3**로 표시한다.

1. recipient 칸에서 S1만 조합 중일 때는 추천이 없다. 영문 입력에서는 문제가 없다고 보고했다.
2. S1S2까지 입력하면 S1을 기준으로 추천이 나타난다고 관찰했다. S2는 아직 조합 중이다.
3. 원하는 이름의 추천이 선택되어 Mail이 나머지를 미리 채우며, 다음 입력으로 대체할 부분이 선택된 것처럼 보인다.
4. 추천이 나타날 시간을 준 뒤 S3를 입력하면 S2가 사라져 **S1S3**가 된다고 보고했다.

추천 prefix가 실제로 확정된 text만 읽는지, S2가 selected range에 포함됐는지, 별도 편집으로 사라졌는지는 미확인이다.
추천이 늦게 나타나는 동작과 글자 유실은 구분한다. 이후 주인이 같은 조건의 누락을 다시 확인했고 아래 callback 순서를 확보했다.
주인의 구체적 가설은 Mail이 **S1만 사용자가 입력한 prefix로 기억한 채 S2S3를 자동완성의 selection으로 두어, 다음 S3가 전체를 대체한다**는 것이다.
그렇다면 homi가 S2를 확정해 보내도 이후 completion이 S2를 다시 교체 대상에 넣을 수 있다. 현재 callback 순서와 양립하지만 실제 selection·prefix는 아직 관측하지 못했다.

### 실패 재현 때의 callback (2026-11-01 10:24 KST)

빈 recipient 칸에서 두 음절 입력 → 약 2초 대기 → 세 번째 음절 입력을 요청했고, 주인은 추천을 직접 고르지 않는 이 검사에 **중간 음절 누락**으로 답했다.
동시 관측은 `metadata-3.log`의 새 controller `45843-4CD2CFD2-28B0-4585-BE61-8D18CE742D0D/16`이다. 실제 글자·key code는 기록하지 않았다.

| 시각 | 관측한 homi 경계 |
|---|---|
| 10:24:13.293–15.077 | 한글 mode로 입력을 시작하고 mark 네 차례 뒤 insert → mark를 보냈다. 마지막 반환 때 composing=true다. |
| 10:24:15.465 | 마지막 mark 반환 약 0.39초 뒤, inputDepth=0에서 `commitComposition`이 왔다. renderer=notFound라 TIS를 질의하지 않고 `insert`를 보냈다. 반환 때 composing=false다. |
| 10:24:16.984·17.260 | 이후 두 입력은 각각 새 mark만 보냈다. 두 번째에 이전 조합을 확정하는 insert는 없었다. |
| 10:24:18.438 | 다른 app으로 돌아가는 시점에 deactivate·insert와 그 안의 commit callback이 왔다. 앞선 대기 중 commit과 구분한다. |

**해석**: 주인이 수행한 순서와 대조하면 S2 조합 뒤 기다리는 동안 먼저 확정 요청을 받고, S3는 새 조합으로 시작한 흐름에 해당한다.
문자 대응은 주인 보고·순수 Session의 정상 순서와의 대조이며 trace가 문자열을 직접 확인한 것은 아니다.
이 controller의 생성부터 기록한 구간에는 일반 key 재진입 신호나 중첩 key의 client action이 관측되지 않았다. 다른 경로의 재진입 가능성을 배제하지 않는다.

조합 종료 callback과 homi의 insert 호출은 확인했다. **그 insert가 Mail 문서에 S2를 보존했는지, 자동완성이 이후 S2를 포함하는 selection을 만들었는지는 아직 모른다.**
Mail 자동완성 코드가 callback을 직접 일으켰는지도 시각만으로 확정하지 않는다. 기존 일반 key 재진입 반례 대신 이 idle commit 전후의 외부 편집 경계를 우선 대조한다.

### 가상 글자로 Mail에서 재현 (2026-11-01 10:38 KST)

빈 recipient에서 `가나` → 약 2초 대기 → `다`를 입력했고 주인은 **`가다`**, **추천 목록 나타남**으로 확인했다.
가상 글자에서도 누락이 재현됐으나 추천이 없을 때의 대조에는 해당하지 않는다. 추천 내용은 수집하지 않았다.
`metadata-5.log`의 같은 controller `/16`에서 10:38:20.899 mark 반환 → 21.283 idle commit → 21.284 insert 반환·composing=false →
23.768·23.886 새 mark 순서였다. 마지막 mark와 idle commit 사이 약 0.38초는 앞선 실패와 비슷하며, 실제 문서의 음절 소실 시점은 여전히 미확인이다.

### 기본 AppKit control 대조 (2026-11-01 10:28 KST)

별도 app의 기본 `NSTokenField`와 `NSTextField`에서 `가나` → 약 2초 대기 → `다`를 입력했고, 주인은 **두 칸 모두 `가나다`**로 정상 확인했다.
token field에는 가상 후보 `가나다`·`가나마`, completion delay 0.4초, 첫 후보 선택 0을 설정했다. field editor·selection은 직접 바꾸지 않았다.

시험창 자체 기록에서 `가나` 뒤 marked range와 selection은 모두 `{1,1}`로 유지됐다. 대기 뒤 `ㄷ`에 `가낟`, 다음 `ㅏ`에 `insert(나) → mark(다)`가 반영됐다.
그 대기 중 completion delegate는 호출되지 않았고 homi trace에도 idle commit이 없었다. 따라서 **Mail에서 실패한 자동완성·idle commit 경로에 도달하지 않은 대조 결과**다.
영문 예비 입력에는 token completion delegate가 호출됐으므로 delegate 연결 자체가 빠진 시험은 아니다.
근거는 `build/mail-recipient-20261101/completion-probe-2D225E11-17E7-41E6-AD50-D7741ABD0F53.log`와 `metadata-4.log`다. 시험창의 가상 글자만 기록했고 실제 Mail 내용은 수집하지 않았다.

초기 선택 -1 조건은 실행하지 않았다. 현재는 한글 조합 중 후보 callback 자체가 없어 선택 index만 바꾸는 반복보다, 공개 completion API의 조합 종료 동작을 먼저 대조한다.
실제 Mail의 commit 경로에는 재사용할 range 질의 결과가 없다. 관측용 client 질의를 새로 넣으면 재진입·timing을 바꿀 수 있어, 우선 자체 client 안의 합성 관측을 진행한다.

별도 standalone `NSTextView`에서 `complete(nil)`을 직접 호출하면 후보를 빈 배열로 돌려줘도 `unmarkText → completions(range: {0,2})`가 호출되고 `가나`의 mark가 해제됐다.
mark 끝 caret와 전체 mark 선택 양쪽에서 같았다. 이는 window·IMK에 연결하지 않은 API 실험이며 Mail callback이나 음절 누락을 재현한 것이 아니다.
근거는 같은 directory의 `completion-api-fixture.swift`·`completion-api-output.log`·`completion-api-review.md`다.

### 명시적 completion과 실제 IMK 대조 (2026-11-01 10:45 KST)

`ExplicitCompletionProbe.app`에서 첫 음절 확정 뒤 0.4초에, 같은 focused editor에 mark가 남아 있을 때만 공개 `complete(nil)`을 한 번 호출했다.
주인은 `가나` → 대기 → `다` 입력에 **위 token field와 아래 일반 field 모두 `가나다`**, 위쪽 **추천 목록 표시**를 확인했다.
이전 시험 요청과 답변 시점의 혼선을 보고해 창을 재시작했고, 다음 새 run의 기록만 이 확인과 대응한다.

| 시각 | 자기 token field와 homi에서 관측한 상태 |
|---|---|
| 10:45:45.754 | completion 직전 text=`가나`, selection·mark=`{1,1}`, hasMark=true |
| 45.759 | completion delegate가 받은 substring은 **`가나` 전체**다. |
| 45.764–.765 | homi controller `/22`에서 idle `commitComposition → insert`가 왔다. renderer=notFound, TIS 질의 없음으로 Mail과 같은 정책이다. |
| 48.594 | completion 반환 뒤 text=`가나다`, selection=`{2,1}`(**마지막 `다`만**), hasMark=false |
| 48.601·.727 | 다음 mark에 `가나ㄷ → 가나다`로 반영돼 `나`가 보존됐다. |

근거는 `explicit-completion-probe-E0494799-1F27-4A93-9587-765EC1E35FB4.log`와 `metadata-7.log`다. 둘 다 위 `build/` directory에 있다.
아래 일반 field는 조합이 유지된 뒤 도깨비불로 마지막 음절을 만들었고, 위의 강제 completion 경로와 구분한다.
**idle commit·확정 전송·새 조합이라는 순서 자체만으로 누락을 설명할 수 없다.** 그 순서로도 정상인 실제 IMK 대조를 확보했으며, Mail의 prefix·선택 범위 차이는 아직 가설이다.

### 짧은 prefix를 주는 합성 모델

창·IMK에 연결하지 않은 `NSTextView`에 `가나`와 mark `{1,1}`을 만들고 `insertCompletion`의 partial range를 직접 바꿨다.

| 모델에서 직접 넘긴 partial range | completion 뒤 selection | 다음 합성 `ㄷ → 다` |
|---|---|---|
| `{0,1}` — 첫 음절만 | `{1,2}` — `나`와 후보의 마지막 글자 | `가ㄷ → 가다` |
| `{0,2}` — 두 음절 전체 | `{2,1}` — 후보의 마지막 글자만 | `가나ㄷ → 가나다` |

mark 끝 caret·전체 mark 선택, 후보 `가나다`·`가나마`의 조합 8개에서 이 차이를 확인했다.
주인 가설이 **주어진 조건 아래 실제 AppKit API로 가능한 메커니즘**임을 보인다. range를 의도적으로 지정한 모델이며 Mail이 그 값이나 API를 사용했다는 증거는 아니다.
실제 homi의 commit·IMK proxy 호출도 이 모델에는 없다. 재실행 source·결과는 `stale-prefix-model.swift`·`stale-prefix-output.log`·`stale-prefix-model.md`다.

별도 합성 `rangeForUserCompletion` 대조에서는 `가`의 범위가 `{0,1}`, mark를 포함한 `가나`의 범위가 `{0,2}`였다.
후자는 전체 mark 선택·끝 caret 양쪽에서 같았으며, 이 질의 자체가 `unmarkText`를 호출해 mark를 해제했다.
따라서 이 API가 언제나 mark를 제외한다고 해석하지 않는다. 짧은 범위를 **언제 저장하고 다시 갱신했는지**가 남은 질문이다.
창·IMK 없는 관측이며 source·질의 전후를 분리한 기록은 `completion-range-model.swift`·`.log`·`.md`에 있다.

### MailUI 정적 구현 대조

현재 설치본의 Mail 실행 파일에서 `HeadersEditor.toField`의 선언 type은 `MUIAddressField`다. 이는 재현 당시 실제 object의 class 확인은 아니다.
연결된 MailUI의 arm64e image UUID는 `766F301A-6E14-3705-820A-97A599E9D4C7`이며 `_currentPrefix`·`_editingRange`라는 별도 ivar와 접근 구현을 확인했다.
REA 도구는 연결되지 않아 설치·설정 없이 시스템 `dyld_info` 등으로 shared cache의 code를 읽었다. Mail process·연락처·사용자 데이터에는 접근하지 않았다.

독립 검토에서도 stub instruction → cache의 VM/file offset → selector 문자열 바이트를 대조해 다음 연결을 확인했다.

- `_updateEditingRange`는 `tokenField.currentEditor.rangeForUserCompletion` 결과를 `setEditingRange:`로 저장한다.
- `_showSelectedCompletionInField`의 확인한 분기는 `editingRange` getter의 두 정수를 editor의 `insertCompletion:forPartialWordRange:movement:isFinal:`에 넘긴다.
- `handleControlTextChange`는 조건에 따라 `_editingStringWithRange:`가 얻은 범위와 문자열을 `editingRange`·`currentPrefix`에 저장하고 `_startCompleting`을 지연 예약한다.
- `_startCompleting`의 block은 저장한 `currentPrefix`를 읽어 검색 request에 사용한다. 이 block 본문에는 범위를 직접 재계산하는 호출이 없지만,
  다른 callee의 부작용과 비동기 결과 callback 전체는 확인하지 않아 표시 전 갱신이 전혀 없다고 결론내리지 않는다.
- 후속 flag 대조에서 `_showSelectedCompletionInField`는 `insertCompletion` 호출 전 `isShowingSelectedCompletion=true`, 반환 뒤 false로 둔다.
  `handleControlTextChange`는 showing이 true이면 저장 range와 prefix를 모두 갱신하지 않는다. 따라서 **completion 중 동기 재진입한 변경 알림**에는
  이 갱신 차단이 적용될 수 있다. flag 검사 전 `_editingStringWithRange:` 질의는 실행된다. `ignoreCompletionForTextChange`만 true일 때는
  range 갱신만 막고 prefix 갱신까지 반드시 막는 것은 아니다. selector 바이트·분기 대조는 `mailui-completion-flags-review.md`·`mailui-completion-flags-resolution.*`에 있다.

**저장된 편집 범위를 이후 completion에 사용하는 경로는 실제 code에 있다.** 그러나 실제 시험에서 이 분기가 실행됐는지, 그때 저장한 범위가 짧았는지, 중간 갱신이 있었는지는 미확인이다.
현재 구체적 가설은 **S1 확정 때의 text change가 짧은 범위를 저장 → S2 mark 뒤에도 그 값 유지 → 지연된 completion이 S2를 교체 대상에 포함**하는 흐름이다.
첫 확정과 다음 mark 사이에 text change가 오는 것은 자기 AppKit probe에서 확인했다. 실제 Mail의 저장 값과 중간 갱신 여부는 아직 관측하지 못했다.
정적 자료와 독립 검토는 `mail-static-review.md`·`mail-static-independent.md`·`mailui-block-review.md`, 주소·바이트 대조는 `mailui-stub-resolution.*`·`mailui-block-resolution.*`에 있다.
원본 disassembly는 `build/`에만 두고, 정적 경로를 실제 실행 관측이나 Mail의 결함 확정으로 확대하지 않는다.

### insert range 단독 대조 (2026-11-01, 원복)

주인 요청으로 IMK 계약과 다른 `insertText`의 인자만 분리해 시험했다. 기준은 `7c7cea3`의 제품 코드·09:18 설치본이며,
유일한 runtime 변경은 `.insert`의 `replacementRange.length`를 `0`에서 `NSNotFound`로 바꾼 것이다. location은 계속 `NSNotFound`이고,
mark의 `{NSNotFound,0}`·조합·commit 정책·추가 질의·timing 코드는 바꾸지 않았다.

- SDK sentinel을 검사하도록 기존 test를 먼저 바꾸니 insert 검사 두 개는 실패하고 mark 검사는 통과했다.
  단독 변경 후 `swift build`와 Debug·Release 각각 347개 test에서 기존 일반 key 재진입 known issue 1개 외 실패·warning은 없었다.
- 11:12 시험본 UUID는 `6A3EB3B4-A74F-321C-A007-18BF565948E6`, CDHash는 `ea907058ca1a38b3ea3fd01d3c928e0276ad4638`, 서명은 `homi code signing`이다.
  시작 log의 PID `56247`·실행 UUID가 설치본과 일치했다.
- 같은 Mail 빈 recipient에서 `가나` → 추천 대기 → `다`를 입력한 주인은 **추천 목록이 나타났고 여전히 `가다`**라고 확인했다.
  controller `56247-B3BBCD1B-1A60-4B22-90E1-21D472AB88D3/2`의 첫 시험 구간에서 11:15:11.497 mark 반환 → 11.880 idle commit → 11.884 insert 반환 →
  13.297·13.381 새 mark가 관측돼, 앞선 `{NSNotFound,0}` 조건과 같은 형태의 종료 순서였다.

**이 인자 차이만 교정해서는 이번 Mail 누락이 해결되지 않았다.** 이는 기존 인자가 계약상 옳다거나, 모든 상황에서 길이가 무시된다는 증거는 아니다.
시험본의 Chrome·native 기본 입력 등 다른 경로는 주인 확인을 받지 않았으므로, 효과 없는 전역 실험을 유지하지 않고 11:17에 제품 코드·test와 서명된 기존 bundle을 원복했다.
원복 UUID `A73858F5-93E6-398F-AE3E-38F5860283DF`, CDHash `24db9b36de31460285c6a71d604362523c531f9c`를 검사했고, 11:17:25 새 PID `83907`의 시작 UUID도 일치했다.
계약 차이의 독립 교정·호환성 검증은 남는다.

패치·red/Debug/Release test·설치·시작·내용 없는 callback·원복 기록은 `build/mail-range-20261101/`에 있다.
기존 signed bundle은 그 directory의 `baseline-homi.zip`으로 보존했다. 단독 시험은 Mail의 실제 prefix·selection 값을 관측한 것이 아니다.

### Apple 한국어 입력기와의 차이 (2026-11-01, 주인 관측)

주인은 Apple 한국어 입력기로 비교했을 때 **S1에서 대기하면 추천이 나오고, S1S2에서는 나오지 않으며, S1S2S3에서는 다시 나온다**고 보고했다.
입력 누락이 없었고, homi처럼 S1S2를 입력한 상태에서 S1 기준으로 보이는 추천이 나타나는 장면도 없었다.
이는 같은 Mail에서 입력기별 상호작용이 다르다는 단서다. 후보의 실제 검색어·selection·Apple의 client 호출은 이 비교에서 수집하지 않았다.
S1S2의 추천 부재를 단순한 prefix 불일치, Apple만의 특례, 모든 조합 중 추천 억제로 단정하지 않는다.

앞선 자체 token field에서는 10:45:45.353에 `controlTextDidChange`가 **text=`가`, hasMark=false**를 관측했고,
같은 key의 처리가 끝난 45.357에는 **text=`가나`, hasMark=true**였다. 일반 field에서도 같은 중간 notification을 확인했다.
즉 homi의 `insert(가) → mark(나)` 사이 상태를 client가 볼 수 있다는 것은 실제 AppKit 대조의 사실이다.
Mail이 그 시점의 prefix를 저장하고 새 mark 뒤에도 유지한다는 것은 여전히 가설이다.

과거 [Apple 입력기의 별도 probe](../macos-input.md#marked-text-없이-확정하고-바꿔치기한다)는 자모마다 확정 text를 넣고 replacement로 고쳤다.
이때는 client에 보이는 text·변경 알림의 시점이 homi와 달라질 수 있지만, 현재 Mail 안의 Apple 호출 방식까지 확인한 것은 아니다.
또한 [Mozc의 공개 구현](https://github.com/google/mozc/blob/921b8cc99904c8d31b771e395513da0a5d55182a/src/mac/mozc_imk_input_controller.mm)은 preedit segment들을 하나의 mark로 모은다.
조합·확정 단위가 다르면 중간 prefix가 노출되는 시점도 다르므로, 이 조건의 결함이 모든 CJK 입력기에서 똑같이 나타나야 하는 것은 아니다.

조사한 공개 IMK API에서는 insert와 다음 mark를 하나의 client transaction으로 묶거나 Mail 추천을 억제하는 수단을 찾지 못했다.
[NSTextStorage의 batch editing](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextEditing/Tasks/BatchEditing.html)은 client 측 제어이며 외부 입력기의 권한으로 일반화하지 않는다.
기본 입력을 Apple식 replacement로 전환하거나 조합 전체를 무조건 오래 유지하는 것은 확정·편집·focus 경계를 바꾼다.
따라서 새 비교는 **해법 부재나 Mail 단독 결함의 근거가 아니라, 두 입력기의 반영 방식과 자동완성의 접점을 더 좁힐 근거**로 둔다.
공개 계약·코드 검토는 같은 `build/` directory의 `apple-comparison-contract-review.md`·`apple-comparison-code-review.md`에 있다.

별도 창 없는 `NSTextView`에 현재 제품 Session의 action을 적용한 자동 대조도 진행했다.
Apple 조건은 과거 호출 형태의 수동 모델이며 현재 Apple 입력기를 실행한 것이 아니다.

| `가나`까지 만드는 방식 | 마지막 text-change 알림의 text | 알림 때 범위를 저장하는 조건부 completion 모델 |
|---|---|---|
| homi Session의 음절별 insert → mark | `가` (1회) | 저장 `{0,1}` → 후보 `가나다`의 selection `{1,2}` |
| Apple식 확정·replacement 모델 | `가나` (5회) | 저장 `{0,2}` → selection `{2,1}` |
| 전체 단어 mark 모델 | 알림 없음 | completion 경로 미도달 — 해결 통과 아님 |

범위는 상수로 넣지 않고 notification 당시 자체 view의 selection에서 계산했다. 다만 **그 시점에만 저장한다는 host 정책은 가정**이다.
IMK callback이 없는 homi 모델에는 `나` 조합이 남아 이후에도 `가나다`가 됐다. 실제 Mail의 idle commit 뒤 누락 재현으로 세지 않는다.
Apple 모델의 completion 뒤 입력기 상태는 미확인으로 후속 입력을 검사하지 않았다. 근거는 `notification-comparison.swift`·`.log`·`.md`다.
확정 단위를 늘리는 안은 추천 시작 시점·Backspace·focus 처리가 바뀌므로 이 결과만으로 제품에 적용하지 않는다. 설치본은 유지한다.

### 첫 음절의 실제 Apple 대조 (2026-11-01 11:38 KST)

같은 기본 `NSTokenField`에 가상 후보 `가나다`·`가나마`, delay 0.4초를 두고 **강제 completion 없이** Apple 두벌식으로
`가` → 2초 대기 → `나` → 2초 대기 → `다`를 입력했다. 주인은 세 단계 모두 추천이 나왔다고 확인했다.
`first-syllable-probe/run-C04CA3ED-CD74-4A40-8541-C8B6BF27BF20.log`에서 source는 Apple 두벌식으로 확인된다.

| 시각 | 자기 field에서 직접 관측한 것 |
|---|---|
| 11:38:02.549 → 02.969 | `가`의 변경 알림 → completion의 substring=`가`, hasMark=false |
| 04.935 | 추천이 채운 `가나다` 뒤 다음 자음으로 `간`이 됨. 앱에 mark가 없어도 음절 조합은 이어짐 |
| 05.160–.161 → 05.565 | `가`·`가나`의 변경 알림 → completion의 substring=`가나`, hasMark=false |
| 08.409–.410 → 08.813 | `가나`·`가나다`의 변경 알림 → completion의 substring=`가나다`, hasMark=false |

이 probe는 editor 상태·notification을 관측하며 IMK의 insert 호출을 가로채지는 않는다. **입력기 내부 조합과 앱의 marked text가 별개**인 실제 대조이며,
첫 음절 추천에 Mail만의 특례가 필요하다는 근거는 없다. Mail의 S1S2에서만 추천이 없었던 이유는 여전히 별도 질문이다.

homi 대조는 같은 창을 재사용했고, 주인은 기존 입력이 남아 있었다며 준비 혼선을 보고했다. 새 process·빈 칸이 보장된 A/B 시험으로 세지 않는다.
다만 같은 log의 11:40:34.351에 editor가 빈 뒤 35.411 `가` → 38.030 `가나` → 40.441 `가나다`가 관측됐고,
한글 구간에는 hasMark=true이며 completion delegate 호출이 없었다. 다음 빈 칸 재입력 구간도 같고, 11:40:50.583 조합 종료 뒤 50.986에는
substring=`가나다`로 completion이 왔다. 앞선 기본 control 대조와 일치한다. 초기 영문 입력과 추가 편집을 이 한글 구간에 섞지 않는다.
사용자 보고는 모든 단계 추천 없음이며, 이후 별도 편집의 최종 상태까지 같은 시험 결과로 확대하지 않는다.

### idle commit을 포함한 조건부 누락 모델

창 없는 자기 `NSTextView`에 제품 Session의 action을 적용하고, `가나` 뒤 **세 조건 모두 같은 `Session.commit()`을 명시적으로 주입**했다.
범위는 notification 당시 자체 editor의 selection에서 계산했다. 실제 IMK callback·Mail 실행을 재현한 것은 아니다.

| completion 조건 | 다음 `다` 뒤 결과 |
|---|---|
| completion 없음 | `가나다` |
| commit 전 알림의 범위를 보관해 사용 | `가다` |
| commit으로 온 알림의 갱신된 범위를 사용 | `가나다` |

`idle-commit-model.swift`·`.log`·`.md`에 source·실행·가정을 남겼다. 오래된 범위를 사용하는 조건과 idle commit을 결합하면
실제 보고와 같은 유실이 가능하다는 근거이며, Mail의 실제 값·실행 분기 또는 입력기 수정안의 안전성을 증명하지 않는다.

### 공통 mark 확장 후보의 격리 실험 (2026-11-01, 제품 적용 보류)

주인 요청으로 Mail 분기 없이 **완성된 앞 음절을 즉시 insert하지 않고, 현재 음절과 함께 하나의 mark로 유지**하는 후보를 시험했다.
기준 source는 `dc783ed`다. 제품 Session과 자체 창 없는 `NSTextView` 사이에 실험용 wrapper를 두었으며 제품·설치본은 바꾸지 않았다.

단순 wrapper는 `가나다 → Backspace 세 번 → ㅁ → commit`에서 기존 `가ㅁ` 대신 **`가가나ㅁ`**을 만들었다.
현재 음절이 빈 뒤 Backspace를 app으로 넘겨 mark가 끝났지만 wrapper의 앞 글자는 남았기 때문이다. 기존 기대값으로 exit 1을 확인했다.
pending 글자 삭제와 명시적 종료를 보완한 두 번째 모델은 13개 지정 순서의 매 단계에서 기존과 같은 문자열을 남겼다.
일반 조합·겹받침 삭제·빈 현재 음절·반복 종료·모드 전환·문장부호·선택 대체·명시적으로 이전 field를 끝낸 뒤 이동을 포함한다.
단, 앞 글자를 지울 때 Backspace의 `handled`는 false에서 true로 달라졌다. key 전달·selection·undo·실제 focus 소유권의 동등성은 검사하지 않았다.

같은 wrapper에 notification 당시 caret까지를 prefix로 저장하는 **합성 host 정책**을 연결했다. 아래 completion 직전 commit은 fixture가 주입한 것이며 실제 IMK callback이 아니다.

| 조건 | 기존 음절별 경로 | 전체 단어 mark 후보 |
|---|---|---|
| `가나` 뒤 이전 알림의 prefix로 completion → `다` | `{0,1}`로 completion, `가다` | 알림이 없어 completion **미도달**, `가나다` |
| `가` 뒤 외부 종료를 먼저 주입 → `나` → 같은 completion → `다` | `가다` | `가다` |
| `가나`를 명시적으로 종료한 뒤 새 알림의 prefix로 completion → `다` | `{0,2}`로 completion, `가나다` | `{0,2}`로 completion, `가나다` |

첫 행은 누락 교정보다 **추천 시작 시점 변경**을 보인다. 두 번째 행의 추가 종료는 실제 Mail에서 관측한 순서가 아니며,
입력기가 중간 insert를 줄여도 외부 종료와 오래된 prefix의 조합까지 막지는 못한다는 조건부 반례다. 세 번째 행도 Mail 해결 검증이 아니다.

한자에도 계약 차이가 있다. `한글` 전체를 mark하면 기존 `textBefore(1)`의 기준점이 mark 시작 0으로 바뀌어 `한`을 읽지 못하고 현재 음절 후보로 fallback한다.
현재 음절의 후보 insert를 전체 mark에 그대로 적용한 합성 대조는 앞의 `한`도 지웠다. 후보 ESC는 조합을 유지해야 하므로 후보 닫힘을 일괄 확정 신호로 쓸 수도 없다.
이는 표시 wrapper만으로 연결하기 어렵다는 근거이며, 한자 처리를 함께 설계하면 불가능하다는 뜻은 아니다.

**판단:** 단순한 공통 보정으로 채택하지 않는다. 전체 mark는 조합 범위·확정·한자·app의 key 처리 계약을 함께 바꾸는 설계다.
재검토하려면 확정 전 추천을 늦추는 타협을 명시하고, 남은 조합의 소유권을 Session 한 곳에서 관리하며 한자·종료·실제 app 검증을 갖춰야 한다.
이를 Mail 전용 우회가 안전하다는 근거로도 쓰지 않는다. [부분 insert의 공개 계약·AppKit 대조](../macos-input.md#부분-insert와-남은-mark-2026-11-01)에서도 더 작은 원자적 교정은 확인하지 못했다.

재실행 source·명령·출력은 `build/mail-common-20261101/`의 `prefix-model`·`knownbad-requirement`·`word-mark-wrapper`·`completion-boundary-model`·`hanja-boundary-fixture`와 각 검토 문서에 있다.
13개 통과는 문자열 fixture의 범위다. 실제 Mail 해결·IMK lifecycle·다른 app의 입력 안전성을 뜻하지 않는다.
source에서 다시 만든 모듈로 첫 반례의 exit 1과 보완·completion·한자 모델의 지정 결과를 재확인했다. `swift build`·Debug 347개 test도 기존 known issue 1개 외 실패·warning 없이 끝났다. 기록은 같은 directory의 `*-review.log`·`build.log`·`debug-tests.log`다.

## 구분할 경계

- **대기 중 종료 없이 조합이 이어지는 경우**에는 S3의 초성이 S2의 종성이 되고, 다음 모음에서 도깨비불로 `insert(S2) → mark(S3)`가 나온다.
  실제 제품 Session의 합성 `가교주`로 확인했다(`build/mail-recipient-20261101/session-fixture/output.txt`). 이번 Mail 실측은 그 사이 idle commit이 있으므로 이 정상 순서와 구분한다.
- 실제 Mail의 다음 mark 직전 selection을 한 번 묻는 진단도 보류했다. 새 client IPC 중 일반 key가 재진입하면 이미 만든 outer mark가 새 조합을 덮는 기존 반례를 더 유발할 수 있다.
  sample을 invalid로 표시해도 입력 손상을 막지 못한다. 근거는 `one-query-proposal.md`이며 제품 코드·설치본은 유지한다.
  실제 Mail의 prefix·선택 범위를 확인할 수 있는 읽기 전용 근거를 우선한다. 안전한 구별 없이 commit을 무시하거나 이미 확정한 음절을 다시 넣는 우회는 채택하지 않는다.
- callback 뒤 별도 closure의 idle range 질의도 검토했다. query 뒤에 action을 적용하지 않으면 앞선 특정 stale mark 반례는 피할 수 있지만,
  추가 동기 IPC·nested run loop·입력칸 식별의 한계가 남는다. main queue 예약만으로 client가 completion을 끝낸 시점이 보장되지는 않는다.
  실제 Mail에 설치하지 않았으며 `idle-range-observation-review.md`에 검토 범위를 남겼다.
- 기존 [일반 key 재진입 반례](../stability-review.md#imk-이론-검증-범위-2026-11-01)와 동일 원인을 전제하지 않는다.
  제품 trace의 action·call·controller·종료 순서를 실제 결과와 대조하되 호출 반환을 client 반영 완료의 증거로 삼지 않는다.
- `replacementRange` 전역 변경·늦은 mark 재질의·강제 확정은 [이전 실패](../lessons.md#imk-현재-selection-의-range-계약이-구현과-다르다-2026-10-09-교정-보류)를 먼저 대조한다.

## 관측과 대조 준비

현재 Mail의 빈 `New Message` 창과 AX의 `Mail.toField`를 확인했다. 이 role·identifier로 구현 class나 실제 mark/selection 관계를 확정하지 않는다.
제품 코드는 유지한 채 내용 없는 homi trace 관측을 준비했다. 실제 recipient·주소·본문이나 최근 key recorder를 file로 수집하지 않는다.
첫 4분 관측에는 Mail과 연결할 controller·실패 구간을 확보하지 못했다. 이는 Mail에서 callback이나 재진입이 없었다는 증거가 아니다.
Mail로 식별된 controller만 저장하는 두 번째 관측에도 해당 입력 구간이 없었다. 세 번째 관측에서 위 재현 순서를 확보한 뒤 수집을 종료했다.
별도 AppKit 시험창은 고정 가상 후보를 가진 기본 `NSTokenField`와 일반 `NSTextField`를 대조한다. 주소록·Mail 계정은 사용하지 않는다.
별도 bundle의 compile·서명 검증과 위 실제 keyboard 대조를 마쳤다. 이 시험창의 성공·실패도 Mail의 실제 구현과 같은 경로라는 증거는 아니다.

Apple은 Mail이 [이전 수신자로 주소를 제안·완성](https://support.apple.com/en-au/guide/mail/mlhlp1113/mac)한다고 설명한다.
[`NSTokenField`](https://developer.apple.com/documentation/appkit/nstokenfield)는 일반 mail app 주소의 예를 들지만 현재 Apple Mail이 이 class를 쓴다는 증거는 아니다.
공개 계약·코드 검토·시험 source는 `build/mail-recipient-20261101/{research,code-review,completion-probe-readme}.md`와 `completion-probe.swift`에 있다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-11-01 | 설치본 16.0 (3901.200.71.1.16) | recipient의 대기 중 음절 누락을 두 차례 주인 확인. 기본·명시적 completion 대조는 정상이며 후자는 Mail과 같은 idle commit 순서도 관측. 짧은 prefix 모델에서 같은 누락이 가능하나 실제 Mail selection·구현은 미확정. 제품 유지 |
| 2026-11-01 11:15 | 같은 Mail 설치본 | insert length만 SDK sentinel로 바꿔도 추천 뒤 `가다`로 누락. 다른 호환 경로 미검증으로 11:17 기준 코드·signed bundle 원복 |
