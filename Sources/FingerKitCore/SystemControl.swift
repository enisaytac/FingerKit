import Foundation

/// Daire menünün üst yarısına konabilen Denetim Merkezi düğmesi. Her uygulamada aynı kalır;
/// üst yarının geri kalanına öndeki uygulamanın kısayolları gelir.
public enum SystemControl: String, Codable, CaseIterable, Sendable {
    case wifi, bluetooth, focus, darkMode, volume, brightness, airDrop, screenMirroring

    public enum Kind: Sendable {
        /// Tıklayınca açılır/kapanır; dilimde aç/kapa anahtarı görünür
        case toggle
        /// Dilimin kendisi yarım ay biçiminde çubuk; sürükleyince değişir
        case slider
        /// Tıklayınca açılır/kapanır; iki parmakla tıklayınca küçük seçim açılır (AirDrop: Kapalı / Kişiler / Herkes)
        case choice
        /// Tıklayınca Denetim Merkezi'nde ilgili bölüm açılır (ekran yansıtma: aygıt listesi)
        case panel
    }

    public var kind: Kind {
        switch self {
        case .wifi, .bluetooth, .focus, .darkMode: .toggle
        case .volume, .brightness: .slider
        case .airDrop: .choice
        case .screenMirroring: .panel
        }
    }

    public var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .focus: String(localized: "Rahatsız Etme")
        case .darkMode: String(localized: "Koyu görünüm")
        case .volume: String(localized: "Ses")
        case .brightness: String(localized: "Parlaklık")
        case .airDrop: "AirDrop"
        case .screenMirroring: String(localized: "Ekran yansıtma")
        }
    }

    /// Dilimde ve listede görünen simge (SF Symbols); `on` kapalıyken farklı simgesi olanlar için.
    /// Bluetooth'un sistemde simgesi yok; arayüz onu kendisi çizer, bu ad yalnız yedek.
    public func symbol(on: Bool = true) -> String {
        switch self {
        case .wifi: on ? "wifi" : "wifi.slash"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .focus: "moon.fill"
        case .darkMode: "circle.lefthalf.filled"
        case .volume: on ? "speaker.wave.2.fill" : "speaker.slash.fill"
        case .brightness: "sun.max.fill"
        case .airDrop: "dot.radiowaves.up.forward"
        case .screenMirroring: "rectangle.on.rectangle"
        }
    }

    /// Sekmede ne yaptığını anlatan kısa cümle
    public var detail: String {
        switch self {
        case .wifi: String(localized: "Tıkla: Wi-Fi açılır ya da kapanır.")
        case .bluetooth: String(localized: "Tıkla: Bluetooth açılır ya da kapanır.")
        case .focus: String(localized: "Tıkla: bildirimler susar ya da geri gelir.")
        case .darkMode: String(localized: "Tıkla: Mac koyu ve açık görünüm arasında geçer.")
        case .volume: String(localized: "Dilime bas ve sürükle: ses değişir. İçe doğru kısılır, dışa doğru açılır.")
        case .brightness: String(localized: "Dilime bas ve sürükle: ekran parlaklığı değişir.")
        case .airDrop: String(localized: "Tıkla: açılır ya da kapanır. İki parmakla tıkla: Herkes / Yalnızca Kişiler seçimi.")
        case .screenMirroring: String(localized: "Tıkla: Denetim Merkezi'nde yansıtılacak ekran listesi açılır.")
        }
    }

    /// Yeni kullanıcının ve eski ayar dosyalarının üst yarısı
    public static let defaults: [SystemControl] = [.bluetooth, .volume, .brightness, .airDrop]
}

/// AirDrop'un kimlere açık olduğu (Denetim Merkezi'ndeki üç seçenek)
public enum AirDropMode: String, CaseIterable, Sendable {
    case off, contacts, everyone

    /// `com.apple.sharingd` › `DiscoverableMode` değerinden
    public init(discoverable: String?) {
        switch discoverable {
        case "Everyone": self = .everyone
        case "Contacts Only": self = .contacts
        default: self = .off
        }
    }

    public var title: String {
        switch self {
        case .off: String(localized: "Kapalı")
        case .contacts: String(localized: "Yalnızca Kişiler")
        case .everyone: String(localized: "Herkes")
        }
    }

    /// Dilimde görünen kısa ad
    public var short: String {
        switch self {
        case .off: String(localized: "Kapalı")
        case .contacts: String(localized: "Kişiler")
        case .everyone: String(localized: "Herkes")
        }
    }
}

/// Bir düğmenin o anki durumu (daire açılınca okunur)
public enum ControlValue: Hashable, Sendable {
    case on(Bool)
    /// 0-1
    case level(Double)
    case airDrop(AirDropMode)
    /// Okunamadı (izin yok ya da bu Mac'te yok)
    case unknown

    /// Çubuk değeri (yalnız ses/parlaklık)
    public var levelValue: Double? {
        if case .level(let v) = self { return v }
        return nil
    }

    public var isOn: Bool {
        switch self {
        case .on(let b): b
        case .level(let v): v > 0
        case .airDrop(let m): m != .off
        case .unknown: false
        }
    }
}

/// Üst yarı: önce Denetim Merkezi düğmeleri (her uygulamada aynı), kalan yuvalarda kısayollar
public enum RadialTop {
    /// Kısayollara kalan yuva sayısı
    public static func shortcutRoom(controls: Int) -> Int {
        max(RadialMenuSettings.limit - controls, 0)
    }

    /// Yarım ay çubukta imlecin değeri: dilimin iç kenarı 0, dış kenarı 1
    public static func level(radius r: Double, inner: Double, outer: Double) -> Double {
        guard outer > inner else { return 0 }
        return min(max((r - inner) / (outer - inner), 0), 1)
    }
}
