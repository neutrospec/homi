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
추천이 늦게 나타나는 동작과 글자 유실은 구분한다. 반복 가능한 사용자 보고이며 agent가 실제 실패를 포착한 결과는 아직 아니다.

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
Mail로 식별된 controller만 저장하는 10분 관측을 이어 준비했으며, 실제 재현 결과는 주인 확인을 기다린다.
별도 AppKit 시험창은 고정 가상 후보를 가진 기본 `NSTokenField`와 일반 `NSTextField`를 대조한다. 주소록·Mail 계정은 사용하지 않는다.
첫 후보의 초기 선택 0과 -1을 비교하며 field editor를 교체하거나 selection을 직접 조작하지 않는다.
별도 bundle의 compile·서명 검증까지 마쳤고 실제 keyboard 시험은 아직이다. 이 시험창의 성공·실패도 Mail의 실제 구현과 같은 경로라는 증거는 아니다.

Apple은 Mail이 [이전 수신자로 주소를 제안·완성](https://support.apple.com/en-au/guide/mail/mlhlp1113/mac)한다고 설명한다.
[`NSTokenField`](https://developer.apple.com/documentation/appkit/nstokenfield)는 일반 mail app 주소의 예를 들지만 현재 Apple Mail이 이 class를 쓴다는 증거는 아니다.
공개 계약·코드 검토·시험 source는 `build/mail-recipient-20261101/{research,code-review,completion-probe-readme}.md`와 `completion-probe.swift`에 있다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-11-01 | 설치본 16.0 (3901.200.71.1.16) | recipient 자동완성 대기 뒤 중간 음절 누락 보고. 원인·다른 app으로의 일반화는 미확정. 관측·대조 준비 |
