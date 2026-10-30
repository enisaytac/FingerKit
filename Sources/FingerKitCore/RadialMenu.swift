import Foundation

/// Daire menünün alt yarısındaki bir uygulama
public struct RadialApp: Codable, Identifiable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Dock ayarındaki `persistent-apps` listesindeki uygulamalar (kullanım kaydı okunamazsa yedek sıra)
    public static func fromDock(_ tiles: [[String: Any]]) -> [RadialApp] {
        var result: [RadialApp] = []
        for tile in tiles {
            guard let data = tile["tile-data"] as? [String: Any],
                  let id = data["bundle-identifier"] as? String, !id.isEmpty,
                  !result.contains(where: { $0.bundleID == id }) else { continue }
            result.append(RadialApp(bundleID: id, name: data["file-label"] as? String ?? id))
        }
        return result
    }
}

/// Daire menünün üst yarısındaki bir kısayol
public struct RadialShortcut: Codable, Hashable, Sendable {
    public var title: String
    /// "⇧⌘T"; aynı tuşlar = aynı dilim
    public var keys: String
    public var action: AppAction

    public init(title: String, keys: String, action: AppAction) {
        self.title = title
        self.keys = keys
        self.action = action
    }

    /// Hazır iş: kısayolu varsa o yazar
    public init(task: ReadyTask) {
        self.init(title: task.title, keys: task.keys?.display ?? "", action: .task(task))
    }

    /// Aynı dilim mi: tuşlar; tuşu olmayan hazır işte adı
    public var identity: String { keys.isEmpty ? "iş:" + title : keys }
}

/// Dairedeki bir dilim: hangi yuvada, sabit mi
public struct RadialSlot<Item: Hashable & Sendable>: Hashable, Sendable {
    public var slot: Int
    public var item: Item
    public var pinned: Bool

    public init(slot: Int, item: Item, pinned: Bool) {
        self.slot = slot
        self.item = item
        self.pinned = pinned
    }
}

/// Trackpad'in sol alt köşesine tıklayınca açılan daire menü.
/// Alt yarı: o an açık olmayan, en çok kullanılan uygulamalar. Üst yarı: öndeki uygulamanın sık kısayolları.
/// Kullanıcının sabitlediği dilim yerinde kalır; boş yuvaları FingerKit doldurur.
/// Daireyi açan trackpad köşesi
public enum RadialCorner: String, Codable, CaseIterable, Sendable {
    case bottomLeft, bottomRight, topLeft, topRight

    public var title: String {
        switch self {
        case .bottomLeft: String(localized: "Sol alt köşe")
        case .bottomRight: String(localized: "Sağ alt köşe")
        case .topLeft: String(localized: "Sol üst köşe")
        case .topRight: String(localized: "Sağ üst köşe")
        }
    }

    /// Cümle içi ad: yalnız ilk harf küçülür (Almanca adlar büyük harfli kalır)
    public var inlineTitle: String { title.prefix(1).lowercased() + title.dropFirst() }

    /// Aynı köşeye dokunma hareketi (çakışma uyarısı için)
    public var tapGesture: Gesture {
        switch self {
        case .bottomLeft: .cornerTapBottomLeft
        case .bottomRight: .cornerTapBottomRight
        case .topLeft: .cornerTapTopLeft
        case .topRight: .cornerTapTopRight
        }
    }

    /// Parmak bu köşede mi (x: 0 sol, y: 0 alt)
    public func contains(x: Double, y: Double) -> Bool {
        let s = RadialMenuSettings.cornerSize
        switch self {
        case .bottomLeft: return x < s && y < s
        case .bottomRight: return x > 1 - s && y < s
        case .topLeft: return x < s && y > 1 - s
        case .topRight: return x > 1 - s && y > 1 - s
        }
    }
}

public struct RadialMenuSettings: Codable, Equatable, Sendable {
    /// Her yarıda en çok dilim
    public static let limit = 6
    /// Köşe karesi: trackpad genişliğinin ve yüksekliğinin bu oranı
    public static let cornerSize = 0.2

    public var enabled = true
    /// Alt yarıda sabitlenen uygulamalar; sıra = yuva (soldan sağa), nil = otomatik
    public var appPins: [RadialApp?] = []
    /// Uygulama başına üst yarıda sabitlenen kısayollar; sıra = yuva, nil = otomatik
    public var shortcutPins: [String: [RadialShortcut?]] = [:]
    /// Üst yarının başındaki Denetim Merkezi düğmeleri, soldan sağa; her uygulamada aynı
    /// (eski dosyalarda yok; o zaman Bluetooth, ses, parlaklık, AirDrop)
    public var controls: [SystemControl] = SystemControl.defaults
    /// Daireyi açan köşe (eski dosyalarda yok; o zaman sol alt)
    public var corner: RadialCorner = .bottomLeft

    public init(enabled: Bool = true, appPins: [RadialApp?] = [], shortcutPins: [String: [RadialShortcut?]] = [:],
                controls: [SystemControl] = SystemControl.defaults) {
        self.enabled = enabled
        self.appPins = appPins
        self.shortcutPins = shortcutPins
        self.controls = controls
    }

    private enum CodingKeys: String, CodingKey { case enabled, appPins, shortcutPins, controls, corner }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        appPins = try c.decodeIfPresent([RadialApp?].self, forKey: .appPins) ?? []
        shortcutPins = try c.decodeIfPresent([String: [RadialShortcut?]].self, forKey: .shortcutPins) ?? [:]
        // Bilinmeyen (daha yeni sürümden kalan) düğme adları atlanır
        let names = try c.decodeIfPresent([String].self, forKey: .controls)
        controls = names.map { $0.compactMap(SystemControl.init(rawValue:)) } ?? SystemControl.defaults
        corner = (try? c.decodeIfPresent(RadialCorner.self, forKey: .corner)) ?? .bottomLeft
    }

    /// Üst yarıda kısayollara kalan yuva sayısı
    public var shortcutRoom: Int { RadialTop.shortcutRoom(controls: controls.count) }

    /// Düğmeyi üst yarıya ekler (zaten varsa ya da yer yoksa dokunmaz)
    public mutating func addControl(_ control: SystemControl) {
        guard !controls.contains(control), controls.count < Self.limit else { return }
        controls.append(control)
    }

    /// Parmak daireyi açan köşede mi (x: 0 sol, y: 0 alt)
    public func isCorner(x: Double, y: Double) -> Bool {
        corner.contains(x: x, y: y)
    }

    /// Yuvalar: sabitlenen yerinde, boşlara sırayla otomatik gelenler (sabitlenenle aynısı atlanır).
    /// Otomatik liste biterse boş yuvalar atlanır.
    public static func fill<T>(pins: [T?], auto: [T], same: (T, T) -> Bool, limit: Int = limit) -> [RadialSlot<T>] {
        let pinned = pins.compactMap { $0 }
        var rest = auto.filter { a in !pinned.contains { same($0, a) } }.makeIterator()
        var result: [RadialSlot<T>] = []
        var used: [T] = []
        for slot in 0..<limit {
            if slot < pins.count, let p = pins[slot] {
                result.append(RadialSlot(slot: slot, item: p, pinned: true))
            } else {
                while let next = rest.next() {
                    if used.contains(where: { same($0, next) }) { continue }
                    used.append(next)
                    result.append(RadialSlot(slot: slot, item: next, pinned: false))
                    break
                }
            }
        }
        return result
    }

    public func apps(auto: [RadialApp]) -> [RadialSlot<RadialApp>] {
        Self.fill(pins: appPins, auto: auto) { $0.bundleID == $1.bundleID }
    }

    /// Üst yarının kısayolları: Denetim Merkezi düğmelerinden kalan yuvalar kadar
    public func shortcuts(for bundleID: String, auto: [RadialShortcut]) -> [RadialSlot<RadialShortcut>] {
        Self.fill(pins: shortcutPins[bundleID] ?? [], auto: auto, same: { $0.identity == $1.identity }, limit: shortcutRoom)
    }

    /// Yuvaya uygulama sabitler (nil: sabitlemeyi kaldırır). Aynı uygulama başka yuvadaysa oradan kalkar.
    public mutating func pinApp(_ app: RadialApp?, at slot: Int) {
        appPins = Self.set(app, at: slot, in: appPins) { $0.bundleID == $1.bundleID }
    }

    public mutating func pinShortcut(_ shortcut: RadialShortcut?, at slot: Int, for bundleID: String) {
        let list = Self.set(shortcut, at: slot, in: shortcutPins[bundleID] ?? []) { $0.identity == $1.identity }
        shortcutPins[bundleID] = list.isEmpty ? nil : list
    }

    private static func set<T>(_ item: T?, at slot: Int, in pins: [T?], same: (T, T) -> Bool) -> [T?] {
        guard (0..<limit).contains(slot) else { return pins }
        var list = pins
        if let item { list = list.map { p in p.flatMap { same($0, item) ? nil : $0 } } }
        while list.count <= slot { list.append(nil) }
        list[slot] = item
        while let last = list.last, last == nil { list.removeLast() }
        return list
    }
}

/// Dairede imlecin gösterdiği dilim
public enum RadialPick: Equatable, Sendable {
    /// Üst yarı (kısayollar), soldan sağa sıra
    case top(Int)
    /// Alt yarı (uygulamalar), soldan sağa sıra
    case bottom(Int)
}

/// Dairenin geometrisi: ortada boş daire, çevresinde iki yarım halka
public struct RadialGeometry: Sendable {
    /// Ortadaki boş dairenin yarıçapı; içine tıklamak kapatır
    public var inner: Double
    /// Halkanın dış yarıçapı
    public var outer: Double
    /// Halkanın bu kadar dışına kadar yön yine dilim seçer; daha uzağa tıklamak kapatır
    public var reach: Double

    public init(inner: Double = 48, outer: Double = 190, reach: Double = 90) {
        self.inner = inner
        self.outer = outer
        self.reach = reach
    }

    /// `dx`, `dy`: imlecin merkeze göre yeri (y yukarı doğru artar). Yarıda `top`/`bottom` dilim var.
    public func pick(dx: Double, dy: Double, top: Int, bottom: Int) -> RadialPick? {
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= inner, r <= outer + reach else { return nil }
        // 0 = sol, π = sağ; üst yarıda soldan sağa, alt yarıda da soldan sağa
        if dy >= 0 {
            guard top > 0 else { return nil }
            let a = Double.pi - atan2(dy, dx)
            return .top(min(Int(a / (Double.pi / Double(top))), top - 1))
        } else {
            guard bottom > 0 else { return nil }
            let a = Double.pi + atan2(dy, dx)
            return .bottom(min(Int(a / (Double.pi / Double(bottom))), bottom - 1))
        }
    }

    /// Dilimin ortasında (`angle` yönünde, merkezden `radius` uzakta) duran, `height` yüksekliğindeki yazı
    /// kutusunun dilim çizgilerine değmeden alabileceği en büyük genişlik. Yan dilimler geniş, tepedekiler dar.
    public func labelWidth(angle: Double, count n: Int, radius: Double, height: Double, margin: Double = 4) -> Double {
        // Dilimin yarıçapa dik yöndeki genişliği ve halkanın kalınlığı
        let across = 2 * radius * sin(Double.pi / Double(2 * n)) - 2 * margin
        let depth = outer - inner - 2 * margin
        let s = abs(sin(angle)), c = abs(cos(angle))
        let byAcross = s > 0.01 ? (across - height * c) / s : depth
        let byDepth = c > 0.01 ? (depth - height * s) / c : depth
        return max(40, min(byAcross, byDepth, depth))
    }

    /// `i`. dilimin ortasının açısı (radyan; 0 = sağ, saat yönünün tersi). Üst yarıda soldan sağa.
    public static func angle(top: Bool, index i: Int, count n: Int) -> Double {
        let step = Double.pi / Double(n)
        let fromLeft = (Double(i) + 0.5) * step
        return top ? Double.pi - fromLeft : Double.pi + fromLeft
    }
}

/// Uygulama menüsünde kısayolu olan bir madde
public struct MenuShortcutEntry: Hashable, Sendable {
    /// Üst menüden başlayan yol: ["Dosya", "Yeni Sekme"]
    public var path: [String]
    /// "⇧⌘T"
    public var keys: String

    public init(path: [String], keys: String) {
        self.path = path
        self.keys = keys
    }

    public var title: String { path.last ?? "" }

    /// Erişilebilirlikteki AXMenuItemCmdModifiers: 1 ⇧, 2 ⌥, 4 ⌃, 8 = ⌘ yok
    public static func keys(key: String, modifiers: Int) -> String {
        var s = ""
        if modifiers & 4 != 0 { s += "⌃" }
        if modifiers & 2 != 0 { s += "⌥" }
        if modifiers & 1 != 0 { s += "⇧" }
        if modifiers & 8 == 0 { s += "⌘" }
        return s + key
    }

    /// Menü maddesinin tuş adı: harf ya da (oklar, boşluk gibi) özel tuş. Okunamazsa nil.
    /// `glyph`: AXMenuItemCmdGlyph, `virtualKey`: AXMenuItemCmdVirtualKey
    public static func keyName(char: String?, glyph: Int?, virtualKey: Int?) -> String? {
        if let char, let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 {
            if let arrow = functionKeyArrows[scalar.value] { return arrow }
            // Kısayol harfleri İngilizce büyük harfle gösterilir ("i" → "I", "İ" değil)
            if scalar.value > 0x20, scalar.value < 0xF700 { return char.uppercased() }
        }
        if let glyph, let name = glyphNames[glyph] { return name }
        if let virtualKey, virtualKey > 0, let name = Shortcut.specialKeyNames[UInt16(virtualKey)] { return name }
        return nil
    }

    /// Menülerde ok tuşları özel harflerle gelir
    private static let functionKeyArrows: [UInt32: String] = [0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→"]
    /// Carbon menü simge numaraları
    private static let glyphNames: [Int: String] = [
        100: "←", 101: "→", 104: "↑", 106: "↓", 9: String(localized: "Boşluk"), 11: "↩", 23: "⌫", 27: "⎋",
    ]

    /// Daireye konacak en çok `limit` madde: önce bilinen sık maddeler (Yeni, Aç, Kaydet, Bul, Kapat),
    /// sonra menü sırasıyla diğerleri, en son düzen menüsünün herkesin bildiği maddeleri.
    public static func autoPick(_ entries: [MenuShortcutEntry], limit: Int = RadialMenuSettings.limit) -> [MenuShortcutEntry] {
        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
                .trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr_TR"))
        }
        let rank: (MenuShortcutEntry) -> Int = { entry in
            let t = norm(entry.title)
            if let i = preferred.firstIndex(of: t) { return i }
            return basics.contains(t) ? 2000 : 1000
        }
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.keys).inserted && !excluded.contains(norm($0.title)) }
        return Array(unique.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .prefix(limit)
            .map(\.element))
    }

    /// Sık kullanılan maddeler, öncelik sırasıyla (Türkçe ve İngilizce menüler)
    private static let preferred = [
        "yeni sekme", "new tab", "yeni pencere", "new window", "yeni", "new", "yeni not", "new note",
        "yeni klasör", "new folder", "aç", "open", "kaydet", "save", "bul", "find", "ara", "search",
        "sekmeyi kapat", "close tab", "pencereyi kapat", "close window", "kapat", "close",
        "sayfayı yeniden yükle", "reload page", "yenile", "reload", "yazdır", "print",
    ]
    /// Herkesin zaten bildiği düzen maddeleri: yer kalırsa en sona
    private static let basics: Set<String> = [
        "geri al", "undo", "yinele", "redo", "kes", "cut", "kopyala", "copy", "yapıştır", "paste",
        "tümünü seç", "select all",
    ]
    /// Yanlışlıkla seçilince zarar verecek ya da işe yaramayan maddeler
    private static let excluded: Set<String> = [
        "çık", "quit", "çıkış", "zorla çık", "force quit",
    ]
}

/// Uygulama başına insanların en çok kullandığı kısayollar (25 Ekim 2026 araştırması:
/// uygulamaların kendi kısayol sayfaları ve "en çok kullanılan kısayollar" yazıları).
/// Listesi olmayan uygulamada üst yarı menüden seçilir.
public enum PopularShortcuts {
    /// Bu uygulamanın üst yarısı (sabitlenenler hariç): önce hazır liste, kalan yer menüden.
    /// Hazır listedeki kısayol menüde de varsa menü maddesine basılır (klavye düzeninden bağımsız).
    public static func auto(for bundleID: String, menu: [MenuShortcutEntry]) -> [RadialShortcut] {
        var result: [RadialShortcut] = (table[bundleID] ?? []).map { title, shortcut in
            let keys = shortcut.display
            if let entry = menu.first(where: { $0.keys == keys }) {
                return RadialShortcut(title: title, keys: keys, action: .menu(entry.path))
            }
            return RadialShortcut(title: title, keys: keys, action: .shortcut(shortcut))
        }
        for entry in MenuShortcutEntry.autoPick(menu, limit: menu.count) where !result.contains(where: { $0.keys == entry.keys }) {
            result.append(RadialShortcut(title: entry.title, keys: entry.keys, action: .menu(entry.path)))
        }
        return result
    }

    public static func hasList(_ bundleID: String) -> Bool { table[bundleID] != nil }

    private static func key(_ code: UInt16, _ mods: Modifiers, _ name: String) -> Shortcut {
        Shortcut(keyCode: code, modifiers: mods, key: name)
    }

    private static let browser: [(String, Shortcut)] = [
        (String(localized: "Yeni Sekme"), key(17, .command, "T")),
        (String(localized: "Kapanan Sekmeyi Aç"), key(17, [.shift, .command], "T")),
        (String(localized: "Adres Çubuğu"), key(37, .command, "L")),
        (String(localized: "Sayfada Bul"), key(3, .command, "F")),
        (String(localized: "Yenile"), key(15, .command, "R")),
        (String(localized: "Sekmeyi Kapat"), key(13, .command, "W")),
    ]

    static let table: [String: [(String, Shortcut)]] = [
        "com.apple.Safari": browser,
        "com.operasoftware.Opera": browser,
        "com.google.Chrome": browser,
        "com.microsoft.edgemac": browser,
        "com.brave.Browser": browser,
        "org.mozilla.firefox": browser,
        "company.thebrowser.Browser": browser,
        "com.microsoft.VSCode": [
            (String(localized: "Komut Paleti"), key(35, [.shift, .command], "P")),
            (String(localized: "Dosyaya Git"), key(35, .command, "P")),
            (String(localized: "Dosyalarda Ara"), key(3, [.shift, .command], "F")),
            (String(localized: "Kenar Çubuğu"), key(11, .command, "B")),
            (String(localized: "Kaydet"), key(1, .command, "S")),
            (String(localized: "Sekmeyi Kapat"), key(13, .command, "W")),
        ],
        "com.spotify.client": [
            (String(localized: "Önceki"), key(123, .command, "←")),
            (String(localized: "Oynat / Duraklat"), key(49, [], String(localized: "Boşluk"))),
            (String(localized: "Sonraki"), key(124, .command, "→")),
            (String(localized: "Ara"), key(40, .command, "K")),
            (String(localized: "Sesi Kıs"), key(125, .command, "↓")),
            (String(localized: "Sesi Aç"), key(126, .command, "↑")),
        ],
        "com.apple.finder": [
            (String(localized: "Yeni Sekme"), key(17, .command, "T")),
            (String(localized: "Yeni Klasör"), key(45, [.shift, .command], "N")),
            (String(localized: "Klasöre Git"), key(5, [.shift, .command], "G")),
            (String(localized: "Bilgi Al"), key(34, .command, "I")),
            (String(localized: "Ara"), key(3, .command, "F")),
            (String(localized: "Yeni Pencere"), key(45, .command, "N")),
        ],
        "com.apple.Notes": [
            (String(localized: "Yeni Not"), key(45, .command, "N")),
            (String(localized: "Kontrol Listesi"), key(37, [.shift, .command], "L")),
            (String(localized: "Başlık"), key(17, [.shift, .command], "T")),
            (String(localized: "Tablo"), key(17, [.option, .command], "T")),
            (String(localized: "Notlarda Ara"), key(3, [.option, .command], "F")),
            (String(localized: "Notta Bul"), key(3, .command, "F")),
        ],
        "com.microsoft.Outlook": [
            (String(localized: "Yeni E-posta"), key(45, .command, "N")),
            (String(localized: "Yanıtla"), key(15, .command, "R")),
            (String(localized: "Tümünü Yanıtla"), key(15, [.shift, .command], "R")),
            (String(localized: "İlet"), key(38, .command, "J")),
            (String(localized: "Ara"), key(3, [.option, .command], "F")),
            (String(localized: "Gönder"), key(36, .command, "↩")),
        ],
        "com.apple.mail": [
            (String(localized: "Yeni İleti"), key(45, .command, "N")),
            (String(localized: "Yanıtla"), key(15, .command, "R")),
            (String(localized: "Tümünü Yanıtla"), key(15, [.shift, .command], "R")),
            (String(localized: "İlet"), key(3, [.shift, .command], "F")),
            (String(localized: "Postaları Al"), key(45, [.shift, .command], "N")),
            (String(localized: "Ara"), key(3, [.option, .command], "F")),
        ],
        "com.apple.Terminal": [
            (String(localized: "Yeni Sekme"), key(17, .command, "T")),
            (String(localized: "Yeni Pencere"), key(45, .command, "N")),
            (String(localized: "Temizle"), key(40, .command, "K")),
            (String(localized: "Bul"), key(3, .command, "F")),
            (String(localized: "Böl"), key(2, .command, "D")),
            (String(localized: "Sekmeyi Kapat"), key(13, .command, "W")),
        ],
    ]
}
