import CoreGraphics
import Foundation

/// Hyper + bir tuş → bir uygulamayı aç (açıksa öne getir).
public struct HyperBinding: Codable, Identifiable, Hashable, Sendable {
    /// Yalnız arayüz için; dosyaya yazılmaz
    public var id = UUID()
    /// Tuşun konum numarası (klavye düzeninden bağımsız)
    public var keyCode: UInt16
    /// Ekranda görünen tuş adı ("S")
    public var key: String
    /// Açılacak uygulamanın kimliği (ör. com.apple.Safari)
    public var bundleID: String
    public var appName: String
    /// Uygulama açmak yerine hazır iş (pencereyi küçült, site aç, Kestirme…); nil = uygulamayı aç
    public var task: ReadyTask?

    public init(keyCode: UInt16, key: String, bundleID: String, appName: String) {
        self.keyCode = keyCode
        self.key = key
        self.bundleID = bundleID
        self.appName = appName
    }

    public init(keyCode: UInt16, key: String, task: ReadyTask) {
        self.init(keyCode: keyCode, key: key, bundleID: "", appName: task.title)
        self.task = task
    }

    /// Satırda ne yaptığı: uygulamanın adı ya da hazır işin adı (ve kısayolu)
    public var display: String { task?.label ?? appName }

    private enum CodingKeys: String, CodingKey { case keyCode, key, bundleID, appName, task }
}

/// Pencerenin ekranda alacağı yer
public enum SnapLayout: String, Codable, CaseIterable, Sendable {
    case left, right, top, bottom, fill

    public var title: String {
        switch self {
        case .left: String(localized: "Sol yarı")
        case .right: String(localized: "Sağ yarı")
        case .top: String(localized: "Üst yarı")
        case .bottom: String(localized: "Alt yarı")
        case .fill: String(localized: "Ekranı doldur")
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // İlk sürümdeki "center" (ortala) kullanıcı isteğiyle "ekranı doldur" oldu
        guard let layout = Self(rawValue: raw == "center" ? "fill" : raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bilinmeyen yerleşim: \(raw)"))
        }
        self = layout
    }

    /// Pencerenin yeni yeri. `visible`: ekranın menü çubuğu ve Dock dışında kalan alanı.
    /// İkisi de aynı koordinatta (üst sol köşe başlangıç, y aşağı doğru artar).
    public func frame(in visible: CGRect) -> CGRect {
        let v = visible
        switch self {
        case .left: return CGRect(x: v.minX, y: v.minY, width: (v.width / 2).rounded(), height: v.height)
        case .right:
            let w = (v.width / 2).rounded()
            return CGRect(x: v.maxX - w, y: v.minY, width: w, height: v.height)
        case .top: return CGRect(x: v.minX, y: v.minY, width: v.width, height: (v.height / 2).rounded())
        case .bottom:
            let h = (v.height / 2).rounded()
            return CGRect(x: v.minX, y: v.maxY - h, width: v.width, height: h)
        case .fill: return v
        }
    }

    /// Uygulama pencereyi istenenden büyük bırakırsa (en küçük boyut sınırı) hangi kenara
    /// yapışık kalsın: sağ yarı sağ kenara, alt yarı alt kenara.
    public func align(_ actual: CGSize, to target: CGRect) -> CGPoint {
        switch self {
        case .left, .top, .fill: target.origin
        case .right: CGPoint(x: target.maxX - actual.width, y: target.minY)
        case .bottom: CGPoint(x: target.minX, y: target.maxY - actual.height)
        }
    }
}

/// Hyper + bir tuş → öndeki pencereyi yerleştir.
public struct SnapBinding: Codable, Identifiable, Hashable, Sendable {
    /// Yalnız arayüz için; dosyaya yazılmaz
    public var id = UUID()
    public var layout: SnapLayout
    public var keyCode: UInt16
    public var key: String
    public var enabled = true

    public init(layout: SnapLayout, keyCode: UInt16, key: String, enabled: Bool = true) {
        self.layout = layout
        self.keyCode = keyCode
        self.key = key
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case layout, keyCode, key, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try c.decode(SnapLayout.self, forKey: .layout)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        key = try c.decode(String.self, forKey: .key)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Caps Lock'un Hyper tuşu olması: tek basış büyük harf kilidi, başka tuşla birlikte ⌘⌥⌃⇧.
public struct HyperSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var bindings: [HyperBinding]
    /// Pencere yaslama satırları (her yerleşimden bir tane)
    public var snaps: [SnapBinding]
    /// Caps Lock basılıyken parmak kaydırmak imlecin altındaki pencereyi taşır
    public var move = true

    public init(enabled: Bool = true, bindings: [HyperBinding], snaps: [SnapBinding] = Self.defaultSnaps, move: Bool = true) {
        self.enabled = enabled
        self.bindings = bindings
        self.snaps = snaps
        self.move = move
    }

    private enum CodingKeys: String, CodingKey { case enabled, bindings, snaps, move }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        bindings = try c.decodeIfPresent([HyperBinding].self, forKey: .bindings) ?? []
        move = try c.decodeIfPresent(Bool.self, forKey: .move) ?? true
        if let saved = try c.decodeIfPresent([SnapBinding].self, forKey: .snaps) {
            snaps = saved
        } else {
            // 2. aşamadan kalan dosya: yaslama satırları ve Hyper+C VS Code bir kez eklenir
            snaps = Self.defaultSnaps
            if !bindings.contains(where: { $0.keyCode == Self.vsCode.keyCode }) { bindings.append(Self.vsCode) }
        }
    }

    /// Bu tuşa bağlı uygulama; yoksa Hyper+tuş ⌘⌥⌃⇧+tuş olarak geçer
    public func binding(for keyCode: UInt16) -> HyperBinding? {
        bindings.first { $0.keyCode == keyCode }
    }

    /// Bu tuşa bağlı, açık yaslama satırı. Aynı tuş uygulama açmaya da bağlıysa yaslama önce gelir.
    public func snap(for keyCode: UInt16) -> SnapBinding? {
        snaps.first { $0.keyCode == keyCode && $0.enabled }
    }

    /// Bu tuşu kullanan başka yaslama satırı (açık ya da kapalı; `editing` sayılmaz)
    public func snapUsing(_ keyCode: UInt16, editing: UUID? = nil) -> SnapBinding? {
        snaps.first { $0.keyCode == keyCode && $0.id != editing }
    }

    /// Aynı tuşu kullanan başka satır (`editing` satırın kendisi sayılmaz)
    public func duplicate(of keyCode: UInt16, editing: UUID? = nil) -> HyperBinding? {
        bindings.first { $0.keyCode == keyCode && $0.id != editing }
    }

    /// Satırı ekler; aynı tuş başka satırdaysa o satır silinir (yenisi onun yerine geçer).
    public mutating func set(_ binding: HyperBinding) {
        bindings.removeAll { $0.keyCode == binding.keyCode && $0.id != binding.id }
        if let i = bindings.firstIndex(where: { $0.id == binding.id }) {
            bindings[i] = binding
        } else {
            bindings.append(binding)
        }
    }

    /// İlk sürümün üç kısayolu: Hyper+S Safari, Hyper+N Notes, Hyper+F Finder
    public static let defaults = HyperSettings(bindings: [
        HyperBinding(keyCode: 1, key: "S", bundleID: "com.apple.Safari", appName: "Safari"),
        HyperBinding(keyCode: 45, key: "N", bundleID: "com.apple.Notes", appName: "Notes"),
        HyperBinding(keyCode: 3, key: "F", bundleID: "com.apple.finder", appName: "Finder"),
        vsCode,
    ])

    /// Yeni kullanıcı: Caps Lock'a dokunulmaz; yaslama satırları kapalı durur
    public static let off = HyperSettings(enabled: false, bindings: [],
                                          snaps: defaultSnaps.map { var s = $0; s.enabled = false; return s }, move: false)

    static let vsCode = HyperBinding(keyCode: 8, key: "C", bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code")

    /// 3. aşamanın beş yerleşimi: Hyper + oklar yarımlar, Hyper + Boşluk ekranı doldurur
    public static let defaultSnaps = [
        SnapBinding(layout: .left, keyCode: 123, key: "←"),
        SnapBinding(layout: .right, keyCode: 124, key: "→"),
        SnapBinding(layout: .top, keyCode: 126, key: "↑"),
        SnapBinding(layout: .bottom, keyCode: 125, key: "↓"),
        SnapBinding(layout: .fill, keyCode: 49, key: String(localized: "Boşluk")),
    ]
}
