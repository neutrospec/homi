# Orca

| | |
|---|---|
| bundle ID | `com.stablyai.orca` |
| 엔진 | Chromium (Electron) → [engines/chromium.md](engines/chromium.md) |
| 확인한 version | 1.4.210 · 2026-09-25 · macOS 27.0 |
| homi 규칙 | — |

## 특징

- **확정한 단어를 marked text 로 되돌리면 `나는한자漢字`** 가 된다 — VS Code 와 같다. Apple 방식 한자는 쓰지 않는다.
  `1.4.210 · 2026-09-25 · 주인` ✅

## homi 의 우회

- Chromium 규칙 (`7e4c1fd`).

## 다시 확인할 것

- 조합 중 click → 음절이 한 번만 남는다.
- 조합 중인 글자 + ⌥↩ → 한자.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 1.4.210 | 확정한 단어의 재변환이 틀어짐 → Apple 방식 한자 안 씀 (`c884edd`) |
