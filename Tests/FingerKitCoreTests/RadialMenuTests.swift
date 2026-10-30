import Foundation
import Testing
@testable import FingerKitCore

struct RadialMenuTests {
    let g = RadialGeometry(inner: 40, outer: 160, reach: 90)

    @Test func centerAndFarAwayPickNothing() {
        #expect(g.pick(dx: 10, dy: 10, top: 6, bottom: 6) == nil)
        #expect(g.pick(dx: 0, dy: 300, top: 6, bottom: 6) == nil)
        #expect(g.pick(dx: 0, dy: 100, top: 0, bottom: 6) == nil)
    }

    @Test func slicesGoLeftToRight() {
        // Üst yarı: sol baş, sağ son
        #expect(g.pick(dx: -100, dy: 5, top: 6, bottom: 6) == .top(0))
        #expect(g.pick(dx: 100, dy: 5, top: 6, bottom: 6) == .top(5))
        #expect(g.pick(dx: -5, dy: 100, top: 2, bottom: 6) == .top(0))
        #expect(g.pick(dx: 5, dy: 100, top: 2, bottom: 6) == .top(1))
        // Alt yarı da soldan sağa
        #expect(g.pick(dx: -100, dy: -5, top: 6, bottom: 3) == .bottom(0))
        #expect(g.pick(dx: 0, dy: -100, top: 6, bottom: 3) == .bottom(1))
        #expect(g.pick(dx: 100, dy: -5, top: 6, bottom: 3) == .bottom(2))
        // Halkanın biraz dışı da seçer
        #expect(g.pick(dx: 0, dy: -220, top: 6, bottom: 1) == .bottom(0))
    }

    @Test func sliceAnglesMatchPicking() {
        for n in 1...6 {
            for i in 0..<n {
                for top in [true, false] {
                    let a = RadialGeometry.angle(top: top, index: i, count: n)
                    let pick = g.pick(dx: cos(a) * 100, dy: sin(a) * 100, top: n, bottom: n)
                    #expect(pick == (top ? .top(i) : .bottom(i)))
                }
            }
        }
    }

    @Test func cornerIsBottomLeft() {
        let s = RadialMenuSettings()
        #expect(s.corner == .bottomLeft)
        #expect(s.isCorner(x: 0.1, y: 0.1))
        #expect(!s.isCorner(x: 0.1, y: 0.5))
        #expect(!s.isCorner(x: 0.9, y: 0.1))
        #expect(RadialCorner.topRight.contains(x: 0.9, y: 0.9))
        #expect(!RadialCorner.topRight.contains(x: 0.1, y: 0.1))
    }

    @Test func dockOrderSkipsFolders() {
        let tiles: [[String: Any]] = (1...8).map { ["tile-data": ["bundle-identifier": "app\($0)", "file-label": "App \($0)"]] }
            + [["tile-data": ["file-label": "Klasör"]]]
        let apps = RadialApp.fromDock(tiles)
        #expect(apps.count == 8)
        #expect(apps.first == RadialApp(bundleID: "app1", name: "App 1"))
    }

    @Test func oldSettingsGetRadialDefaults() throws {
        // İlk sürümün "apps" alanı artık okunmaz
        let json = #"{"apps": [], "radial": {"enabled": false, "apps": [{"bundleID": "a", "name": "A"}]}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(!s.radial.enabled)
        #expect(s.radial.appPins.isEmpty)
        var r = s.radial
        r.pinApp(RadialApp(bundleID: "x", name: "X"), at: 2)
        r.pinShortcut(RadialShortcut(title: "Yeni", keys: "⌘N", action: .menu(["Dosya", "Yeni"])), at: 0, for: "com.apple.Notes")
        let back = try JSONDecoder().decode(RadialMenuSettings.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }

    @Test func pinsKeepTheirSlot() {
        let a = ["a", "b", "c", "d", "e", "f", "g"].map { RadialApp(bundleID: $0, name: $0.uppercased()) }
        var s = RadialMenuSettings()
        s.pinApp(RadialApp(bundleID: "z", name: "Z"), at: 2)
        s.pinApp(RadialApp(bundleID: "c", name: "C"), at: 0)
        let slots = s.apps(auto: a)
        #expect(slots.map(\.item.bundleID) == ["c", "a", "z", "b", "d", "e"])
        #expect(slots.map(\.pinned) == [true, false, true, false, false, false])
        // Aynı uygulamayı başka yuvaya sabitlemek eskisini kaldırır
        s.pinApp(RadialApp(bundleID: "c", name: "C"), at: 5)
        #expect(s.appPins.compactMap { $0?.bundleID } == ["z", "c"])
        s.pinApp(nil, at: 5)
        s.pinApp(nil, at: 2)
        #expect(s.appPins.isEmpty)
        // Otomatik liste kısaysa boş yuvalar atlanır
        #expect(RadialMenuSettings().apps(auto: Array(a.prefix(2))).count == 2)
    }

    @Test func popularListUsesMenuWhenPresent() {
        let menu = [
            MenuShortcutEntry(path: ["Dosya", "Yeni Sekme"], keys: "⌘T"),
            MenuShortcutEntry(path: ["Görüntü", "Kenar Çubuğunu Göster"], keys: "⇧⌘L"),
        ]
        let list = PopularShortcuts.auto(for: "com.apple.Safari", menu: menu)
        #expect(list.first == RadialShortcut(title: "Yeni Sekme", keys: "⌘T", action: .menu(["Dosya", "Yeni Sekme"])))
        #expect(list[1].keys == "⇧⌘T")
        if case .shortcut = list[1].action {} else { Issue.record("menüde olmayan kısayol tuş olarak gönderilmeli") }
        #expect(list.count == 7)
        #expect(list.last?.title == "Kenar Çubuğunu Göster")
        // Listesi olmayan uygulama: yalnız menü
        #expect(PopularShortcuts.auto(for: "x", menu: menu).map(\.keys) == ["⌘T", "⇧⌘L"])
    }

    @Test func autoPickPrefersKnownItems() {
        let entries = [
            MenuShortcutEntry(path: ["Düzen", "Geri Al"], keys: "⌘Z"),
            MenuShortcutEntry(path: ["Dosya", "Kapat"], keys: "⌘W"),
            MenuShortcutEntry(path: ["Görüntü", "Kenar Çubuğu"], keys: "⌃⌘S"),
            MenuShortcutEntry(path: ["Dosya", "Yeni Sekme"], keys: "⌘T"),
            MenuShortcutEntry(path: ["Dosya", "Çık"], keys: "⌘Q"),
            MenuShortcutEntry(path: ["Dosya", "Kaydet…"], keys: "⌘S"),
            MenuShortcutEntry(path: ["Dosya", "Aynı tuş"], keys: "⌘S"),
        ]
        let picked = MenuShortcutEntry.autoPick(entries, limit: 4).map(\.title)
        #expect(picked == ["Yeni Sekme", "Kaydet…", "Kapat", "Kenar Çubuğu"])
        #expect(MenuShortcutEntry.autoPick(entries).last?.title == "Geri Al")
    }

    @Test func menuKeyNames() {
        func name(_ c: String?, _ g: Int? = nil, _ v: Int? = nil) -> String? { MenuShortcutEntry.keyName(char: c, glyph: g, virtualKey: v) }
        #expect(MenuShortcutEntry.keys(key: name("t")!, modifiers: 1) == "⇧⌘T")
        #expect(MenuShortcutEntry.keys(key: name("i")!, modifiers: 0) == "⌘I")
        #expect(MenuShortcutEntry.keys(key: name("s")!, modifiers: 4) == "⌃⌘S")
        #expect(name("\u{F703}") == "→")
        #expect(name("", 100) == "←")
        #expect(MenuShortcutEntry.keys(key: name(nil, 9)!, modifiers: 8) == "Boşluk")
        #expect(name("\u{8}") == nil)
        // Hazır listedeki gösterimle aynı olmalı (eşleşme buna dayanıyor)
        #expect(Shortcut(keyCode: 49, modifiers: [], key: "Boşluk").display == "Boşluk")
    }
}

struct RadialLabelTests {
    @Test func sideLabelsAreWiderThanTopOnes() {
        let g = RadialGeometry()
        let side = g.labelWidth(angle: RadialGeometry.angle(top: true, index: 0, count: 6), count: 6, radius: 138, height: 40)
        let top = g.labelWidth(angle: RadialGeometry.angle(top: true, index: 2, count: 6), count: 6, radius: 138, height: 40)
        #expect(side > top)
        #expect(top >= 50)
        #expect(side <= g.outer - g.inner)
    }
}

@Suite struct SystemControlTests {
    @Test func oldFilesGetDefaultControlsAndUnknownNamesAreSkipped() throws {
        let old = try JSONDecoder().decode(RadialMenuSettings.self, from: Data(#"{"enabled": true}"#.utf8))
        #expect(old.controls == SystemControl.defaults)
        let newer = try JSONDecoder().decode(RadialMenuSettings.self, from: Data(#"{"controls": ["wifi", "hologram", "volume"]}"#.utf8))
        #expect(newer.controls == [.wifi, .volume])
    }

    @Test func controlsLeaveRoomForShortcuts() {
        var s = RadialMenuSettings(controls: [.bluetooth, .volume, .brightness, .airDrop])
        #expect(s.shortcutRoom == 2)
        let auto = (0..<6).map { RadialShortcut(title: "\($0)", keys: "⌘\($0)", action: .menu(["\($0)"])) }
        #expect(s.shortcuts(for: "x", auto: auto).count == 2)
        s.addControl(.wifi)
        s.addControl(.focus)
        s.addControl(.darkMode)
        #expect(s.controls.count == 6)
        #expect(s.shortcutRoom == 0)
        s.addControl(.wifi)
        #expect(s.controls.count == 6)
    }

    @Test func sliderLevelFollowsRadius() {
        #expect(RadialTop.level(radius: 50, inner: 60, outer: 180) == 0)
        #expect(RadialTop.level(radius: 120, inner: 60, outer: 180) == 0.5)
        #expect(RadialTop.level(radius: 400, inner: 60, outer: 180) == 1)
    }

    @Test func airDropModeReadsSharingdValues() {
        #expect(AirDropMode(discoverable: "Everyone") == .everyone)
        #expect(AirDropMode(discoverable: "Contacts Only") == .contacts)
        #expect(AirDropMode(discoverable: "Off") == .off)
        #expect(AirDropMode(discoverable: nil) == .off)
    }
}
