# TextEdit

| | |
|---|---|
| bundle ID | `com.apple.TextEdit` |
| 엔진 | AppKit `NSTextView` → [engines/appkit.md](engines/appkit.md) |
| 확인한 version | 1.21 (419) · 2026-09-25 · macOS 27.0 |
| homi 규칙 | — |

## 특징

- **Apple 방식 한자(방금 친 단어)가 된다** — `나는한자` + ⌥↩ 에 `한자` 에만 밑줄이 생긴다.
  `1.21 · 2026-09-25 · 주인` ✅
- 엔진의 기준이 되는 app 이다. 다른 app 에서 이상하면 여기서 먼저 비교해 본다.

## homi 의 우회

- 없다.

## 확인하는 법

- `나는한자` + ⌥↩ → 漢字. 선택한 한글 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 1.21 | Apple 방식 한자 확인 (`c884edd`) |
