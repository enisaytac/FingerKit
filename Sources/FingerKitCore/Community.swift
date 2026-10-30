import Foundation

/// "Topluluğun sevdiği ayarlar": her sayfada hazır öneriler. Liste uygulamanın içinde gelir
/// (FingerKit internete bağlanmaz); nereden seçildikleri depodaki notlarda yazar. Sayı/yüzde yok.
public enum CommunityPage: String, CaseIterable, Sendable {
    case gestures, hyper, clipboard, shortcuts, radial
}

/// Bir önerinin ayarlara yaptığı tek değişiklik
public enum CommunityChange: Hashable, Sendable {
    /// "Her yerde" listesine hareket
    case gesture(Gesture, Shortcut)
    /// Caps Lock + tuş → uygulama aç
    case hyperApp(keyCode: UInt16, key: String, bundleID: String, appName: String)
    /// Beş yaslama satırının hepsini aç
    case snaps
    /// Caps Lock + parmak kaydır = pencere taşı
    case windowMove
    /// Pano geçmişi Caps Lock + tuş ile
    case clipboard(keyCode: UInt16, key: String)
    /// Bir uygulamada tetik → başka kısayol
    case appShortcut(bundleID: String, appName: String, trigger: Shortcut, send: Shortcut)
    case radial
    /// Daire menünün alt yarısına uygulama sabitle
    case radialApp(bundleID: String, appName: String)
    /// Daire menünün üst yarısına (o uygulamada) kısayol sabitle
    case radialShortcut(bundleID: String, title: String, send: Shortcut)
    /// Daire menünün üst yarısına Denetim Merkezi düğmesi
    case radialControl(SystemControl)
}

/// Canlı örnekte ne gösterileceği: trackpad'de/klavyede ne yapılır, ekranda ne olur
public struct CommunityDemo: Hashable, Sendable {
    public enum Input: Hashable, Sendable {
        case gesture(Gesture)
        /// Klavyede yanan tuşlar ("⇪", "V")
        case keys([String])
        /// Caps Lock basılıyken parmak kaydırma
        case hyperDrag
    }

    public enum Effect: Hashable, Sendable {
        case newTabFromLink, closeTab, previousTab, nextTab, reopenTab
        case screenshot, fullScreen, lock
        case snap(SnapLayout)
        /// Caps Lock + dört ok sırayla: sol, sağ, üst, alt yarı (tek paket)
        case snapAll
        case moveWindow
        /// Uygulama penceresi öne gelir (SF Symbol adı, renk tonu 0-1)
        case openApp(symbol: String, hue: Double)
        case clipboardList
        case pastePlain
        /// ⌘Q'ya basılır, uygulama kapanmaz, yalnız sekme kapanır
        case quitGuard
        case radialMenu
        /// Tarayıcıda boş sekme açılır / adres çubuğu seçilir
        case newTab, addressBar
        /// Seçili yazı kopyalanır / imlecin yerine yapıştırılır
        case copyText, pasteText
        /// Başka bir uygulamanın penceresinde kısayolun sonucu (daire menü önerileri)
        case app(AppScene)
        /// Dairede Denetim Merkezi dilimi: imleç dilime gider, düğme değişir, ekranda sonucu görünür
        case control(SystemControl)
    }

    /// Daire menü kısayol önerilerinde gösterilen uygulama ve sonuç
    public enum AppScene: Hashable, Sendable {
        case finderNewFolder, finderGoTo, finderHidden
        case notesNew, notesChecklist
        case codePalette, codeTerminal, codeSidebar
        case musicLike, musicSearch
    }

    public var input: Input
    public var effect: Effect

    public init(_ input: Input, _ effect: Effect) {
        self.input = input
        self.effect = effect
    }
}

/// Tek öneri
public struct CommunityPick: Identifiable, Hashable, Sendable {
    public var id: String
    public var page: CommunityPage
    public var title: String
    /// Neden seviliyor, tek cümle
    public var why: String
    public var changes: [CommunityChange]
    public var demo: CommunityDemo
    /// Yalnız bu uygulama kuruluysa gösterilir
    public var needsApp: String?

    public init(_ id: String, _ page: CommunityPage, title: String, why: String, needsApp: String? = nil,
                demo: CommunityDemo, _ changes: [CommunityChange]) {
        self.id = id
        self.page = page
        self.title = title
        self.why = why
        self.changes = changes
        self.demo = demo
        self.needsApp = needsApp
    }

    /// Ayarlarda zaten var mı (hepsi açık ve aynı)
    public func isAdded(in s: Settings) -> Bool {
        changes.allSatisfy { change in
            switch change {
            case let .gesture(g, shortcut):
                return s.apps.first(where: \.isEverywhere)?.bindings
                    .contains { $0.gesture == g && $0.enabled && $0.shortcut.sameKeys(shortcut) } == true
            case let .hyperApp(keyCode, _, bundleID, _):
                return s.hyper.enabled && s.hyper.binding(for: keyCode)?.bundleID == bundleID
            case .snaps:
                return s.hyper.enabled && s.hyper.snaps.allSatisfy(\.enabled)
            case .windowMove:
                return s.hyper.enabled && s.hyper.move
            case let .clipboard(keyCode, _):
                return s.hyper.enabled && s.clipboard.enabled && s.clipboard.keyCode == keyCode
            case let .appShortcut(bundleID, _, trigger, send):
                return s.appShortcuts.enabled && s.appShortcuts.apps.first { $0.bundleID == bundleID }?.shortcuts
                    .contains { $0.enabled && $0.trigger.sameKeys(trigger) && $0.action == .shortcut(send) } == true
            case .radial:
                return s.radial.enabled
            case let .radialApp(bundleID, _):
                return s.radial.enabled && s.radial.appPins.contains { $0?.bundleID == bundleID }
            case let .radialShortcut(bundleID, _, send):
                return s.radial.enabled && (s.radial.shortcutPins[bundleID] ?? []).contains { $0?.keys == send.display }
            case let .radialControl(control):
                return s.radial.enabled && s.radial.controls.contains(control)
            }
        }
    }

    /// Eklenince yerinden edilecek ayarlar (kullanıcıya önce sorulur)
    public func replaces(in s: Settings) -> [String] {
        var result: [String] = []
        for change in changes {
            switch change {
            case let .gesture(g, shortcut):
                if let old = s.apps.first(where: \.isEverywhere)?.bindings.first(where: { $0.gesture == g }),
                   !old.shortcut.sameKeys(shortcut) {
                    result.append(String(localized: "“\(g.name)” şu an \(old.shortcut.display) gönderiyor; onun yerine geçer."))
                }
            case let .hyperApp(keyCode, key, bundleID, _):
                if let old = s.hyper.binding(for: keyCode), old.bundleID != bundleID {
                    result.append(String(localized: "Caps Lock + \(key) şu an \(old.appName) uygulamasını açıyor; onun yerine geçer."))
                }
                if s.hyper.snap(for: keyCode) != nil {
                    result.append(String(localized: "Caps Lock + \(key) pencere yaslamada kullanılıyor; yaslama önce gelir."))
                }
            case let .clipboard(keyCode, key):
                if let old = s.hyper.binding(for: keyCode) {
                    result.append(String(localized: "Caps Lock + \(key) şu an \(old.appName) uygulamasını açıyor; onun yerine geçer."))
                }
                if s.clipboard.enabled, s.clipboard.keyCode != keyCode {
                    result.append(String(localized: "Pano şu an Caps Lock + \(s.clipboard.key) ile açılıyor; tuş \(key) olur."))
                }
            case let .appShortcut(bundleID, _, trigger, _):
                if let old = s.appShortcuts.duplicate(of: trigger, in: bundleID) {
                    result.append(String(localized: "\(trigger.display) bu uygulamada zaten var (\(old.action.display)). Onun yerine geçer."))
                }
            case let .radialControl(control):
                if !s.radial.controls.contains(control), s.radial.controls.count >= RadialMenuSettings.limit {
                    result.append(String(localized: "Üst yarı dolu (\(RadialMenuSettings.limit) düğme); önce birini çıkar."))
                }
            case .snaps, .windowMove, .radial, .radialApp, .radialShortcut:
                break
            }
        }
        return result
    }

    /// Öneriyi ayarlara ekler; kapalı olan bölümü (Hyper Key, pano, daire menü) açar
    public func apply(to s: inout Settings) {
        guard !isAdded(in: s) else { return }
        for change in changes {
            switch change {
            case let .gesture(g, shortcut):
                if !s.apps.contains(where: \.isEverywhere) {
                    s.apps.insert(AppProfile(bundleID: AppProfile.everywhere, name: "Her yerde"), at: 0)
                }
                let a = s.apps.firstIndex(where: \.isEverywhere)!
                s.apps[a].bindings.removeAll { $0.gesture == g }
                s.apps[a].bindings.append(GestureBinding(gesture: g, shortcut: shortcut))
            case let .hyperApp(keyCode, key, bundleID, appName):
                s.hyper.enabled = true
                s.hyper.set(HyperBinding(keyCode: keyCode, key: key, bundleID: bundleID, appName: appName))
            case .snaps:
                s.hyper.enabled = true
                for i in s.hyper.snaps.indices { s.hyper.snaps[i].enabled = true }
            case .windowMove:
                s.hyper.enabled = true
                s.hyper.move = true
            case let .clipboard(keyCode, key):
                s.hyper.enabled = true
                s.hyper.bindings.removeAll { $0.keyCode == keyCode }
                s.clipboard.enabled = true
                s.clipboard.keyCode = keyCode
                s.clipboard.key = key
            case let .appShortcut(bundleID, appName, trigger, send):
                s.appShortcuts.enabled = true
                s.appShortcuts.set(AppShortcut(trigger: trigger, action: .shortcut(send)), in: bundleID, name: appName)
            case .radial:
                s.radial.enabled = true
            case let .radialApp(bundleID, appName):
                s.radial.enabled = true
                guard !s.radial.appPins.contains(where: { $0?.bundleID == bundleID }) else { break }
                s.radial.pinApp(RadialApp(bundleID: bundleID, name: appName), at: Self.freeSlot(s.radial.appPins))
            case let .radialShortcut(bundleID, title, send):
                s.radial.enabled = true
                let pins = s.radial.shortcutPins[bundleID] ?? []
                guard !pins.contains(where: { $0?.keys == send.display }) else { break }
                s.radial.pinShortcut(RadialShortcut(title: title, keys: send.display, action: .shortcut(send)),
                                     at: Self.freeSlot(pins, limit: max(s.radial.shortcutRoom, 1)), for: bundleID)
            case let .radialControl(control):
                s.radial.enabled = true
                s.radial.addControl(control)
            }
        }
    }

    /// Uygulama adları Mac'teki adıyla (ör. "Notes" yerine "Notlar"); `name` bulamazsa olduğu gibi kalır
    public func renamingApps(_ name: (String) -> String?) -> CommunityPick {
        var copy = self
        copy.changes = changes.map { change in
            switch change {
            case let .hyperApp(keyCode, key, bundleID, appName):
                .hyperApp(keyCode: keyCode, key: key, bundleID: bundleID, appName: name(bundleID) ?? appName)
            case let .appShortcut(bundleID, appName, trigger, send):
                .appShortcut(bundleID: bundleID, appName: name(bundleID) ?? appName, trigger: trigger, send: send)
            case let .radialApp(bundleID, appName):
                .radialApp(bundleID: bundleID, appName: name(bundleID) ?? appName)
            default:
                change
            }
        }
        return copy
    }

    /// İlk sabitlenmemiş yuva (hepsi doluysa sonuncusu)
    static func freeSlot<T>(_ pins: [T?], limit: Int = RadialMenuSettings.limit) -> Int {
        (0..<limit).first { $0 >= pins.count || pins[$0] == nil } ?? limit - 1
    }
}

// MARK: - Liste

extension CommunityPick {
    private static func key(_ code: UInt16, _ name: String, _ mods: Modifiers) -> Shortcut {
        Shortcut(keyCode: code, modifiers: mods, key: name)
    }

    public static func picks(for page: CommunityPage) -> [CommunityPick] {
        all.filter { $0.page == page }
    }

    /// Kaynaklar: notlar/topluluk-kaynaklari.md (BetterTouchTool forumları, Hyper Key paylaşımları,
    /// pano ve kısayol rehberleri). Her sayfada en sık anılanlar, sık anılan önce.
    public static var all: [CommunityPick] {
        let cmdW = key(13, "W", [.command])
        return [
            // Hareketler
            CommunityPick("middle-click", .gestures,
                          title: String(localized: "3 parmakla tıkla: orta tık"),
                          why: String(localized: "Bağlantıyı arka sekmede açar, sekmeye tıklayınca kapatır. Fareden gelenlerin ilk aradığı şey."),
                          demo: CommunityDemo(.gesture(.threeFingerClick), .newTabFromLink),
                          [.gesture(.threeFingerClick, Shortcut(mouse: .middle))]),
            CommunityPick("tiptap-tabs", .gestures,
                          title: String(localized: "TipTap: önceki / sonraki sekme"),
                          why: String(localized: "Bir parmak dururken diğeriyle sola ya da sağa dokun; tarayıcıda ve kod düzenleyicide sekmeler arasında gezinirsin."),
                          demo: CommunityDemo(.gesture(.tipTapRight), .nextTab),
                          [.gesture(.tipTapLeft, key(33, "[", [.shift, .command])),
                           .gesture(.tipTapRight, key(30, "]", [.shift, .command]))]),
            CommunityPick("close-tab", .gestures,
                          title: String(localized: "2 parmakla çift dokun: sekmeyi kapat"),
                          why: String(localized: "⌘W'nin hareket hali; klavyeye uzanmadan sekme ya da pencere kapanır."),
                          demo: CommunityDemo(.gesture(.twoFingerDoubleTap), .closeTab),
                          [.gesture(.twoFingerDoubleTap, cmdW)]),
            CommunityPick("reopen-tab", .gestures,
                          title: String(localized: "3 parmakla çift dokun: kapanan sekmeyi geri aç"),
                          why: String(localized: "Yanlışlıkla kapattığın sekme geri gelir (⇧⌘T)."),
                          demo: CommunityDemo(.gesture(.threeFingerDoubleTap), .reopenTab),
                          [.gesture(.threeFingerDoubleTap, key(17, "T", [.shift, .command]))]),
            CommunityPick("screenshot", .gestures,
                          title: String(localized: "4 parmakla dokun: ekran görüntüsü"),
                          why: String(localized: "Seçtiğin alanın görüntüsünü alır (⇧⌘4); üç tuşu birden aramak gerekmez."),
                          demo: CommunityDemo(.gesture(.fourFingerTap), .screenshot),
                          [.gesture(.fourFingerTap, key(21, "4", [.shift, .command]))]),
            CommunityPick("full-screen", .gestures,
                          title: String(localized: "5 parmakla dokun: tam ekran"),
                          why: String(localized: "Öndeki pencere tam ekrana geçer, yeniden dokununca çıkar."),
                          demo: CommunityDemo(.gesture(.fiveFingerTap), .fullScreen),
                          [.gesture(.fiveFingerTap, key(3, "F", [.control, .command]))]),
            CommunityPick("lock", .gestures,
                          title: String(localized: "Sağ üst köşeye dokun: ekranı kilitle"),
                          why: String(localized: "Masadan kalkarken tek dokunuşla ekran kilitlenir (⌃⌘Q)."),
                          demo: CommunityDemo(.gesture(.cornerTapTopRight), .lock),
                          [.gesture(.cornerTapTopRight, key(12, "Q", [.control, .command]))]),

            // Hyper Key
            CommunityPick("snaps", .hyper,
                          title: String(localized: "Caps Lock + oklar: dört yöne yaslama"),
                          why: String(localized: "Tek pakette dört yön: ← sol yarı, → sağ yarı, ↑ üst yarı, ↓ alt yarı; Boşluk ile tam ekran. En sık paylaşılan Hiper kullanımı."),
                          demo: CommunityDemo(.keys(["⇪", "←", "→", "↑", "↓"]), .snapAll),
                          [.snaps]),
            CommunityPick("move", .hyper,
                          title: String(localized: "Caps Lock + kaydır: pencere taşı"),
                          why: String(localized: "Pencereyi başlığından tutmadan, imlecin altından kaydırarak taşırsın."),
                          demo: CommunityDemo(.hyperDrag, .moveWindow),
                          [.windowMove]),
            CommunityPick("hyper-safari", .hyper,
                          title: String(localized: "Caps Lock + S: Safari"),
                          why: String(localized: "Uygulamayı açar, açıksa öne getirir; Dock'a ya da ⌘Sekme'ye gerek kalmaz."),
                          needsApp: "com.apple.Safari",
                          demo: CommunityDemo(.keys(["⇪", "S"]), .openApp(symbol: "safari", hue: 0.58)),
                          [.hyperApp(keyCode: 1, key: "S", bundleID: "com.apple.Safari", appName: "Safari")]),
            CommunityPick("hyper-finder", .hyper,
                          title: String(localized: "Caps Lock + F: Finder"),
                          why: String(localized: "Dosyalara her yerden tek tuşla ulaşırsın."),
                          needsApp: "com.apple.finder",
                          demo: CommunityDemo(.keys(["⇪", "F"]), .openApp(symbol: "folder.fill", hue: 0.56)),
                          [.hyperApp(keyCode: 3, key: "F", bundleID: "com.apple.finder", appName: "Finder")]),
            CommunityPick("hyper-notes", .hyper,
                          title: String(localized: "Caps Lock + N: Notlar"),
                          why: String(localized: "Aklına geleni kaybetmeden hızlı not: Notlar hemen öne gelir."),
                          needsApp: "com.apple.Notes",
                          demo: CommunityDemo(.keys(["⇪", "N"]), .openApp(symbol: "note.text", hue: 0.13)),
                          [.hyperApp(keyCode: 45, key: "N", bundleID: "com.apple.Notes", appName: "Notes")]),
            CommunityPick("hyper-terminal", .hyper,
                          title: String(localized: "Caps Lock + T: Terminal"),
                          why: String(localized: "Geliştiricilerin listesinde hep var: terminal bir tuş uzakta."),
                          needsApp: "com.apple.Terminal",
                          demo: CommunityDemo(.keys(["⇪", "T"]), .openApp(symbol: "apple.terminal", hue: 0.0)),
                          [.hyperApp(keyCode: 17, key: "T", bundleID: "com.apple.Terminal", appName: "Terminal")]),
            CommunityPick("hyper-settings", .hyper,
                          title: String(localized: "Caps Lock + virgül: Sistem Ayarları"),
                          why: String(localized: "Uygulamalarda ayarlar ⌘ virgüldür; Mac'in kendi ayarları da aynı tuşta."),
                          needsApp: "com.apple.systempreferences",
                          demo: CommunityDemo(.keys(["⇪", ","]), .openApp(symbol: "gearshape.fill", hue: 0.6)),
                          [.hyperApp(keyCode: 43, key: ",", bundleID: "com.apple.systempreferences", appName: "System Settings")]),

            // Pano
            CommunityPick("clipboard-v", .clipboard,
                          title: String(localized: "Caps Lock + V: pano geçmişi"),
                          why: String(localized: "Yapıştırmanın (⌘V) yanındaki tuş; son kopyaladıkların listede, seçtiğin yapıştırılır."),
                          demo: CommunityDemo(.keys(["⇪", "V"]), .clipboardList),
                          [.clipboard(keyCode: 9, key: "V")]),
            CommunityPick("copy-tap", .clipboard,
                          title: String(localized: "3 parmakla dokun: kopyala"),
                          why: String(localized: "Seçtiğin yazı tek dokunuşla kopyalanır (⌘C), sonra pano geçmişinde durur."),
                          demo: CommunityDemo(.gesture(.threeFingerTap), .copyText),
                          [.gesture(.threeFingerTap, key(8, "C", [.command]))]),
            CommunityPick("paste-corner", .clipboard,
                          title: String(localized: "Sağ alt köşeye dokun: yapıştır"),
                          why: String(localized: "Son kopyaladığın imlecin yerine gelir (⌘V); klavyeye uzanmazsın."),
                          demo: CommunityDemo(.gesture(.cornerTapBottomRight), .pasteText),
                          [.gesture(.cornerTapBottomRight, key(9, "V", [.command]))]),

            // Kısayollar
            CommunityPick("safari-quit-guard", .shortcuts,
                          title: String(localized: "Safari: ⌘Q yanlışlıkla kapatmasın"),
                          why: String(localized: "⌘W yerine ⌘Q'ya basınca bütün pencereler gider; bu ayarla ⌘Q yalnız sekmeyi kapatır."),
                          needsApp: "com.apple.Safari",
                          demo: CommunityDemo(.keys(["⌘", "Q"]), .quitGuard),
                          [.appShortcut(bundleID: "com.apple.Safari", appName: "Safari", trigger: key(12, "Q", [.command]), send: cmdW)]),
            CommunityPick("chrome-quit-guard", .shortcuts,
                          title: String(localized: "Chrome: ⌘Q yanlışlıkla kapatmasın"),
                          why: String(localized: "⌘W yerine ⌘Q'ya basınca bütün pencereler gider; bu ayarla ⌘Q yalnız sekmeyi kapatır."),
                          needsApp: "com.google.Chrome",
                          demo: CommunityDemo(.keys(["⌘", "Q"]), .quitGuard),
                          [.appShortcut(bundleID: "com.google.Chrome", appName: "Google Chrome", trigger: key(12, "Q", [.command]), send: cmdW)]),
            pastePlain("notes-paste-plain", "com.apple.Notes", "Notes", String(localized: "Notlar: ⇧⌘V biçimsiz yapıştır")),
            pastePlain("mail-paste-plain", "com.apple.mail", "Mail", String(localized: "Mail: ⇧⌘V biçimsiz yapıştır")),
            pastePlain("textedit-paste-plain", "com.apple.TextEdit", "TextEdit", String(localized: "TextEdit: ⇧⌘V biçimsiz yapıştır")),
            pastePlain("pages-paste-plain", "com.apple.iWork.Pages", "Pages", String(localized: "Pages: ⇧⌘V biçimsiz yapıştır")),

            // Daire menü
            CommunityPick("radial-on", .radial,
                          title: String(localized: "Sol alt köşeye tıkla: daire menü"),
                          why: String(localized: "İmlecin yanında açılır: altta sık kullandığın uygulamalar, üstte öndeki uygulamanın kısayolları."),
                          demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .radialMenu),
                          [.radial]),
            CommunityPick("radial-finder", .radial,
                          title: String(localized: "Finder hep dairede"),
                          why: String(localized: "Dock'taki gibi sabit bir yer: dosyalar her zaman aynı dilimde."),
                          needsApp: "com.apple.finder",
                          demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .openApp(symbol: "folder.fill", hue: 0.56)),
                          [.radialApp(bundleID: "com.apple.finder", appName: "Finder")]),
            CommunityPick("radial-settings", .radial,
                          title: String(localized: "Sistem Ayarları hep dairede"),
                          why: String(localized: "Ses, ekran, Wi-Fi ayarları iki hareket uzakta."),
                          needsApp: "com.apple.systempreferences",
                          demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .openApp(symbol: "gearshape.fill", hue: 0.6)),
                          [.radialApp(bundleID: "com.apple.systempreferences", appName: "System Settings")]),
            CommunityPick("radial-safari-reopen", .radial,
                          title: String(localized: "Safari'de: kapanan sekmeyi geri aç"),
                          why: String(localized: "Safari öndeyken dairenin üst yarısında hep ilk sırada durur."),
                          needsApp: "com.apple.Safari",
                          demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .reopenTab),
                          [.radialShortcut(bundleID: "com.apple.Safari", title: String(localized: "Kapanan sekmeyi aç"),
                                           send: key(17, "T", [.shift, .command]))]),
            radialControl(.bluetooth, String(localized: "Dairede Bluetooth anahtarı"),
                          why: String(localized: "Kulaklığı bağlamadan önce tek tık; Denetim Merkezi'ni açmana gerek yok.")),
            radialControl(.volume, String(localized: "Dairede ses çubuğu"),
                          why: String(localized: "Dilime basıp sürükle: ses yarım ay çubukta iner ya da çıkar.")),
            radialControl(.brightness, String(localized: "Dairede parlaklık çubuğu"),
                          why: String(localized: "Akşam ekranı kısmak için tuş aramazsın; dilimi içe doğru sürükle.")),
            radialControl(.airDrop, String(localized: "Dairede AirDrop seçimi"),
                          why: String(localized: "Herkes / Yalnızca Kişiler / Kapalı: telefondan fotoğraf alırken bir tıkta açılır.")),
            radialControl(.focus, String(localized: "Dairede Rahatsız Etme"),
                          why: String(localized: "Toplantıya girerken bildirimleri tek tıkla sustur.")),
            radialControl(.darkMode, String(localized: "Dairede koyu görünüm"),
                          why: String(localized: "Gece gündüz arasında Mac'in bütün görünümü tek tıkla değişir.")),
            radialControl(.wifi, String(localized: "Dairede Wi-Fi anahtarı"),
                          why: String(localized: "Ağ takılınca kapat-aç; Denetim Merkezi'ni aramazsın.")),
            radialKey("radial-safari-new-tab", "com.apple.Safari", String(localized: "Safari'de: yeni sekme"),
                      String(localized: "Yeni sekme"), key(17, "T", [.command]), .newTab,
                      why: String(localized: "Klavyeye uzanmadan boş sekme; imleç zaten dairede.")),
            radialKey("radial-safari-address", "com.apple.Safari", String(localized: "Safari'de: adres çubuğuna git"),
                      String(localized: "Adres çubuğu"), key(37, "L", [.command]), .addressBar,
                      why: String(localized: "Adres seçili gelir, hemen yazıp aramaya başlarsın.")),
            radialKey("radial-chrome-new-tab", "com.google.Chrome", String(localized: "Chrome'da: yeni sekme"),
                      String(localized: "Yeni sekme"), key(17, "T", [.command]), .newTab,
                      why: String(localized: "Klavyeye uzanmadan boş sekme; imleç zaten dairede.")),
            radialKey("radial-chrome-reopen", "com.google.Chrome", String(localized: "Chrome'da: kapanan sekmeyi geri aç"),
                      String(localized: "Kapanan sekmeyi aç"), key(17, "T", [.shift, .command]), .reopenTab,
                      why: String(localized: "Yanlışlıkla kapattığın sekme geri gelir (⇧⌘T).")),
            radialKey("radial-finder-new-folder", "com.apple.finder", String(localized: "Finder'da: yeni klasör"),
                      String(localized: "Yeni klasör"), key(45, "N", [.shift, .command]), .app(.finderNewFolder),
                      why: String(localized: "Klasör açılır, adı yazılmaya hazır gelir.")),
            radialKey("radial-finder-go", "com.apple.finder", String(localized: "Finder'da: klasöre git"),
                      String(localized: "Klasöre git"), key(5, "G", [.shift, .command]), .app(.finderGoTo),
                      why: String(localized: "Yolu yazarsın, gizli klasörlere bile tek adımda gidersin.")),
            radialKey("radial-finder-hidden", "com.apple.finder", String(localized: "Finder'da: gizli dosyaları göster"),
                      String(localized: "Gizli dosyalar"), key(47, ".", [.shift, .command]), .app(.finderHidden),
                      why: String(localized: "Gizli dosyalar soluk görünür; bir daha seçince yine gizlenir.")),
            radialKey("radial-notes-new", "com.apple.Notes", String(localized: "Notlar'da: yeni not"),
                      String(localized: "Yeni not"), key(45, "N", [.command]), .app(.notesNew),
                      why: String(localized: "Boş not en üstte açılır, hemen yazmaya başlarsın.")),
            radialKey("radial-notes-checklist", "com.apple.Notes", String(localized: "Notlar'da: yapılacaklar listesi"),
                      String(localized: "Yapılacaklar listesi"), key(37, "L", [.shift, .command]), .app(.notesChecklist),
                      why: String(localized: "Satırların başına işaret yuvarlakları gelir; liste bir dokunuşta hazır.")),
            radialKey("radial-code-palette", "com.microsoft.VSCode", String(localized: "VS Code'da: komut paleti"),
                      String(localized: "Komut paleti"), key(35, "P", [.shift, .command]), .app(.codePalette),
                      why: String(localized: "Bütün komutlar tek kutuda; adını yazıp seçersin.")),
            radialKey("radial-code-terminal", "com.microsoft.VSCode", String(localized: "VS Code'da: terminali aç/kapat"),
                      String(localized: "Terminal"), key(50, "`", [.control]), .app(.codeTerminal),
                      why: String(localized: "Terminal alttan açılır; ⌃` tuşunu aramak gerekmez.")),
            radialKey("radial-code-sidebar", "com.microsoft.VSCode", String(localized: "VS Code'da: kenar çubuğunu gizle"),
                      String(localized: "Kenar çubuğu"), key(11, "B", [.command]), .app(.codeSidebar),
                      why: String(localized: "Dosya listesi kapanır, kod bütün pencereye yayılır.")),
            radialKey("radial-spotify-like", "com.spotify.client", String(localized: "Spotify'da: şarkıyı beğen"),
                      String(localized: "Beğen"), key(11, "B", [.option, .shift]), .app(.musicLike),
                      why: String(localized: "Çalan şarkı beğenilenlere eklenir; pencereyi aramazsın.")),
            radialKey("radial-spotify-search", "com.spotify.client", String(localized: "Spotify'da: ara"),
                      String(localized: "Ara"), key(40, "K", [.command]), .app(.musicSearch),
                      why: String(localized: "Arama kutusu seçili gelir, şarkının adını yazarsın.")),
        ]
    }

    /// Daire menünün üst yarısına o uygulamada bir kısayol: önizlemede imleç dilime gider, sonuç görünür
    private static func radialKey(_ id: String, _ bundleID: String, _ title: String, _ slice: String, _ send: Shortcut,
                                  _ effect: CommunityDemo.Effect, why: String) -> CommunityPick {
        CommunityPick(id, .radial, title: title, why: why, needsApp: bundleID,
                      demo: CommunityDemo(.gesture(.cornerTapBottomLeft), effect),
                      [.radialShortcut(bundleID: bundleID, title: slice, send: send)])
    }

    /// Daire menünün üst yarısına Denetim Merkezi düğmesi: önizlemede düğme değişir, ekranda sonucu görünür
    private static func radialControl(_ control: SystemControl, _ title: String, why: String) -> CommunityPick {
        CommunityPick("radial-control-\(control.rawValue)", .radial, title: title, why: why,
                      demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .control(control)),
                      [.radialControl(control)])
    }

    /// Notlar, Mail, TextEdit, Pages: "Yapıştır ve Stili Eşle" ⌥⇧⌘V'dir; ⇧⌘V ona yönlenir
    private static func pastePlain(_ id: String, _ bundleID: String, _ name: String, _ title: String) -> CommunityPick {
        CommunityPick(id, .shortcuts, title: title,
                      why: String(localized: "Web'den kopyalanan yazı kendi rengi ve boyuyla gelmesin; ⌥⇧⌘V'yi aramak gerekmez."),
                      needsApp: bundleID,
                      demo: CommunityDemo(.keys(["⇧", "⌘", "V"]), .pastePlain),
                      [.appShortcut(bundleID: bundleID, appName: name, trigger: key(9, "V", [.shift, .command]),
                                    send: key(9, "V", [.option, .shift, .command]))])
    }
}
