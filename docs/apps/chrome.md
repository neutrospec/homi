# Chrome

| | |
|---|---|
| bundle ID | `com.google.Chrome` |
| 엔진 | Chromium → [engines/chromium.md](engines/chromium.md) |
| 확인한 version | 154.0.8037.98 · 2026-10-09 · macOS 27.0.1 (26A434) |
| homi 규칙 | — |

## 특징

- **확정한 단어를 marked text 로 되돌리는 것이 입력칸에 따라 됐다 안 됐다 했다.** 평범한 입력칸은 되고 JS editor 는 틀어지는 것으로 본다 🔶.
  Apple 방식 한자는 쓰지 않는다.
  `154.0.8037.57 · 2026-09-25 · 주인` ✅
- renderer helper 는 `Google Chrome Framework.framework/Versions/<version>/Helpers/` 에 있고 `Helpers` symlink 로 닿는다 — Chromium 판별이 여기에 기댄다.
  옛 version 의 폴더(153)도 남아 있다.
  `154.0.8037.57 · 2026-09-25 · 실험` ✅

## homi 의 우회

- Chromium 규칙 (`7e4c1fd`).

## 확인하는 법

- 조합 중 click → 음절이 한 번만 남는다.
- 일반 text field 와 rich text editor 를 각각 확인한다. `한` 조합 → input menu 의 ABC → homi → `글` 입력에서 `한글` 이 남아야 한다.
  전환 뒤 `한글` 두 음절 전체를 새로 입력하면 `한한글` 이 남아야 한다 — 한 음절만 입력한 결과와 구분한다.
  [browser probe](../../tools/probe/browser.html)는 기본 `input`·`textarea`·`contenteditable` 를 같은 페이지에서 비교한다.
- 조합 중인 글자·선택한 한글 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 154.0.8037.57 | 확정한 단어의 재변환이 입력칸마다 달랐다 → Apple 방식 한자 안 씀 (`c884edd`) |
| 2026-10-09 | 154.0.8037.98 | 주인: mouse 로 입력 위치 이동은 정상. 조합 중 input menu 로 ABC → homi 전환 후 바로 조합하면 이전 글자가 새 글자로 대체됨. callback 뒤 mark 확인으로 교정한 뒤 일반 text field 는 정상으로 보이지만 rich text editor 는 여전히 대체된다고 보고. 클리앙 본문은 전환 뒤 한 음절과 두 음절을 입력한 결과가 달랐다(아래). 남은 원인은 검증 중. ⌃Space 전환은 아직 확인하지 않음 |

### 클리앙 본문 · 2026-10-09

- 글쓰기 본문은 `.fr-element.fr-view[contenteditable=true]`. 로드한 asset 경로는 Froala `4.0.5`. ✅ (현재 tab DOM·script 경로만 조회, 입력 내용은 읽지 않음)
- 주인: `한` 조합 → mouse 로 ABC → homi → `글` 에서 `한글` 이 남은 회차를 확인. ✅
- 주인: 같은 전환 뒤 `한글` 두 음절 전체를 입력하면 앞의 `한` 이 유실·대체됨. `한한글` 이 남아야 하는 경로는 아직 실패한다. ✅
- 같은 관찰 구간에서 source 종료 때 page 의 `compositionend` 가 있는 회차와 없는 회차가 있었다.
  08:43:51.812 에 homi 는 `client marked: true` 로 종료를 처리했으나 page 의 `compositionend` 는 이때 기록되지 않았다.
  08:43:54 이후 조합 event 를 거쳐 08:43:55.281 에 기록됐다. ✅ (입력 내용 없는 lifecycle·DOM event 관찰)
- 09:09:33.907 에는 local 조합·client mark 가 모두 남았고 `insertText` 호출·반환까지 확인됐다.
  page 는 source 종료 때 `compositionend` 를 기록하지 않고, 복귀 뒤 새 `compositionstart` 없이 `compositionupdate` 를 받았다.
  `compositionend` 는 09:09:45.586 의 blur 때 기록됐다. ✅ (같은 방식의 관찰, 위의 두 음절 실패 실험 구간)
- 확정 호출과 page 조합 종료 사이를 더 가른다. 아직 Froala 의 결함이나 homi 의 해결 완료로 판정하지 않는다.

### 기본 입력칸 비교 · 2026-10-09

- 주인: browser probe 에서 `한` → ABC → homi → `글` 은 정상으로 보였다. 그러나 `글` 을 조합 중인 채 다음 입력칸을 click 하고
  `한` 을 치면 새 칸에 `글한` 이 들어갔다. ✅
- 같은 page 의 여러 DOM 입력칸은 IMK client 하나를 공유할 수 있다. `client()` 에 묶는 것만으로 이전 입력칸의 위치가 보존되지는 않는다.
  callback 뒤 다음 key 까지 미룬 확정은 이 이동 경로에서 안전하지 않다. Cocoa mark 답만으로 이전 입력칸의 가용성을 판단한 가정을 다시 검증한다.
- 09:40:29.754 에 이전 input 의 `compositionend`, 29.755 에 blur·다음 textarea 의 focus 가 기록됐다.
  다음 key 인 31.081 에 homi 가 `client marked: true` 로 이전 조합을 `insertText` 했고, 새 textarea 의 `compositionstart` 는 31.085 에 기록됐다. ✅
  textarea → plaintext-only, plaintext-only → rich text 에서도 같은 순서였다. 입력 내용 없는 lifecycle·DOM event 관찰이다.
- `{NSNotFound, NSNotFound}` 확정 range 실험을 설치한 뒤 주인: 첫 입력은 여전히 대체되고 다음 칸에는 `글` 이 따라와 상태가 더 나쁘다고 보고했다. ✅
  range 변경과 악화의 인과는 분리하지 못했다. 보류한 확정과 range 실험을 09:54 KST 설치본에서 되돌렸다.
  이후 source 전환 없는 `글` 조합 → 새 입력칸 click → `한` 확인을 요청했다. 후속 기본 입력 정상 보고는 [작업 기록](../lessons.md#2026-10-09-activation-교정callback-관측)에 있으며 이 경로의 개별 결과는 받지 않았다.
- 기본 입력칸에서도 source 전환 뒤 대체가 보고됐다. Froala 에만 있는 결함으로 좁힐 근거는 없다.

## 다음 작업

주인 결정(2026-10-09): 드문 다른 input source 왕복의 교정은 일상 입력을 악화시키면서까지 하지 않는다. [개선 검토](../stability-review.md)의 기본 경로가 먼저다.
activation 교정본에서도 source 전환 없는 입력칸 이동을 확인한다. 아래 source 왕복 표는 후속 검증 기준으로 보존한다.
homi 를 한글 모드로 두고 다음 표를 새 빈자리에서 별개로 실행하고,
전환 실험 사이에는 입력칸을 다시 click 하지 않는다. 지금까지의 긍정·부정 관측은 위 기록에 있고, 이 표는 다음 확인의 기준이다.

| 경로 | 기대 결과 | 다음 확인 |
|---|---|---|
| ABC 전환 없이 `글` 조합 → 빈 다른 칸 click → `한` 입력 | 옛 칸 `글`, 새 칸 `한` | activation 교정본의 기본 입력 확인 |
| `한` 조합 → mouse ABC → mouse homi → 새 `글` 한 음절 | `한글` | 한 음절 결과만으로 교정 완료라 하지 않음 |
| `한` 조합 → mouse ABC → mouse homi → 새 `한글` 두 음절 전체 | `한한글` | 일반 input·rich contenteditable 을 각각 확인 |
| 같은 source 전환을 ⌃Space 로 | 위와 동일 | mouse 경로와 분리, 아직 확인하지 않음 |

source 왕복 조사를 다시 시작할 때에는 입력기 호출과 page 조합 종료 사이를 가른다. 입력 내용 없이 controller ID·TIS 선택·callback 순서와
DOM `compositionstart/update/end`·focus/blur 의 시각을 함께 관찰한다. `insertText` 반환을 page 의 확정 완료로 세지 않는다.
추가한 [client 호출 단계](../macos-input.md#client-호출-단계의-관측)는 다음 mark 의 계획과 이전 mark 호출 반환을 가르지만 callback 의 확정 대상을 증명하지 않는다.
event 의 `isTrusted` 값만으로 editor 나 extension 을 원인으로 지목하지 않는다.
필요하면 마지막 mark 를 받은 proxy·bound client·callback sender 가 같은 object 인지 진단 정보를 더한다.
이는 호출 대상을 비교하는 관측이며 DOM 입력칸의 소유권 증명은 아니다. 확인 없이 callback sender 로 확정 대상을 바꾸지 않는다.
⌃Space 실험은 현재 단축키 설정부터 확인하고, system 설정을 임의로 바꾸지 않는다.

- [browser probe](../../tools/probe/browser.html)를 Chrome 에 열면 기본 `input`·`textarea`·plain/rich `contenteditable` 을 비교할 수 있다.
  일반 page 에 JS keyboard event 를 보내는 검사는 native IMK 경로를 대신하지 못한다.
- [browser-trace.js](../../tools/probe/browser-trace.js)는 비교 page 또는 클리앙 글쓰기의 event·상태만 관찰한다.
  클리앙 확인 위치는 `https://www.clien.net/service/board/regist?boardCd=park` 이며 로그인이 필요하다.
  script 는 DevTools 에서 실행하거나 Chrome AppleScript 의 `execute … javascript` 로 평가한다.
  `window.__homiImeTrace.read()`·`.clear()` 로 조회·초기화하고, 끝나면 반드시 `.stop()` 한다. 최대 240건을 memory 에만 보관한다.
  입력 값·event.data·key code·HTML 은 읽거나 저장하지 않는다. AppleScript 의 실행 환경에서는 Froala global 이 안 보였으므로 version 은 asset 경로로만 확인했다.
- 이번 작업에서 주인이 Chrome Automation 권한과 **Allow JavaScript from Apple Events** 를 허용했다.
  임시 observer 와 `/usr/bin/log stream` 은 마감 때 종료했다. 다음 관찰은 다시 시작해야 한다.

TIS 선택·늦은 mark 답·client identity 만으로 종료 원인이나 이전 입력칸의 소유권을 판단하는 접근은 실패했다.
`composedString` 누락·Froala·extension·off-event 전달 실패는 원인으로 확정하지 않았다.
일반 입력칸에서도 실패하므로 클리앙 draft 를 읽거나 editor 우회를 먼저 추가할 근거는 없다.
