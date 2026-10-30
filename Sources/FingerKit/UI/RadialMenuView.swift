import SwiftUI
import FingerKitCore

/// "Daire menü" sekmesi: aç/kapa, önizleme, iki yarının 6 yuvası (sabitle, değiştir)
struct RadialMenuView: View {
    @Environment(Engine.self) private var engine
    @Environment(RadialUIState.self) private var state
    private let usage = AppUsage.shared
    @State private var menu: [MenuShortcutEntry] = []
    /// Mac'teki kestirmeler (hazır işler listesi için)
    @State private var macShortcuts: [String]?

    /// Üst yarısı düzenlenen uygulama; soldaki listeden seçilir
    private var shortcutApp: String? { state.shortcutApp }

    var body: some View {
        let radial = engine.settings.radial
        let appSlots = radial.apps(auto: RadialMenu.autoApps())
        let bundleID = shortcutApp ?? defaultShortcutApp
        let shortcutSlots = radial.shortcuts(for: bundleID, auto: PopularShortcuts.auto(for: bundleID, menu: menu))
        VStack(spacing: 0) {
            header
            ScrollView {
                // Öneriler sayfayla birlikte kayar: açılınca sayfayı pencereden taşırmaz
                CommunitySection(page: .radial)
                VStack(alignment: .leading, spacing: UIStyle.pad(16)) {
                    notices
                    HStack(alignment: .center, spacing: UIStyle.pad(20)) {
                        RadialWheel(state: preview(appSlots, shortcutSlots, bundleID), geometry: RadialMenu.geometry)
                            .scaleEffect(0.52)
                            .frame(width: 208, height: 208)
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 8) {
                            Label(String(localized: "Trackpad'de \(radial.corner.inlineTitle)sine tek parmakla tıkla"), systemImage: "hand.point.up.left")
                            Label(String(localized: "İmleci bir yöne kaydır, dilim yanar; tıkla, seçilir"), systemImage: "cursorarrow.click")
                            Label(String(localized: "Dilim yanarken iki parmakla tıkla: sabitlenir (bir daha: sabitlik kalkar)"), systemImage: "pin")
                            Label(String(localized: "Ses ve parlaklık çubuğuna bas, sürükle: değişir"), systemImage: "slider.horizontal.below.sun.max")
                            Label(String(localized: "Ortaya tıkla ya da Esc: kapanır"), systemImage: "xmark.circle")
                        }
                        .font(.callout)
                        .labelStyle(SoftListLabelStyle())
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        CornerPicker(corner: Binding(get: { engine.settings.radial.corner },
                                                     set: { engine.settings.radial.corner = $0 }))
                    }

                    sectionTitle(String(localized: "Alt yarı: uygulamalar"),
                                 String(localized: "Son 30 günde en çok kullandığın ve şu an açık olmayan uygulamalar. Sabitlediğin dilim açık olsa da yerinde kalır."))
                    slotList {
                        ForEach(0..<RadialMenuSettings.limit, id: \.self) { slot in
                            let s = appSlots.first { $0.slot == slot }
                            SlotRow(number: slot + 1, pinned: s?.pinned == true, empty: s == nil,
                                    last: slot == RadialMenuSettings.limit - 1) {
                                if let app = s?.item {
                                    BundleIcon(bundleID: app.bundleID).frame(width: 22, height: 22)
                                    Text(app.name)
                                    Text(s?.pinned == true ? "sabit" : usage.hours(app.bundleID).map { "otomatik · \(hoursText($0))" } ?? "otomatik")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(String(localized: "Boş")).foregroundStyle(.secondary)
                                }
                            } togglePin: {
                                engine.settings.radial.pinApp(s?.pinned == true ? nil : s?.item, at: slot)
                            } change: {
                                appChoices(slot)
                            }
                        }
                    }

                    FeatureExplainer(
                        title: String(localized: "Denetim Merkezi dairede"),
                        lines: [String(localized: "Bluetooth, Wi-Fi, Rahatsız Etme gibi düğmelere tıklayınca hemen açılır ya da kapanır; anahtar rengiyle gösterir."),
                                String(localized: "Ses ve parlaklık dilimi yarım ay çubuktur: bas ve sürükle. AirDrop'ta iki parmakla tıklayınca Herkes / Kişiler seçilir.")],
                        demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .control(.volume)),
                        caption: String(localized: "Dairede ses çubuğu"), slice: SystemControl.volume.title)
                    controlsSection

                    HStack(alignment: .firstTextBaseline) {
                        sectionTitle(String(localized: "Üst yarı: kısayollar"),
                                     String(localized: "Her uygulamada insanların en çok kullandığı kısayollar; hazır listesi olmayan uygulamada menüsünden seçilir."))
                        Spacer()
                        if let app = RadialMenu.app(bundleID) {
                            HStack(spacing: 6) {
                                BundleIcon(bundleID: app.bundleID).frame(width: 18, height: 18)
                                Text(app.name).font(.callout.weight(.medium))
                            }
                        }
                    }
                    if radial.shortcutRoom == 0 {
                        Text(String(localized: "Üst yarı Denetim Merkezi düğmeleriyle dolu; kısayollara yer kalmadı."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    slotList {
                        ForEach(0..<radial.shortcutRoom, id: \.self) { slot in
                            let s = shortcutSlots.first { $0.slot == slot }
                            SlotRow(number: radial.controls.count + slot + 1, pinned: s?.pinned == true, empty: s == nil,
                                    last: slot == radial.shortcutRoom - 1) {
                                if let item = s?.item {
                                    Text(item.title)
                                    Text(item.keys)
                                        .font(.system(.callout, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    if s?.pinned == true {
                                        Text("sabit").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(String(localized: "Boş")).foregroundStyle(.secondary)
                                }
                            } togglePin: {
                                engine.settings.radial.pinShortcut(s?.pinned == true ? nil : s?.item, at: slot, for: bundleID)
                            } change: {
                                shortcutChoices(slot, bundleID)
                            }
                        }
                    }
                    if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                        Text(String(localized: "Bu uygulama şu an açık değil; menüsü açıkken okunur. Şimdilik yalnız hazır liste görünüyor."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(UIStyle.pad(20))
                .frame(maxWidth: .infinity)
            }
            .opacity(radial.enabled ? 1 : 0.5)
        }
        .onPageVisibility(show: {
            engine.refreshSystemTrackpad()
            usage.refreshIfStale()
            loadMenu(bundleID)
            if macShortcuts == nil { Shortcuts.list { macShortcuts = $0 } }
        })
        .onChange(of: shortcutApp) { _, id in
            menu = []
            loadMenu(id ?? defaultShortcutApp)
        }
    }

    // MARK: - Parçalar

    /// Denetim Merkezi düğmeleri: üst yarının başında, her uygulamada aynı. Ekle, çıkar, sırala.
    private var controlsSection: some View {
        let controls = engine.settings.radial.controls
        let missing = SystemControl.allCases.filter { !controls.contains($0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(String(localized: "Üst yarı: Denetim Merkezi"),
                             String(localized: "Her uygulamada aynı kalır, soldan başlar. Kalan yerlere öndeki uygulamanın kısayolları gelir."))
                Spacer()
                Menu {
                    ForEach(missing, id: \.self) { control in
                        Button {
                            engine.settings.radial.addControl(control)
                        } label: {
                            Label(control.title, systemImage: control.symbol())
                        }
                    }
                } label: {
                    Label(String(localized: "Düğme ekle"), systemImage: "plus")
                }
                .fixedSize()
                .disabled(missing.isEmpty || controls.count >= RadialMenuSettings.limit)
                .help(controls.count >= RadialMenuSettings.limit ? String(localized: "Üst yarı dolu; önce birini çıkar") : String(localized: "Denetim Merkezi'nden bir düğme ekle"))
            }
            if controls.isEmpty {
                Text(String(localized: "Düğme yok; üst yarının tamamı kısayol."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                slotList {
                    ForEach(Array(controls.enumerated()), id: \.element) { i, control in
                        ControlRow(number: i + 1, control: control, last: i == controls.count - 1,
                                   canUp: i > 0, canDown: i < controls.count - 1) { move in
                            var list = engine.settings.radial.controls
                            switch move {
                            case .up: list.swapAt(i, i - 1)
                            case .down: list.swapAt(i, i + 1)
                            case .remove: list.remove(at: i)
                            }
                            engine.settings.radial.controls = list
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if !engine.settings.enabled, engine.settings.radial.enabled {
            notice(String(localized: "FingerKit kapalı; köşe tıklaması normal tıklama olarak geçer. Sol üstteki düğmeden aç."))
        }
        let corner = engine.settings.radial.corner
        if (corner == .bottomLeft && engine.systemTrackpad.leftCornerRightClick) || (corner == .bottomRight && engine.systemTrackpad.rightCornerRightClick) {
            notice(String(localized: "Mac'te “\(corner.inlineTitle)ye tıklama = sağ tık” açık. Aynı köşe: daire menü önce gelir. Başka köşe seç ya da Sistem Ayarları › İzleme Paneli › İkincil tıklama'dan kapat."))
        }
        if engine.settings.apps.contains(where: { $0.bindings.contains { $0.gesture == corner.tapGesture && $0.enabled } }) {
            notice(String(localized: "Aynı köşeye dokunma hareketi de bağlı (İzleme Dörtgeni). Dokunarak tıklama açıksa ikisi karışabilir; başka köşe seçmek en temizi."))
        }
        if usage.readable == false {
            VStack(alignment: .leading, spacing: 8) {
                notice(String(localized: "En çok kullandığın uygulamaları görmek için FingerKit'in Mac'in Ekran Süresi kaydını okuması gerekiyor. Açılan pencerede listeden FingerKit'i bulup yanındaki anahtarı aç. Şimdilik Dock sırası kullanılıyor."))
                HStack {
                    Button(String(localized: "İzin ekranını aç")) { usage.openFullDiskAccessSettings() }
                        .buttonStyle(.softPrimary)
                    Button("Yeniden dene") { usage.refresh() }
                }
            }
        }
    }

    private var header: some View {
        @Bindable var engine = engine
        return PageHeader(icon: "circle.bottomhalf.filled",
                          title: String(localized: "Daire menü"),
                          detail: String(localized: "Trackpad'in seçtiğin köşesine tıklayınca imlecin yerinde daire açılır: altta uygulamalar, üstte Denetim Merkezi düğmeleri ve öndeki uygulamanın kısayolları.")) {
            Toggle("", isOn: $engine.settings.radial.enabled)
                .toggleStyle(.soft)
                .labelsHidden()
                .help(engine.settings.radial.enabled ? String(localized: "Daire menü açık") : String(localized: "Daire menü kapalı; köşe tıklaması normal tıklamadır"))
        }
    }

    private func sectionTitle(_ title: String, _ detail: String) -> some View {
        SectionTitle(title: title, detail: detail)
    }

    private func slotList<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let rows = content()
        return CardStack(spacing: 5) { rows }
    }

    private func notice(_ text: String) -> some View {
        SoftNotice(text: text)
    }

    private func hoursText(_ h: Double) -> String {
        h >= 1 ? String(localized: "\(Int(h.rounded())) sa") : String(localized: "\(max(Int((h * 60).rounded()), 1)) dk")
    }

    // MARK: - Seçenekler

    /// Yuvaya sabitlenebilecek uygulamalar: en çok kullanılanlar ve açık olanlar
    @ViewBuilder
    private func appChoices(_ slot: Int) -> some View {
        let used = usage.ranked.prefix(20).compactMap { RadialMenu.app($0.bundleID) }
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { $0.bundleIdentifier.flatMap(RadialMenu.app) }
            .filter { r in !used.contains { $0.bundleID == r.bundleID } }
        Section(String(localized: "En çok kullandıkların")) {
            ForEach(used) { app in
                Button(app.name) { engine.settings.radial.pinApp(app, at: slot) }
            }
        }
        if !running.isEmpty {
            Section(String(localized: "Açık uygulamalar")) {
                ForEach(running) { app in
                    Button(app.name) { engine.settings.radial.pinApp(app, at: slot) }
                }
            }
        }
        Divider()
        Button(String(localized: "Başka bir uygulama seç…")) {
            let panel = NSOpenPanel()
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.prompt = "Sabitle"
            panel.message = String(localized: "Daire menüde bu yuvaya sabitlenecek uygulamayı seç")
            guard panel.runModal() == .OK, let url = panel.url,
                  let id = Bundle(url: url)?.bundleIdentifier, let app = RadialMenu.app(id) else { return }
            engine.settings.radial.pinApp(app, at: slot)
        }
    }

    /// Yuvaya sabitlenebilecek kısayollar: hazır liste ve menüdeki bütün kısayollar (üst menüye göre)
    @ViewBuilder
    private func shortcutChoices(_ slot: Int, _ bundleID: String) -> some View {
        let all = PopularShortcuts.auto(for: bundleID, menu: [])
        if !all.isEmpty {
            Section(String(localized: "Sık kullanılanlar")) {
                ForEach(all, id: \.keys) { item in
                    Button("\(item.title)  \(item.keys)") { pinShortcut(item, slot, bundleID) }
                }
            }
        }
        let groups = Dictionary(grouping: menu) { $0.path.first ?? "" }
        ForEach(topMenus, id: \.self) { top in
            Menu(top) {
                ForEach(groups[top] ?? [], id: \.self) { entry in
                    Button("\(entry.path.dropFirst().joined(separator: " › "))  \(entry.keys)") {
                        pinShortcut(RadialShortcut(title: entry.title, keys: entry.keys, action: .menu(entry.path)), slot, bundleID)
                    }
                }
            }
        }
        if all.isEmpty, menu.isEmpty {
            Text(String(localized: "Seçenek yok: uygulama açık değil"))
        }
        Divider()
        Menu(String(localized: "Hazır işler")) {
            TaskMenuItems(shortcuts: macShortcuts) { task in
                engine.settings.radial.pinShortcut(RadialShortcut(task: task), at: slot, for: bundleID)
            }
        }
    }

    /// Menüdeki üst menü adları, menü sırasıyla
    private var topMenus: [String] {
        var names: [String] = []
        for entry in menu { if let top = entry.path.first, !names.contains(top) { names.append(top) } }
        return names
    }

    private func pinShortcut(_ item: RadialShortcut, _ slot: Int, _ bundleID: String) {
        // Hazır listedeki kısayol menüde de varsa menü maddesine bağlanır
        let resolved = PopularShortcuts.auto(for: bundleID, menu: menu).first { $0.keys == item.keys } ?? item
        engine.settings.radial.pinShortcut(resolved, at: slot, for: bundleID)
    }

    private var defaultShortcutApp: String { RadialUIState.defaultApp }

    private func loadMenu(_ bundleID: String) {
        RadialMenu.shared.menuEntries(for: bundleID) { entries in
            if (shortcutApp ?? defaultShortcutApp) == bundleID { menu = entries }
        }
    }

    private func preview(_ apps: [RadialSlot<RadialApp>], _ shortcuts: [RadialSlot<RadialShortcut>], _ bundleID: String) -> RadialState {
        let s = RadialState()
        s.apps = apps
        s.shortcuts = shortcuts
        s.controls = engine.settings.radial.controls
        s.readControls()
        s.appName = RadialMenu.app(bundleID)?.name ?? ""
        return s
    }
}

/// Denetim Merkezi düğmesi satırı: simge, ad, ne yaptığı, sırala ve çıkar
private struct ControlRow: View {
    enum Move { case up, down, remove }

    let number: Int
    let control: SystemControl
    let last: Bool
    let canUp: Bool
    let canDown: Bool
    let action: (Move) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            SettingsIcon(control: control)
            VStack(alignment: .leading, spacing: 1) {
                Text(control.title)
                Text(control.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { action(.up) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.softQuiet)
                .disabled(!canUp)
                .help(String(localized: "Sola al"))
            Button { action(.down) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.softQuiet)
                .disabled(!canDown)
                .help(String(localized: "Sağa al"))
            Button { action(.remove) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.softQuiet)
                .help(String(localized: "Daireden çıkar"))
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(6))
    }
}

/// Yuva satırı: numara, içerik, raptiye, değiştir menüsü
private struct SlotRow<Content: View, Choices: View>: View {
    let number: Int
    let pinned: Bool
    let empty: Bool
    var last = false
    @ViewBuilder let content: () -> Content
    let togglePin: () -> Void
    @ViewBuilder let change: () -> Choices

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            content()
            Spacer()
            Button(action: togglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .foregroundStyle(pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.softQuiet)
            .disabled(empty)
            .help(pinned ? String(localized: "Sabitliği kaldır: bu yuvayı FingerKit doldursun") : String(localized: "Sabitle: bu dilim yerinde kalsın"))
            Menu(String(localized: "Değiştir")) { change() }
                .controlSize(.small)
                .fixedSize()
                .help(String(localized: "Bu yuvaya başka bir şey sabitle"))
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(6))
    }
}

/// Daire menü sekmesinin durumu: sol sütundaki uygulama listesi ile sağ taraf paylaşır
@Observable
final class RadialUIState {
    var shortcutApp: String?

    /// En çok kullanılan ve şu an açık uygulama; yoksa Safari
    static var defaultApp: String {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return AppUsage.shared.ranked.first { running.contains($0.bundleID) && $0.bundleID != Bundle.main.bundleIdentifier }?.bundleID
            ?? "com.apple.Safari"
    }
}

/// Daire menü sekmesinin sol sütunu: üst yarıdaki kısayolları hangi uygulama için düzenlediğini seçersin.
/// Her uygulamanın dairesi kendi kısayollarını gösterir; alt yarı (uygulamalar) her yerde aynıdır.
struct RadialAppSidebar: View {
    @Environment(Engine.self) private var engine
    @Environment(RadialUIState.self) private var state
    private let usage = AppUsage.shared

    var body: some View {
        return SidebarScroll {
            SidebarHeader(title: String(localized: "Uygulamalar"))
            ForEach(apps) { app in
                SidebarRow(selected: state.shortcutApp == app.bundleID) { state.shortcutApp = app.bundleID } label: {
                    BundleIcon(bundleID: app.bundleID)
                        .frame(width: 20, height: 20)
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    if engine.settings.radial.shortcutPins[app.bundleID]?.isEmpty == false {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Bu uygulamada sabitlediğin kısayollar var"))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(String(localized: "Dairenin üst yarısı öndeki uygulamaya göre değişir. Soldan bir uygulama seç, kısayollarını sağda düzenle."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .onAppear {
            usage.refreshIfStale()
            if state.shortcutApp == nil { state.shortcutApp = RadialUIState.defaultApp }
        }
    }

    /// Son kullanılanlar, kısayol sabitlenenler ve şu an açık olanlar; tekrarsız
    private var apps: [RadialApp] {
        let used = usage.ranked.prefix(15).map(\.bundleID)
        let pinned = Array(engine.settings.radial.shortcutPins.keys).sorted()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap(\.bundleIdentifier)
        var ids: [String] = []
        for id in [RadialUIState.defaultApp] + used + pinned + running where !ids.contains(id) { ids.append(id) }
        return ids.compactMap(RadialMenu.app)
    }
}

/// Daireyi açan köşe: küçük trackpad çizimi, köşesine tıklanınca seçilir
private struct CornerPicker: View {
    @Binding var corner: RadialCorner

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: min(UIStyle.card, 26), style: .continuous)
                    .fill(Color.fieldFill)
                ForEach(RadialCorner.allCases, id: \.self) { c in
                    Button { withAnimation(.snappy(duration: 0.2)) { corner = c } } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: min(UIStyle.small + 2, 14), style: .continuous)
                                .fill(c == corner ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                            if c == corner {
                                Image(systemName: "circle.bottomhalf.filled")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.75))
                            }
                        }
                        .frame(width: 40, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(c.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(c))
                    .padding(7)
                }
            }
            .frame(width: 168, height: 108)
            Text(corner.title)
                .font(.caption.weight(.semibold))
            Text(String(localized: "Daire bu köşeden açılır"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func alignment(_ c: RadialCorner) -> Alignment {
        switch c {
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        }
    }
}

/// Apple'ın Sistem Ayarları'ndaki gibi simge: renkli yuvarlatılmış kare, içinde beyaz işaret
struct SettingsIcon: View {
    let control: SystemControl
    var size: CGFloat = 24

    var body: some View {
        let color = Self.color(control)
        ControlGlyph(control: control)
            .frame(width: size * 0.56, height: size * 0.56)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.12), color], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }

    /// Sistem Ayarları'ndaki renkler
    static func color(_ control: SystemControl) -> Color {
        switch control {
        case .wifi, .bluetooth, .airDrop, .brightness, .screenMirroring: Color(red: 0.04, green: 0.52, blue: 1)
        case .focus: Color(red: 0.37, green: 0.36, blue: 0.9)
        case .darkMode: Color(white: 0.17)
        case .volume: Color(red: 1, green: 0.18, blue: 0.33)
        }
    }
}
