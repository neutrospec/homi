import HangulCore
import Testing

@testable import InputSession

/// client 호출 도중 lifecycle 을 끼워 부른다. 글자는 이 test 안에서 만든 것뿐이다.
private final class Host {
    let driver = SessionDriver(hanja: dictionary)
    var text = ""
    var marked = ""
    var candidates = false
    var onInsert: (() -> Void)?
    var onMark: (() -> Void)?

    func apply(_ actions: [Action]) {
        for action in actions {
            switch action {
            case .insert(let value):
                text += value
                marked = ""
                let callback = onInsert
                onInsert = nil
                callback?()
            case .mark(let value):
                marked = value
                let callback = onMark
                onMark = nil
                callback?()
            case .showCandidates: candidates = true
            case .hideCandidates: candidates = false
            default: break
            }
        }
    }

    func type(_ letters: String) {
        for letter in letters {
            driver.perform({ $0.handle(key(letter), mode: .korean) }, apply: { apply($0.actions) })
        }
    }
    func deactivate() { driver.deactivate(apply: apply) }
    func commit(insert: Bool = true) { driver.commit(insert: insert, apply: apply) }
    func sourceChanged(selected: Bool) { driver.sourceChanged(selected: selected, apply: apply) }
    func clientConfirmed() { driver.clientConfirmed(apply: apply) }
}

/// Chrome 의 여러 DOM 입력칸은 proxy 하나를 공유한다. markedRange 답은 이전 mark 를 그대로 돌려줄 수 있다.
private final class SharedClient {
    struct Field { var text = ""; var marked = "" }
    let driver = SessionDriver()
    var fields = [Field(), Field()]
    var focus = 0

    func apply(_ actions: [Action]) {
        for action in actions {
            switch action {
            case .insert(let value):
                fields[focus].text += value
                fields[focus].marked = ""
            case .mark(let value): fields[focus].marked = value
            default: break
            }
        }
    }

    func type(_ letters: String) {
        for letter in letters {
            driver.perform({ $0.handle(key(letter), mode: .korean) }, apply: { apply($0.actions) })
        }
    }

    func clickNextField() {
        fields[focus].text += fields[focus].marked
        fields[focus].marked = ""
        // 2026-10-09 lifecycle·DOM 관찰: 이전 칸은 이미 compositionend, proxy 는 여전히 mark 를 보고한다.
        driver.clientConfirmed(apply: apply)
        focus = 1
    }
}

@Test("같은 proxy 의 새 입력칸에 이전 조합을 넣지 않는다 — client mark 답이 stale 이어도")
func confirmedCompositionCannotFollowSharedClientFocus() {
    let host = SharedClient()
    host.type("rmf")
    host.clickNextField()
    #expect(host.driver.composing.isEmpty)
    host.type("gks")
    host.driver.commit(apply: host.apply)
    #expect(host.fields[0].text == "글")
    #expect(host.fields[1].text == "한")
    #expect(host.fields.allSatisfy { $0.marked.isEmpty })
}

@Test("source 종료의 명시적 확정·알림·deactivate 는 한 번만 넣는다")
func explicitSourceCommitBeforeSourceNotification() {
    let host = Host()
    host.type("gks")
    host.commit()
    host.sourceChanged(selected: false)
    host.deactivate()
    host.driver.activate()
    host.type("gksrmf")
    host.commit()
    #expect(host.text == "한한글")
    #expect(host.marked.isEmpty)
}

@Test("Chromium 의 blur callback 뒤 client 가 mark 를 지우면 다시 넣지 않는다")
func clientConfirmsAfterCommitCallback() {
    let host = Host()
    host.type("gks")
    host.clientConfirmed()
    // page 는 이미 확정했지만 Cocoa 의 mark flag 는 callback 이 돌아온 뒤에 꺼진다.
    host.text += host.marked
    host.marked = ""
    host.type("rk")
    host.commit()
    #expect(host.text == "한가")
    #expect(host.marked.isEmpty)
}

@Test("client 의 확정 뒤 deactivate·source 종료가 와도 다시 넣지 않는다")
func clientConfirmationThenDeactivation() {
    let host = Host()
    host.type("gks")
    host.clientConfirmed()
    host.text += host.marked
    host.marked = ""
    host.deactivate()
    host.sourceChanged(selected: false)
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
}

@Test("mark 반영 중 client 의 확정은 같은 event 의 끝에 Session 을 닫는다")
func clientConfirmationDuringMark() {
    let host = Host()
    host.type("gk")
    host.onMark = {
        host.clientConfirmed()
        host.text += host.marked
        host.marked = ""
    }
    host.type("s")
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
}

@Test("client 가 확정한 뒤 같은 event 에 종료가 겹쳐도 글자를 다시 넣지 않는다", arguments: [false, true])
func clientConfirmationAndClosureDuringMark(sourceNotification: Bool) {
    let host = Host()
    host.type("gk")
    host.onMark = {
        host.clientConfirmed()
        host.text += host.marked
        host.marked = ""
        if sourceNotification { host.sourceChanged(selected: false) }
        else { host.deactivate() }
    }
    host.type("s")
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
    #expect(!host.driver.isHandlingEvent)
}

@Test("client 의 확정은 같은 event 의 activate 로 취소되지 않는다")
func clientConfirmationSurvivesActivation() {
    let host = Host()
    host.type("gk")
    host.onMark = {
        host.clientConfirmed()
        host.text += host.marked
        host.marked = ""
        host.driver.activate()
    }
    host.type("s")
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(!host.driver.isHandlingEvent)
}

@Test("insertText 도중 deactivate — 남은 mark 뒤에 한 번만 확정한다")
func deactivateDuringInsert() {
    let host = Host()
    host.type("gks")
    host.onInsert = { host.deactivate() }
    host.type("r")
    #expect(host.text == "한ㄱ")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
    host.deactivate()
    #expect(host.text == "한ㄱ")
}

@Test("insertText 도중 deactivate → activate — 같은 session 의 조합을 이어 간다")
func reactivationDuringInsert() {
    let host = Host()
    host.type("gks")
    host.onInsert = { host.deactivate(); host.driver.activate() }
    host.type("rmf")
    host.commit()
    #expect(host.text == "한글")
    #expect(host.marked.isEmpty)
}

@Test("한자 질의 도중 commit — Session 의 exclusive access 와 겹치지 않는다")
func commitDuringQuery() {
    let host = Host()
    host.driver.perform({ session in
        session.handle(optionReturn, mode: .korean, selectedText: {
            host.commit()
            return "한자"
        })
    }, apply: { host.apply($0.actions) })
    #expect(!host.candidates)
    #expect(host.driver.composing.isEmpty)
}

@Test("한자 질의 도중 deactivate → activate — 후보를 정상적으로 고른다")
func reactivationDuringQuery() {
    let host = Host()
    host.driver.perform({ session in
        session.handle(optionReturn, mode: .korean, selectedText: {
            host.deactivate()
            host.driver.activate()
            return "한자"
        })
    }, apply: { host.apply($0.actions) })
    #expect(host.candidates)
    host.driver.perform({ $0.handle(digit(1), mode: .korean) }, apply: { host.apply($0.actions) })
    #expect(!host.candidates)
    #expect(!host.text.isEmpty)
    #expect(host.marked.isEmpty)
}

@Test("확정 요청은 뒤의 activate 가 취소하지 않는다")
func explicitCommitSurvivesActivation() {
    let host = Host()
    host.type("gk")
    host.onMark = { host.commit(); host.driver.activate() }
    host.type("s")
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
}

@Test("client 가 이미 확정한 조합은 lifecycle 이 겹쳐도 다시 넣지 않는다")
func hostCommittedDuringMark() {
    let host = Host()
    host.type("gk")
    host.onMark = {
        host.text += host.marked
        host.marked = ""
        host.commit(insert: false)
        host.deactivate()
    }
    host.type("s")
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
}

@Test("deactivate 가 없는 source 전환도 조합을 한 번만 확정한다")
func sourceChangeWithoutDeactivation() {
    let host = Host()
    host.type("gks")
    host.sourceChanged(selected: true)
    #expect(host.marked == "한")
    host.sourceChanged(selected: false)
    host.sourceChanged(selected: false)
    host.deactivate()
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
}

@Test("질의 도중 source 를 떠나면 candidate 와 Session 을 같이 정리한다")
func sourceChangeDuringHanjaQuery() {
    let host = Host()
    host.driver.perform({ session in
        session.handle(optionReturn, mode: .korean, selectedText: {
            host.sourceChanged(selected: false)
            host.driver.activate()
            return "한자"
        })
    }, apply: { host.apply($0.actions) })
    #expect(host.text == "한자")
    #expect(host.marked.isEmpty)
    #expect(!host.candidates)
}

@Test("insertText 도중 다른 controller 가 활성화돼도 옛 client 에만 확정한다")
func anotherControllerDuringInsert() {
    let first = Host()
    let second = Host()
    first.type("gks")
    first.onInsert = { first.deactivate(); second.driver.activate() }
    first.type("r")
    second.type("rk")
    #expect(first.text == "한ㄱ")
    #expect(first.marked.isEmpty)
    #expect(second.text.isEmpty)
    #expect(second.marked == "가")
}

@Test("flush 의 insertText 도중 다시 온 commit·deactivate 도 글자를 중복하지 않는다")
func reentryDuringFlush() {
    let host = Host()
    host.type("gks")
    host.onInsert = { host.commit(); host.deactivate() }
    host.commit()
    #expect(host.text == "한")
    #expect(host.marked.isEmpty)
    #expect(host.driver.composing.isEmpty)
}

@Test("candidate 표시 준비도 재진입한 종료와 flush 가 끝난 뒤에 실행한다")
func presentationAfterLifecycleDrain() {
    let host = Host()
    var presented = false
    host.driver.perform({ $0.handle(optionReturn, mode: .korean, selectedText: { "한자" }) }, apply: {
        host.apply($0.actions)
        host.driver.afterEvent {
            #expect(!host.driver.isHandlingEvent)
            #expect(!host.candidates)
            #expect(host.text == "한자")
            presented = true
        }
        #expect(!presented)
        host.sourceChanged(selected: false)
    })
    #expect(presented)
}
