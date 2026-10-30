import Foundation
import Testing
@testable import FingerKitCore

struct CommunityTests {
    @Test func everyPageHasPicksAndIDsAreUnique() {
        for page in CommunityPage.allCases {
            #expect(!CommunityPick.picks(for: page).isEmpty)
        }
        let ids = CommunityPick.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyPickAppliesToFreshSettings() {
        for pick in CommunityPick.all {
            var s = Settings.fresh
            #expect(!pick.isAdded(in: s), "\(pick.id) boş ayarda eklenmiş görünüyor")
            #expect(pick.replaces(in: s).isEmpty, "\(pick.id) boş ayarda bir şeyin yerine geçiyor")
            pick.apply(to: &s)
            #expect(pick.isAdded(in: s), "\(pick.id) eklenince eklenmiş görünmüyor")
            // İkinci kez eklemek bir şey değiştirmez
            let once = s
            pick.apply(to: &s)
            #expect(s == once, "\(pick.id) iki kez eklenince değişti")
        }
    }

    @Test func applyTurnsSectionOn() {
        var s = Settings.fresh
        CommunityPick.all.first { $0.id == "clipboard-v" }!.apply(to: &s)
        #expect(s.hyper.enabled && s.clipboard.enabled && s.clipboard.key == "V")
        #expect(s.hyper.bindings.isEmpty && !s.hyper.move)
        #expect(s.hyper.snaps.allSatisfy { !$0.enabled })
    }

    @Test func tipTapAddsBothSides() {
        var s = Settings.fresh
        CommunityPick.all.first { $0.id == "tiptap-tabs" }!.apply(to: &s)
        #expect(s.shortcut(for: .tipTapLeft, app: nil)?.display == "⇧⌘[")
        #expect(s.shortcut(for: .tipTapRight, app: nil)?.display == "⇧⌘]")
    }

    @Test func replacingIsReported() {
        var s = Settings.defaults
        // Caps Lock + C ilk sürümde VS Code'u açar; panoyu C'ye alan öneri onun yerine geçer
        let pick = CommunityPick("clipboard-c", .clipboard, title: "", why: "",
                                 demo: CommunityDemo(.keys(["⇪", "C"]), .clipboardList), [.clipboard(keyCode: 8, key: "C")])
        #expect(pick.replaces(in: s).count == 2)
        pick.apply(to: &s)
        #expect(s.hyper.binding(for: 8) == nil)
        #expect(s.clipboard.keyCode == 8)

        // Aynı hareket başka kısayola bağlıysa
        s.apps[0].bindings.append(GestureBinding(gesture: .fiveFingerTap, shortcut: Shortcut(keyCode: 46, modifiers: [.command], key: "M")))
        let full = CommunityPick.all.first { $0.id == "full-screen" }!
        #expect(full.replaces(in: s).count == 1)
        full.apply(to: &s)
        #expect(s.apps[0].bindings.filter { $0.gesture == .fiveFingerTap }.count == 1)
        #expect(s.shortcut(for: .fiveFingerTap, app: nil)?.display == "⌃⌘F")
    }

    @Test func radialPinsUseFreeSlots() {
        var s = Settings.fresh
        s.radial.pinApp(RadialApp(bundleID: "x", name: "X"), at: 0)
        CommunityPick.all.first { $0.id == "radial-finder" }!.apply(to: &s)
        #expect(s.radial.appPins.compactMap { $0?.bundleID } == ["x", "com.apple.finder"])
        #expect(s.radial.enabled)
    }

    @Test func pastePlainSendsMatchStyle() {
        var s = Settings.fresh
        CommunityPick.all.first { $0.id == "notes-paste-plain" }!.apply(to: &s)
        let action = s.appShortcuts.action(keyCode: 9, modifiers: [.shift, .command], app: "com.apple.Notes")
        #expect(action?.display == "⌥⇧⌘V")
        #expect(s.appShortcuts.hasPlainTriggers)
    }
}
