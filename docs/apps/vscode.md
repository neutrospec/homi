# VS Code

| | |
|---|---|
| bundle ID | `com.microsoft.VSCode` · `com.microsoft.VSCodeInsiders` (Insiders 는 지금 설치돼 있지 않다 — 규칙은 같다) |
| 엔진 | Chromium (Electron) → [engines/chromium.md](engines/chromium.md). editor(Monaco)는 입력을 숨은 textarea 나 EditContext 로 받는다 |
| 확인한 version | 1.139.0 · 2026-09-25 · macOS 27.0 |
| homi 규칙 | ESC → 영문 (조합 중이면 확정, key 는 VS Code 로) |

## 특징

- **ESC 는 영문 전환 trigger** — Hammerspoon 규칙에서 옮겼다.
  `2026-09-25 · 주인 요청` ✅
- **조합 중 click 은 Chromium 이 확정한다** — homi 는 넣지 않는다 ([engines/chromium.md](engines/chromium.md)).
  `1.139.0 · 2026-09-25 · 기록` ✅
- **그래도 가끔 click 한 자리에 음절이 한 번 더 들어간다** — `한자`(`자` 조합 중)를 mouse 로 선택하면 `자한자`. homi 기록에는 넣은 것이 없다.
  VS Code 안의 타이밍으로 본다. 비슷한 계열: microsoft/vscode#337197(EditContext 가 조합 중 선택을 바꿀 때), #13818.
  `1.139.0 · 2026-09-25 · 주인 + 기록` ✅ (원인 🔶) — 주인 판단: 조심해서 쓰고 더 파지 않는다
- **확정한 단어를 marked text 로 되돌리면 `나는한자漢字`** 가 된다 — 되돌린 조합을 커서 자리의 새 입력으로 다룬다. Apple 방식 한자는 쓰지 않는다.
  `1.139.0 · 2026-09-25 · 주인` ✅
- **조합 중인 글자와 선택한 한글의 한자 변환은 된다.**
  `1.139.0 · 2026-09-25 · 주인` ✅

## homi 의 우회

- ESC 영문 trigger (`AppRules`, `c08572b`).
- Chromium 규칙 — click·blur 의 `commitComposition` 에 넣지 않는다 (`7e4c1fd`).

## 확인하는 법

- 조합 중 ESC → 확정 + 영문, ESC 는 VS Code 에 간다.
- 조합 중(`자`) click → 음절이 한 번만 남는다. 가끔의 `자한자` 는 알려진 것이고, 잦아지면 기록을 저장한다.
- 조합 중인 글자·선택한 한글 + ⌥↩ → 한자.
- editor 의 입력 방식이 바뀌면(설정 `editor.experimentalEditContextEnabled`) 위를 모두 다시 본다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 1.139.0 | click 때 음절 중복 → Chromium 규칙 (`7e4c1fd`). 남은 가끔의 중복은 VS Code 쪽 |
| 2026-09-25 | 1.139.0 | 확정한 단어의 재변환이 틀어짐 → Apple 방식 한자 안 씀 (`c884edd`) |
