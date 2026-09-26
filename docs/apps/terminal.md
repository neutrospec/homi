# Terminal

| | |
|---|---|
| bundle ID | `com.apple.Terminal` |
| 엔진 | 자체 🔶 |
| 확인한 version | 2.15 (488) · 2026-09-25 · macOS 27.0 — 규칙만 있고 homi 로 본 것은 없다 |
| homi 규칙 | 한자는 조합 중인 글자만 |

## 특징

- homi 로 본 것은 아직 없다. terminal 이라 보낸 글자는 고칠 수 없고 선택 영역은 출력이다 — 다른 terminal 에 맞춘 규칙이다.

## homi 의 우회

- `convertsEnteredText: false` (`AppRules`, `c884edd`).

## 확인하는 법

- 조합 중 ESC·Enter → 확정된 뒤 key 도 간다. 잃으면 다시 보내기 규칙이 필요하다.
- Caps Lock·오른쪽 ⌘ 전환 때 글자가 새지 않는다.
- Secure Keyboard Entry 를 켜도 homi 가 동작하는가 (AGENTS.md 열린 결정 "설치 위치").

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 2.15 | 원장을 시작함 — terminal 규칙만 |
