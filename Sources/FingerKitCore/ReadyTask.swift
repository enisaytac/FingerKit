import Foundation

/// "Ne yapsın" listesindeki hazır iş. Hareket, Hyper Key, daire menü ve uygulama kısayolları aynı listeyi kullanır.
/// Karşılığı bir kısayol olan işin yanında o kısayol da yazar ("Pencereyi küçült · ⌘M"); öyle işler kısayol
/// gönderilerek yapılır. Kısayolu olmayanları (uygulama aç, site aç, Kestirme, ses) FingerKit kendisi yapar.
public enum ReadyTask: Hashable, Sendable {
    // Pencere ve uygulama
    case minimize, fullScreen, closeWindow, hideApp, quitApp
    case snap(SnapLayout)
    // Tarayıcı
    case newTab, reopenTab, nextTab, previousTab, back, forward, reload
    // Düzen
    case copy, paste, pastePlain, undo
    // Mac
    case spotlight, missionControl, appWindows, nextSpace, previousSpace, screenshot, screenshotTools, lockScreen
    // Ses ve müzik (Mac'in kendi ses tuşları gibi; ekranda sesin göstergesi çıkar)
    case volumeUp, volumeDown, mute, playPause, nextTrack, previousTrack
    // FingerKit'in kendisi yapar
    case openApp(bundleID: String, name: String)
    case openURL(String)
    /// Apple Kestirmeler uygulamasındaki bir kestirme (adıyla)
    case runShortcut(String)

    /// Listede gruplar
    public enum Group: CaseIterable, Sendable {
        case window, browser, edit, mac, media

        public var title: String {
            switch self {
            case .window: String(localized: "Pencere")
            case .browser: String(localized: "Tarayıcı")
            case .edit: String(localized: "Düzen")
            case .mac: "Mac"
            case .media: String(localized: "Ses ve müzik")
            }
        }

        public var tasks: [ReadyTask] {
            switch self {
            case .window: [.minimize, .fullScreen, .closeWindow, .hideApp, .quitApp] + SnapLayout.allCases.map { .snap($0) }
            case .browser: [.newTab, .reopenTab, .nextTab, .previousTab, .back, .forward, .reload]
            case .edit: [.copy, .paste, .pastePlain, .undo]
            case .mac: [.spotlight, .missionControl, .appWindows, .nextSpace, .previousSpace, .screenshot, .screenshotTools, .lockScreen]
            case .media: [.volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .previousTrack]
            }
        }
    }

    public var title: String {
        switch self {
        case .minimize: String(localized: "Pencereyi küçült")
        case .fullScreen: String(localized: "Tam ekran")
        case .closeWindow: String(localized: "Pencereyi ya da sekmeyi kapat")
        case .hideApp: String(localized: "Uygulamayı gizle")
        case .quitApp: String(localized: "Uygulamadan çık")
        case .snap(let layout): String(localized: "Pencere: \(layout.title)")
        case .newTab: String(localized: "Yeni sekme")
        case .reopenTab: String(localized: "Kapanan sekmeyi geri aç")
        case .nextTab: String(localized: "Sonraki sekme")
        case .previousTab: String(localized: "Önceki sekme")
        case .back: String(localized: "Geri")
        case .forward: String(localized: "İleri")
        case .reload: String(localized: "Sayfayı yenile")
        case .copy: String(localized: "Kopyala")
        case .paste: String(localized: "Yapıştır")
        case .pastePlain: String(localized: "Biçimsiz yapıştır")
        case .undo: String(localized: "Geri al")
        case .spotlight: "Spotlight"
        case .missionControl: "Mission Control"
        case .appWindows: String(localized: "Uygulamanın pencereleri")
        case .nextSpace: String(localized: "Sağdaki masaüstü")
        case .previousSpace: String(localized: "Soldaki masaüstü")
        case .screenshot: String(localized: "Ekran görüntüsü (alan seç)")
        case .screenshotTools: String(localized: "Ekran görüntüsü ve kayıt araçları")
        case .lockScreen: String(localized: "Ekranı kilitle")
        case .volumeUp: String(localized: "Sesi aç")
        case .volumeDown: String(localized: "Sesi kıs")
        case .mute: String(localized: "Sesi kapat / aç")
        case .playPause: String(localized: "Oynat / duraklat")
        case .nextTrack: String(localized: "Sonraki şarkı")
        case .previousTrack: String(localized: "Önceki şarkı")
        case .openApp(_, let name): String(localized: "\(name) uygulamasını aç")
        case .openURL(let url): String(localized: "Siteyi aç: \(Self.shortURL(url))")
        case .runShortcut(let name): String(localized: "Kestirme: \(name)")
        }
    }

    /// Karşılığı olan kısayol; varsa iş bu kısayol gönderilerek yapılır
    public var keys: Shortcut? {
        func k(_ code: UInt16, _ mods: Modifiers, _ name: String) -> Shortcut { Shortcut(keyCode: code, modifiers: mods, key: name) }
        return switch self {
        case .minimize: k(46, .command, "M")
        case .fullScreen: k(3, [.control, .command], "F")
        case .closeWindow: k(13, .command, "W")
        case .hideApp: k(4, .command, "H")
        case .quitApp: k(12, .command, "Q")
        case .newTab: k(17, .command, "T")
        case .reopenTab: k(17, [.shift, .command], "T")
        case .nextTab: k(48, .control, "⇥")
        case .previousTab: k(48, [.control, .shift], "⇥")
        case .back: k(33, .command, "[")
        case .forward: k(30, .command, "]")
        case .reload: k(15, .command, "R")
        case .copy: k(8, .command, "C")
        case .paste: k(9, .command, "V")
        case .pastePlain: k(9, [.option, .shift, .command], "V")
        case .undo: k(6, .command, "Z")
        case .spotlight: k(49, .command, String(localized: "Boşluk"))
        case .missionControl: k(126, .control, "↑")
        case .appWindows: k(125, .control, "↓")
        case .nextSpace: k(124, .control, "→")
        case .previousSpace: k(123, .control, "←")
        case .screenshot: k(21, [.shift, .command], "4")
        case .screenshotTools: k(23, [.shift, .command], "5")
        case .lockScreen: k(12, [.control, .command], "Q")
        default: nil
        }
    }

    /// Ekranda tek satır: "Pencereyi küçült · ⌘M"
    public var label: String {
        guard let keys else { return title }
        return "\(title) · \(keys.display)"
    }

    /// Simge (SF Symbols)
    public var symbol: String {
        switch self {
        case .minimize: "minus.square"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .closeWindow: "xmark.square"
        case .hideApp: "eye.slash"
        case .quitApp: "power"
        case .snap(let layout):
            switch layout {
            case .left: "rectangle.lefthalf.filled"
            case .right: "rectangle.righthalf.filled"
            case .top: "rectangle.tophalf.filled"
            case .bottom: "rectangle.bottomhalf.filled"
            case .fill: "rectangle.fill"
            }
        case .newTab: "plus.square.on.square"
        case .reopenTab: "arrow.uturn.backward.square"
        case .nextTab: "arrow.right.square"
        case .previousTab: "arrow.left.square"
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .reload: "arrow.clockwise"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .pastePlain: "textformat"
        case .undo: "arrow.uturn.backward"
        case .spotlight: "magnifyingglass"
        case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"
        case .nextSpace: "arrow.right.to.line"
        case .previousSpace: "arrow.left.to.line"
        case .screenshot: "camera.viewfinder"
        case .screenshotTools: "record.circle"
        case .lockScreen: "lock.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .openApp: "app.badge"
        case .openURL: "safari"
        case .runShortcut: "square.stack.3d.up.fill"
        }
    }

    /// "https://www.example.com/a/b" → "example.com/a/b"
    static func shortURL(_ url: String) -> String {
        var s = url
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        return s.count > 32 ? String(s.prefix(31)) + "…" : s
    }

    /// Yazılan adresi açılabilir hâle getirir ("example.com" → "https://example.com"); geçersizse nil
    public static func normalizedURL(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let full = t.contains("://") ? t : "https://" + t
        guard let url = URL(string: full), url.host?.contains(".") == true || url.scheme != "https" else { return nil }
        return full
    }
}

// Ayar dosyasında: {"task": "minimize"}, {"task": "snap", "layout": "left"},
// {"task": "openApp", "bundleID": "...", "name": "..."}, {"task": "openURL", "url": "..."}, {"task": "runShortcut", "name": "..."}
extension ReadyTask: Codable {
    private enum CodingKeys: String, CodingKey { case task, layout, bundleID, name, url }

    private static let simple: [String: ReadyTask] = {
        var map: [String: ReadyTask] = [:]
        for group in Group.allCases { for task in group.tasks where task.simpleName != nil { map[task.simpleName!] = task } }
        return map
    }()

    /// Ek bilgisi olmayan işin dosyadaki adı
    private var simpleName: String? {
        switch self {
        case .snap, .openApp, .openURL, .runShortcut: nil
        default: String(describing: self)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .task)
        switch name {
        case "snap": self = .snap(try c.decode(SnapLayout.self, forKey: .layout))
        case "openApp": self = .openApp(bundleID: try c.decode(String.self, forKey: .bundleID), name: try c.decode(String.self, forKey: .name))
        case "openURL": self = .openURL(try c.decode(String.self, forKey: .url))
        case "runShortcut": self = .runShortcut(try c.decode(String.self, forKey: .name))
        default:
            guard let task = Self.simple[name] else {
                throw DecodingError.dataCorruptedError(forKey: .task, in: c, debugDescription: "bilinmeyen iş: \(name)")
            }
            self = task
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snap(let layout):
            try c.encode("snap", forKey: .task)
            try c.encode(layout, forKey: .layout)
        case .openApp(let bundleID, let name):
            try c.encode("openApp", forKey: .task)
            try c.encode(bundleID, forKey: .bundleID)
            try c.encode(name, forKey: .name)
        case .openURL(let url):
            try c.encode("openURL", forKey: .task)
            try c.encode(url, forKey: .url)
        case .runShortcut(let name):
            try c.encode("runShortcut", forKey: .task)
            try c.encode(name, forKey: .name)
        default:
            try c.encode(simpleName, forKey: .task)
        }
    }
}

extension Shortcut {
    /// Kısayolu olmayan hazır işin satırında duran boş kısayol (hiç gönderilmez, çakışma sayılmaz)
    public static let none = Shortcut(keyCode: UInt16.max, modifiers: [], key: "")
    public var isNone: Bool { keyCode == UInt16.max && mouse == nil }
}
