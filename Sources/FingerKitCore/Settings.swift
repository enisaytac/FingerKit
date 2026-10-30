import Foundation

/// Bir hareketin bir kısayola bağlanması.
public struct GestureBinding: Codable, Identifiable, Hashable, Sendable {
    /// Yalnız arayüz için; dosyaya yazılmaz
    public var id = UUID()
    public var gesture: Gesture
    public var shortcut: Shortcut
    public var enabled = true
    /// Hazır iş seçildiyse adı ve (kısayolu yoksa) FingerKit'in yaptığı iş; kısayolu olan işte `shortcut` onun kısayoludur
    public var task: ReadyTask?

    public init(gesture: Gesture, shortcut: Shortcut, enabled: Bool = true, task: ReadyTask? = nil) {
        self.gesture = gesture
        self.shortcut = shortcut
        self.enabled = enabled
        self.task = task
    }

    /// Hazır işle: kısayolu varsa o gönderilir, yoksa iş FingerKit'te yapılır
    public init(gesture: Gesture, task: ReadyTask) {
        self.init(gesture: gesture, shortcut: task.keys ?? .none, task: task)
    }

    /// Ekranda: "Pencereyi küçült · ⌘M" ya da yalnız kısayol
    public var display: String { task?.label ?? shortcut.display }

    private enum CodingKeys: String, CodingKey { case gesture, shortcut, enabled, task }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gesture = try c.decode(Gesture.self, forKey: .gesture)
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .none
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        task = try c.decodeIfPresent(ReadyTask.self, forKey: .task)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(gesture, forKey: .gesture)
        if !shortcut.isNone { try c.encode(shortcut, forKey: .shortcut) }
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(task, forKey: .task)
    }
}

/// "Her yerde" ya da tek bir uygulamanın hareket listesi.
public struct AppProfile: Codable, Identifiable, Hashable, Sendable {
    public static let everywhere = "*"

    /// Uygulamanın kimliği (ör. com.apple.Safari); "*" = her yerde
    public var bundleID: String
    public var name: String
    public var bindings: [GestureBinding]

    public var id: String { bundleID }
    public var isEverywhere: Bool { bundleID == Self.everywhere }
    /// Ekranda görünen ad: "Her yerde" listesinin adı Mac'in diline göre değişir
    public var title: String { isEverywhere ? String(localized: "Her yerde") : name }

    public init(bundleID: String, name: String, bindings: [GestureBinding] = []) {
        self.bundleID = bundleID
        self.name = name
        self.bindings = bindings
    }
}

public struct Settings: Codable, Equatable, Sendable {
    /// FingerKit açık mı (menü çubuğundan ya da pencerenin üstünden)
    public var enabled = true
    public var apps: [AppProfile]
    /// Caps Lock → Hyper (eski ayar dosyalarında yok; o zaman üç hazır kısayolla gelir)
    public var hyper: HyperSettings
    /// Pano geçmişi (eski dosyalarda yok; o zaman açık, Caps Lock + V)
    public var clipboard: ClipboardSettings
    /// Uygulamaya özel kısayollar (eski dosyalarda yok; o zaman açık ve boş)
    public var appShortcuts: AppShortcutSettings
    /// Sol alt köşe daire menüsü (eski dosyalarda yok; o zaman açık, uygulamalar Dock'tan gelir)
    public var radial: RadialMenuSettings
    /// Ekran bildirimi: hareket ya da tuş çalışınca ortada kısa süre ne yapıldığı yazar (varsayılan açık)
    public var notify = true

    public init(enabled: Bool = true, apps: [AppProfile], hyper: HyperSettings = .defaults,
                clipboard: ClipboardSettings = ClipboardSettings(), appShortcuts: AppShortcutSettings = AppShortcutSettings(),
                radial: RadialMenuSettings = RadialMenuSettings()) {
        self.enabled = enabled
        self.apps = apps
        self.hyper = hyper
        self.clipboard = clipboard
        self.appShortcuts = appShortcuts
        self.radial = radial
    }

    private enum CodingKeys: String, CodingKey { case enabled, apps, hyper, clipboard, appShortcuts, radial, notify }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        apps = try c.decode([AppProfile].self, forKey: .apps)
        hyper = try c.decodeIfPresent(HyperSettings.self, forKey: .hyper) ?? .defaults
        clipboard = try c.decodeIfPresent(ClipboardSettings.self, forKey: .clipboard) ?? ClipboardSettings()
        appShortcuts = try c.decodeIfPresent(AppShortcutSettings.self, forKey: .appShortcuts) ?? AppShortcutSettings()
        radial = try c.decodeIfPresent(RadialMenuSettings.self, forKey: .radial) ?? RadialMenuSettings()
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        if !apps.contains(where: \.isEverywhere) {
            apps.insert(AppProfile(bundleID: AppProfile.everywhere, name: "Her yerde"), at: 0)
        }
    }

    /// Ön plandaki uygulamada bu hareketin kısayolu: önce o uygulamanın listesi, yoksa "Her yerde".
    /// Kapalı (enabled = false) satırlar yok sayılır.
    public func shortcut(for gesture: Gesture, app bundleID: String?) -> Shortcut? {
        binding(for: gesture, app: bundleID)?.shortcut
    }

    /// Ön plandaki uygulamada bu hareketin satırı (kısayol ya da hazır iş)
    public func binding(for gesture: Gesture, app bundleID: String?) -> GestureBinding? {
        func find(_ id: String) -> GestureBinding? {
            apps.first { $0.bundleID == id }?.bindings.first { $0.gesture == gesture && $0.enabled }
        }
        if let bundleID, let b = find(bundleID) { return b }
        return find(AppProfile.everywhere)
    }

    /// Yeni kullanıcının ilk açılışı: boş. Hareket yok, Caps Lock, pano ve daire menü kapalı;
    /// sayfalardaki "Topluluğun sevdiği ayarlar"dan tek tıkla eklenir.
    public static let fresh = Settings(apps: [AppProfile(bundleID: AppProfile.everywhere, name: "Her yerde")],
                                       hyper: .off, clipboard: ClipboardSettings(enabled: false),
                                       radial: RadialMenuSettings(enabled: false))

    /// İlk sürümlerin hazır 7 hareketi (yalnız testlerde örnek ayar olarak kullanılır)
    public static let defaults = Settings(apps: [
        AppProfile(bundleID: AppProfile.everywhere, name: "Her yerde", bindings: [
            GestureBinding(gesture: .fourFingerSwipeUp, shortcut: Shortcut(keyCode: 3, modifiers: [.control, .command], key: "F")),
            GestureBinding(gesture: .fourFingerSwipeDown, shortcut: Shortcut(keyCode: 46, modifiers: [.command], key: "M")),
            GestureBinding(gesture: .fourFingerClick, shortcut: Shortcut(keyCode: 12, modifiers: [.command], key: "Q")),
        ]),
        AppProfile(bundleID: "com.apple.Safari", name: "Safari", bindings: [
            GestureBinding(gesture: .fourFingerSwipeLeft, shortcut: Shortcut(keyCode: 123, modifiers: [.shift, .command], key: "←")),
            GestureBinding(gesture: .fourFingerSwipeRight, shortcut: Shortcut(keyCode: 124, modifiers: [.shift, .command], key: "→")),
            GestureBinding(gesture: .threeFingerClick, shortcut: Shortcut(keyCode: 17, modifiers: [.command], key: "T")),
            GestureBinding(gesture: .twoFingerDoubleTap, shortcut: Shortcut(keyCode: 13, modifiers: [.command], key: "W")),
        ]),
    ])
}

/// Ayarların diskteki dosyası: ~/Library/Application Support/FingerKit/ayarlar.json
public struct SettingsFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: SettingsFile {
        SettingsFile(url: folder.appendingPathComponent("ayarlar.json"))
    }

    /// Ayar klasörü. FINGERKIT_KLASOR verilirse orası (denemelerde boş, yeni kullanıcı gibi açmak için).
    public static var folder: URL {
        if let custom = ProcessInfo.processInfo.environment["FINGERKIT_KLASOR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FingerKit", isDirectory: true)
    }

    public enum LoadResult {
        case loaded(Settings)
        /// Dosya yoktu; varsayılanlar kullanıldı (ilk açılış)
        case created(Settings)
        /// Dosya okunamadı; yedeklendi, varsayılanlar kullanıldı
        case recovered(Settings, backup: URL, error: Error)
    }

    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            try? save(.fresh)
            return .created(.fresh)
        }
        do {
            return .loaded(try JSONDecoder().decode(Settings.self, from: data))
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent().appendingPathComponent("ayarlar-bozuk-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            try? save(.fresh)
            return .recovered(.fresh, backup: backup, error: error)
        }
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}

// MARK: - Yedekleme ve paylaşma

extension Settings {
    /// Başka bir ayar dosyası içe alınınca neyin değişeceği, sade cümlelerle (boşsa değişen bir şey yok)
    public func changes(to new: Settings) -> [String] {
        var result: [String] = []
        func count(_ s: Settings) -> Int { s.apps.reduce(0) { $0 + $1.bindings.count } }
        // Satırların arayüz kimlikleri (id) dosyada yok; karşılaştırma dosyadaki hâliyle yapılır
        func differ<T: Encodable>(_ a: T, _ b: T) -> Bool {
            let e = JSONEncoder()
            e.outputFormatting = .sortedKeys
            return (try? e.encode(a)) != (try? e.encode(b))
        }
        func state(_ on: Bool) -> String { on ? String(localized: "açık") : String(localized: "kapalı") }
        if differ(apps, new.apps) {
            let names = Set(new.apps.map(\.title)).subtracting(apps.map(\.title)).sorted()
            result.append(String(localized: "Hareketler: \(count(self)) → \(count(new)) satır") +
                          (names.isEmpty ? "" : " (" + String(localized: "yeni uygulamalar: \(names.joined(separator: ", "))") + ")"))
        }
        if differ(hyper, new.hyper) {
            result.append(String(localized: "Hiper Tuş: \(state(hyper.enabled)) → \(state(new.hyper.enabled)), \(hyper.bindings.count) → \(new.hyper.bindings.count) tuş"))
        }
        if differ(clipboard, new.clipboard) {
            result.append(String(localized: "Pano: \(state(clipboard.enabled)) → \(state(new.clipboard.enabled)), ⇪ + \(new.clipboard.key), \(new.clipboard.keepDays) gün"))
        }
        if differ(appShortcuts, new.appShortcuts) {
            func n(_ s: AppShortcutSettings) -> Int { s.apps.reduce(0) { $0 + $1.shortcuts.count } }
            result.append(String(localized: "Uygulama kısayolları: \(n(appShortcuts)) → \(n(new.appShortcuts)) satır"))
        }
        if differ(radial, new.radial) {
            result.append(String(localized: "Daire menü: \(state(radial.enabled)) → \(state(new.radial.enabled)), \(new.radial.controls.count) Denetim Merkezi düğmesi"))
        }
        if notify != new.notify {
            result.append(new.notify ? String(localized: "Ekran bildirimi açılır") : String(localized: "Ekran bildirimi kapanır"))
        }
        if enabled != new.enabled {
            result.append(new.enabled ? String(localized: "FingerKit açılır") : String(localized: "FingerKit kapanır"))
        }
        return result
    }

    /// Paylaşılan dosyanın içeriği (ayar dosyasıyla aynı biçim, okunaklı)
    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Dışarıdan gelen dosya: bozuksa hata
    public static func imported(_ data: Data) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: data)
    }
}
