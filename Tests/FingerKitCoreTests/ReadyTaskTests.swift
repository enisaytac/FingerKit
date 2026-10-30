import Foundation
import Testing
@testable import FingerKitCore

struct ReadyTaskTests {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test func everyTaskRoundTrips() throws {
        let extra: [ReadyTask] = [.openApp(bundleID: "com.apple.Notes", name: "Notlar"), .openURL("https://example.com"), .runShortcut("Günaydın")]
        for task in ReadyTask.Group.allCases.flatMap(\.tasks) + extra {
            #expect(try roundTrip(task) == task)
        }
    }

    @Test func labelShowsShortcut() {
        #expect(ReadyTask.minimize.label.hasSuffix("· ⌘M"))
        #expect(ReadyTask.openURL("https://example.com").keys == nil)
        #expect(!ReadyTask.volumeUp.label.contains("·"))
    }

    @Test func gestureWithKeylessTaskSavesWithoutShortcut() throws {
        let binding = GestureBinding(gesture: .threeFingerClick, task: .runShortcut("Odak"))
        #expect(binding.shortcut.isNone)
        let json = String(decoding: try JSONEncoder().encode(binding), as: UTF8.self)
        #expect(!json.contains("keyCode"))
        let back = try roundTrip(binding)
        #expect(back.task == .runShortcut("Odak"))
        #expect(back.shortcut.isNone)
    }

    @Test func keylessTasksDoNotClash() {
        var s = Settings.fresh
        s.apps[0].bindings = [GestureBinding(gesture: .threeFingerClick, task: .volumeUp)]
        let conflicts = s.conflicts(gesture: .fourFingerClick, shortcut: .none, app: AppProfile.everywhere, editing: nil, system: SystemTrackpad())
        #expect(conflicts.isEmpty)
    }

    @Test func urlsAreNormalized() {
        #expect(ReadyTask.normalizedURL("youtube.com") == "https://youtube.com")
        #expect(ReadyTask.normalizedURL("  https://a.org/x ") == "https://a.org/x")
        #expect(ReadyTask.normalizedURL("not a site") == nil)
        #expect(ReadyTask.normalizedURL("") == nil)
    }

    @Test func hyperAndAppActionsCarryTasks() throws {
        let hyper = HyperBinding(keyCode: 46, key: "M", task: .minimize)
        #expect(try roundTrip(hyper).task == .minimize)
        let action = AppAction.task(.openURL("https://example.com"))
        #expect(try roundTrip(action) == action)
        let radial = RadialShortcut(task: .volumeUp)
        #expect(radial.identity != RadialShortcut(task: .volumeDown).identity)
    }
}

struct BackupTests {
    @Test func importShowsWhatChanges() throws {
        let old = Settings.fresh
        var new = Settings.defaults
        new.notify = false
        let back = try Settings.imported(try new.exported())
        #expect(try back.exported() == new.exported())
        #expect(back.changes(to: new).isEmpty)
        let changes = old.changes(to: back)
        #expect(changes.contains { $0.hasPrefix("Hareketler: 0 → 7") })
        #expect(changes.contains { $0.contains("Ekran bildirimi") })
        #expect(old.changes(to: old).isEmpty)
        #expect(throws: (any Error).self) { try Settings.imported(Data("bozuk".utf8)) }
    }
}
