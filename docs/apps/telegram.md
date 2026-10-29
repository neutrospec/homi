# Telegram

| | |
|---|---|
| bundle ID | `ru.keepcoder.Telegram` |
| 엔진 | AppKit — 입력칸은 TelegramSwift `ChatInputTextView` 안의 `NSTextView` → [engines/appkit.md](engines/appkit.md) |
| 확인한 version | 12.9 (282526) · 2026-09-25 · macOS 27.0 |
| 최근 조사 환경 | 설치된 app 13.1.0 (283357) · 2026-10-29 · macOS 27.2 — 아래 첫 key 문제의 발생 당시 version 은 별도 미확인 |
| homi 규칙 | 조합 중 Return·keypad Enter 는 확정 → 먹고 → 다시 보낸다 |

## 특징

- **조합 중 Enter 는 전송이 아니라 줄바꿈이 된다** (Apple 입력기 때부터). Telegram 은 marked text 가 없고 수식키도 없을 때만 Enter 로 보낸다.
  조합 중이면 key 를 입력기에 넘기고, 입력기가 확정한 뒤 줄바꿈이 된다 — 일본어·중국어의 "Enter = 변환 확정" 관례다.
  `12.9 · 2026-09-25 · source(ChatInputTextView.keyDown, a404806) + 주인` ✅
- **다시 보낸 Enter 는 새 event 여야 닿는다** — 원래 event 의 복사본을 key 처리 도중에 보냈더니 "틱" 소리만 나고 사라졌다.
  `12.9 · 2026-09-25 · 주인 + 기록` ✅ (까닭 🔶 — docs/lessons.md)
- **Apple 방식 한자(방금 친 단어)가 된다** — `나는한자` + ⌥↩ 에 `한자` 에만 밑줄이 생긴다.
  `12.9 · 2026-09-25 · 주인` ✅
- Apple 두벌식에서 첫 초성이 사라진 적이 있다(`아` → `ㅏ`). homi 로는 재현되지 않았다.
  `12.9 · 2026-09-25 · 주인` 🔶

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
도착하지 않은 경로, 영문으로 통과시킨 경로, 한글 mark 를 보냈으나 client 반영이 어긋난 경로를 구분한다.
현재 원인이 특정되지 않았으므로 app 우회·모드 강제 reset·source 선택은 추가하지 않는다.

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
| 2026-10-29 | 조사 시 설치본 13.1.0 | 창 전환 뒤 Caps 없이 첫 key 만 영문이라는 주인 보고. 실제 event 미확보, activation·app 식별 경계의 model 검토 |
| 2026-09-25 | 12.9 | 조합 중 Enter 다시 보내기 — 복사본은 닿지 않아 새 event 로 (`c08572b`) |
| 2026-09-25 | 12.9 | Apple 방식 한자 확인 (`c884edd`) |
