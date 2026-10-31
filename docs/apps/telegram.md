# Telegram

| | |
|---|---|
| bundle ID | `ru.keepcoder.Telegram` |
| 엔진 | AppKit — 입력칸은 TelegramSwift `ChatInputTextView` 안의 `NSTextView` → [engines/appkit.md](engines/appkit.md) |
| 확인한 version | 12.9 (282526) · 2026-09-25 · macOS 27.0 |
| 최근 조사 환경 | 설치된 app 13.1.0 (283357) · 2026-10-29–31 · macOS 27.2 — 보고된 실패 순간의 version·event 는 별도 미확인 |
| homi 규칙 | 조합 중 Return·keypad Enter 는 확정 → 먹고 → 다시 보낸다 |

## 특징

### resend 목적지 교정 확인 (2026-10-31)

설치된 Telegram **13.1.0**·macOS **27.2**에서 15:23 homi 교정본의 조합 중 Enter 확인을 요청했다.
주인은 저장한 메시지의 Enter 한 번 전송과 terminal 확인 요청에 정상이라고 답했고, Telegram 과 terminal 양쪽임을 추가 확인했다.
도구가 메시지 내용이나 전송 결과를 읽은 것은 아니다. 15:32 최종본도 같은 resend 구현이다.
전달 경로를 전역 HID 에서 원래 app 의 process 로 지정하도록 바꿨다. 새 down/up 준비 실패 때는 원래 key 를 넘긴다.
[공통 변경·한계](../macos-input.md#key-다시-보내기)를 따른다. 빠른 다음 key·focus 변경 순간의 전달은 별도 미확인이다.

### 기존 확인

- **조합 중 Enter 는 전송이 아니라 줄바꿈이 된다** (Apple 입력기 때부터). Telegram 은 marked text 가 없고 수식키도 없을 때만 Enter 로 보낸다.
  조합 중이면 key 를 입력기에 넘기고, 입력기가 확정한 뒤 줄바꿈이 된다 — 일본어·중국어의 "Enter = 변환 확정" 관례다.
  `12.9 · 2026-09-25 · source(ChatInputTextView.keyDown, a404806) + 주인` ✅
- **다시 보낸 Enter 는 새 event 여야 닿는다** — 원래 event 의 복사본을 key 처리 도중에 보냈더니 "틱" 소리만 나고 사라졌다.
  `12.9 · 2026-09-25 · 주인 + 기록` ✅ (까닭 🔶 — docs/lessons.md)
- **Apple 방식 한자(방금 친 단어)가 된다** — `나는한자` + ⌥↩ 에 `한자` 에만 밑줄이 생긴다.
  `12.9 · 2026-09-25 · 주인` ✅
- 2026-09-25 에는 Apple 두벌식에서 첫 초성 누락(`아` → `ㅏ`)을 보고했고 당시 homi 에서는 미재현이었다.
  2026-10-30 에는 homi 사용 중에도 [초성 누락을 보고](#창-전환-뒤-초성-누락-2026-10-30-미해결)했다. 과거의 미재현을 현재 원인 배제 근거로 쓰지 않는다.

## 창 전환 뒤 첫 key 가 영문 (2026-10-29, 미해결)

- **주인 보고**: Telegram 으로 창을 전환해 바로 입력하면 가끔 첫 `ㅁ` 자리가 `a` 로 나오고 두 번째 key 부터 한글이 된다.
  **Caps Lock 을 누르지 않고 입력한 경우**다. 실제 발생 구간의 event·mode 기록은 아직 없다.
- **현재 설정 확인**: 저장된 Telegram mode 는 `korean` 이며 영문 시작·입력 통과·ESC 영문 전환 목록에 없다. 전환 key 는 Caps Lock 하나다.
  이는 조사 시점의 저장값이며, 실패 당시 runtime mode 의 증거는 아니다. Enter resend 우회도 이 일반 문자 key 의 경로에는 해당하지 않는다.
- **Caps Lock 조사와의 관계**: [tap 의 counter 판정](../stability-review.md#caps-lock-전환-code-review-2026-10-29)이 취소돼도
  뒤의 일반 문자 key 가 스스로 한글 mode 로 바꾸지는 않는다. Caps 를 누르지 않았고 다음 key 에서 회복된다는 조건을 별도 activation·app 식별 문제로 조사한다.
- **code model**: `4326e70` 의 `ModeActivation`·`ModeMemory`·`Session` 을 실행했다. 실제 Telegram ID 와 한글 mode 로 시작하면 첫 key 는
  `handled=true, mark("ㅁ")` 이다. 반면 첫 key 에 client ID 가 없고 fallback 이 영문인 이전 app 이라는 조건을 넣으면 그 key 는 통과한다.
  그 뒤 별도 activation 이 들어오고 두 번째 key 에 실제 Telegram ID 를 알게 되는 순서를 주입하면 두 번째 key 는 한글이다.
  **중간 activation 없이 ID 만 늦게 보정하면 영문을 이어 갔다.** 따라서 "ID 가 늦으면 자동으로 첫 key 만 영문"이라고 일반화하지 않는다.
  주입한 순서의 성립은 실제 Telegram 의 callback 순서나 원인 확정이 아니다.

다음은 첫 key 가 IMK 에 도착했는지, 도착했다면 controller·app ID 의 출처(client/cache/fallback)·mode·modifier·handled·mark 호출을 대조하는 것이다.
후속 [source review](../stability-review.md#focus와-source-전환-code-review-2026-10-31)는 조합·명시적 전환 없이 넘긴 key 도
fallback 의 mode 를 실제 app 에 복사하는 반례를 확인했다. 실제 Telegram 의 실패 원인으로 확인한 것은 아니다.
도착하지 않은 경로, 영문으로 통과시킨 경로, 한글 mark 를 보냈으나 client 반영이 어긋난 경로를 구분한다.
현재 원인이 특정되지 않았으므로 app 우회·모드 강제 reset·source 선택은 추가하지 않는다.
2026-10-31 에 [system 의 문서별 source 자동 복원이 켜져 있음을 확인해 해제](../macos-input.md#문서별-input-source-복원-재확인-2026-10-31)했다.
실패 당시 설정값과의 대응은 미확인이다. 이후 재발은 이 설정을 끈 조건으로 구분한다.

## 창 전환 뒤 초성 누락 (2026-10-30, 미해결)

**주인 보고**: homi 사용 중 Telegram 으로 창 전환한 직후, **Caps Lock 을 누르지 않고** `당`을 쳤으나 `ㅏㅇ`이 남았다.
첫 `ㄷ`이 영문 `e`로 남은 것도 아니다. 전환 방식과 정확한 발생 시각은 아직 확인하지 못했다.
앞선 첫 key 영문과 같은 창 전환 경계를 조사하되, 원인이 같다고 합치지 않는다. 기본 입력의 글자 유실로 우선 조사한다.

**코드로 구분한 조건**: `623adcb`의 실제 `Session`·Telegram `AppProfile`을 별도 process 에서 합성 입력으로 실행했다.
입력칸 model 에 같은 조합의 mark 를 교체하고 insert 를 확정하는 조건을 주었으며, 실제 IMK·Telegram 에 연결하지 않았다.

| 합성 조건 | 결과 |
|---|---|
| 정상 `ㄷ·ㅏ·ㅇ` | `당` |
| 첫 `ㄷ` event 를 Session 에 주지 않음 | `ㅏㅇ` |
| 첫 mark 만 client 에 반영하지 않고 Session 은 유지 | `당` |
| 첫 `ㄷ` 뒤 정상 commit 과 client 반영 | `ㄷㅏㅇ` |
| 첫 key 만 영문으로 통과하고 client 가 정상 입력 | `eㅏㅇ` |
| 첫 key 에 Command 가 붙고 client 가 문자 없이 소비한다고 가정 | `ㅏㅇ` |
| 첫 `ㄷ` 뒤 Session 과 client mark 가 함께 사라진다고 가정 | `ㅏㅇ` |

첫 mark 의 화면 표시만 빠졌다면 다음 모음의 mark 는 `다`이므로 보고된 결과를 설명하지 못한다.
첫 자음이 조합에 들어오지 않았거나, 다음 key 전에 조합 상태·입력 대상이 끊겼거나, 이후 client 가 다른 처리를 한 경로를 가려야 한다.
Command 조건은 가능한 통과 경로를 보인 것뿐이며 주인의 조작 실수나 실제 modifier 상태를 입증하지 않는다.

**남아 있던 metadata**:

- 20:52:06.025 KST, controller `7eb8a1b94f6ab41e`는 Telegram·한글 mode 로 activate 됐다.
- 20:52:07.931, 이 controller 가 `composing=true`, `localMarkPlan=1`, `markAttempt=1`, `markReturn=1`인 상태로 deactivate 됐다.
  반환 때 composing 은 false 였다. mark 호출이 반환됐다는 사실은 Telegram 이 글자를 보존했다는 증거가 아니다.
- 2ms 뒤 다른 Telegram controller `2cb7206614952704`가 한글 mode 로 activate 됐다.
  이 controller 는 이전 mark 이력 `107`이 있었고 20:52:14.760에는 `111`이었다.
- 이 구간에 받은 source 알림은 homi selected=true 였다. 발생 시각과 아직 대응시키지 못했으므로
  **이 controller 교체가 `당 → ㅏㅇ`의 원인이었다고 판단하지 않는다.**

다음 관측은 첫 key 의 IMK 도착·modifier·app ID 출처·mode·handled 와 controller 전환,
첫 mark·commit 의 대상과 다음 key 의 조합 상태를 함께 본다. 지금 log 는 첫 key 를 식별하거나 client 에 글자가 남았는지 확인할 수 없다.
기존 Enter resend 는 이 일반 문자 경로에 적용되지 않으며, 제품 코드·설치본은 바꾸지 않았다.

근거: 주인 답변, Info.plist·현재 설정, homi unified log. 로컬 합성 검사 7개 조건은 모두 예상대로 통과했다.
도구·결과는 `build/TelegramInitialLossModel.swift`·`build/telegram-initial-loss-model.log`, 입력 내용 없는 metadata 는
`build/telegram-initial-loss-20261030.log`에 둔다. 이 검사는 실제 결함의 재현 test 나 교정 완료의 증거가 아니다.

### 자동 복원 해제 뒤 재발 (2026-10-31)

주인은 system 의 문서별 source 자동 복원을 끈 뒤에도 **⌘Tab 으로 Telegram 에 돌아와 Caps Lock 없이 처음 입력할 때 초성이 빠졌다**고 보고했다.
`이 → ㅣ`였던 듯하나 `서`였는지 확신하지 못했다. 정확한 문자열은 미확정이며, 전날의 `당 → ㅏㅇ` 보고와 구분한다.

- 05:22 KST 조사에서 자동 복원 저장값은 false, 현재 source 는 homi, process 는 기존 PID `85292`였다.
  [설정 해제](../macos-input.md#문서별-input-source-복원-재확인-2026-10-31)만으로 초성 누락은 해결되지 않았다.
- 주변 log 에서 05:21:27.946, controller `7eb8a1b94f6ab41e`가 한글 mode 로 준비됐다.
  05:21:32.504 deactivate 때 mark 계획·호출·반환 횟수는 각각 `1 → 2`로 늘었고 조합 중이었다.
  2ms 뒤 다른 Telegram controller `4138dcb0b8b504f0`가 한글 mode 로 준비됐다. 이 구간의 source 알림은 homi selected=true 였다.
  정확한 실패 시각·첫 key 와의 대응은 없으므로, 이 교체를 누락 원인으로 보거나 알림 사이의 source 상태까지 보장하지 않는다.
  metadata 는 `build/telegram-first-key-20261031.log`에 보관했다.
- **⌘Tab 에 따른 코드 확인**: `KeyEvent(NSEvent)`는 각 event 의 `modifierFlags`를 읽는다.
  이전 `flagsChanged`의 Command 상태를 일반 문자 key 에 덧붙이지 않는다. 따라서 homi 가 Command release 알림을 놓쳤다는 가정만으로
  첫 문자가 단축키로 처리되는 것은 아니다. 실제 첫 event 에 Command 가 붙었다면 `Session`은 app 으로 넘기지만,
  그 event 의 도착·modifier·app 의 소비 여부는 아직 관측하지 못했다.

다음 관측은 **Command release → 첫 key 의 modifier·handled → mark·controller 전환**을 연결해야 한다.
현재 lifecycle log 만으로는 첫 key 가 IMK 에 오지 않은 경우와, 도착 후 통과·조합한 경우를 가를 수 없다.
입력 문자·일반 key code 를 지속 기록하지 않고 이 경계의 metadata 를 관찰한다. 이번에는 문서만 갱신했고 제품 코드·설치본은 유지했다.

## Caps Lock 비교 진단 (2026-10-29)

13:25–13:28 KST, 설치된 Telegram 13.1.0 (283357)·macOS 27.2 에서 기존 판정을 유지한 진단본으로 8쌍을 관측했다.
각 press·release 는 IMK 에 한 번씩 왔고, 기존 판정·gesture 후보가 모두 전환으로 인정했으며 실제 mode 변경도 8회였다.
[연결 방식의 관측](../macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29)이며,
Caps 를 누르지 않은 복귀 후 첫 key 문제나 조합·전송 전체를 검증한 결과는 아니다.

## homi 의 우회

- 조합 중 Return·keypad Enter 는 확정하고 먹은 뒤 새 event 로 다시 보낸다. 두 번째 Enter 가 도착할 때는 marked text 가 없어 전송된다
  (`AppRules` 의 `resendWhileComposing`, `Resend`, `c08572b`). 손쉬운 사용 허가가 필요하다.

## 확인하는 법

- 한글을 조합하다 Enter → 한 번에 전송된다.
- `나는한자` + ⌥↩ → `한자` 에만 밑줄 → 漢字 로 바뀐다. ⌥↩ 를 한 번 더 누르면 `자` 로 짧아진다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-10-31 | 조사 시 설치본 13.1.0 | 문서별 source 자동 복원 해제 후에도 ⌘Tab·Caps 없이 첫 초성 누락 보고. 정확한 음절은 불확실. 각 key 의 modifier 를 직접 읽는 경로와 주변 controller 교체 기록을 확인했으나 실패 event 와의 대응은 미확인 |
| 2026-10-30 | 조사 시 설치본 13.1.0 | Caps 없이 창 전환 직후 `당 → ㅏㅇ` 보고. 합성 조건 7개를 비교하고 조합 중 controller 교체 metadata 확보. 실제 실패 순간과의 대응은 미확인 |
| 2026-10-29 | 조사 시 설치본 13.1.0 | 창 전환 뒤 Caps 없이 첫 key 만 영문이라는 주인 보고. 실제 event 미확보, activation·app 식별 경계의 model 검토 |
| 2026-09-25 | 12.9 | 조합 중 Enter 다시 보내기 — 복사본은 닿지 않아 새 event 로 (`c08572b`) |
| 2026-09-25 | 12.9 | Apple 방식 한자 확인 (`c884edd`) |
