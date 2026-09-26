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

| 날짜 | 환경 | 내용 |
|---|---|---|
| 2026-09-25 | macOS 27.0 | attribute 목록을 확인하고 Apple 방식 한자의 판별 기준으로 삼음 (`c884edd`) |
