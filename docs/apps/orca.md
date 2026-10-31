# Orca

| | |
|---|---|
| bundle ID | `com.stablyai.orca` |
| 엔진 | Chromium (Electron) → [engines/chromium.md](engines/chromium.md) |
| 확인한 version | 한자: 1.4.210 · 2026-09-25 · macOS 27.0. Caps Lock: 1.4.239 · 2026-10-29 · macOS 27.2 |
| 최근 조사 환경 | 설치 bundle 1.4.244 · Electron 43.8.1 · macOS 27.2 · 2026-10-31 |
| homi 규칙 | — |

## 특징

- **확정한 단어를 marked text 로 되돌리면 `나는한자漢字`** 가 된다 — VS Code 와 같다. Apple 방식 한자는 쓰지 않는다.
  `1.4.210 · 2026-09-25 · 주인` ✅

## homi 의 우회

- Chromium 규칙 (`7e4c1fd`).

## input menu 의 homi 누락 보고와 회복 (2026-10-31, 미해결)

**주인이 정정해 확정한 순서**: 웹 browser 에서 ⌘Tab 으로 Orca 에 돌아오자 homi 가 보이지 않아 보고했다.
그 창에서 기다리다가 다시 선택할 수 있었다. **회복하려고 다른 app 을 다녀온 것이 아니다.**
주인은 menu 를 잘못 보았을 가능성도 배제하지 말라고 했다. 입력칸의 실제 focus 와 menu 표시 조건을 함께 조사한다.

| 관측 | 보고 직후 08:48–08:50 KST | 회복 보고 뒤 08:51:52–53 KST |
|---|---|---|
| frontmost app | Orca (`com.stablyai.orca`) | Orca |
| 현재 TIS source | ABC | homi 한국어 mode |
| homi parent·mode | 모두 enabled | 모두 enabled |
| Secure Event Input | false (08:48:45) | false |
| process | homi `85292` · Orca `5860` · TextInputMenuAgent `10398` | 모두 같은 PID·시작 시각 |

문서별 source 자동 복원 저장값도 false 였다. 설치본 CDHash 는 `39e0a7603bf12ded5c6f648ee98e323780144eed`로 유지됐다.
agent 는 input source 선택·focus 이동·설정 변경·재등록·process 재시작·재설치를 하지 않았다.

**menu 관측과 한계**: TextInputMenuAgent 의 status menu 접근성 조회에는 `ABC, enabled=true` 한 항목만 나왔다.
주인 보고를 뒷받침하는 별도 관측이지만, screenshot 으로 화면 전체를 검증하거나 그 조회가 모든 표시 항목을 포함한다고 확인한 것은 아니다.
회복 뒤 같은 조회에는 항목이 없었다. menu 개폐·갱신 상태에 따라 조회 결과도 달라질 수 있으므로 빈 결과를 새 누락으로 세지 않는다.
Orca 의 focused element 조회는 실패했고, homi 선택이 확인된 08:53:39 에도 같은 AX error `-25204`였다.
이 error 자체를 실패 당시 focus 상실의 증거로 쓰지 않는다.

**회복 주변 source 전이**: 08:51:09–08:53:09 동안 외부 `tis watch`와 homi log 를 비교했다.

- 08:51:10.425 외부 조회는 homi, 10.448 은 ABC 였다. homi 에도 activate·deactivate 와 selected true → false 가 남았다.
- 08:51:23 homi log 에는 잠깐 selected=true 뒤 false 가 남았지만, 외부 observer 가 알림을 처리할 때는 모두 ABC 였다.
  알림은 전환 때의 source ID 를 담은 이력이 아니라, callback 때 현재 source 를 다시 읽은 값이다.
- 08:51:31.280 이후 외부 조회와 homi log 모두 homi 선택을 확인했고, 이후 snapshot 도 homi 였다. 관찰 구간에 enabled 변경 알림은 없었다.

이 전이는 실제 상태 변화의 증거다. 다만 각 선택의 요청자·focus·menu 조작을 동시 관측하지 않아 자동 회복의 원인이나
정확한 회복 시작 시각으로 단정하지 않는다. 여러 controller log 에 같은 `aa59b8495d20600`이 나오지만,
mark 이력이 `3498 → none`으로 바뀌고 최초 event log 도 다시 나온다. 관측 당시 설치본의 `traceID`는 객체 identity 의 hash 이므로
**같은 표시값만으로 같은 controller 수명이 이어졌다고 판단하지 않는다.**

**판단**: 조사 때 등록과 process 는 살아 있었고 Secure Event Input 은 꺼져 있었다. 등록 소실·process crash 로 설명할 근거는 없다.
현재 창의 input context·허용 source·menu 갱신을 우선 조사하되, 보기 착오와 focus 에 따른 정상적인 제한도 열어둔다.
[해당 Chromium version 의 context·갱신 경로](engines/chromium.md#orca-설치-version-대조-2026-10-31)는 후보 기전이며 실제 실행 분기는 미확인이다.
homi 의 activation 중 layout 지정과 AppKit 의 상호작용까지 원인에서 제외한 것은 아니다. Telegram 의 첫 초성 누락과 같은 원인으로 합치지 않는다.

다음 재발에서는 같은 입력칸의 focus·menu 가 열린 상태의 항목 전체와 source·Secure Event Input 을 함께 확인한다.
관찰만으로 회복한 이번 사례를 교정 완료로 세거나 source 강제 선택·timer retry 의 근거로 쓰지 않는다.
관측 요약은 `build/input-availability-20261031-summary.json`, source 전이는 `build/input-availability-transition-20261031.log`,
회복 주변 lifecycle 은 `build/input-availability-recovered-20261031.log`에 있다. 입력 내용·일반 key code 는 수집하지 않았다.

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
| 2026-10-31 | 조사 시 bundle 1.4.244 | 웹에서 ⌘Tab 복귀 직후 homi 누락 보고 → 같은 창에서 기다린 뒤 회복. enabled·process 유지, Secure Event Input=false, 접근성 menu 의 ABC 한 항목과 source 왕복을 관측. focus·menu 조회 범위와 원인은 미확정 |
| 2026-09-25 | 1.4.210 | 확정한 단어의 재변환이 틀어짐 → Apple 방식 한자 안 씀 (`c884edd`) |
| 2026-10-29 | 1.4.239 | 물리·remap 신호가 도착한 Caps Lock 의 mode 전환 누락 관측. 원인 미확정, app 우회 추가 없음 |
