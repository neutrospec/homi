# Excel

| | |
|---|---|
| bundle ID | `com.microsoft.Excel` |
| 엔진 | Microsoft Office → [engines/office.md](engines/office.md) |
| 확인한 version | 16.113.2 (16.113.26092012) · 2026-09-25 · macOS 27.0 — 규칙만 있고 homi 로 본 것은 없다 |
| homi 규칙 | 한자는 조합 중인 글자만 |

## 특징

- homi 로 본 것은 아직 없다. 셀 편집마다 새 client 라고 한다 ([engines/office.md](engines/office.md)).

## homi 의 우회

- `convertsEnteredText: false` (`AppRules`, `c884edd`).

## 확인하는 법

- 셀에서 한글을 조합하다 Enter·Tab → 조합이 확정되고 key 도 간다 (다음 셀로).
- 새 셀에서도 한/영 모드가 app 별 기억대로다.
- 조합 중인 글자 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 16.113.2 | 원장을 시작함 — Office 규칙만 |
