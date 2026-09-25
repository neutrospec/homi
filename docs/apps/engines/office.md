# Microsoft Office

Word·Excel·PowerPoint 는 같은 text 구현을 쓸 것이다 🔶. source 가 없어 관측과 다른 입력기의 조사에 기댄다.

| | |
|---|---|
| app | Word, Excel, PowerPoint |

## 특징

- **`replacementRange` 를 NSNotFound 가 아닌 값으로 주면 깨진다** — 그래서 입력기는 늘 NSNotFound 를 준다.
  `조사(vChewing InputSession_HandleStates.swift)` ✅ (homi 로는 시험하지 않았다)
- **Excel 은 셀 편집마다 새 client 다.** `조사(vChewing#446)` ✅
- "문서의 입력 소스로 자동 전환" 이 켜져 있으면 셀이 한글로 시작해 영문으로 이어지는 일이 있었다 — 이 Mac 에서는 그 설정을 껐다.
  `조사(drchung.net 2019-09-24)` ✅
- Word 에서 관측한 것은 [word.md](../word.md) 에 있다.

## homi 의 우회

- 한자는 조합 중인 글자만 (`AppRules` 의 `convertsEnteredText: false`, `c884edd`).

## 다시 확인할 것

- Word·Excel·PowerPoint 에서 한글 조합, 조합 중인 글자 + ⌥↩.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 16.113.2 | 조사를 근거로 한자 변환을 조합 중인 글자로 제한 (`c884edd`) |
