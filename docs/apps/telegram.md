# Telegram

| | |
|---|---|
| bundle ID | `ru.keepcoder.Telegram` |
| 엔진 | AppKit — 입력칸은 TelegramSwift `ChatInputTextView` 안의 `NSTextView` → [engines/appkit.md](engines/appkit.md) |
| 확인한 version | 12.9 (282526) · 2026-09-25 · macOS 27.0 |
| homi 규칙 | 조합 중 Return·keypad Enter 는 확정 → 먹고 → 다시 보낸다 |

## 특징

- **조합 중 Enter 는 전송이 아니라 줄바꿈이 된다** (Apple 입력기 때부터). Telegram 은 marked text 가 없고 수식키도 없을 때만 Enter 로 보낸다.
  조합 중이면 key 를 입력기에 넘기고, 입력기가 확정한 뒤 줄바꿈이 된다 — 일본어·중국어의 "Enter = 변환 확정" 관례다.
  `12.9 · 2026-09-25 · source(ChatInputTextView.keyDown, a404806) + 주인` ✅
- **다시 보낸 Enter 는 새 event 여야 닿는다** — 원래 event 의 복사본을 key 처리 도중에 보냈더니 "틱" 소리만 나고 사라졌다.
  `12.9 · 2026-09-25 · 주인 + 기록` ✅ (까닭 🔶 — docs/lessons.md)
- **Apple 방식 한자(방금 친 단어)가 된다** — `나는한자` + ⌥↩ 에 `한자` 에만 밑줄이 생긴다.
  `12.9 · 2026-09-25 · 주인` ✅
- Apple 두벌식에서 첫 초성이 사라진 적이 있다(`아` → `ㅏ`). homi 로는 재현되지 않았다.
  `12.9 · 2026-09-25 · 주인` 🔶

## homi 의 우회

- 조합 중 Return·keypad Enter 는 확정하고 먹은 뒤 새 event 로 다시 보낸다. 두 번째 Enter 가 도착할 때는 marked text 가 없어 전송된다
  (`AppRules` 의 `resendWhileComposing`, `Resend`, `c08572b`). 손쉬운 사용 허가가 필요하다.

## 확인하는 법

- 한글을 조합하다 Enter → 한 번에 전송된다.
- `나는한자` + ⌥↩ → `한자` 에만 밑줄 → 漢字 로 바뀐다. ⌥↩ 를 한 번 더 누르면 `자` 로 짧아진다.

## 기록

| 날짜 | version | 내용 |
|---|---|---|
| 2026-09-25 | 12.9 | 조합 중 Enter 다시 보내기 — 복사본은 닿지 않아 새 event 로 (`c08572b`) |
| 2026-09-25 | 12.9 | Apple 방식 한자 확인 (`c884edd`) |
