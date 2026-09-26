# Emacs

| | |
|---|---|
| bundle ID | `org.gnu.Emacs` |
| 엔진 | — (Emacs 자체의 입력기를 쓴다) |
| 확인한 version | 이 Mac 에 없다 (2026-09-25) |
| homi 규칙 | 한/영 전환 없는 app (설정의 기본값) — 한/영 전환도 조합도 하지 않고, Caps Lock 도 원래대로 |

## 특징

- **Emacs 에는 자체 한글 입력기가 있고 품질이 아주 좋다** — homi 는 한/영 전환도 조합도 하지 않고 key 를 그대로 넘긴다.
  Emacs 의 한/영 전환(`toggle-input-method` 등)도 그대로 Emacs 에 간다.
  `2026-09-25 · 주인` ✅
- terminal 안의 `emacs -nw` 는 그 terminal 의 bundle ID 라서 여기에 해당하지 않는다.

## homi 의 우회

- 한/영 전환 없는 app (`Preferences.passThroughApps`, M7).

## 다시 확인할 것 (설치하면)

- menu bar 표시가 `–` 다. Emacs 의 한글 입력기로 조합되고, Emacs 의 한/영 전환 key 가 먹힌다.
- bundle ID 가 `org.gnu.Emacs` 가 아니면(배포판마다 다를 수 있다) 설정에서 그 app 을 더한다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | — | "한/영 전환 없는 app" 기본 목록에 넣음 (주인, M7) |
