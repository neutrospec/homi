# AppKit `NSTextView` — 기준

macOS 의 text 엔진이다. `NSTextInputClient` 의 기준 구현이라 다른 엔진을 볼 때 비교 기준이 된다.

| | |
|---|---|
| app | TextEdit, Telegram(입력칸), probe (`tools/probe`) |
| 확인한 환경 | macOS 27.0 (26A428) · 2026-09-25 |

## 특징

- **입력기에 알리는 marked text attribute** (`validAttributesForMarkedText`):
  `NSFont` `NSUnderline` `NSColor` `NSBackgroundColor` `NSUnderlineColor` `NSMarkedClauseSegment` `NSLanguage`
  `NSTextInputReplacementRangeAttributeName` `NSGlyphInfo` `NSTextAlternatives` `NSTextInsertionUndoable` `NSAttachment`
  (field editor 는 `NSGlyphInfo`·`NSAttachment` 가 빠진다).
  `macOS 27.0 · 2026-09-25 · 실험` ✅
- **교체 범위(`replacementRange`)를 문서 위치 그대로 받는다** — 확정한 글자를 marked text 로 되돌려 바꾸는 Apple 방식 한자가 맞게 된다.
  `TextEdit 1.21, Telegram 12.9 · 2026-09-25 · 주인` ✅
- **입력기가 보낸 marked text 안의 선택 `{글자 수, 0}` 이 app 에는 `{0, 글자 수}` 로 왔다** — IMK 가 중간에서 바꾼 것으로 보인다. 화면에 드러난 문제는 없다.
  `macOS 27.0 · 2026-09-25 · probe run 3` 🔶
- **Apple 두벌식은 이 엔진에서 marked text 없이 확정한 뒤 `insertText(replacementRange:)` 로 바꿔치기한다** — homi 가 피하는 방식이다 (결정 5).
  `macOS 27.0 · 2026-09-25 · probe run 1` ✅

## homi 의 우회

- 없다. 이 엔진이 기준이다.
- Apple 방식 한자는 client 가 이 엔진 수준(교체 범위 + `NSTextAlternatives`)을 알릴 때만 쓴다 (`Client.replacesLikeTextView`, `c884edd`).

## 확인하는 법

- `validAttributesForMarkedText` 목록 — Apple 방식 한자의 판별이 여기에 기댄다.
  `swift` script 로 `NSTextView` 를 만들어 `validAttributesForMarkedText()` 를 출력해 본다.
- TextEdit 에서 `나는한자` + ⌥↩ → `한자` 에만 밑줄 → 漢字.

## 기록

### 세 경계 교정본의 probe 확인 (2026-10-31)

macOS **27.2 (26B123)**, `local.hangul.probe` 0, homi **15:23 설치본**에서 주인이 실제 keyboard 로
`한글` 조합·Backspace·`ㄹ` 복원, `한`의 ⌥Enter 후보 열기·↓·Enter 선택, 조합 중 다른 app 왕복을 정상 확인했다.
최종 `한글 漢 한글`은 AX 로도 읽었다. probe controller 는 새 process `70357-C287E948-A404-4D4F-9EE9-9A667EBD83DC/3`이다.
근거: 주인 보고, probe AX, `build/remaining-boundaries-runtime-20261031.log`.
이 시험은 AppKit 의 기본 경로를 확인한다. insert 중 client 자체 확정 callback 이나 busy 중 후보 Task 의 실제 발생을 재현한 것은 아니다.

### probe 의 후보 UI 검증 (2026-10-31)

macOS **27.2 (26B123)**, `local.hangul.probe` 0, homi **14:41 설치본**에서 실제 keyboard 로 확인했다.
주인은 기본 `한글` 조합·Backspace·`ㄹ` 복원, `한`의 ⌥Enter 후보 표시·↓ 선택·Enter 확정이 정상이라고 보고했다.
후보를 연 채 ⌘Tab 으로 다른 app 에 갔다가 돌아와 이어 입력하는 시험도 정상으로 보고했다(요청한 최종값 `한글 漢 한글`).
도구가 최종 문자열 전체를 다시 확인한 것은 아니다. 내용 없는 homi trace 에서는 probe controller 의 14:44:23 deactivate 전
`composing=true,candidates=true`가 종료 뒤 둘 다 false 로 바뀌고, 14:44:25 재활성화되는 것을 확인했다.
근거: 주인 보고, `build/candidate-revision-runtime-20261031.log`. 자동 Task 순서 test 와 실제 AppKit 입력 검증은 구분한다.
다른 AppKit app 전체의 통과를 뜻하지 않는다.

### 후보 뜻의 첫 표시 누락 보고 (2026-10-31, 미해결)

같은 시험에서 주인은 **첫 목록에는 첫 후보 뒤의 한글 설명이 없었지만, 두 번째 `한` 목록에는 설명이 있었다**고 보고했다.
첫 목록도 `한` 한 글자의 후보였음을 추가 확인했다. 누락 화면은 도구로 확보하지 못했다.
`hanja.txt`의 `한` 첫 9개 후보는 모두 뜻이 있고, 설치 resource 와 repository 원본의 SHA-256 도 같다
(`b1004034589f1357daaea3534a6136f6b5ef825afa8779886b20f0b7908bbe3b`). 단어 후보의 빈 뜻으로 설명할 수 없다.
후보 데이터의 `meaning`을 label 에 넘기는 코드와 panel layout 은 이번 revision 분리에서 바꾸지 않았다. 회귀 여부·원인은 미확정이다.
주인 결정(2026-10-31): 문제가 다시 나타날 때 살펴본다. 그때 첫 show·다음 show 의 후보 데이터와 각 label 의 frame·가시성을 대조한다.
fake panel test 는 실제 AppKit rendering 을 검증하지 않는다.

| 날짜 | 환경 | 내용 |
|---|---|---|
| 2026-09-25 | macOS 27.0 | attribute 목록을 확인하고 Apple 방식 한자의 판별 기준으로 삼음 (`c884edd`) |
