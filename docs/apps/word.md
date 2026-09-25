# Word

| | |
|---|---|
| bundle ID | `com.microsoft.Word` |
| 엔진 | Microsoft Office → [engines/office.md](engines/office.md) |
| 확인한 version | 16.113.2 (16.113.26092012) · 2026-09-25 · macOS 27.0 |
| homi 규칙 | 한자는 조합 중인 글자만 |

## 특징

- **조합 중인 글자의 한자 변환은 된다.**
  `16.113.2 · 2026-09-25 · 주인` ✅
- **선택만 있고 marked text 가 없을 때는 ⌥↩ 가 입력기에 오지 않는다** — homi 기록에 그 key 가 없다. Word 가 먼저 가져가는 듯하다.
  선택 영역 변환이 켜져 있던 때는 선택이 사라지거나 무시됐다.
  `16.113.2 · 2026-09-25 · 기록 + 주인` ✅ (까닭 🔶)
- **click 때 입력기에 `commitComposition` 을 먼저 부르고, 그다음 mouse down 을 넘긴다** — 조합 중이던 음절은 `commitComposition` 에서 확정된다.
  `16.113.2 · 2026-09-25 · 기록` ✅

## homi 의 우회

- `convertsEnteredText: false` — 한자는 조합 중인 글자만 ([engines/office.md](engines/office.md), `c884edd`).

## 다시 확인할 것

- 조합 중인 글자 + ⌥↩ → 한자.
- 조합 중에 click → 음절이 한 번만 남고 사라지지 않는다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 16.113.2 | 선택 영역의 ⌥↩ 가 입력기에 오지 않음을 기록으로 확인 → 한자는 조합 중인 글자만 (`c884edd`) |
