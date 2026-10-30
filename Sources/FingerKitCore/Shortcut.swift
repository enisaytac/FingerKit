public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    /// macOS'un menülerde kullandığı sıra ve simgeler
    static let ordered: [(Modifiers, symbol: String, word: String, key: String)] = [
        (.control, "⌃", "Ctrl", "control"),
        (.option, "⌥", "Option", "option"),
        (.shift, "⇧", "Shift", "shift"),
        (.command, "⌘", "Cmd", "command"),
    ]

    public var symbols: String {
        Self.ordered.filter { contains($0.0) }.map(\.symbol).joined()
    }
}

/// Klavye tuşu yerine gönderilebilecek fare tıklaması (imlecin olduğu yere)
public enum MouseButton: String, Codable, CaseIterable, Sendable {
    case left, right, middle

    public var name: String {
        switch self {
        case .left: return String(localized: "Tık")
        case .right: return String(localized: "Sağ tık")
        case .middle: return String(localized: "Orta tık")
        }
    }
}

/// Bir klavye kısayolu: tuşun konum numarası (keyCode) ve basılı tutulan değiştirici tuşlar.
/// `mouse` doluysa tuş yerine o fare tıklaması gönderilir (ör. ⌘ + tık).
public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// Ekranda görünen tuş adı ("F", "←")
    public var key: String
    public var mouse: MouseButton?

    public init(keyCode: UInt16, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public init(mouse: MouseButton, modifiers: Modifiers = []) {
        self.keyCode = 0
        self.modifiers = modifiers
        self.key = mouse.name
        self.mouse = mouse
    }

    /// "⌃⌘F", "⌘ Tık"
    public var display: String {
        guard let mouse else { return modifiers.symbols + key }
        return modifiers.isEmpty ? mouse.name : modifiers.symbols + " " + mouse.name
    }

    /// "Ctrl + Cmd + F" (simgeleri bilmeyenler için)
    public var spoken: String {
        let last = mouse?.name ?? Self.spokenKeyNames[keyCode] ?? key
        return (Modifiers.ordered.filter { modifiers.contains($0.0) }.map(\.word) + [last])
            .joined(separator: " + ")
    }

    /// Ok tuşları ve F tuşları gerçek klavyede "fn" işaretiyle gelir; gönderirken de öyle yapılır.
    public var isArrow: Bool { (123...126).contains(keyCode) }
    public var isFunctionKey: Bool { Self.specialKeyNames[keyCode]?.hasPrefix("F") == true }

    /// Harf olmayan tuşların adı
    public static let specialKeyNames: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        36: "↩", 76: "⌤", 48: "⇥", 49: String(localized: "Boşluk"), 51: "⌫", 117: "⌦", 53: "⎋",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static let spokenKeyNames: [UInt16: String] = [
        123: "Sol ok", 124: String(localized: "Sağ ok"), 125: String(localized: "Aşağı ok"), 126: String(localized: "Yukarı ok"),
        36: "Return", 48: "Tab", 51: "Sil", 117: String(localized: "İleri sil"), 53: "Esc",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    // Ayar dosyasında okunaklı dursun diye: {"keyCode": 3, "modifiers": ["control", "command"], "key": "F"}
    // ya da fare için {"mouse": "left", "modifiers": ["command"]}
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, key, mouse }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mouse = try c.decodeIfPresent(MouseButton.self, forKey: .mouse)
        if let mouse {
            keyCode = 0
            key = mouse.name
        } else {
            keyCode = try c.decode(UInt16.self, forKey: .keyCode)
            key = try c.decode(String.self, forKey: .key)
        }
        let names = try c.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        modifiers = Modifiers.ordered.filter { names.contains($0.key) }.reduce(into: []) { $0.insert($1.0) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let mouse {
            try c.encode(mouse, forKey: .mouse)
        } else {
            try c.encode(keyCode, forKey: .keyCode)
            try c.encode(key, forKey: .key)
        }
        try c.encode(Modifiers.ordered.filter { modifiers.contains($0.0) }.map(\.key), forKey: .modifiers)
    }
}
