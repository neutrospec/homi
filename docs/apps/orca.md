# Orca

| | |
|---|---|
| bundle ID | `com.stablyai.orca` |
| 엔진 | Chromium (Electron) → [engines/chromium.md](engines/chromium.md) |
| 확인한 version | 한자: 1.4.210 · 2026-09-25 · macOS 27.0. Caps Lock: 1.4.239 · 2026-10-29 · macOS 27.2 |
| homi 규칙 | — |

## 특징

- **확정한 단어를 marked text 로 되돌리면 `나는한자漢字`** 가 된다 — VS Code 와 같다. Apple 방식 한자는 쓰지 않는다.
  `1.4.210 · 2026-09-25 · 주인` ✅

## homi 의 우회

- Chromium 규칙 (`7e4c1fd`).

## Caps Lock 누락 관측 (2026-10-29)

주인과 읽기 전용 관찰기로 PN06 의 물리 HID Caps Lock, Quartz 오른쪽 Control, homi 의 mode log 를 대조했다.
기존 설치본을 그대로 사용했으며 글자 내용·일반 key code 는 수집하지 않았다.

| 구간 | 물리 누름·뗌 | Quartz 누름·뗌 | 모드 변경 |
|---|---|---|---|
| 첫 입력 비교 | 34쌍 | 34쌍 | 32번 |
| release 뒤 기다리는 입력을 포함한 비교 | 34쌍 | 34쌍 | 32번 |
| Caps Lock 단독 구간 | 24쌍 | 24쌍 | 24번 |
| 입력을 섞은 후속 구간 | 31쌍 | 31쌍 | 26번 |

누락과 외부 관찰기의 counter 변화가 함께 나타났다. 이 결과만으로 Orca 의 결함이라고 판단하지 않는다.
counter 조회와 관찰기의 부하, 시간 단위의 제한, 원인 가설과 다음 검증은 [macOS 구조](../macos-input.md#caps-lock-전환-누락-관측-2026-10-29)에 둔다.

후속 비교 진단에서는 하나의 Quartz press·release 에 각각 두 IMK callback 이 들어오는 경우를 확인했다.
각 callback 의 timestamp 도 달랐다. [공통 전달 구조의 관측](../macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29)이며,
중복 자체를 Orca 의 결함이나 이번 누락의 원인으로 확정하지 않는다.

### 기존 판정과 gesture 후보의 동시 비교 (2026-10-29 13:20 KST)

Orca 1.4.239·macOS 27.2 (`26B123`), 진단본 CDHash `c88f80e2defabf06d07a189380ce1159eea91b99`.
주인이 Caps 단독 및 입력을 섞은 시험 뒤 누락이 다시 느껴졌다고 보고했다.

| 관측 항목 | 결과 |
|---|---|
| 연결한 Quartz Caps press·release | 29쌍 |
| IMK callback | press 58회·release 58회 — 각 물리 event 에 두 번 |
| 기존 코드의 전환 action / 실제 mode 변경 | 25 / 25회 |
| 새 후보의 전환 action (실행하지 않은 비교 결과) | 29회 |
| 기존 코드만 거부한 release | 4회 — 13:20:34.774, 39.741, 40.306, 43.832 |

4회 모두 같은 context·controller 에서 관찰한 press·release 의 활동 번호가 같았다. 즉 관찰 mask 의 keyDown·mouse·scroll·다른 modifier 가
물리 누름·뗌 사이에 없었는데 기존 코드는 전환을 거부했다. 관찰 범위에서 정상 tap 의 거짓 거부를 직접 포착한 결과다.
이 진단본은 실제 mode 변경에 기존 판정을 썼으므로, 29개의 새 action 을 **실제 입력 성공 29회로 세지 않는다**.
입력 내용을 제외한 집계는 `build/modifier-shadow-summary-20261029.json` 에 있다. app 전용 우회는 추가하지 않았다.

### 교정본의 실제 사용 (2026-10-29 13:35 KST)

CDHash `686f2190b15963148e871777aee4a950064266f7`에서 짧은 전환 action 34회·실제 mode 변경 34회를 관측했다.
주인은 입력을 섞은 반복 시험 뒤 “정말로 사라졌어”라고 누락 개선을 확인했다. 짧은 전환의 재현 시험을 통과한 결과이며 일상 사용은 계속 확인한다.

같은 구간의 긴 누름 4회는 전부 release 에서 `capsLock` action 을 냈다. 누르는 동안의 `modifier hold` 기록은 없었다.
따라서 **누른 채 0.5초 뒤 대문자 고정**까지 통과한 것으로 세지 않았다. 교정본의 hold 경계를 따로 확인한다.
집계는 `build/modifier-installed-summary-20261029.json` 이며 일반 입력 내용은 포함하지 않는다.

13:48 KST 에 보완본(CDHash `cd0baf2767e62f15aceca5a9ad877522ff270b1b`)으로 긴 누름 4회를 확인했다.
각각 press callback 약 0.52초 뒤, release 전에 hold action 을 한 번씩 실행했고 release 에서는 재실행하지 않았다.
주인도 누른 채 대문자 고정이 켜지고 꺼지는 동작을 확인했다. 집계는 `build/modifier-hold-summary-20261029.json`.
긴 누름 당시 직접 key 상태 조회와 관찰이 달랐던 사실은 [공통 구조](../macos-input.md#quartz-와-imk-사이-modifier-event-의-연결-2026-10-29)에 둔다.

## 확인하는 법

- 조합 중 click → 음절이 한 번만 남는다.
- 조합 중인 글자 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 1.4.210 | 확정한 단어의 재변환이 틀어짐 → Apple 방식 한자 안 씀 (`c884edd`) |
| 2026-10-29 | 1.4.239 | 물리·remap 신호가 도착한 Caps Lock 의 mode 전환 누락 관측. 원인 미확정, app 우회 추가 없음 |
