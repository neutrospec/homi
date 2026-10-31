# T3 Code

| | |
|---|---|
| bundle ID | `com.t3tools.t3code` |
| 엔진 | Electron 44.9.3 → [Chromium](engines/chromium.md) |
| 확인한 version | T3 Code (Beta) 0.1.3 · macOS 27.2 (26B123) · 2026-10-30 |
| homi 규칙 | Chromium 공통 경로. app 전용 우회 없음 |

## input menu 에서 homi 누락 (2026-10-30, 미해결)

**주인 관측**: AI 에 메시지를 쓰는 입력칸에서 homi 를 선택하려 했으나 input menu 에 **항목 자체가 없었다**.
흐린 항목을 누르지 못한 경우와 구분한다. app 을 다시 방문한 뒤에는 선택할 수 있었다.

**확보한 증거**:

- homi 는 전날 20:19:33 KST 부터 같은 PID `85292`로 실행 중이었다. 설치본 CDHash
  `39e0a7603bf12ded5c6f648ee98e323780144eed`는 [Emacs 옵션본](emacs.md#caps-lock-전달-2026-10-29)과 같다.
  이 구간에 process 재실행으로 회복한 것은 아니다.
- homi lifecycle log 에서 T3 의 같은 controller 표시 ID `14e507fd10d49ff7`에 다음 순서가 남았다.
  입력 글자·일반 key code 는 수집하지 않았다.

| 시각 (KST) | 관찰 |
|---|---|
| 07:44:38.613 | T3 activate → 즉시 deactivate → `homi selected: false` |
| 07:45:39.248 | T3 activate → 즉시 deactivate → `homi selected: false` |
| 07:45:42.225 | Orca activate → `homi selected: true` |
| 07:45:46.337 | T3 activate → `homi selected: false` → deactivate |
| 07:45:49.155 | 같은 표시 ID 의 T3 controller activate → `homi selected: true` |

- 최초 상태 조회를 시작했을 때는 이미 마지막 회복 뒤였다. 07:46:55 의 TIS 조회에서는 homi parent·한국어 mode 가 enabled,
  한국어 mode 가 selected, 하위 layout 은 ABC 였다. **실패 순간에도 등록이 유지됐다는 증명은 아니다.**
- 관측 당시 설치본의 controller 표시 ID 는 객체 identity 의 hash 이므로 수명 간 유일성을 보장하지 않는다.
  [후속 Orca 관측](orca.md#input-menu-의-homi-누락-보고와-회복-2026-10-31-미해결)에 따라 같은 ID 만으로 instance 재사용·교체를 확정하지 않는다.
- 회복 뒤 main thread 의 `IsSecureEventInputEnabled()`는 false 였다. 실패 순간의 보안 입력·허용 source 목록은 미관측이다.
- 저장 설정에서 T3 는 pass-through·영문 시작 목록에 없다. 제품 코드에는 T3 전용 규칙이나 input source 를 disable/remove 하는 호출이 없다.
  단, `activateServer`의 하위 layout 지정 등 IMK 와 homi 의 상호작용까지 원인에서 제외한 것은 아니다.
- 07:40:56 의 `imklaunchagent`에는 `InputMethodConnectionName` 거절과 endpoint invalid log 가 있다.
  대상 bundle ID 는 private 이고, 뒤의 endpoint 요청 PID `1315`는 Ghostty 였다. 이를 T3·homi 의 연결 실패 증거로 단정하지 않는다.

**현재 판단**: T3 를 방문할 때 input source 의 활성 상태가 유지되지 않는 경로가 우선 조사 대상이다.
회복 후 등록 정상·process 생존만으로 homi 의 결함을 배제하지 않는다. 목록의 누락을 직접 관찰하거나 그 원인을 확인한 것은 아니다.
입력칸의 편집 가능 상태·입력 context·허용 source 제한과 input menu 갱신을 함께 봐야 한다.
[Chromium 의 context·source 제한 코드](engines/chromium.md#입력-context-와-source-제한-2026-10-30)는 후보 기전이며 이번 발생의 증거와 다르다.
2026-10-31 에 [system 의 문서별 source 자동 복원을 해제](../macos-input.md#문서별-input-source-복원-재확인-2026-10-31)했다.
창별 source 복귀를 설명하는 설정이지만 menu 항목 누락의 원인으로 확인한 것은 아니다.

다음 재발은 [공통 상태 관측](../macos-input.md#input-menu-의-비활성누락-2026-10-09-미해결)을 app 이동 전에 확보한다.
특히 menu 에 ABC 만 남는지, 다른 CJK 입력기도 함께 없어지는지와 Secure Event Input 의 동시 상태가 필요하다.
그 뒤에야 T3 입력칸의 focus·type·flags 또는 IMK 연결을 좁혀 관찰한다. input source 강제 선택·재등록·설치 변경으로 우회하지 않는다.

근거: 주인 답변, 설치 bundle 의 Info.plist·codesign, `ps`, `tis`, homi unified log.
입력 내용 없는 lifecycle 발췌는 로컬 `build/t3-input-availability-20261030.log`에 보관했다.
