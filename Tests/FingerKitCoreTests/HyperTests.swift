import CoreGraphics
import Foundation
import Testing
@testable import FingerKitCore

struct HyperTests {
    @Test func oldSettingsFileGetsDefaults() throws {
        let json = #"{"enabled": true, "apps": []}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(s.hyper == .defaults)
        #expect(s.hyper.binding(for: 1)?.bundleID == "com.apple.Safari")
    }

    @Test func roundTrip() throws {
        var s = Settings.defaults
        s.hyper.enabled = false
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back.hyper.enabled == false)
        #expect(back.hyper.bindings.map(\.key) == ["S", "N", "F", "C"])
    }

    @Test func sameKeyReplacesOldRow() {
        var h = HyperSettings.defaults
        let mail = HyperBinding(keyCode: 1, key: "S", bundleID: "com.apple.mail", appName: "Mail")
        #expect(h.duplicate(of: 1)?.appName == "Safari")
        h.set(mail)
        #expect(h.bindings.count == 4)
        #expect(h.binding(for: 1)?.appName == "Mail")
    }

    @Test func editingRowIsNotItsOwnDuplicate() {
        let h = HyperSettings.defaults
        let safari = h.bindings[0]
        #expect(h.duplicate(of: safari.keyCode, editing: safari.id) == nil)
    }

    @Test func stageTwoFileGetsSnapsAndVSCode() throws {
        let json = #"{"apps": [], "hyper": {"enabled": true, "bindings": [{"keyCode": 1, "key": "S", "bundleID": "com.apple.Safari", "appName": "Safari"}]}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(s.hyper.snaps.map(\.layout) == SnapLayout.allCases)
        #expect(s.hyper.binding(for: 8)?.bundleID == "com.microsoft.VSCode")
        #expect(s.hyper.snap(for: 123)?.layout == .left)
    }

    @Test func vsCodeNotAddedTwiceOrOverC() throws {
        // Kullanıcı C'yi başka uygulamaya bağlamışsa dokunulmaz
        let json = #"{"apps": [], "hyper": {"bindings": [{"keyCode": 8, "key": "C", "bundleID": "com.apple.iCal", "appName": "Takvim"}]}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(s.hyper.bindings.map(\.appName) == ["Takvim"])
        // Yaslama satırları kayıtlıysa (3. aşama dosyası) VS Code yeniden eklenmez, kapalı satır kapalı kalır
        var h = s.hyper
        h.bindings = []
        h.snaps[0].enabled = false
        let back = try JSONDecoder().decode(HyperSettings.self, from: JSONEncoder().encode(h))
        #expect(back.bindings.isEmpty)
        #expect(back.snaps[0].enabled == false)
        #expect(back.snap(for: 123) == nil)
    }

    @Test func snapFrames() {
        // 1440×900 ekran, üstte 25 menü çubuğu, altta 60 Dock → görünür alan y 25…840
        let v = CGRect(x: 0, y: 25, width: 1440, height: 815)
        #expect(SnapLayout.left.frame(in: v) == CGRect(x: 0, y: 25, width: 720, height: 815))
        #expect(SnapLayout.right.frame(in: v) == CGRect(x: 720, y: 25, width: 720, height: 815))
        #expect(SnapLayout.top.frame(in: v) == CGRect(x: 0, y: 25, width: 1440, height: 408))
        #expect(SnapLayout.bottom.frame(in: v) == CGRect(x: 0, y: 432, width: 1440, height: 408))
        #expect(SnapLayout.fill.frame(in: v) == v)
        // İkinci ekran solda (eksi x): yerleşim o ekranın içinde kalır
        let second = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        #expect(SnapLayout.right.frame(in: second) == CGRect(x: -960, y: 0, width: 960, height: 1050))
    }

    @Test func savedCenterBecomesFill() throws {
        let json = #"{"layout": "center", "keyCode": 49, "key": "Boşluk"}"#
        let snap = try JSONDecoder().decode(SnapBinding.self, from: Data(json.utf8))
        #expect(snap.layout == .fill)
    }

    @Test func tooWideWindowStaysOnRightEdge() {
        let target = CGRect(x: 720, y: 25, width: 720, height: 815)
        #expect(SnapLayout.right.align(CGSize(width: 800, height: 815), to: target) == CGPoint(x: 640, y: 25))
        #expect(SnapLayout.left.align(CGSize(width: 800, height: 815), to: target) == target.origin)
    }

    @Test func moveDefaultsOnAndIsSaved() throws {
        // 3. aşamadan kalan dosyada "move" yok: açık sayılır
        let old = try JSONDecoder().decode(HyperSettings.self, from: Data(#"{"enabled": true, "bindings": [], "snaps": []}"#.utf8))
        #expect(old.move)
        var off = old
        off.move = false
        let back = try JSONDecoder().decode(HyperSettings.self, from: JSONEncoder().encode(off))
        #expect(back.move == false)
    }
}
