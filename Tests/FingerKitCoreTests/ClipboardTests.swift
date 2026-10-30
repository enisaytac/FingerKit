import Foundation
import Testing
@testable import FingerKitCore

struct ClipboardTests {
    @Test func newestFirstNoDuplicates() {
        var h = ClipboardHistory()
        h.add("bir")
        h.add("iki")
        h.add("bir")
        h.add("  \n ")
        #expect(h.items.map(\.text) == ["bir", "iki"])
    }

    @Test func linksGoToTheirShelfAndPinsComeFirst() {
        var h = ClipboardHistory()
        h.add("https://example.com/a")
        h.add("düz yazı")
        h.add(ClipItem(kind: .image, text: "Ekran Resmi", date: .now, file: "/tmp/a.png", hash: "abc"))
        h.add("ikinci yazı")
        #expect(h.shelf(.links).map(\.text) == ["https://example.com/a"])
        #expect(h.shelf(.links).first?.host == "example.com")
        #expect(h.shelf(.images).count == 1)
        let older = h.shelf(.texts).last!
        h.togglePin(older.id)
        #expect(h.shelf(.texts).first?.text == "düz yazı")
        // Aynı görsel ikinci kez gelince başa çıkar, çift olmaz
        h.add(ClipItem(kind: .image, text: "kopya", date: .now, hash: "abc"))
        #expect(h.shelf(.images).count == 1)
        #expect(h.shelf(.images).first?.file == "/tmp/a.png")
    }

    @Test func expiresOldButKeepsPinned() {
        let now = Date()
        var h = ClipboardHistory()
        h.add("eski", at: now - 10 * 86_400)
        h.add("sabit eski", at: now - 10 * 86_400)
        h.add("yeni", at: now)
        h.togglePin(h.items.first { $0.text == "sabit eski" }!.id)
        let removed = h.expire(keepDays: 7, now: now)
        #expect(removed.map(\.text) == ["eski"])
        #expect(Set(h.items.map(\.text)) == ["yeni", "sabit eski"])
        h.clear()
        #expect(h.items.map(\.text) == ["sabit eski"])
    }

    @Test func screenshotNames() {
        #expect(ClipboardSettings.isScreenshot(fileName: "Ekran Resmi 2026-10-29 14.02.11.png"))
        #expect(ClipboardSettings.isScreenshot(fileName: "Screen Recording 2026-10-29 at 14.02.mov"))
        #expect(!ClipboardSettings.isScreenshot(fileName: "tatil.png"))
        #expect(!ClipboardSettings.isScreenshot(fileName: ".Ekran Resmi 2026.png"))
    }

    @Test func filterIgnoresCaseTurkish() {
        var h = ClipboardHistory()
        h.add("İstanbul adresi")
        h.add("telefon")
        #expect(h.filtered("istanbul").map(\.text) == ["İstanbul adresi"])
        #expect(h.filtered("ADRES").count == 1)
        #expect(h.filtered("").count == 2)
    }

    @Test func titleAndAge() {
        let item = ClipItem(text: "\n   ilk satır  \nikinci", date: Date(timeIntervalSince1970: 0))
        #expect(item.title() == "ilk satır")
        #expect(ClipItem(text: String(repeating: "a", count: 90), date: .now).title(limit: 10) == "aaaaaaaaaa…")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = Date(timeIntervalSince1970: 1_761_400_000) // 25 Ekim 2025 öğleden sonra
        func age(_ ago: TimeInterval) -> String { ClipItem(text: "x", date: now - ago).age(now: now, calendar: cal) }
        #expect(age(10) == "şimdi")
        #expect(age(120) == "2 dk önce")
        #expect(age(3 * 3600) == "3 sa önce")
        #expect(age(24 * 3600) == "dün")
    }

    @Test func fileRoundTripAndOldSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pano-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var h = ClipboardHistory()
        h.add("şifre123")
        try ClipboardFile(url: url).save(h)
        #expect(ClipboardFile(url: url).load().items.map(\.text) == ["şifre123"])
        // Eski ayar dosyası: pano satırı yok → açık, Caps Lock + V
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"apps": []}"#.utf8))
        #expect(old.clipboard == ClipboardSettings())
        // İlk sürümün pano dosyası: tür yok, bağlantı kendiliğinden tanınır
        let first = try JSONDecoder().decode(ClipItem.self, from: Data(#"{"text": "https://a.org", "date": 0}"#.utf8))
        #expect(first.kind == .link)
    }
}
