import Foundation
import Testing
@testable import FingerKitCore

/// Sahte trackpad: parmak koyar, kaydırır, kaldırır; kareleri tanıyıcıya verir.
final class FakePad {
    let recognizer = GestureRecognizer(widthMM: 130, heightMM: 80)
    var time = 0.0
    var fingers: [Int32: (x: Double, y: Double)] = [:]
    var fired: [Gesture] = []
    var taps: [Int] = []
    var timers: [(at: Double, work: () -> Void)] = []

    init(wanted: Set<Gesture>? = nil) {
        recognizer.isWanted = { wanted?.contains($0) ?? true }
        recognizer.onGesture = { [unowned self] in fired.append($0) }
        recognizer.onTap = { [unowned self] in taps.append($0) }
        recognizer.schedule = { [unowned self] delay, work in timers.append((time + delay, work)) }
    }

    func frame() {
        let touches = fingers.map { Touch(id: $0.key, x: $0.value.x, y: $0.value.y) }
        recognizer.process(TouchFrame(time: time, touches: touches))
    }

    /// Zamanı ilerletir; süresi dolan zamanlayıcıları çalıştırır
    func wait(_ seconds: Double) {
        let end = time + seconds
        while let i = timers.indices.min(by: { timers[$0].at < timers[$1].at }), timers[i].at <= end {
            let t = timers.remove(at: i)
            time = t.at
            t.work()
        }
        time = end
    }

    func put(_ points: [(Double, Double)], firstID: Int32 = 1) {
        for (i, p) in points.enumerated() { fingers[firstID + Int32(i)] = p }
        frame()
    }

    /// Basılı tüm parmakları (dx, dy) kadar (0-1 ölçeğinde) adım adım kaydırır
    func move(dx: Double, dy: Double, steps: Int = 10, duration: Double = 0.15) {
        for _ in 0..<steps {
            wait(duration / Double(steps))
            for id in fingers.keys { fingers[id]!.x += dx / Double(steps); fingers[id]!.y += dy / Double(steps) }
            frame()
        }
    }

    func lift(_ ids: [Int32]? = nil) {
        for id in ids ?? Array(fingers.keys) { fingers[id] = nil }
        frame()
    }

    func tap(_ points: [(Double, Double)], hold: Double = 0.08) {
        put(points)
        wait(hold)
        lift()
    }
}

let fourFingers = [(0.3, 0.5), (0.4, 0.55), (0.5, 0.55), (0.6, 0.5)]
let threeFingers = [(0.35, 0.5), (0.45, 0.55), (0.55, 0.5)]
let twoFingers = [(0.4, 0.5), (0.55, 0.5)]

@Test func fourFingerSwipeUpIsRecognized() {
    let pad = FakePad()
    pad.put(fourFingers)
    pad.move(dx: 0, dy: 0.25)
    pad.lift()
    #expect(pad.fired == [.fourFingerSwipeUp])
}

@Test func swipeFiresOnlyOncePerTouch() {
    let pad = FakePad()
    pad.put(fourFingers)
    pad.move(dx: 0, dy: -0.25)
    pad.move(dx: -0.3, dy: 0)
    pad.lift()
    #expect(pad.fired == [.fourFingerSwipeDown])
}

@Test func unwantedSwipeIsIgnored() {
    let pad = FakePad(wanted: [.fourFingerSwipeUp])
    pad.put(fourFingers)
    pad.move(dx: -0.3, dy: 0)
    pad.lift()
    #expect(pad.fired.isEmpty)
}

@Test func fingersLandingOneByOneStillMakeFourFingerSwipe() {
    let pad = FakePad(wanted: [.fourFingerSwipeLeft])
    for (i, p) in fourFingers.enumerated() {
        pad.fingers[Int32(i + 1)] = p
        pad.frame()
        pad.wait(0.01)
    }
    pad.move(dx: -0.25, dy: 0)
    pad.lift()
    #expect(pad.fired == [.fourFingerSwipeLeft])
}

@Test func smallMovementIsNotASwipe() {
    let pad = FakePad()
    pad.put(fourFingers)
    pad.move(dx: 0.03, dy: 0.03, duration: 1)
    pad.lift()
    #expect(pad.fired.isEmpty)
}

@Test func threeFingerTap() {
    let pad = FakePad()
    pad.tap(threeFingers)
    pad.wait(1)
    #expect(pad.fired == [.threeFingerTap])
}

@Test func slowTouchIsNotATap() {
    let pad = FakePad()
    pad.tap(threeFingers, hold: 0.6)
    pad.wait(1)
    #expect(pad.fired.isEmpty)
}

@Test func twoFingerDoubleTap() {
    let pad = FakePad(wanted: [.twoFingerDoubleTap])
    pad.tap(twoFingers)
    pad.wait(0.12)
    pad.tap(twoFingers)
    pad.wait(1)
    #expect(pad.fired == [.twoFingerDoubleTap])
    #expect(pad.taps == [2, 2])
}

@Test func twoTapsTooFarApartAreNotADoubleTap() {
    let pad = FakePad(wanted: [.twoFingerDoubleTap])
    pad.tap(twoFingers)
    pad.wait(0.6)
    pad.tap(twoFingers)
    pad.wait(1)
    #expect(pad.fired.isEmpty)
}

@Test func singleTapWaitsForPossibleDoubleTap() {
    let pad = FakePad(wanted: [.threeFingerTap, .threeFingerDoubleTap])
    pad.tap(threeFingers)
    #expect(pad.fired.isEmpty)
    pad.wait(0.5)
    #expect(pad.fired == [.threeFingerTap])

    let pad2 = FakePad(wanted: [.threeFingerTap, .threeFingerDoubleTap])
    pad2.tap(threeFingers)
    pad2.wait(0.1)
    pad2.tap(threeFingers)
    pad2.wait(1)
    #expect(pad2.fired == [.threeFingerDoubleTap])
}

@Test func secondTapStartedInTimeButEndingLateIsStillDecided() {
    let pad = FakePad(wanted: [.threeFingerTap, .threeFingerDoubleTap])
    pad.tap(threeFingers)
    pad.wait(0.25)
    // İkinci dokunuş süre içinde başladı ama zamanlayıcı dolarken hâlâ sürüyor
    pad.put(threeFingers)
    pad.wait(0.1)
    pad.lift()
    pad.wait(1)
    #expect(pad.fired == [.threeFingerDoubleTap])
}

@Test func tipTapLeftAndRight() {
    let pad = FakePad()
    pad.put([(0.5, 0.5)])
    pad.wait(0.4)
    pad.fingers[2] = (0.3, 0.5)
    pad.frame()
    pad.wait(0.08)
    pad.lift([2])
    pad.wait(0.3)
    pad.fingers[3] = (0.7, 0.5)
    pad.frame()
    pad.wait(0.08)
    pad.lift([3])
    pad.wait(0.3)
    pad.lift()
    pad.wait(1)
    #expect(pad.fired == [.tipTapLeft, .tipTapRight])
}

@Test func edgeSwipeFromLeft() {
    let pad = FakePad()
    pad.put([(0.03, 0.5)])
    pad.move(dx: 0.2, dy: 0.01)
    pad.lift()
    #expect(pad.fired == [.edgeSwipeFromLeft])
}

@Test func movementInTheMiddleIsNotAnEdgeSwipe() {
    let pad = FakePad()
    pad.put([(0.4, 0.5)])
    pad.move(dx: 0.3, dy: 0)
    pad.lift()
    #expect(pad.fired.isEmpty)
}

@Test func cornerTap() {
    let pad = FakePad()
    pad.tap([(0.95, 0.92)])
    #expect(pad.fired == [.cornerTapTopRight])
    pad.tap([(0.5, 0.5)])
    #expect(pad.fired == [.cornerTapTopRight])
}

@Test func clickPreventsTapAndSwipe() {
    let pad = FakePad()
    pad.put(fourFingers)
    let ctx = pad.recognizer.clickContext()
    #expect(ctx.fingers == 4)
    #expect(ctx.movement < 0.5)
    pad.recognizer.markClicked(consumed: true)
    pad.move(dx: 0, dy: 0.3)
    pad.lift()
    pad.wait(1)
    #expect(pad.fired.isEmpty)
}

@Test func clickContextReportsDragMovement() {
    let pad = FakePad()
    pad.put(threeFingers)
    pad.move(dx: 0.05, dy: 0, steps: 3)
    #expect(pad.recognizer.clickContext().movement > 5)
}

// MARK: - Ayarlar

@Test func defaultsHaveSevenGestures() {
    let all = Settings.defaults.apps.flatMap(\.bindings)
    #expect(all.count == 7)
    #expect(Settings.defaults.shortcut(for: .fourFingerSwipeUp, app: "com.apple.Safari")?.display == "⌃⌘F")
    #expect(Settings.defaults.shortcut(for: .fourFingerSwipeLeft, app: "com.apple.Safari")?.display == "⇧⌘←")
    #expect(Settings.defaults.shortcut(for: .fourFingerSwipeLeft, app: "com.apple.finder") == nil)
    #expect(Settings.defaults.shortcut(for: .threeFingerClick, app: nil) == nil)
}

@Test func appSpecificBindingWinsAndDisabledFallsBack() {
    var s = Settings.defaults
    s.apps[1].bindings.append(GestureBinding(gesture: .fourFingerSwipeUp, shortcut: Shortcut(keyCode: 17, modifiers: [.command], key: "T")))
    #expect(s.shortcut(for: .fourFingerSwipeUp, app: "com.apple.Safari")?.key == "T")
    s.apps[1].bindings[s.apps[1].bindings.count - 1].enabled = false
    #expect(s.shortcut(for: .fourFingerSwipeUp, app: "com.apple.Safari")?.key == "F")
}

@Test func settingsFileRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = SettingsFile(url: dir.appendingPathComponent("ayarlar.json"))
    guard case .created = file.load() else { Issue.record("ilk açılış bekleniyordu"); return }
    guard case .loaded(let loaded) = file.load() else { Issue.record("dosya okunamadı"); return }
    // Yeni kullanıcı boş başlar
    #expect(loaded.apps.map(\.bindings.count) == [0])
    #expect(!loaded.hyper.enabled && !loaded.clipboard.enabled && !loaded.radial.enabled)

    try Data("bozuk".utf8).write(to: file.url)
    guard case .recovered(_, let backup, _) = file.load() else { Issue.record("bozuk dosya fark edilmedi"); return }
    #expect(FileManager.default.fileExists(atPath: backup.path))
    try? FileManager.default.removeItem(at: dir)
}
