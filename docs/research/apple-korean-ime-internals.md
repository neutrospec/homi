# Apple 한국어 입력기의 내부 경로 — binary 분석 (2026-11-02)

출처는 주인이 따로 맡긴 binary 분석이다: `~/.t3/projects/apple-im/docs/special-behaviours.md`(`566c208` 위 2026-11-02 수정본)와
같은 날 두 차례의 질의 답, 2026-11-03 probe 대조. 대상은 `KIM_Extension` 104(arm64e)·macOS 27.2, InputMethodKit 는 dyld shared cache 의 disassembly 다.
분석가의 표시를 그대로 옮긴다 — **[O]** code 에서 읽음, **[I]** 해석, **[G]** 미확정. homi 가 Apple 입력기를 실행해 확인한 것이 아니다.
homi 의 관측·결정은 [macOS 입력 구조](../macos-input.md#apple-한국어-입력기가-하는-일)와 [Mail 원장](../apps/mail.md)이 우선한다.

## homi 관측과 맞는 것

- 조합 중인 글자를 marked text 없이 문서에 바로 쓴다 — 첫 자모는 `insertText`(NSNotFound), 다음부터 조합 범위를 `replacementRange` 로 [O].
  첫 key 뒤 조합 범위가 `{0,1}`이 되는 계산도 probe run 1 의 둘째 key `repl={0,1}`과 맞는다 [O]. 2026-11-03 macOS 27.2 에서도 같은 쓰기 순서를 다시 봤다.
  이 경로(IME 의 `showsInline == NO`)를 client 마다 누가 정하는지는 [G]다.
- 앞 음절을 확정하고 새 조합을 시작할 때(`한`+ㄱ) 둘째 `insertText` 는 `ㄱ` 하나다 — probe 관측이다. 분석가의 `doUpdate:` 판독(`한ㄱ`)은 이와 어긋나 분석가가 오독으로 정정했다.
- 선택 영역이 있으면 조합 범위와 선택의 합을 바꾼다 [O] — 2026-11-01 `NSTokenField` 대조에서 추천이 채운 `가나다` 뒤 다음 자음으로 `간`이 된 관측과 맞는다.
- 조합 중 Return 은 확정한 뒤 key 를 넘긴다 [O, 분석가 정정] — probe 의 `insertNewline:` 관측과 같다. ⌥Return(한자)만 key 를 먹는다.
- `hasMarkedText`·`validAttributesForMarkedText` 는 IME 가 아니라 framework 가 묻는다 [O]. IME 는 `markedRange` 도 묻지 않는다 [O].

## insert 와 mark 를 한 번에 보내는 경로는 framework 에도 없다

- framework adaptor 의 `beginEdit`/`endEdit` 는 내부 text model 의 변경을 `endEdit` 에서 한 번 쓰는 flush 경계다 [O 구조, I 합침].
  그 한 번도 marked text 면 `setMarkedText` 하나, 아니면 삭제 뒤 `insertText` 다. insert 와 mark 를 함께 보내는 API 는 이 image 에 없다 [O].
- IME 가 부르는 `insertText`·질의는 adaptor 를 거쳐 client 로 간다. 질의는 대기 중인 변경을 먼저 flush 한다 [O].
- → [Mail 원장](../apps/mail.md)의 "insert 와 다음 mark 를 묶는 공개 수단이 없다"를 framework 내부까지 넓혀 뒷받침한다. Mail 함께 넣기 규칙을 바꿀 근거는 아니다.

## 쓴 뒤의 확인과 app 목록은 이 build 에서 꺼져 있다 [O]

- 확정 뒤 다시 읽어 비교하고, 어긋나면 그 client 를 marked text 경로로 바꾸는 code 가 있지만 그 검사를 켜는 곳이 없다 — `setShouldCheckForInsertionError:` 의 세 호출이 모두 NO 다.
- 그래서 IME 의 `modelessUnsupportedApps` 도 채워지지 않는다. 읽는 곳도 IME·framework 어디에도 없다.
  framework 에는 별개로 adaptor 생성 때 주입하는 `unreliableApps` 가 있다 [O]. 쓰임은 [G]다.

## 자모 풀림의 후보 경로 [I]

- 한글 key 와 Backspace 마다 `convertHangul:` 가 조건 없이 `inlineInconsistent` 를 부른다 — 조합 중인 글자가 커서 앞 한 글자와 다르고
  marked text 경로가 아니면 조합기를 reset 한다 [O]. 커서 앞 글자는 `selectedRange` 뒤 `attributedSubstringFromRange:` 로 client 에 묻는다 [O].
  질의를 건너뛰는 것은 `selectedRange.location` 이 0 이거나 NSNotFound 일 때뿐이다 [O].
- client 가 `selectedRange` 를 한 key 늦게 답하면 이 비교가 틀려 reset 되고 `한`이 `ㅎㅏㄴ`으로 풀릴 수 있다 [I — 손 추적, 재현 없음].
  [왜 만드는가](../../AGENTS.md#왜-만드는가)의 🔶 원인과 같은 방향이지만 확인은 아니다.
- Telegram 의 `아 → ㅏ`(초성 유실)는 설명되지 않았다. 분석가의 첫 후보(범위 뺄셈의 underflow)는 위의 꺼진 확인 code 안에 있고,
  둘째 후보(reset 뒤 조합 범위를 덮음)는 reset 뒤 다음 글자를 커서·선택 자리에 넣는 분석 모델과 맞지 않는다.

## 우리 관측과의 어긋남 — probe 의 사각으로 풀림 (2026-11-03)

probe run 2 에서는 `attributedSubstring` 질의가 한 번도 없었는데, 위 경로대로면 `한`의 둘째 key 에서 `{0,1}`을 물어야 했다.
분석가가 남긴 설명은 둘이었다: 그 순간 `selectedRange.location` 이 0 이었거나, IME 의 질의가 probe 의 override 에 닿지 않는다.

2026-11-03 같은 probe 창에서 Apple 두벌식과 homi 를 차례로 쳐 갈랐다 ([기록](../macos-input.md#probe-에-닿지-않는-입력기의-질의-2026-11-03)).
- Apple 의 둘째 key 에서 `selectedRange` 는 `{1,0}`이었다 — 첫 설명은 틀렸다. 이번에도 `attributedSubstring` 은 기록되지 않았다.
- homi 의 ⌥↩ 는 `markedRange` 와 mark 앞 글자를 받아야만 되는 변환을 해냈는데, 그 두 질의도 probe 에 기록되지 않았다 — 둘째 설명 쪽이다.

그러니 run 2 와 이번 기록은 Apple 이 커서 앞 글자를 묻지 않았다는 증거가 아니다. 분석 모델과 우리 관측은 모순되지 않는다.
기구는 분석가의 셋째 답과 SDK header 로 확정했다 [O]: `IMKTextInput` 의 문서 질의는 TSMDocumentAccess Carbon event 로 가고, `setMarkedText` 는
`kEventTextInputUpdateActiveInputArea`(text + hilite 배열 + replace range)로 간다. 분석가는 `{0,len}` selection 을 "hilite 가 전체를 선택 스타일로 덮은 것" 으로 읽었다 [I].

## 분석가의 3-(b) 와 다른 결론 — markedRange 의 주인은 Mail 이 아니다

분석가는 "`markedRange` 는 TSMDocumentAccess 로 client 가 답하니 IMK 는 범인이 아니다" 라고 했다. 그러나 TSMDocumentAccess event 에는 marked range 를 묻는 것이 없다
(`CarbonEvents.h:2272–2285`). 2026-11-03 평범한 `NSTextView` 에 IMK 경로로 같은 순서를 보내자 Mail 과 같은 `{2,1}` 이 나왔다 ([기록](../docs/macos-input.md#위치를-준-mark-뒤의-markedrange-응답-2026-11-03)).
틀린 값은 Mail 이 아니라 IMK 경로의 것이고, TSM 에 event 가 없으니 IMK 의 계산으로 본다 🔶. 분석가가 제안한 판별 실험과 같은 실험이며 결론의 이름만 다르다.

## 미확정 [G]

- `showsInline` 의 초기값과 client 별 결정 — 그래서 Mail 받는 사람 칸에서 Apple 이 어느 경로인지 모른다.
- focus·source 전환 직후 첫 key 를 조합하지 않는 조건(QTBUG-136128) — 분기 후보만 있다.
