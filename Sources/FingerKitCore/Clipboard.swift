import Foundation

/// Kopyanın türü: panoda üç raf var (görseller, yazılar, bağlantılar)
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, image, video

    /// Hangi rafta durur: görsel ve video aynı rafta (ekran görüntüleri ve kayıtları kendi rafında, `ClipItem.shelf`)
    public var shelf: ClipShelf {
        switch self {
        case .text: .texts
        case .link: .links
        case .image, .video: .images
        }
    }
}

public enum ClipShelf: CaseIterable, Sendable {
    case captures, images, texts, links

    public var title: String {
        switch self {
        case .captures: String(localized: "Ekran görüntüleri ve kayıtları")
        case .images: String(localized: "Görseller")
        case .texts: String(localized: "Yazılar")
        case .links: String(localized: "Bağlantılar")
        }
    }

    public var symbol: String {
        switch self {
        case .captures: "camera.viewfinder"
        case .images: "photo.on.rectangle"
        case .texts: "text.alignleft"
        case .links: "link"
        }
    }
}

/// Panoya kopyalanmış bir şey: yazı, bağlantı, görsel ya da video (ekran kaydı)
public struct ClipItem: Codable, Identifiable, Hashable, Sendable {
    /// Yalnız arayüz için; dosyaya yazılmaz
    public var id = UUID()
    public var kind: ClipKind
    /// Yazı ve bağlantıda kendisi; görselde aramaya giren ad (ör. "Ekran Resmi 2026-10-29") ya da okunan yazı
    public var text: String
    public var date: Date
    /// Görsel ve videonun dosyası: kopyalanan görsel FingerKit'in pano klasörüne kaydedilir,
    /// ekran görüntüsü ve kaydı yerinde kalır (tam yol)
    public var file: String?
    /// Aynı görsel ikinci kez eklenmesin diye içeriğin özeti
    public var hash: String?
    /// Sabitlenen kopya süre dolsa da silinmez, rafın başında durur
    public var pinned = false

    /// Rafı: ekran görüntüsü ve ekran kaydı (dosya adından) kendi rafında, kopyalanan görsellerden ayrı
    public var shelf: ClipShelf {
        if kind.shelf == .images, let file, ClipboardSettings.isScreenshot(fileName: (file as NSString).lastPathComponent) {
            return .captures
        }
        return kind.shelf
    }

    public init(text: String, date: Date) {
        self.init(kind: Self.looksLikeLink(text) ? .link : .text, text: text, date: date)
    }

    public init(kind: ClipKind, text: String, date: Date, file: String? = nil, hash: String? = nil, pinned: Bool = false) {
        self.kind = kind
        self.text = text
        self.date = date
        self.file = file
        self.hash = hash
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey { case kind, text, date, file, hash, pinned }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        // İlk sürümde yalnız yazı vardı
        kind = try c.decodeIfPresent(ClipKind.self, forKey: .kind) ?? (Self.looksLikeLink(text) ? .link : .text)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encodeIfPresent(hash, forKey: .hash)
        if pinned { try c.encode(pinned, forKey: .pinned) }
    }

    /// Tek satırlık, boşluksuz http(s) adresi bağlantı sayılır
    public static func looksLikeLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace), t.hasPrefix("http://") || t.hasPrefix("https://"),
              let url = URL(string: t), url.host != nil else { return false }
        return true
    }

    /// Bağlantının alan adı ("www." olmadan)
    public var host: String? {
        guard kind == .link, let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Listede görünen tek satır: baştaki boşluklar atılır, ilk dolu satır, en çok `limit` harf
    public func title(limit: Int = 80) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    /// "şimdi", "2 dk önce", "3 sa önce", "dün", "12 Eki"
    public func age(now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "şimdi") }
        if seconds < 3600 { return String(localized: "\(Int(seconds / 60)) dk önce") }
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "\(Int(seconds / 3600)) sa önce") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "dün")
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

/// Kopyalananlar, en yeni başta. Belirlenen günden eski olanlar silinir; sabitlenenler kalır.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    /// Gün ne olursa olsun en çok bu kadar kayıt (sabitlenenler hariç)
    public static let limit = 1000
    public private(set) var items: [ClipItem] = []

    public init(items: [ClipItem] = []) {
        self.items = items
        trim()
    }

    /// Yeni yazı ya da bağlantı başa eklenir; aynı yazı zaten varsa yeniden eklenmez, başa çıkar
    /// (sabitliği korunur). Yalnız boşluktan oluşan yazılar eklenmez.
    public mutating func add(_ text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        add(ClipItem(text: text, date: date))
    }

    /// Görsel ya da video: aynı özet ya da aynı dosya varsa başa çıkar
    public mutating func add(_ item: ClipItem) {
        let old = items.first { Self.same($0, item) }
        items.removeAll { Self.same($0, item) }
        var new = item
        if let old {
            new.pinned = old.pinned
            if new.file == nil { new.file = old.file }
        }
        items.insert(new, at: 0)
        trim()
    }

    private static func same(_ a: ClipItem, _ b: ClipItem) -> Bool {
        switch (a.kind, b.kind) {
        case (.text, .text), (.link, .link), (.text, .link), (.link, .text): a.text == b.text
        case (.image, .image), (.video, .video):
            (a.hash != nil && a.hash == b.hash) || (a.file != nil && a.file == b.file)
        default: false
        }
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
    }

    /// Görseldeki yazı okununca aramaya girer
    public mutating func setText(_ text: String, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].text = text
    }

    /// Sabitlenmemişlerin hepsi silinir
    public mutating func clear() {
        items.removeAll { !$0.pinned }
    }

    /// `days` günden eski, sabitlenmemiş kopyalar silinir; silinenler döner (dosyaları da silinsin diye)
    @discardableResult
    public mutating func expire(keepDays days: Int, now: Date = Date()) -> [ClipItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let old = items.filter { !$0.pinned && $0.date < cutoff }
        items.removeAll { !$0.pinned && $0.date < cutoff }
        return old
    }

    private mutating func trim() {
        var unpinned = 0
        items.removeAll { item in
            guard !item.pinned else { return false }
            unpinned += 1
            return unpinned > Self.limit
        }
    }

    /// Bir rafın kopyaları: sabitlenenler başta, sonra en yeniler
    public func shelf(_ shelf: ClipShelf, query: String = "") -> [ClipItem] {
        let list = filtered(query).filter { $0.shelf == shelf }
        return list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    /// İçinde `query` geçenler (büyük/küçük harf ve Türkçe i/İ fark etmez); boşsa hepsi
    public func filtered(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        let needle = Self.fold(q)
        return items.filter { Self.fold($0.text).contains(needle) }
    }

    /// Türkçe küçük harf, şapka/nokta farkı yok, ı = i (aramada "istanbul" "İSTANBUL"u da bulsun)
    private static func fold(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: .diacriticInsensitive, locale: nil)
    }
}

/// Pano geçmişinin ayarı: aç/kapa ve listeyi açan Hyper tuşu
public struct ClipboardSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// Varsayılan: Caps Lock + V
    public var keyCode: UInt16 = 9
    public var key = "V"
    /// Kopyalar kaç gün tutulsun (1-30); sabitlenenler hep kalır
    public var keepDays = 7
    /// Ekran görüntüleri ve ekran kayıtları kaydedildiği klasörden kendiliğinden listeye düşsün
    public var screenshots = true

    public static let dayRange = 1...30

    public init(enabled: Bool = true, keyCode: UInt16 = 9, key: String = "V", keepDays: Int = 7, screenshots: Bool = true) {
        self.enabled = enabled
        self.keyCode = keyCode
        self.key = key
        self.keepDays = keepDays
        self.screenshots = screenshots
    }

    private enum CodingKeys: String, CodingKey { case enabled, keyCode, key, keepDays, screenshots }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keyCode = try c.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? 9
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? "V"
        keepDays = min(max(try c.decodeIfPresent(Int.self, forKey: .keepDays) ?? 7, Self.dayRange.lowerBound), Self.dayRange.upperBound)
        screenshots = try c.decodeIfPresent(Bool.self, forKey: .screenshots) ?? true
    }

    /// Ekran görüntüsü ve kaydı dosya adının başı (Mac'in diline göre); yalnız bunlar listeye düşer
    public static let screenshotPrefixes = [
        "Ekran Resmi", "Ekran Kaydı", "Screenshot", "Screen Recording", "Bildschirmfoto", "Bildschirmaufnahme",
        "Captura de pantalla", "Grabación de pantalla", "Capture d’écran", "Capture d'écran", "Enregistrement de l’écran",
        "スクリーンショット", "画面収録", "Captura de Tela", "Gravação de Tela", "截屏", "录屏",
    ]

    public static func isScreenshot(fileName name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".heic") || lower.hasSuffix(".mov") || lower.hasSuffix(".mp4"),
              !name.hasPrefix(".") else { return false }
        return screenshotPrefixes.contains { name.hasPrefix($0) }
    }
}

/// Geçmişin diskteki dosyası: ~/Library/Application Support/FingerKit/pano.json (depo dışı)
public struct ClipboardFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: ClipboardFile {
        ClipboardFile(url: SettingsFile.folder.appendingPathComponent("pano.json"))
    }

    /// Kopyalanan görsellerin klasörü (pano.json'un yanında)
    public var imageFolder: URL {
        url.deletingLastPathComponent().appendingPathComponent("Pano", isDirectory: true)
    }

    /// Dosya yoksa ya da okunamazsa boş liste
    public func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: url) else { return ClipboardHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ClipboardHistory.self, from: data)) ?? ClipboardHistory()
    }

    public func save(_ history: ClipboardHistory) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(history).write(to: url, options: .atomic)
        // Şifreler de olabilir: yalnız bu kullanıcı okuyabilsin
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
