import Foundation
import Testing
@testable import FingerKitCore

struct AppShortcutTests {
    let ctrlCmdN = Shortcut(keyCode: 45, modifiers: [.control, .command], key: "N")
    let hyperD = Shortcut(keyCode: 2, modifiers: .hyper, key: "D")

    @Test func matchesOnlyInItsApp() {
        var s = AppShortcutSettings()
        s.set(AppShortcut(trigger: ctrlCmdN, action: .menu(["Dosya", "Yeni"])), in: "com.apple.TextEdit", name: "TextEdit")
        #expect(s.action(keyCode: 45, modifiers: [.control, .command], app: "com.apple.TextEdit") == .menu(["Dosya", "Yeni"]))
        #expect(s.action(keyCode: 45, modifiers: [.control, .command], app: "com.apple.Safari") == nil)
        #expect(s.action(keyCode: 45, modifiers: [.command], app: "com.apple.TextEdit") == nil)
        s.enabled = false
        #expect(s.action(keyCode: 45, modifiers: [.control, .command], app: "com.apple.TextEdit") == nil)
    }

    @Test func sameTriggerReplacesOldRow() {
        var s = AppShortcutSettings()
        s.set(AppShortcut(trigger: ctrlCmdN, action: .menu(["Yeni"])), in: "a", name: "A")
        s.set(AppShortcut(trigger: ctrlCmdN, action: .shortcut(Shortcut(keyCode: 45, modifiers: [.command], key: "N"))), in: "a", name: "A")
        #expect(s.apps.count == 1)
        #expect(s.apps[0].shortcuts.count == 1)
        #expect(s.apps[0].shortcuts[0].action.display == "⌘N")
    }

    @Test func plainTriggersAndValidity() {
        var s = AppShortcutSettings()
        #expect(!s.hasPlainTriggers)
        s.set(AppShortcut(trigger: hyperD, action: .menu(["Kopyala"])), in: "a", name: "A")
        #expect(!s.hasPlainTriggers)
        #expect(hyperD.isHyper && hyperD.triggerDisplay == "⇪ + D")
        s.set(AppShortcut(trigger: ctrlCmdN, action: .menu(["Yeni"])), in: "a", name: "A")
        #expect(s.hasPlainTriggers)
        #expect(!Shortcut(keyCode: 0, modifiers: [], key: "A").isValidTrigger)
        #expect(Shortcut(keyCode: 122, modifiers: [], key: "F1").isValidTrigger)
        #expect(!Shortcut(mouse: .left, modifiers: [.command]).isValidTrigger)
    }

    @Test func roundTripsAndOldFilesLoad() throws {
        var settings = Settings.defaults
        settings.appShortcuts.set(AppShortcut(trigger: ctrlCmdN, action: .menu(["Dosya", "Yeni"])), in: "a", name: "A")
        settings.appShortcuts.set(AppShortcut(trigger: hyperD, action: .shortcut(Shortcut(mouse: .middle))), in: "a", name: "A")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(settings)
        // Kimlikler (id) dosyaya yazılmaz; karşılaştırma dosya içeriğiyle
        let again = try JSONDecoder().decode(Settings.self, from: data)
        #expect(try encoder.encode(again) == data)
        #expect(again.appShortcuts.apps[0].shortcuts.map(\.action.display) == ["Dosya › Yeni", "Orta tık"])

        let old = #"{"enabled": true, "apps": []}"#
        let loaded = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        #expect(loaded.appShortcuts.enabled && loaded.appShortcuts.apps.isEmpty)
    }
}
