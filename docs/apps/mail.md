# Apple Mail

| | |
|---|---|
| bundle ID | `com.apple.mail` |
| 입력 구현 | recipient control의 구체적인 class·field editor는 미확인 |
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
다음 실제 대조는 Mail의 빈 recipient에서 가상 `가나` → 대기 → `다`를 입력하고 추천 유무·결과·idle commit을 함께 확인하는 것이다.

## 구분할 경계

- 중첩 key 없이도 자동완성이 mark·selection·문서를 바꿀 가능성을 조사한다. **selection에 S2가 포함된 것만으로 손실이 설명되지는 않는다.**
  보고처럼 S2에 받침이 없으면 S3의 초성은 먼저 S2의 종성으로 붙고, 다음 모음에서 도깨비불로 `insert(S2) → mark(S3)`가 나온다.
  첫 초성의 단일 mark와 다음 모음의 insert→mark 양쪽에서 어느 부분이 바뀌는지, 그 사이 외부 편집이나 종료 callback이 있었는지가 필요하다.
  실제 제품 Session의 합성 `가교주`로 이 순서를 확인했다(`build/mail-recipient-20261101/session-fixture/output.txt`). Mail의 반영 결과 검사는 아니다.
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
| 2026-11-01 | 설치본 16.0 (3901.200.71.1.16) | recipient 자동완성 대기 뒤 중간 음절 누락 재현을 주인 확인. 10:24 대기 중 commit callback·insert·새 조합 순서를 관측. 기본 token/plain 대조는 정상이나 대기 중 completion·idle commit 경로가 없었다. 실제 Mail selection·문서 반영 원인은 미확정 |
