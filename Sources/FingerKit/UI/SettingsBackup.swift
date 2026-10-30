import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FingerKitCore

/// Ayar yedekleme ve paylaşma: tüm ayarlar tek dosyaya kaydedilir; başka Mac'e taşınır ya da arkadaşa gönderilir.
/// İçe alırken neyin değişeceği önce gösterilir, onaylanınca uygulanır. Pano kopyaları dosyaya girmez.
enum SettingsBackup {
    static func export(_ engine: Engine) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "FingerKit ayarları") + ".json"
        panel.message = String(localized: "Ayarların bu dosyaya kaydedilir. Pano kopyaların dosyaya girmez.")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try engine.settings.exported().write(to: url, options: .atomic)
            Log.write("Ayarlar dışa aktarıldı: \(url.lastPathComponent)")
        } catch {
            alert(String(localized: "Dosya kaydedilemedi"), error.localizedDescription)
        }
    }

    static func importFile(_ engine: Engine) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "İçe alınacak FingerKit ayar dosyasını seç")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let new: FingerKitCore.Settings
        do {
            new = try FingerKitCore.Settings.imported(try Data(contentsOf: url))
        } catch {
            alert(String(localized: "Bu dosya okunamadı"), String(localized: "FingerKit'in kaydettiği bir ayar dosyası seç."))
            return
        }
        let changes = engine.settings.changes(to: new)
        guard !changes.isEmpty else {
            alert(String(localized: "Değişen bir şey yok"), String(localized: "Bu dosyadaki ayarlar şu ankilerle aynı."))
            return
        }
        let confirm = NSAlert()
        confirm.messageText = String(localized: "Bu ayarlar içe alınsın mı?")
        confirm.informativeText = String(localized: "Şunlar değişecek:") + "\n\n" + changes.map { "• " + $0 }.joined(separator: "\n")
            + "\n\n" + String(localized: "Şu anki ayarların önce yedeklenir (ayar klasöründe).")
        confirm.addButton(withTitle: String(localized: "İçe al"))
        confirm.addButton(withTitle: String(localized: "Vazgeç"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        // Geri dönmek isteyen için eskisi saklanır
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = engine.settingsFileURL.deletingLastPathComponent().appendingPathComponent("ayarlar-once-\(stamp).json")
        try? engine.settings.exported().write(to: backup)
        engine.settings = new
        Log.write("Ayarlar içe alındı (\(changes.count) bölüm değişti; eskisi \(backup.lastPathComponent))")
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

/// Üst çubukta: ayarları dosyaya kaydet ya da dosyadan içe al
struct BackupButton: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        Menu {
            Button {
                SettingsBackup.export(engine)
            } label: {
                Label(String(localized: "Ayarları dosyaya kaydet…"), systemImage: "square.and.arrow.up")
            }
            Button {
                SettingsBackup.importFile(engine)
            } label: {
                Label(String(localized: "Ayarları dosyadan içe al…"), systemImage: "square.and.arrow.down")
            }
        } label: {
            Label(String(localized: "Yedekle ve paylaş"), systemImage: "externaldrive")
        }
        .help(String(localized: "Ayarları tek dosyaya kaydet; başka Mac'e taşı ya da arkadaşına gönder"))
    }
}
