# Safari

| | |
|---|---|
| bundle ID | `com.apple.Safari` |
| 엔진 | WebKit. focus 가 옮을 때마다 homi 의 activate/deactivate 가 잦고 `deactivate unknown` 이 섞인다 (기록) — 입력 context 가 칸마다 새로 생기는 것으로 보인다 🔶 |
| 확인한 version | 27.2 · 2026-11-05 · macOS 27.2 (26B123) |
| homi 규칙 | — |

## 비밀번호 칸과 보안 입력 (2026-11-05)

- 비밀번호 칸이 focus 를 가진 동안 **session 전역** Secure Event Input 을 켠다 ✅ (`tis watch`·poller — 12:34:16–20, 12:34:40–41, 12:34:43–49, 12:35:06–10, 18:44:27 의 0.16초).
  켜진 동안의 문서 활성화는 [homi 대신 ABC](../macos-input.md#보안-입력이-켜진-동안-문서-활성화는-homi-대신-abc-를-고른다-2026-11-05-확인) 다.
  비밀번호 칸 자체가 ABC 인 것은 정상이다 (AGENTS 함정 7) — 문제는 그 뒤다.
- 12:34 의 4번은 homi 를 깨웠다 몇 ms 뒤 재우는 모양이었고, 꺼진 뒤 첫 활성화에서 homi 로 돌아왔다 ✅.
  18:44:27 은 homi 를 깨우지 않고 ABC 로 갔고(이전 context 는 `deactivate unknown`), 그 뒤 Safari 의 다른 문서(18:46:58)와 Orca(18:47:04)도 ABC 였다.
  18:48:25 Orca 에서의 ⌃Space 로 돌아왔다. 두 모양의 뜻은 [고정되는 경우](../macos-input.md#강제된-문서에서-key-전환을-시도한-뒤에는-다른-app-의-활성화도-abc-였다-2026-11-05-1550-🔶) 에 있다 🔶.
- 다른 process 가 켠 보안 입력([다른 agent 의 Playwright](../macos-input.md#켠-process-는-다른-agent-의-playwright-headless-chromium-2026-11-05-확인)) 중에 Safari 로 옮긴 14:09:00 도 같은 강제였고 40초 뒤 Telegram 활성화에서 돌아왔다.
  06:06:54 에 시작한 긴 ABC(06:45 까지)도 Safari 에서 시작했으나 IMK log 가 남지 않아 모양을 모른다.

근거: `build/availability-20261103-telegram/trap-tis-watch.log`·`secure-poller.log`, IMK signpost (`log show … process == "homi"`), 기록 `record-2026-11-05T185448.txt` (2026-11-16 삭제).
