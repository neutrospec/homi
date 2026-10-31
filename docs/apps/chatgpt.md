# ChatGPT

| | |
|---|---|
| 조사한 설치본 | `/Applications/ChatGPT.app` · 26.1027.30824 (22943) · macOS 27.2 · 2026-10-31 |
| bundle ID | `com.openai.codex` — 현재 설치본의 Info.plist·homi log 에서 확인 |
| framework | `Codex Framework.framework` 156.0.8078.48 · `Codex (Renderer).app` 등 포함. 입력 구현은 별도 미검증 |
| homi 규칙 | app 전용 우회 없음. 조사 때 영문 시작·입력 통과·ESC 영문 목록에 없었고 전환 key 는 Caps Lock |

## 복귀 뒤 source 전환 지연 보고 (2026-10-31, 미해결)

주인은 **11:56 전후** ChatGPT 로 전환한 뒤 다음 순서를 보고했다. 보고 때는 정상으로 돌아온 상태였다.

1. ABC 로 바뀌어 있었다.
2. `⌃Space`를 눌러도 전환 UI 가 나타나지 않았다.
3. 조금 뒤 input source 이름이 있는 popup 이 나타났고 변경되는 듯했으나 한 번 실패했다.
4. 더 지나서는 **같은 `⌃Space`**에 커서 옆 icon 으로 전환이 보였다. 2번과 다른 양상이었다.
5. 현재 정상이다.

후속 답변으로 발생 구간과 4번의 key 를 확인했다. 각 단계의 정확한 시각·실제 선택된 TIS source 는 아직 대응시키지 못했다.
Orca 의 menu 항목 누락과 달리 **이번에는 전환 UI 의 무응답·지연 보고**다. 목록에서 homi 가 사라졌다고 확대하지 않는다.
커서 옆 표시만으로 homi 의 `한/A` HUD 라고 판단하지 않는다. [system 도 커서 옆 source 표시를 제공](../macos-input.md#system-source-전환-ui-와-homi-표시-2026-10-31)한다.

**남아 있는 metadata**: 11:59 KST 에 45분 구간을 요청했지만 homi log 에서 확보된 event 는 11:53:24 이후뿐이다.
이전 구간에 log 가 없다는 사실을 event 가 없었다는 증거로 쓰지 않는다.

- 11:56:20.581 과 25.899, `com.openai.codex`에 한글 mode 로 준비·activate 했고 주변 source 알림은 homi selected=true 였다.
- 11:56:27.115 modifier tap 으로 내부 mode 가 english, 28.136 에 korean 으로 바뀌었다.
  이 내부 mode log 를 `⌃Space`로 본 2–4번의 source 전환 표시와 동일시하지 않는다. 각 조작과의 대응·HUD 표시 완료는 미확인이다.
- TextInputMenuAgent 에는 11:20:21.166 `_InputSwitcherStart`와 remote port 생성 실패 메시지가 남았다.
  주인이 확인한 발생 구간과 다르므로 **이번 증상의 원인 증거에서 제외**한다.
- 조사 시점의 source 는 homi, 문서별 source 자동 복원 저장값은 false, homi 는 기존 PID `85292`였다.
  ChatGPT PID `21216`의 시작은 11:14:50 이다. 이는 회복 뒤 snapshot 이며 실패 당시 상태를 보장하지 않는다.

같은 `⌃Space`에 무표시 → 이름 popup → 커서 옆 표시가 보고됐으므로 Caps Lock 과의 단순 UI 차이로 설명하지 않는다.
activation·한글 mode 준비 log 만으로 source 전환의 성공이나 입력칸 연결 완료를 판정하지 않는다.
다음 관측은 실제 source 선택·유지 여부와 전환 UI 표시를 나누고, `⌃Space`의 누름·뗌 시각 및 focus 를 함께 본다.
[다른 OS version 의 Control+Space 되돌림 보고](../macos-input.md#system-source-전환-ui-와-homi-표시-2026-10-31)는 비교 후보이며 이번 재현은 아니다.
입력 내용 없는 발췌는 `build/chatgpt-availability-20261031-1159.log`·`build/chatgpt-input-menu-20261031-1159.log`에 있다.

## 별도 code review: renderer helper 이름 판별

`623adcb`의 `Chromium.hasRenderer`는 ` Helper (Renderer).app` 접미사만 찾는다. 현재 bundle 에는
`Codex (Renderer).app`·`Codex (Aperitif Renderer).app`가 있으므로 이 판별식에는 맞지 않는다.
2026-10-31 후속 review 에서는 **제품의 `Sources/homi/Chromium.swift` 자체**를 별도 실행 파일에 compile 해
`Chromium.hosts`를 호출했다. 결과는 `com.openai.codex=false`, 대조한 Chrome·Orca 는 각각 true 였다.
검사 source 는 `build/ChromiumReview20261031.swift`다. 실제 bundle 을 읽은 판별 결과이며,
실행 중 homi 의 app별 판별 cache 값이나 이 app 의 IMK commit 동작을 직접 조회한 것은 아니다.

이 분기는 `commitComposition`의 Chromium 정책을 고르는 데 쓰인다. **source 전환 popup 지연의 원인으로 확인한 것은 아니다.**
helper 이름만 넓혀 기존 commit 우회를 적용하면 조합 종료 동작도 달라지므로, 이 app 의 click·focus·source 전환 callback 과
중복·유실 여부를 먼저 확인한다. 이번 조사에서는 제품 코드·설치본을 바꾸지 않았다.
