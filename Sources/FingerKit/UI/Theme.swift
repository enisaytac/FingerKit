import AppKit
import SwiftUI

/// Pencerenin teması: sağ üstteki tema düğmesinden seçilir. İlk açılışta Gece.
enum AppTheme: String, CaseIterable {
    case system, night, light

    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .night: String(localized: "Gece")
        case .light: String(localized: "Açık")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .night: "moon.stars.fill"
        case .light: "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme { ThemePalette.of(self).dark ? .dark : .light }

    /// Menüler ve açılan küçük pencereler de aynı görünsün
    var appearance: NSAppearance? {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}

/// Vurgu rengi: düğmeler, anahtarlar, seçili satırlar. FingerKit'in sarısı ya da Mac'in kendi rengi.
enum AccentChoice: String, CaseIterable {
    case gold, system, blue, green, pink, graphite

    var title: String {
        switch self {
        case .gold: String(localized: "FingerKit sarısı")
        case .system: String(localized: "Mac'in rengi")
        case .blue: String(localized: "Mavi")
        case .green: String(localized: "Yeşil")
        case .pink: String(localized: "Pembe")
        case .graphite: String(localized: "Grafit")
        }
    }

    var color: Color {
        switch self {
        // Açık zeminde sarı yazı okunmaz: açıkta koyu bal rengi, koyuda parlak sarı
        case .gold: .themeGold
        case .system: .accentColor
        case .blue: Color(red: 0.04, green: 0.52, blue: 1)
        case .green: Color(red: 0.2, green: 0.78, blue: 0.35)
        case .pink: Color(red: 1, green: 0.22, blue: 0.47)
        case .graphite: Color(white: 0.55)
        }
    }
}

/// Bir temanın katman renkleri: zemin, sol sütun ve üst çubuk, kart, kartın içindeki çukur alan.
/// Her katman bir öncekinden bir ton ayrı; bölümler birbirine girmez. Temalar Mac'in görünümüne bağlı değil.
struct ThemePalette {
    var dark: Bool
    var page, chrome, card, well: UInt32
    var stroke: NSColor
    /// FingerKit sarısı bu zeminde: koyuda parlak, açıkta okunsun diye koyusu
    var gold: UInt32

    /// FingerKit'in tek sarısı; bütün sarılar (vurgu, parmaklar, daire, önizlemeler) bundan türer.
    /// Deneme için `FINGERKIT_SARI=ffc400` ile değiştirilebilir.
    static let yellow: UInt32 = ProcessInfo.processInfo.environment["FINGERKIT_SARI"].flatMap { UInt32($0, radix: 16) } ?? 0xffd60a

    /// Sarının açık zeminde okunan koyusu (aynı renk tonu, parlaklık düşük)
    static var yellowOnLight: UInt32 { scaled(yellow, brightness: 0.62) }

    /// Gece: grafit katmanlar (değişmez)
    static let night = ThemePalette(dark: true, page: 0x16161a, chrome: 0x1e1e22, card: 0x27272b, well: 0x19191d,
                                    stroke: NSColor(white: 1, alpha: 0.09), gold: yellow)
    /// Sistem: kehribar gece, sıcak kahve-siyah katmanlar
    static let amber = ThemePalette(dark: true, page: 0x1a1813, chrome: 0x221f19, card: 0x2c2820, well: 0x1d1a15,
                                    stroke: rgb(0xffe8a0).withAlphaComponent(0.09), gold: yellow)
    /// Açık: macOS Sistem Ayarları gibi gri pencere, açık gruplar
    static let settings = ThemePalette(dark: false, page: 0xececec, chrome: 0xe3e3e3, card: 0xf9f9f9, well: 0xe6e6e6,
                                       stroke: NSColor(white: 0, alpha: 0.09), gold: yellowOnLight)

    static func of(_ theme: AppTheme) -> ThemePalette {
        switch theme {
        case .night: night
        case .system: amber
        case .light: settings
        }
    }

    private static func scaled(_ v: UInt32, brightness: CGFloat) -> UInt32 {
        let c = rgb(v)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        let d = NSColor(hue: h, saturation: sat, brightness: b * brightness, alpha: 1)
        return (UInt32(d.redComponent * 255) << 16) | (UInt32(d.greenComponent * 255) << 8) | UInt32(d.blueComponent * 255)
    }

    /// Şu an çizilen tema (ThemeModifier değiştirir)
    nonisolated(unsafe) static var current = night

    fileprivate static func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    /// Büyük pano gibi her zaman koyu olan yüzeylerin zemini
    static let nightBackground = Color(red: 0.086, green: 0.086, blue: 0.098)

    /// Sayfa zemini
    static let page = layer { ThemePalette.rgb($0.page) }
    /// Sol sütun, üst çubuk ve sağ panel
    static let chrome = layer { ThemePalette.rgb($0.chrome) }
    /// Kart zemini
    static let card = layer { ThemePalette.rgb($0.card) }
    /// Kart kenarı
    static let cardStroke = layer { $0.stroke }
    /// Kartın içindeki çukur alan (tuş kutusu, alan)
    static let well = layer { ThemePalette.rgb($0.well) }
    /// FingerKit sarısı, temanın zeminine göre
    static let themeGold = layer { ThemePalette.rgb($0.gold) }

    private static func layer(_ pick: @escaping @Sendable (ThemePalette) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in pick(ThemePalette.current) })
    }
}

/// Pencerenin tamamına tema ve vurgu rengini uygular
struct ThemeModifier: ViewModifier {
    @AppStorage("theme") private var theme = AppTheme.night
    @AppStorage("accent") private var accent = AccentChoice.green

    func body(content: Content) -> some View {
        let _ = ThemePalette.current = ThemePalette.of(theme)
        content
            // Aynı görünümdeki iki tema arasında geçince katman renkleri yeniden okunsun
            .id(theme)
            .tint(accent.color)
            .buttonStyle(SoftButtonStyle())
            .menuStyle(.button)
            .preferredColorScheme(theme.colorScheme)
            .toolbarBackground(Color.chrome, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .onAppear { NSApp.appearance = theme.appearance }
            .onChange(of: theme) { _, t in NSApp.appearance = t.appearance }
    }
}

/// Sayfa ve sütun zemini: sistemin grisi yerine FingerKit'in katman renkleri (her temada)
struct NightBackground: ViewModifier {
    var sidebar = false

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(sidebar ? Color.chrome : Color.page)
    }
}

/// Sağ üstteki tema düğmesi: Sistem / Gece / Açık ve vurgu rengi
struct ThemeButton: View {
    @Environment(Engine.self) private var engine
    @AppStorage("theme") private var theme = AppTheme.night
    @AppStorage("accent") private var accent = AccentChoice.green

    /// Hareket ya da tuş çalışınca ortada kısa süre ne yapıldığı yazsın mı
    private var notify: Binding<Bool> {
        Binding(get: { engine.settings.notify }, set: { engine.settings.notify = $0 })
    }

    var body: some View {
        Menu {
            Picker(String(localized: "Tema"), selection: $theme) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Label(t.title, systemImage: t.symbol).tag(t)
                }
            }
            .pickerStyle(.inline)
            Picker(String(localized: "Vurgu rengi"), selection: $accent) {
                ForEach(AccentChoice.allCases, id: \.self) { a in
                    Label {
                        Text(a.title)
                    } icon: {
                        Image(nsImage: Self.swatch(a))
                    }
                    .tag(a)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle(String(localized: "Ekran bildirimi"), isOn: notify)
        } label: {
            Label(String(localized: "Tema"), systemImage: theme.symbol)
        }
        .help(String(localized: "Tema ve vurgu rengi"))
    }

    /// Menüde renk yuvarlağı (menüler SwiftUI renklerini simgede göstermez; resim çizilir)
    private static func swatch(_ a: AccentChoice) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            (a == .system ? NSColor.controlAccentColor : NSColor(a.color)).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        return image
    }
}

/// Pencerenin biçimi ("Sade" yönü, 30 Ekim 2026 seçimi): orta köşeler, geniş boşluklar, kenar çizgisi yerine ton farkı,
/// sarı yalnız seçili şeyde. Bütün ekranlar sabit sayı yerine buradan okur; parçalar Soft.swift'te.
enum UIStyle {
    /// Küçük köşe: tuş kutusu, çip, küçük alan
    static let small: CGFloat = 8
    /// Kart, grup, uyarı kutusu
    static let card: CGFloat = 14
    /// Ayrı pencereler: pano, menü çubuğu penceresi, bildirim
    static let panel: CGFloat = 18
    /// Boşluk çarpanı (1 = eski ölçü)
    static let space: CGFloat = 1.4
    /// Kartın gölgesi (0 yok, 1 belirgin): yalnız ipucu kadar
    static let shadow = 0.25
    /// Hap düğmenin yüksekliği
    static let control: CGFloat = 30
    /// Daire menü diliminin köşesi ve dilimler arası boşluk
    static let sliceRound: CGFloat = 7
    static let sliceGap: CGFloat = 4

    /// Boşluk ölçeği: `UIStyle.pad(16)` eski 16'nın bu biçimdeki karşılığı
    static func pad(_ v: CGFloat) -> CGFloat { (v * space).rounded() }
}

extension Shape where Self == RoundedRectangle {
    /// Kart biçimi (Apple'ın yumuşak köşe eğrisiyle)
    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: UIStyle.card, style: .continuous) }
    /// Tuş kutusu, çukur alan biçimi
    static var small: RoundedRectangle { RoundedRectangle(cornerRadius: UIStyle.small, style: .continuous) }
    /// Ayrı pencere biçimi
    static var panel: RoundedRectangle { RoundedRectangle(cornerRadius: UIStyle.panel, style: .continuous) }
}
