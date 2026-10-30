import Foundation

extension Modifiers {
    /// Hyper (Caps Lock) basılıyken tuşa eklenen dört tuş
    public static let hyper: Modifiers = [.control, .option, .shift, .command]
}

extension Shortcut {
    /// Caps Lock + tuş olarak kaydedilmiş tetik
    public var isHyper: Bool { mouse == nil && modifiers == .hyper }

    /// "⇪ + S" ya da "⌃⌘N"
    public var triggerDisplay: String { isHyper ? "⇪ + " + key : display }

    /// Tetik olabilir mi: fare değil; en az bir değiştirici tuş ya da tek başına F tuşu
    /// (tek başına harf her yazışta tetiklenirdi)
    public var isValidTrigger: Bool { mouse == nil && (!modifiers.isEmpty || isFunctionKey) }

    /// Aynı tuş ve aynı değiştiriciler (ekrandaki ad sayılmaz)
    public func sameKeys(_ other: Shortcut) -> Bool {
        mouse == other.mouse && keyCode == other.keyCode && modifiers == other.modifiers
    }
}

/// Tetiklenince yapılacak iş
public enum AppAction: Hashable, Sendable {
    /// Başka bir kısayol (ya da fare tıklaması) gönder
    case shortcut(Shortcut)
    /// Menüden madde seç; yol üst menüden başlar: ["Dosya", "Yeni"]
    case menu([String])
    /// Hazır iş (uygulama aç, site aç, Kestirme, ses…)
    case task(ReadyTask)

    public var display: String {
        switch self {
        case .shortcut(let s): s.display
        case .menu(let path): path.joined(separator: " › ")
        case .task(let t): t.label
        }
    }
}

// Ayar dosyasında: {"shortcut": {...}} ya da {"menu": ["Dosya", "Yeni"]}
extension AppAction: Codable {
    private enum CodingKeys: String, CodingKey { case shortcut, menu, task }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try c.decodeIfPresent([String].self, forKey: .menu) {
            self = .menu(path)
        } else if let task = try c.decodeIfPresent(ReadyTask.self, forKey: .task) {
            self = .task(task)
        } else {
            self = .shortcut(try c.decode(Shortcut.self, forKey: .shortcut))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shortcut(let s): try c.encode(s, forKey: .shortcut)
        case .menu(let path): try c.encode(path, forKey: .menu)
        case .task(let t): try c.encode(t, forKey: .task)
        }
    }
}

/// Bir uygulamada: tetik → iş
public struct AppShortcut: Codable, Identifiable, Hashable, Sendable {
    /// Yalnız arayüz için; dosyaya yazılmaz
    public var id = UUID()
    public var trigger: Shortcut
    public var action: AppAction
    public var enabled = true

    public init(trigger: Shortcut, action: AppAction, enabled: Bool = true) {
        self.trigger = trigger
        self.action = action
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case trigger, action, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try c.decode(Shortcut.self, forKey: .trigger)
        action = try c.decode(AppAction.self, forKey: .action)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Tek bir uygulamanın kısayol listesi
public struct AppShortcutProfile: Codable, Identifiable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    public var shortcuts: [AppShortcut]

    public var id: String { bundleID }

    public init(bundleID: String, name: String, shortcuts: [AppShortcut] = []) {
        self.bundleID = bundleID
        self.name = name
        self.shortcuts = shortcuts
    }
}

/// Uygulamaya özel kısayollar (eski ayar dosyalarında yok; o zaman açık ve boş)
public struct AppShortcutSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var apps: [AppShortcutProfile] = []

    public init(enabled: Bool = true, apps: [AppShortcutProfile] = []) {
        self.enabled = enabled
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey { case enabled, apps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        apps = try c.decodeIfPresent([AppShortcutProfile].self, forKey: .apps) ?? []
    }

    /// Bu uygulamada bu tuşlara bağlı açık satırın işi
    public func action(keyCode: UInt16, modifiers: Modifiers, app bundleID: String?) -> AppAction? {
        guard enabled, let bundleID else { return nil }
        return apps.first { $0.bundleID == bundleID }?.shortcuts
            .first { $0.enabled && $0.trigger.mouse == nil && $0.trigger.keyCode == keyCode && $0.trigger.modifiers == modifiers }?
            .action
    }

    /// Açık satırlardan normal (Caps Lock'suz) tetik var mı; yoksa tuş yakalayıcı kurulmaz
    public var hasPlainTriggers: Bool {
        enabled && apps.contains { $0.shortcuts.contains { $0.enabled && !$0.trigger.isHyper } }
    }

    /// Aynı uygulamada aynı tetiği kullanan başka satır (`editing` sayılmaz)
    public func duplicate(of trigger: Shortcut, in bundleID: String, editing: UUID? = nil) -> AppShortcut? {
        apps.first { $0.bundleID == bundleID }?.shortcuts.first { $0.id != editing && $0.trigger.sameKeys(trigger) }
    }

    /// Satırı ekler ya da düzenler; aynı tetik o uygulamada başka satırdaysa o satır silinir.
    public mutating func set(_ shortcut: AppShortcut, in bundleID: String, name: String) {
        if !apps.contains(where: { $0.bundleID == bundleID }) {
            apps.append(AppShortcutProfile(bundleID: bundleID, name: name))
        }
        guard let a = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[a].shortcuts.removeAll { $0.id != shortcut.id && $0.trigger.sameKeys(shortcut.trigger) }
        if let i = apps[a].shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            apps[a].shortcuts[i] = shortcut
        } else {
            apps[a].shortcuts.append(shortcut)
        }
    }
}
