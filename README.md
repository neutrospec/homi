# homi

macOS 한글 입력기. 두벌식 한글 조합과 한/영 전환을 입력기 안에서 하나로 처리한다.

이 프로젝트는 주인이 매일 쓰기 위해 만든 개인 입력기다. App Store 배포가 아닌, 직접 build 해서 쓰는 방식이다.

## 요구사항

- **macOS 27 이상.** 그 아래 버전에서는 build 도 설치도 되지 않는다.
- **최신 Xcode** (Swift 6.4 포함). 명령줄 도구만으로는 안 되고, Xcode 에 들어있는 Swift toolchain 이 필요하다.
- Apple 한국어 입력기(`com.apple.inputmethod.Korean.2SetKorean`) 대신 쓸 목적이다.

## 설치

```sh
git clone <이 repository 주소> homi
cd homi
scripts/install.sh --register
```

`install.sh --register` 가 release build → `.app` bundle 조립·서명 → `~/Library/Input Methods/homi.app` 설치 → TIS 등록까지 한 번에 한다.

처음 등록이면 **logout 한 번**이 필요하다 — system 이 입력기를 목록에 반영하는 데 시간이 걸린다. 다시 로그인한 뒤 시스템 설정 > 키보드 > 입력 소스 에서 `homi` 가 보이면 선택한다.

### 손쉬운 사용 허가 (권장)

조합 중 Enter·ESC 를 일부 app(Telegram, terminal)에서 다시 보내려면 손쉬운 사용 권한이 필요하다:

1. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용
2. `homi` 를 켠다

권한이 없어도 입력기는 동작하지만, 해당 app 들에서 Enter·ESC 처리가 덜 완벽하다.

### 서명 관련 — build 마다 허가가 풀리면

이 입력기는 자체 서명 인증서("homi code signing")로 서명한다. 인증서가 없으면 ad-hoc 서명으로 떨어지는데, **ad-hoc 서명은 build 마다 신원이 바뀌어 손쉬운 사용 허가가 매번 풀린다.**

매번 허가를 다시 주기 싫다면 자체 서명 인증서를 하나 만들면 된다:

1. 키체인 접근 앱 실행
2. 메뉴 > 키체인 접근 > 인증서 지원 > 인증서 작성
3. 이름: `homi code signing`, 신원 유형: 자체 서명 루트, 인증서 유형: 코드 서명
4. login 키체인에 만든다

이름이 정확히 `homi code signing` 이어야 `scripts/app.sh` 가 찾는다.

## 쓰기

- **한/영 전환**: Caps Lock 짧게 누르기, 또는 오른쪽 ⌘ 짧게 누르기 (기본값, 설정에서 바꾼다).
- **한자 변환**: ⌥↩ (방금 친 단어, 또는 조합 중인 글자를 한자로 바꾼다).
- **한글 모드 표시**: menu bar 의 한/A 아이콘.

자세한 조작과 설정은 입력기의 설정 창(입력 메뉴 > 설정…)에서 고른다.

## 비상 탈출

입력기가 고장나면 타이핑이 막힌다. **`ABC` 입력 소스를 input source 목록에 남겨두면** menu bar 에서 바로 빠져나올 수 있다. 설치 전에 `ABC` 가 목록에 있는지 확인하라.

## 주의

- 이 입력기는 개인 프로젝트다. Apple 의 한국어 입력기와 동작이 다른 부분이 있다 (같은 자음 연달아 합치지 않기, `` ` `` 는 `` ` `` 그대로 등). 자세한 설계 의도는 `AGENTS.md` 에 있다.
- macOS 입력기는 system 전체에 영향을 준다. 문제가 생기면 `ABC` 로 빠져나가고, 필요하면 `~/Library/Input Methods/homi.app` 을 지우면 된다.
- Remote Desktop·Windows App 같은 원격 환경에서는 이 Mac 의 keyboard layout 으로 한/영을 알린다 — 원격 Mac 은 두벌식 layout 으로 둬야 한다.

## 구조

| module | 역할 |
|---|---|
| `HangulCore` | 두벌식 조합 state machine (AppKit·IMK 모름) |
| `InputSession` | key 해석, 모드, 앱별 기억·규칙 (AppKit·IMK 모름) |
| `homi` | IMK glue — `IMKServer`, `HomiInputController`, menu bar, 설정 창 |

`HangulCore`·`InputSession` 은 순수 Swift 로 `swift test` 로 검증한다. IMK 층은 얇다.

## 개발

```sh
swift test                    # 조합·key 순서 test
scripts/install.sh            # build → 설치 (이미 등록된 경우)
scripts/probe.sh              # test client 창에서 key event 관찰
swift run tis list|current    # input source 조회
```

자세한 개발 규칙·설계 결정·함정은 `AGENTS.md` 와 `docs/` 에 있다.
