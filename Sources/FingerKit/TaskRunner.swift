import AppKit
import FingerKitCore

/// Hazır işi yapar. Kısayolu olan iş o kısayol gönderilerek (işaretli: Caps Lock basılıysa Hyper ona tuş eklemez),
/// olmayanı FingerKit kendisi yapar. Ekran bildirimi açıksa ne yapıldığı ekranın ortasında kısa süre yazar.
enum TaskRunner {
    static func run(_ task: ReadyTask, from source: String) {
        Log.write("\(source) → \(task.label)")
        Toast.show(task.label, symbol: task.symbol)
        if let keys = task.keys {
            KeySender.send(keys, marked: true)
            return
        }
        switch task {
        case .snap(let layout): WindowSnapper.snap(layout)
        case .openApp(let bundleID, let name): AppLauncher.open(bundleID, name: name, from: source)
        case .openURL(let text):
            guard let url = URL(string: text) else { Log.write("HATA: adres açılamadı: \(text)"); return }
            NSWorkspace.shared.open(url)
        case .runShortcut(let name): Shortcuts.run(name)
        case .volumeUp: MediaKey.send(MediaKey.soundUp)
        case .volumeDown: MediaKey.send(MediaKey.soundDown)
        case .mute: MediaKey.send(MediaKey.mute)
        case .playPause: MediaKey.send(MediaKey.play)
        case .nextTrack: MediaKey.send(MediaKey.next)
        case .previousTrack: MediaKey.send(MediaKey.previous)
        default: break
        }
    }
}

/// Mac'in kendi ses ve müzik tuşları (klavyedeki F10-F12, F7-F9): basılmış gibi gönderilir,
/// ekranda sesin göstergesi çıkar, müzik hangi uygulamada çalıyorsa o dinler.
enum MediaKey {
    // IOKit/hidsystem/ev_keymap.h
    static let soundUp: Int32 = 0, soundDown: Int32 = 1, mute: Int32 = 7
    static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18

    static func send(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// Apple Kestirmeler: Mac'teki kestirmeler listelenir ve adıyla çalıştırılır (`shortcuts` komutu, macOS 12+)
enum Shortcuts {
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    static func run(_ name: String) {
        let p = Process()
        p.executableURL = tool
        p.arguments = ["run", name]
        p.terminationHandler = { proc in
            if proc.terminationStatus != 0 { Log.write("HATA: kestirme çalışmadı: \(name) (\(proc.terminationStatus))") }
        }
        do { try p.run() } catch { Log.write("HATA: kestirme başlatılamadı: \(error.localizedDescription)") }
    }

    /// Mac'teki kestirmelerin adları (arka planda okunur)
    static func list(done: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            let out = Pipe()
            p.executableURL = tool
            p.arguments = ["list"]
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            var names: [String] = []
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            }
            DispatchQueue.main.async { done(names) }
        }
    }
}
