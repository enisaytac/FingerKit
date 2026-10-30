import Foundation
import Testing
@testable import FingerKitCore

struct ConflictTests {
    let cmdT = Shortcut(keyCode: 17, modifiers: [.command], key: "T")
    let cmdW = Shortcut(keyCode: 13, modifiers: [.command], key: "W")

    func settings() -> Settings {
        Settings(apps: [
            AppProfile(bundleID: AppProfile.everywhere, name: "Her yerde", bindings: [
                GestureBinding(gesture: .threeFingerClick, shortcut: cmdW),
            ]),
            AppProfile(bundleID: "com.apple.Safari", name: "Safari", bindings: [
                GestureBinding(gesture: .threeFingerClick, shortcut: cmdT),
            ]),
        ])
    }

    @Test func sameGestureInSameList() {
        let kinds = settings().conflicts(gesture: .threeFingerClick, shortcut: cmdW, app: "com.apple.Safari",
                                         system: SystemTrackpad()).map(\.kind)
        #expect(kinds.contains(.duplicate))
        #expect(kinds.contains(.override))
    }

    @Test func editingRowIsNotItsOwnDuplicate() {
        let s = settings()
        let id = s.apps[1].bindings[0].id
        let kinds = s.conflicts(gesture: .threeFingerClick, shortcut: cmdT, app: "com.apple.Safari",
                                editing: id, system: SystemTrackpad()).map(\.kind)
        #expect(!kinds.contains(.duplicate))
    }

    @Test func everywhereWarnsAboutAppOverride() {
        let kinds = settings().conflicts(gesture: .threeFingerClick, shortcut: cmdW, app: AppProfile.everywhere,
                                         system: SystemTrackpad()).map(\.kind)
        #expect(kinds.contains(.override))
    }

    @Test func sameShortcutOnOtherGesture() {
        let kinds = settings().conflicts(gesture: .fourFingerTap, shortcut: cmdT, app: "com.apple.Safari",
                                         system: SystemTrackpad()).map(\.kind)
        #expect(kinds == [.sameShortcut])
    }

    @Test func threeFingerDragClashesWithThreeFingerSwipes() {
        let system = SystemTrackpad { $0 == "TrackpadThreeFingerDrag" ? 1 : 0 }
        #expect(system.conflict(with: .threeFingerSwipeLeft) != nil)
        #expect(system.conflict(with: .threeFingerSwipeUp) != nil)
        #expect(system.conflict(with: .fourFingerSwipeLeft) == nil)
        #expect(system.conflict(with: .threeFingerClick) == nil)
    }

    @Test func systemSwipesOnlyWhenTurnedOn() {
        let on = SystemTrackpad { $0 == "TrackpadFourFingerVertSwipeGesture" ? 2 : 0 }
        #expect(on.conflict(with: .fourFingerSwipeUp) != nil)
        #expect(SystemTrackpad().conflict(with: .fourFingerSwipeUp) == nil)
    }
}

struct MouseShortcutTests {
    @Test func mouseShortcutRoundTrip() throws {
        let s = Shortcut(mouse: .left, modifiers: [.command])
        let data = try JSONEncoder().encode(s)
        #expect(String(decoding: data, as: UTF8.self).contains("\"mouse\":\"left\""))
        let back = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(back == s)
        #expect(back.display == "⌘ Tık")
        #expect(back.spoken == "Cmd + Tık")
    }

    @Test func keyShortcutStillReadsOldFiles() throws {
        let json = #"{"keyCode": 17, "modifiers": ["command"], "key": "T"}"#
        let s = try JSONDecoder().decode(Shortcut.self, from: Data(json.utf8))
        #expect(s.mouse == nil && s.display == "⌘T")
    }
}
