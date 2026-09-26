# app 원장

homi 가 다루는 app 마다 file 하나를 둔다. 그 app 의 입력 구현, 특징, homi 의 규칙과 우회, 그리고 **어느 version 에서 확인한 사실인지**를 적는다.
homi 를 바꿀 때(특히 `Sources/InputSession/AppRules.swift`) 그 app 의 원장을 먼저 읽고, 새로 안 것은 여기에 더한다.

## 쓰는 법

- **사실마다 확인 표시**: `version · 날짜 · 근거`.
  근거는 `주인`(관측) · `기록`(homi 의 key 기록) · `source`(app·엔진의 source) · `probe` · `실험` · `조사`(docs/research).
  ✅ 확인 / 🔶 추정 — 다른 문서와 같다.
- **app 이 update 됐다고 따로 확인하지 않는다.** 문제가 생겨 분석할 때 원장의 version 과 지금 version 을 견주어 무엇이 바뀌었는지 보고,
  "확인하는 법" 으로 사실이 아직 맞는지 본다. 달라졌으면 사실을 고치고 "기록" 에 한 줄 남긴 뒤 homi 도 고친다.
  옛 사실은 지우지 않고 기록에 남긴다 — 다시 바뀌면 되돌아갈 근거다.
- **같은 엔진의 공통 사실**은 `engines/` 에 한 번만 적고, app file 은 그곳을 가리킨다. app 고유의 것(그 위의 editor, plugin)만 app file 에 적는다.
- **새 app 에서 무언가 알게 되면** 아래 형식으로 file 을 만든다. 규칙도 관찰도 없는 app 은 만들지 않는다.
- version 보기: `defaults read "/Applications/<이름>.app/Contents/Info" CFBundleShortVersionString`
- 이 Mac: macOS 27.0 (26A428). macOS 가 바뀌면 엔진의 사실부터 다시 본다.

## 목록

| app | bundle ID | 엔진 | 확인한 version | homi 규칙 |
|---|---|---|---|---|
| [Telegram](telegram.md) | `ru.keepcoder.Telegram` | AppKit | 12.9 | 조합 중 Enter 다시 보내기 |
| [TextEdit](textedit.md) | `com.apple.TextEdit` | AppKit | 1.21 | — |
| [VS Code](vscode.md) | `com.microsoft.VSCode` · `com.microsoft.VSCodeInsiders` | Chromium | 1.139.0 | ESC → 영문 |
| [Obsidian](obsidian.md) | `md.obsidian` | Chromium | 1.13.7 | ESC → 영문 |
| [Chrome](chrome.md) | `com.google.Chrome` | Chromium | 154.0.8037.57 | — |
| [Orca](orca.md) | `com.stablyai.orca` | Chromium | 1.4.210 | — |
| [Wave](wave.md) | `dev.commandline.waveterm` | Chromium + xterm.js | 0.14.5 | ESC → 영문, 한자는 조합 중인 글자만 |
| [iTerm2](iterm2.md) | `com.googlecode.iterm2` | 자체 | 3.6.10 | ESC → 영문, 다시 보내기, 한자는 조합 중인 글자만 |
| [Ghostty](ghostty.md) | `com.mitchellh.ghostty` | 자체 | 1.3.1 | ESC·Ctrl-B·Ctrl-A → 영문, 다시 보내기, 한자는 조합 중인 글자만 |
| [Terminal](terminal.md) | `com.apple.Terminal` | 자체 | 2.15 | 한자는 조합 중인 글자만 |
| [IntelliJ IDEA](intellij.md) | `com.jetbrains.intellij` · `com.jetbrains.intellij.ce` | JetBrains Runtime | 2026.2.3 | ESC → 영문 |
| [Word](word.md) | `com.microsoft.Word` | Office | 16.113.2 | 한자는 조합 중인 글자만 |
| [Excel](excel.md) | `com.microsoft.Excel` | Office | 16.113.2 | 한자는 조합 중인 글자만 |
| [PowerPoint](powerpoint.md) | `com.microsoft.Powerpoint` | Office | 16.113.2 | 한자는 조합 중인 글자만 |
| [LaunchBar](launchbar.md) | `at.obdev.LaunchBar` | — | 6.24 | 늘 영문으로 시작* |
| [Remote Desktop](remote-desktop.md) | `com.apple.RemoteDesktop` | — | 3.10 | 한/영을 keyboard layout 으로 (원격은 두벌식) |
| [Windows App](windows-app.md) | `com.microsoft.rdc.macos` | — | 11.4.2 | 한/영 전환 없음* |
| [Emacs](emacs.md) | `org.gnu.Emacs` | — | (이 Mac 에 없다) | 한/영 전환 없음* |

\* 설정 창의 기본값 — 주인이 바꿀 수 있다. ESC → 영문도 설정의 기본값이다. 나머지(다시 보내기, 한자 제한, Ghostty 의 Ctrl-B·Ctrl-A)는 source(`AppRules.swift`)의 우회다.

## 엔진

| 엔진 | file | app |
|---|---|---|
| AppKit `NSTextView` (기준) | [engines/appkit.md](engines/appkit.md) | TextEdit, Telegram |
| Chromium (Electron 포함) | [engines/chromium.md](engines/chromium.md) | VS Code, Obsidian, Chrome, Orca, Wave, Claude |
| JetBrains Runtime | [engines/jbr.md](engines/jbr.md) | IntelliJ IDEA |
| Microsoft Office | [engines/office.md](engines/office.md) | Word, Excel, PowerPoint |

## file 형식

기존 file(예: [word.md](word.md))을 따른다 — 머리 표(bundle ID·엔진·확인한 version·homi 규칙), 특징(사실마다 확인 표시), homi 의 우회(코드 위치와 commit),
확인하는 법(해 볼 동작과 기대하는 결과), 기록(날짜·version·내용).
