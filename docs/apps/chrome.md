# Chrome

| | |
|---|---|
| bundle ID | `com.google.Chrome` |
| 엔진 | Chromium → [engines/chromium.md](engines/chromium.md) |
| 확인한 version | 154.0.8037.57 · 2026-09-25 · macOS 27.0 |
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
- 조합 중인 글자·선택한 한글 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 154.0.8037.57 | 확정한 단어의 재변환이 입력칸마다 달랐다 → Apple 방식 한자 안 씀 (`c884edd`) |
