# Apple 한국어 입력기의 내부 경로 — binary 분석 (2026-11-02)

출처는 주인이 따로 맡긴 binary 분석이다: `~/.t3/projects/apple-im/docs/special-behaviours.md`(`566c208` 위 2026-11-02 수정본)와
같은 날 질의 답. 대상은 `KIM_Extension` 104(arm64e)·macOS 27.2, InputMethodKit 는 dyld shared cache 의 disassembly 다.
분석가의 표시를 그대로 옮긴다 — **[O]** code 에서 읽음, **[I]** 해석, **[G]** 미확정. homi 가 Apple 입력기를 실행해 확인한 것이 아니다.
homi 의 관측·결정은 [macOS 입력 구조](../macos-input.md#apple-한국어-입력기가-하는-일)와 [Mail 원장](../apps/mail.md)이 우선한다.

## homi 관측과 맞는 것

- 조합 중인 글자를 marked text 없이 문서에 바로 쓴다 — 첫 자모는 `insertText`(NSNotFound), 다음부터 조합 범위를 `replacementRange` 로 [O].
  probe run 1·2 의 바꿔치기 관측과 같다. 이 경로(IME 의 `showsInline == NO`)를 쓰는지 client 마다 누가 정하는지는 [G]다.
- 선택 영역이 있으면 조합 범위와 선택의 합을 바꾼다 [O] — 2026-11-01 `NSTokenField` 대조에서 추천이 채운 `가나다` 뒤 다음 자음으로 `간`이 된 관측과 맞는다.
- 조합 중 Return 은 확정한 뒤 key 를 넘긴다 [O, 분석가 정정] — probe 의 `insertNewline:` 관측과 같다. ⌥Return(한자)만 key 를 먹는다.
- framework 에는 adaptor 생성 때 주입하는 app 목록 `unreliableApps` 가 있다 [O]. IME 의 `modelessUnsupportedApps` 는 별개이며, 쓰기만 하고 읽는 곳이 IME·framework 어디에도 없다 [O].

## insert 와 mark 를 한 번에 보내는 경로는 framework 에도 없다

- framework adaptor 의 `beginEdit`/`endEdit` 는 내부 text model 의 변경을 `endEdit` 에서 한 번 쓰는 flush 경계다 [O 구조, I 합침].
  그 한 번도 marked text 면 `setMarkedText` 하나, 아니면 삭제 뒤 `insertText` 다. insert 와 mark 를 함께 보내는 API 는 이 image 에 없다 [O].
- IME 가 부르는 `insertText` 는 adaptor 를 거쳐 곧바로 client 로 간다 [O]. 질의(`selectedRange`·`markedRange`·`validAttributesForMarkedText`)는 대기 중인 변경을 먼저 flush 한다 [O].
- → [Mail 원장](../apps/mail.md)의 "insert 와 다음 mark 를 묶는 공개 수단이 없다"를 framework 내부까지 넓혀 뒷받침한다. Mail 함께 넣기 규칙을 바꿀 근거는 아니다.

## 자모 풀림의 후보 경로 [I]

- 한글 key 와 Backspace 마다 `convertHangul:` 의 서두에서 `inlineInconsistent` 를 본다 — 조합 중인 글자가 커서 앞 한 글자와 다르고 marked text 경로가 아니면
  조합기를 reset 한다 [O]. 커서 앞 글자는 `selectedRange` 뒤 `attributedSubstringFromRange:` 로 client 에 묻는다 [O]. 커서 앞이 비면 비교를 건너뛴다 [O].
- client 가 `selectedRange` 를 한 key 늦게 답하면 이 비교가 틀려 reset 되고, `한`이 `ㅎㅏㄴ`으로 풀릴 수 있다 [I — 손으로 따라간 결과, 재현 없음].
  [왜 만드는가](../../AGENTS.md#왜-만드는가)의 🔶 원인과 같은 방향이지만 확인은 아니다. Telegram 의 `아 → ㅏ`(초성 유실)는 이 경로로 설명되지 않는다 — 결과는 `ㅇㅏ`다.
- 확정 뒤 다시 읽어 확인하고, 어긋나면 그 client 를 marked text 경로로 바꾸는 장치도 있다 [O]. 검사가 언제 켜지는지는 [G]다.

## 우리 관측과 어긋나는 것 — 미해결

probe run 2 (2026-09-25, `NSTextView`, 당시 macOS build 미기록)에서 Apple 입력기는 `attributedSubstring` 을 한 번도 묻지 않았다. probe 는 처음부터 이 질의를 기록했다.
위 경로대로면 `한`의 둘째 key 부터 물어야 한다(조합 중인 글자가 있는 한글 key). 분석가의 설명(한글 key 가 아니었거나 조합 중인 글자가 비었다)은 이 key 에 맞지 않는다.
version 차이·app 쪽 응답 경로·분석의 오독 중 무엇인지 모른다. **이 경로를 근거로 쓰기 전에 현재 macOS 에서 Apple 입력기로 probe 를 다시 본다** —
Apple 입력기를 input source 에 다시 넣는 일이라 주인 확인이 필요하다.

## 미확정 [G]

- `showsInline` 의 초기값과 client 별 결정 — 그래서 Mail 받는 사람 칸에서 Apple 이 어느 경로인지 모른다.
- focus·source 전환 직후 첫 key 를 조합하지 않는 조건(QTBUG-136128) — 분기 후보만 있다.
