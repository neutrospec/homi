# Apple 입력 API·macOS 27 조사 (2026-11-01)

source `9f30c23`, macOS 27.2 (`26B123`), Xcode 27.2 (`27B52`)의 공개 자료·설치 SDK와 homi 코드를 정적으로 대조했다. `MacOSX.sdk`, `MacOSX27.sdk`, `MacOSX27.2.sdk`는 같은 SDK 대상이다. 이전 SDK가 없어 26→27 header diff는 하지 못했다. availability 표기는 도입 시점이지 header나 runtime의 동등성 증거가 아니다. 새로 확정한 사용자 영향 결함은 없다.

[macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes), AppKit 163365571: Apple은 `NSTextSelectionManager`의 gesture 기반 선택과 `NSTextView`의 사용을 설명한다. 기존 `mouseDown:` override subclass에는 binary-compatible fallback이 있다. 설치 SDK의 `NSTextSelectionManager.h:32,36–37,66,136–137`에서도 gesture 설명과 API의 macOS 27.0 도입 표기를 확인했다. fallback은 release notes의 설명이다. 이는 native text client의 click 뒤 조합을 비교할 이유이지 IMK callback 변화의 증거가 아니다. [27.2 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes)에서 조사 대상 입력·lifecycle 변경을 찾지 못했으나 변경이 없다는 뜻은 아니다. 27.1 notes는 Apple 목록과 직접 URL에서 확인하지 못했다. 확인일은 2026-11-01이며 notes의 build는 명시되지 않았다.

## SDK 계약과 homi

아래 header 경로와 hash는 표 뒤에 있다. SDK 주석은 API 계약이며 각 app 구현이나 Apple 한국어 입력기의 private 구조가 아니다. 실제 관측과 추정은 [macOS 입력 구조](../macos-input.md), Apple 입력기 조사와 각 [app 원장](../apps/)을 따른다.

| 계약 · 근거 | homi 대응과 검증 범위 |
|---|---|
| `IMKServer.h:50`, `IMKInputController.h:226–230,333–338`: controller와 client는 session에 연결된다. | bound client로 종료하지만 하나의 client가 여러 입력칸을 가리킬 수 있다. 늦은 callback의 실제 입력칸 소유권과 순서는 보장하지 않는다. [Chromium](../apps/engines/chromium.md) 참조. |
| `IMKInputController.h:100–105`: `commitComposition:`은 조합 종료 요청이며 보통 insert 후 session을 끝낸다. | client가 이미 확정했는지는 별도 판단이다. `markedRange` 확인만으로 구분하는 제안은 실제 실패해 폐기했다. [Chrome](../apps/chrome.md), [교훈](../lessons.md) 참조. |
| `IMKInputController.h:156–162`: keyDown mask만 반환할 때 조합 밖 click의 기본 commit을 설명한다. | homi는 flagsChanged·leftMouseDown도 요청하고 받은 click에서 종료한다. 모든 client가 click을 전달한다는 뜻은 아니다. 일반 focus·click의 실제 결과를 우선 확인한다. |
| `IMKInputSession.h:63–89`: insert의 현재 selection 지정은 location·length 모두 `NSNotFound`; mark는 현재 위치에 location `NSNotFound`를 명시한다. | 현재 insert의 `{NSNotFound, 0}`은 알려진 호환 타협이다. 계약형 변경은 Chrome 실패를 해결하지 못해 복귀했다. 독립 client와 실제 app 비교 전 일괄 변경하지 않는다. [기록](../macos-input.md) 참조. |
| `IMKInputSession.h:93–119`, `NSTextInputClient.h:50–57`: IMK의 질의 실패와 AppKit의 mark 없음은 서로 다른 sentinel을 기술한다. [AppKit setMarkedText](https://developer.apple.com/documentation/appkit/nstextinputclient/setmarkedtext(_:selectedrange:replacementrange:))와 IMK header는 replacement range 기준도 다르게 설명한다. | 서로 다른 API 층의 범위를 섞지 않는다. 선택·최근 단어 변환은 client 응답 검증 뒤 진행한다. 문구 차이만으로 중간 변환이나 실제 오변환을 단정할 수 없다. |
| `IMKInputSession.h:151–168,242–264`: 위치 index는 inline session 기준이며 inline이 없을 때만 0은 현재 selection을 뜻한다. 실제 range는 요청과 다를 수 있다. | homi의 index 0은 조합 중 inline 시작이다. 현재 caret 위치라는 보장은 없지만 잘못된 인자라는 뜻도 아니다. 후보를 조합 시작에 붙일 표시 의도와 실제 좌표, 질의 실패 시 zero rect의 후보 창 표시는 미검증 UI 후보로 후순위다. [기존 안건](../stability-review.md#기능표시와-cold-path-의-안건)에서 검증한다. |
| `NSTextInputContext.h:40–43,84–88`, `TextInputSources.h:211–298,725–778,952–985`: context별 이용 가능한 source와 TIS enabled 전체 목록은 다르다. enable 가능 여부와 현재 enabled도 다르다. | 선택된 source ID만으로 menu의 availability·누락 원인을 알 수 없다. 재발 때 context·enabled·선택 상태를 읽기 전용으로 구분해 관측한다. |
| `CarbonEventsCore.h:2971–3064`: Secure Event Input은 keyboard focus app에 입력하고 event monitor에는 echo하지 않는다. 조회는 어느 process의 활성화든 반영하며 thread safe하지 않다. | 설치 위치나 source 제한 전체를 증명하지 않는다. 관련 [관측](../macos-input.md#input-menu-의-비활성누락-2026-10-09-미해결)을 따른다. |

조사한 IMK header에서 callback의 main thread·Swift actor, 비재진입, lifecycle 순서 보장은 찾지 못했다. 반대 동작의 증거도 아니다. `MainActor.assumeIsolated`와 probe crash는 [기존 검증 범위](../lessons.md#2026-10-09-activation-교정callback-관측)를 따른다.

## 재확인 경로

기준 `$F=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks`; `I=InputMethodKit.framework/Versions/A/Headers`, `A=AppKit.framework/Versions/C/Headers`, `H=Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers`. SHA-256:

| `$F` 상대 header | SHA-256 |
|---|---|
| `I/IMKServer.h` | `a6070ad67e6b1888e0bb13ae699cd5599a27f6fd73eb90a13b1b54aded7d9e02` |
| `I/IMKInputController.h` | `8057ec10d791466bcf2c8077309fdd2247364a3adb4b48e7cb2bc3953dd20c95` |
| `H/IMKInputSession.h` | `9c98da92677d79a4f918ba99f8a689031d3c0b6731217b4ee8279fff0f4ccdda` |
| `H/TextInputSources.h` | `e3c1a70e0cb8e21476a8f88f1e247a897a0c7d5723d43e3d63ff091d05927cd9` |
| `H/CarbonEventsCore.h` | `dcf2bb524f4577fd7ea7940c57372dc980c911047cece6e8e810de6c213cf81c` |
| `A/NSTextInputContext.h` | `afb79153e9541185beea7c3ebea49b163bdda7eaa8d422b31f77af342624ae3e` |
| `A/NSTextSelectionManager.h` | `e10531021b8a1570eb97dfa9e906e64cb6a1445ed4d706bb6b8d9009bf4c0226` |
| `A/NSTextInputClient.h` | `389131a0a835334b2d328ab8b6f93114a237b9c4a4bb3743a9275bc11cde4900` |

## 다음 조사

이전 SDK를 확보하면 header의 경로·hash를 기록하고 동일 API의 선언과 주석을 diff한다.
실제 문제가 발생하면 해당 native client의 click 후 조합 또는 후보 표시 위치를 관측해 비교한다.
