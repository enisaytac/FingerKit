import AppKit
import SwiftUI
import FingerKitCore

/// Uygulamayı açar ya da açıksa öne getirir (Hyper Key ve daire menü kullanır)
enum AppLauncher {
    static func open(_ bundleID: String, name: String, from source: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.write("HATA: \(source): \(name) bulunamadı (\(bundleID))")
            return
        }
        Log.write("\(source) → \(name)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { Log.write("HATA: \(name) açılamadı: \(error.localizedDescription)") }
        }
    }
}

@Observable
final class RadialState {
    var apps: [RadialSlot<RadialApp>] = []
    var shortcuts: [RadialSlot<RadialShortcut>] = []
    /// Üst yarının başındaki Denetim Merkezi düğmeleri (her uygulamada aynı)
    var controls: [SystemControl] = []
    /// Düğmelerin daire açılınca okunan durumu
    var values: [SystemControl: ControlValue] = [:]
    /// AirDrop dilimine tıklandı: üst yarı geçici olarak üç seçenek olur
    var choosingAirDrop = false
    /// Yarım ay çubuğu sürükleniyor
    var dragging: SystemControl?
    /// Çubuk sürükleniyor ya da kaydırılıyor: değer her karede değişir, canlandırma beklemeden çizilir
    var live = false
    /// Öndeki uygulamanın menüsü henüz okunmadı
    var loading = false
    var appName = ""
    var pick: RadialPick?

    /// Üst yarıdaki bir dilim
    enum TopItem: Equatable {
        case control(SystemControl)
        case shortcut(RadialSlot<RadialShortcut>)
        case airDrop(AirDropMode)
    }

    var topCount: Int { choosingAirDrop ? AirDropMode.allCases.count : controls.count + shortcuts.count }

    func top(_ i: Int) -> TopItem? {
        if choosingAirDrop { return AirDropMode.allCases.indices.contains(i) ? .airDrop(AirDropMode.allCases[i]) : nil }
        if controls.indices.contains(i) { return .control(controls[i]) }
        let j = i - controls.count
        return shortcuts.indices.contains(j) ? .shortcut(shortcuts[j]) : nil
    }

    func value(_ control: SystemControl) -> ControlValue { values[control] ?? .unknown }

    /// Daire açılınca düğmelerin durumu okunur
    func readControls() {
        values = Dictionary(uniqueKeysWithValues: controls.map { ($0, SystemControls.value($0)) })
    }
}

/// Trackpad'in sol alt köşesine tıklayınca imlecin yerinde açılan daire.
/// İmlecin yönü dilimi yakar, tıklama seçer, sağ tık dilimi sabitler. Tıklamaları ClickInterceptor
/// yakalayıp buraya verir; pencere fareye hiç dokunmaz, öndeki uygulama öndeki kalır.
final class RadialMenu: NSObject, NSWindowDelegate {
    static let shared = RadialMenu()
    static let geometry = RadialGeometry()

    private var panel: RadialPanel?
    private let state = RadialState()
    private weak var engine: Engine?
    private var app: NSRunningApplication?
    /// Merkez (ekran koordinatı, y yukarı)
    private var center = NSPoint.zero
    private var timer: Timer?
    private var keyMonitor: Any?
    /// Sürüklemede imlecin toplam yolu (nokta); kısa kalırsa bir dokunuş sayılır
    private var dragTravel: CGFloat = 0
    private var liveToken = 0
    /// Açılıştaki otomatik listeler (sabitleme değişince yuvalar bunlardan yeniden dolar)
    private var autoApps: [RadialApp] = []
    private var menuEntries: [MenuShortcutEntry] = []
    /// Uygulama başına menüden okunan kısayollar (açılışta beklemeden gösterilsin)
    private var menuCache: [pid_t: (date: Date, entries: [MenuShortcutEntry])] = [:]

    var isShown: Bool { panel?.isVisible == true }

    func show(_ engine: Engine) {
        if isShown { close(); return }
        self.engine = engine
        let front = NSWorkspace.shared.frontmostApplication
        app = front
        state.appName = front?.localizedName ?? ""
        state.pick = nil
        state.choosingAirDrop = false
        state.dragging = nil
        state.live = false
        state.controls = engine.settings.radial.controls
        state.readControls()
        autoApps = Self.autoApps()
        let cached = front.flatMap { menuCache[$0.processIdentifier] }
        menuEntries = cached?.entries ?? []
        refill()
        state.loading = cached == nil && state.shortcuts.isEmpty
        if let front { refreshMenu(front) }
        AppUsage.shared.refreshIfStale()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let side = panel.frame.width
        center = clampedCenter(NSEvent.mouseLocation, side: side)
        panel.setFrameOrigin(NSPoint(x: center.x - side / 2, y: center.y - side / 2))
        // Yumuşak açılış
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.track() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            // Pencere tuşları alıyor; Esc ve diğer her tuş kapatır
            self?.close()
            return nil
        }
        Log.write("Daire menü açıldı [\(front?.bundleIdentifier ?? "?")]: \(state.apps.count) uygulama, \(state.shortcuts.count) kısayol")
    }

    /// Açılıştan kısa süre sonra görünmez olarak bir kez çizilir: ilk köşe tıklamasında daire beklemeden gelsin
    func warmUp(_ engine: Engine) {
        guard panel == nil else { return }
        self.engine = engine
        state.controls = engine.settings.radial.controls
        state.readControls()
        autoApps = Self.autoApps()
        refill()
        let panel = makePanel()
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.timer == nil else { return }
            panel.orderOut(nil)
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Denetim Merkezi'ne basılırken onun penceresi öne gelir; daire açık kalır
        if ControlCenter.isBusy { return }
        close()
    }

    var isDragging: Bool { state.dragging != nil }

    // MARK: Gösteri modu (Demo.swift)

    func demoCount(top: Bool) -> Int { top ? state.topCount : state.apps.count }

    /// Denetimin üst yarıdaki sırası; `nil` verilirse ilk kısayol dilimi
    func demoIndex(of control: SystemControl?) -> Int? {
        guard let control else { return state.shortcuts.isEmpty ? nil : state.controls.count }
        return state.controls.firstIndex(of: control)
    }

    /// Dilimin ortası (ekran noktası, AppKit)
    func demoPoint(top: Bool, index: Int) -> NSPoint? {
        let n = demoCount(top: top)
        guard isShown, index < n else { return nil }
        let a = RadialGeometry.angle(top: top, index: index, count: n)
        let r = (Self.geometry.inner + Self.geometry.outer) / 2
        return NSPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
    }

    /// Daire açıkken fare basıldı: yarım ay çubuğun üstündeyse sürükleme başlar, değilse tıklama sayılır
    func mouseDown() {
        if let (i, control) = sliderUnderCursor() {
            state.dragging = control
            state.pick = .top(i)
            state.live = true
            dragTravel = 0
            return
        }
        click()
    }

    /// Basılıyken imleç kıpırdadı (`dx`, `dy` ekran noktası, y aşağı doğru; event tap'ten).
    /// Değer kaldığı yerden değişir, zıplamaz: dışa ya da yukarı çekmek artırır, içe ya da aşağı azaltır.
    func drag(dx: CGFloat, dy: CGFloat) {
        guard let control = state.dragging, case .top(let i)? = state.pick else { return }
        dragTravel += hypot(dx, dy)
        let up = -dy
        // Dilimin ortasından dışarı bakan yön
        let a = (Double(i) + 0.5) * .pi / Double(max(state.topCount, 1))
        let outward = dx * CGFloat(-cos(a)) + up * CGFloat(sin(a))
        let change = abs(up) >= abs(outward) ? up : outward
        adjust(control, by: Double(change) / 240)
    }

    /// Sürükleme bitti: daire açık kalır, başka dilim seçilebilir. Kıpırdamadan bırakıldıysa
    /// basılan yer değeri belirler (iç kenar 0, dış kenar 1).
    func mouseUp() {
        guard let control = state.dragging else { return }
        if dragTravel < 4 {
            let mouse = NSEvent.mouseLocation
            let r = hypot(mouse.x - center.x, mouse.y - center.y)
            setLevel(control, RadialTop.level(radius: r, inner: Self.geometry.inner + 12, outer: Self.geometry.outer - 12))
        }
        state.dragging = nil
        state.live = false
        Log.write(String(format: "Daire menü: %@ %%%.0f", control.rawValue, (state.value(control).levelValue ?? 0) * 100))
    }

    /// İki parmakla kaydırma: imleç ses/parlaklık dilimindeyse değer değişir (basmadan da olur).
    /// Yutulduysa true döner. Kaydırmanın sonundaki kendiliğinden süzülme yok sayılır, değer taşmaz.
    func scroll(_ event: CGEvent) -> Bool {
        guard isShown, state.dragging == nil, !state.choosingAirDrop, let (_, control) = sliderUnderCursor() else { return false }
        guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return true }
        var delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if delta == 0 { delta = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 8 }
        // "Doğal kaydırma" açıksa sayı ters gelir; parmak yukarı = artır olsun
        if NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice == true { delta = -delta }
        state.live = true
        liveToken += 1
        let token = liveToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.liveToken == token, self?.state.dragging == nil { self?.state.live = false }
        }
        adjust(control, by: delta / 300)
        return true
    }

    private func sliderUnderCursor() -> (Int, SystemControl)? {
        guard case .top(let i)? = currentPick(), case .control(let control)? = state.top(i), control.kind == .slider else { return nil }
        return (i, control)
    }

    private func adjust(_ control: SystemControl, by change: Double) {
        let old = state.value(control).levelValue ?? SystemControls.value(control).levelValue ?? 0.5
        setLevel(control, old + change)
    }

    private func setLevel(_ control: SystemControl, _ level: Double) {
        let level = min(max(level, 0), 1)
        if let old = state.value(control).levelValue, abs(old - level) < 0.002 { return }
        state.values[control] = .level(level)
        SystemControls.setLevel(control, level)
    }

    /// Daire açıkken tıklama: imlecin gösterdiği dilim seçilir; ortaya ya da uzağa tıklamak yalnız kapatır.
    /// Denetim Merkezi düğmeleri daireyi kapatmaz (Apple'daki gibi); değişiklik dilimde hemen görünür.
    func click() {
        let pick = currentPick()
        if state.choosingAirDrop {
            chooseAirDrop(pick)
            return
        }
        if case .top(let i)? = pick, case .control(let control)? = state.top(i) {
            controlClicked(control)
            return
        }
        let target = app
        close()
        switch pick {
        case .top(let i)? where i >= state.controls.count && i - state.controls.count < state.shortcuts.count:
            let item = state.shortcuts[i - state.controls.count].item
            guard let target else { return }
            Log.write("Daire menü: \(item.title) (\(item.keys))")
            // Daire penceresi kapanıp öndeki uygulama tuşları yeniden alsın diye kısa bekleme
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                switch item.action {
                case .menu(let path): MenuPresser.press(path, in: target)
                case .shortcut, .task: AppShortcutTap.perform(item.action, in: target)
                }
            }
        case .bottom(let i)? where i < state.apps.count:
            let item = state.apps[i].item
            AppLauncher.open(item.bundleID, name: item.name, from: String(localized: "Daire menü"))
        default:
            let mouse = NSEvent.mouseLocation
            Log.write(String(format: "Daire menü kapandı (seçim yok; imleç merkeze göre %.0f, %.0f)", mouse.x - center.x, mouse.y - center.y))
        }
    }

    /// Daire açıkken sağ tık: imlecin gösterdiği dilim sabitlenir ya da sabitliği kalkar; daire açık kalır.
    /// Dilim göstermiyorsa daire kapanır.
    func rightClick() {
        guard let engine, let pick = currentPick() else { close(); return }
        if !state.choosingAirDrop, case .top(let i) = pick, case .control(.airDrop)? = state.top(i) {
            state.choosingAirDrop = true
            state.pick = nil
            return
        }
        switch pick {
        case .top(let i) where !state.choosingAirDrop && i >= state.controls.count && i - state.controls.count < state.shortcuts.count:
            guard let bundleID = app?.bundleIdentifier else { return }
            let s = state.shortcuts[i - state.controls.count]
            engine.settings.radial.pinShortcut(s.pinned ? nil : s.item, at: s.slot, for: bundleID)
            Log.write("Daire menü: \(s.item.title) \(s.pinned ? "sabitlikten çıktı" : "sabitlendi") (yuva \(s.slot + 1))")
        case .bottom(let i) where i < state.apps.count:
            let a = state.apps[i]
            engine.settings.radial.pinApp(a.pinned ? nil : a.item, at: a.slot)
            Log.write("Daire menü: \(a.item.name) \(a.pinned ? "sabitlikten çıktı" : "sabitlendi") (yuva \(a.slot + 1))")
        default:
            return
        }
        refill()
    }

    /// Uygulama öne geçince menüsü arka planda okunur; açılışta hazır olur
    func prefetch(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if let cached = menuCache[app.processIdentifier], Date().timeIntervalSince(cached.date) < 60 { return }
        refreshMenu(app)
    }

    func forget(_ app: NSRunningApplication) {
        menuCache[app.processIdentifier] = nil
    }

    /// Sekme için: uygulamanın menüdeki kısayolları (açık değilse boş)
    func menuEntries(for bundleID: String, done: @escaping ([MenuShortcutEntry]) -> Void) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            done([])
            return
        }
        if let cached = menuCache[app.processIdentifier] { done(cached.entries) }
        MenuPresser.shortcutEntries(of: app) { [weak self] entries in
            self?.menuCache[app.processIdentifier] = (Date(), entries)
            done(entries)
        }
    }

    // MARK: - Denetim Merkezi

    private func controlClicked(_ control: SystemControl) {
        switch control.kind {
        case .toggle:
            let before = state.value(control)
            // Hemen yeni durum gösterilir; gerçek durum işlem bitince okunur
            state.values[control] = .on(!before.isOn)
            Log.write("Daire menü: \(control.rawValue) → \(before.isOn ? "kapat" : "aç")")
            SystemControls.toggle(control, from: before) { [weak self] value in
                self?.state.values[control] = value
                self?.panel?.makeKey()
            }
        case .choice:
            // Tek tık aç/kapa: kapalıysa en son seçilen moda (ilk sefer Yalnızca Kişiler) döner.
            // Herkes / Kişiler seçimi sağ tıkla (iki parmakla tık) açılır.
            let current: AirDropMode = { if case .airDrop(let m) = state.value(.airDrop) { return m }; return .off }()
            let saved = AirDropMode(rawValue: UserDefaults.standard.string(forKey: "airDropLastMode") ?? "") ?? .contacts
            setAirDrop(current == .off ? (saved == .off ? .contacts : saved) : .off)
        case .panel:
            close()
            Log.write("Daire menü: ekran yansıtma listesi")
            ControlCenter.showScreenMirroring()
        case .slider:
            break
        }
    }

    /// AirDrop seçimi açıkken: seçenek seçilir, ortaya ya da uzağa tıklamak seçimi kapatır
    private func chooseAirDrop(_ pick: RadialPick?) {
        state.choosingAirDrop = false
        guard case .top(let i)? = pick, AirDropMode.allCases.indices.contains(i) else { return }
        setAirDrop(AirDropMode.allCases[i])
    }

    private func setAirDrop(_ mode: AirDropMode) {
        if mode != .off { UserDefaults.standard.set(mode.rawValue, forKey: "airDropLastMode") }
        state.values[.airDrop] = .airDrop(mode)
        Log.write("Daire menü: AirDrop → \(mode.rawValue)")
        SystemControls.setAirDrop(mode) { [weak self] ok in
            self?.state.values[.airDrop] = SystemControls.value(.airDrop)
            self?.panel?.makeKey()
            if !ok { Log.write("HATA: AirDrop seçimi yapılamadı") }
        }
    }

    // MARK: - İçerik

    /// Alt yarının otomatik sırası: önce son 30 günde en çok kullanılan, şu an açık olmayan uygulamalar;
    /// sonra Dock'takiler. Yine altı dolmazsa açık olanlar da gelir (dilim boş kalmasın).
    static func autoApps() -> [RadialApp] {
        let running = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
        var seen: Set<String> = [Bundle.main.bundleIdentifier ?? ""]
        let all = (AppUsage.shared.ranked.map(\.bundleID) + RadialApp.fromDock(tiles).map(\.bundleID)).filter { seen.insert($0).inserted }
        let closed = all.filter { !running.contains($0) }
        let open = all.filter { running.contains($0) }
        return (closed + open).lazy.compactMap(app).prefix(RadialMenuSettings.limit * 2).map { $0 }
    }

    /// Kurulu uygulamanın adı; kurulu değilse nil
    static func app(_ bundleID: String) -> RadialApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return RadialApp(bundleID: bundleID, name: name)
    }

    private func refill() {
        guard let radial = engine?.settings.radial else { return }
        state.apps = radial.apps(auto: autoApps)
        if let bundleID = app?.bundleIdentifier {
            state.shortcuts = radial.shortcuts(for: bundleID, auto: PopularShortcuts.auto(for: bundleID, menu: menuEntries))
        } else {
            state.shortcuts = []
        }
    }

    private func refreshMenu(_ app: NSRunningApplication) {
        let started = Date()
        MenuPresser.shortcutEntries(of: app) { [weak self] entries in
            guard let self else { return }
            menuCache[app.processIdentifier] = (Date(), entries)
            Log.write(String(format: "Daire menü: %@ menüsü okundu (%d kısayol, %.2f sn)",
                             app.localizedName ?? "?", entries.count, Date().timeIntervalSince(started)))
            // Daire açıksa hemen güncellenir (hazır listedeki kısayollar menü maddesine bağlanır)
            if isShown, self.app == app {
                menuEntries = entries
                refill()
                state.loading = false
            }
        }
    }

    // MARK: - İmleç

    private func currentPick() -> RadialPick? {
        let mouse = NSEvent.mouseLocation
        return Self.geometry.pick(dx: mouse.x - center.x, dy: mouse.y - center.y,
                                  top: state.topCount, bottom: state.choosingAirDrop ? 0 : state.apps.count)
    }

    private func track() {
        // Sürüklerken seçim çubukta kalır, imleç dilimden çıksa da
        if state.dragging != nil { return }
        let pick = currentPick()
        if pick != state.pick { state.pick = pick }
    }

    // MARK: - Pencere

    private func makePanel() -> RadialPanel {
        let side = (Self.geometry.outer + 10) * 2
        let panel = RadialPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: RadialWheel(state: state, geometry: Self.geometry))
        return panel
    }

    /// Daire ekrandan taşmasın: merkez gerekirse içeri itilir
    private func clampedCenter(_ mouse: NSPoint, side: CGFloat) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let f = screen?.frame ?? .zero
        let half = side / 2
        return NSPoint(x: min(max(mouse.x, f.minX + half), f.maxX - half),
                       y: min(max(mouse.y, f.minY + half), f.maxY - half))
    }
}

/// Odak çalmadan tuş (Esc) alabilen pencere
private final class RadialPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Çizim

/// Daire: ortada boş daire, üst yarıda kısayollar, alt yarıda uygulamalar.
/// Hem açılan menü hem "Daire menü" sekmesindeki önizleme bunu çizer.
struct RadialWheel: View {
    let state: RadialState
    let geometry: RadialGeometry

    private var outer: CGFloat { geometry.outer }
    private var inner: CGFloat { geometry.inner }
    private var mid: CGFloat { (geometry.inner + geometry.outer) / 2 }
    /// Kısayol yazıları dışa yakın durur: orada dilim daha geniş
    private var labelRadius: CGFloat { geometry.outer - 52 }
    private let labelHeight = 40.0
    private let controlHeight = 54.0
    private let iconSize: CGFloat = 42
    /// Dilimlerin yumuşak köşesi: dilim bu kadar içeriden çizilir, aynı renkte kalın çizgiyle çevrilir
    private let round = Double(UIStyle.sliceRound)
    private var sliceInner: CGFloat { inner + 5 + round }
    private var sliceOuter: CGFloat { outer - 6 - round }

    var body: some View {
        ZStack {
            // Arkada daire yok: yalnız ayrı ayrı, köşeleri yuvarlak dilimler ve ortadaki göbek
            slices(top: true, count: state.topCount)
            if !state.choosingAirDrop { slices(top: false, count: state.apps.count) }

            ForEach(0..<state.topCount, id: \.self) { i in
                let n = state.topCount
                let a = RadialGeometry.angle(top: true, index: i, count: n)
                let selected = state.pick == .top(i)
                switch state.top(i) {
                case .shortcut(let slot)?:
                    shortcutLabel(slot.item, selected: selected,
                                  width: geometry.labelWidth(angle: a, count: n, radius: labelRadius, height: labelHeight))
                        .offset(offset(a, labelRadius))
                    pin(slot.pinned, selected: selected)
                        .offset(offset(a, outer - 13))
                case .control(let control)? where control.kind != .panel:
                    sliderLabels(control, angle: a, range: sliceStart(top: true, index: i, count: n), selected: selected)
                case .control(let control)?:
                    controlLabel(control, selected: selected,
                                 width: geometry.labelWidth(angle: a, count: n, radius: labelRadius - 8, height: controlHeight))
                        .offset(offset(a, labelRadius - 8))
                case .airDrop(let mode)?:
                    airDropOption(mode, selected: selected,
                                  width: geometry.labelWidth(angle: a, count: n, radius: mid, height: labelHeight))
                        .offset(offset(a, mid))
                case nil:
                    EmptyView()
                }
            }
            if !state.choosingAirDrop {
                ForEach(Array(state.apps.enumerated()), id: \.offset) { i, slot in
                    let a = RadialGeometry.angle(top: false, index: i, count: state.apps.count)
                    let selected = state.pick == .bottom(i)
                    BundleIcon(bundleID: slot.item.bundleID)
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .scaleEffect(selected ? 1.14 : 1)
                        .offset(offset(a, mid + 6))
                    pin(slot.pinned, selected: selected)
                        .offset(offset(a, outer - 13))
                }
            }
            if state.topCount == 0 {
                Text(state.loading ? String(localized: "Kısayollar okunuyor…") : String(localized: "Bu uygulamada kısayol yok"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .offset(y: -mid)
            }
            if state.apps.isEmpty, !state.choosingAirDrop {
                Text("Uygulama yok")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .offset(y: mid)
            }

            // Orta göbek: biraz daha açık, kabarık
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: .black.opacity(0.25 + 0.25 * UIStyle.shadow), radius: 8, y: 3)
                .frame(width: inner * 2, height: inner * 2)
            Text(centerText)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(state.pick == nil && state.dragging == nil ? 0.55 : 0.95))
                .frame(width: inner * 1.7)
        }
        .frame(width: (outer + 10) * 2, height: (outer + 10) * 2)
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.16), value: state.pick)
        .animation(.snappy(duration: 0.2), value: state.choosingAirDrop)
        .animation(state.live ? nil : .snappy(duration: 0.18), value: state.values)
    }

    private var centerText: String {
        if let control = state.dragging { return "\(control.title)\n\(percent(state.value(control)))" }
        guard let pick = state.pick else { return state.choosingAirDrop ? "AirDrop" : state.appName }
        switch pick {
        case .top(let i):
            switch state.top(i) {
            case .shortcut(let slot)?: return slot.item.title
            case .control(let control)? where control.kind == .slider: return "\(control.title)\n\(percent(state.value(control)))"
            case .control(let control)?: return control.title
            case .airDrop(let mode)?: return "AirDrop\n\(mode.title)"
            case nil: return state.appName
            }
        case .bottom(let i) where i < state.apps.count: return state.apps[i].item.name
        default: return state.appName
        }
    }

    private func percent(_ value: ControlValue) -> String {
        value.levelValue.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
    }

    private func sliceStart(top: Bool, index i: Int, count n: Int) -> (start: Double, end: Double) {
        let step = Double.pi / Double(n)
        let start = top ? Double.pi - Double(i + 1) * step : Double.pi + Double(i) * step
        let gap = (Double(UIStyle.sliceGap) + round) / Double(mid)
        return (start + gap, start + step - gap)
    }

    private func slices(top: Bool, count n: Int) -> some View {
        ZStack {
            ForEach(0..<n, id: \.self) { i in
                let selected = state.pick == (top ? .top(i) : .bottom(i))
                let item = top ? state.top(i) : nil
                let pinned: Bool = {
                    if top, case .shortcut(let slot)? = item { return slot.pinned }
                    return !top && state.apps.indices.contains(i) && state.apps[i].pinned
                }()
                let slider: SystemControl? = { if case .control(let c)? = item, c.kind != .panel { return c }; return nil }()
                let range = sliceStart(top: top, index: i, count: n)
                let slice = RingSlice(start: range.start, end: range.end, inner: sliceInner, outer: sliceOuter)
                // Çubuk dilimi seçilince zemini değil dolgusu sarı olur
                let gold = AnyShapeStyle(LinearGradient(colors: [.fingerGoldLight, .fingerGold, .fingerGoldDeep], startPoint: .top, endPoint: .bottom))
                let lit = pinned || (selected && slider != nil)
                let base = selected && slider == nil
                    ? gold
                    : AnyShapeStyle(LinearGradient(colors: [Color(white: lit ? 0.2 : 0.16),
                                                            Color(white: lit ? 0.14 : 0.1)],
                                                   startPoint: .top, endPoint: .bottom))
                ZStack {
                    slice.fill(base)
                    slice.stroke(base, style: StrokeStyle(lineWidth: round * 2, lineJoin: .round))
                    if let slider, let level = fillLevel(slider), level > 0.005 {
                        let fill = RingSlice(start: range.start, end: range.end, inner: sliceInner,
                                             outer: sliceInner + (sliceOuter - sliceInner) * CGFloat(level))
                        let style = selected || state.dragging == slider
                            ? gold
                            : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
                        fill.fill(style)
                        fill.stroke(style, style: StrokeStyle(lineWidth: round * 2, lineJoin: .round))
                    }
                }
                .compositingGroup()
                .shadow(color: selected ? Color.fingerGold.opacity(0.5) : .black.opacity(0.2 + 0.2 * UIStyle.shadow),
                        radius: selected ? 10 : 6 + 4 * UIStyle.shadow, y: selected ? 0 : 3)
            }
        }
        .frame(width: outer * 2, height: outer * 2)
    }

    /// Merkezden `a` açısında `r` uzaklık (ekranda y aşağı doğru artar)
    private func offset(_ a: Double, _ r: CGFloat) -> CGSize {
        CGSize(width: CGFloat(cos(a)) * r, height: -CGFloat(sin(a)) * r)
    }

    /// Sabitlenen dilimin dış kenarında küçük raptiye
    @ViewBuilder
    private func pin(_ pinned: Bool, selected: Bool) -> some View {
        if pinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.fingerGold)
        }
    }

    /// Yazı kutusu dilimin içine sığacak genişlikte; sığmayan yazı küçülür
    private func shortcutLabel(_ item: RadialShortcut, selected: Bool, width: Double) -> some View {
        VStack(spacing: 2) {
            Text(item.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(item.keys)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.black.opacity(0.6) : Color.white.opacity(0.45))
        }
        .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.white.opacity(0.88))
        .frame(width: width, height: labelHeight)
    }

    /// Aç/kapa, AirDrop ve yansıtma dilimi: yuvarlak simge, ad, altında anahtar ya da seçili mod
    private func controlLabel(_ control: SystemControl, selected: Bool, width: Double) -> some View {
        let value = state.value(control)
        let on = value.isOn
        return VStack(spacing: 3) {
            ControlGlyph(control: control, on: on || control.kind == .panel)
                .frame(width: 14, height: 14)
                .foregroundStyle(on ? (selected ? Color.fingerGold : Color.black.opacity(0.8)) : Color.white.opacity(0.9))
                .frame(width: 25, height: 25)
                .background(Circle().fill(on ? (selected ? Color.black.opacity(0.78) : Color.fingerGold) : Color.white.opacity(selected ? 0.3 : 0.14)))
            Text(control.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.white.opacity(0.88))
            switch control.kind {
            case .toggle:
                if value == .unknown {
                    Text("–").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                } else {
                    MiniSwitch(on: on, onGold: selected)
                }
            case .choice:
                if case .airDrop(let mode) = value {
                    Text(mode.short)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color.black.opacity(0.6) : Color.white.opacity(0.5))
                }
            default:
                EmptyView()
            }
        }
        .frame(width: width, height: controlHeight)
    }

    /// Dilimin ne kadar dolu olduğu: çubukta değer, aç/kapa düğmesinde açıksa tamamı
    private func fillLevel(_ control: SystemControl) -> Double? {
        let value = state.value(control)
        if control.kind == .slider { return value.levelValue }
        return value == .unknown ? nil : (value.isOn ? 1 : 0)
    }

    /// Ses, parlaklık ve aç/kapa düğmeleri aynı biçimde: içte simge, dışta küçük etiket (yüzde ya da durum).
    /// Etiket kutusuz, dilimin tam ortasında ve göbeğe göre döndürülmüş (tabanı merkeze bakar);
    /// rengi dolgunun ona ulaşıp ulaşmadığına göre koyu ya da açık olur.
    private func sliderLabels(_ control: SystemControl, angle a: Double, range: (start: Double, end: Double), selected: Bool) -> some View {
        let value = state.value(control)
        let level = fillLevel(control) ?? 0
        let iconR = sliceInner + 14
        // Yazı dilimin içiyle dışı arasında tam ortada
        let textR = (sliceInner + sliceOuter) / 2 + 4
        let fillR = sliceInner + (sliceOuter - sliceInner) * CGFloat(level) + round
        let status: String = {
            switch control.kind {
            case .slider: return percent(value)
            case .choice: if case .airDrop(let m) = value { return m.short }; return "–"
            default: return value == .unknown ? "–" : (value.isOn ? String(localized: "Açık") : String(localized: "Kapalı"))
            }
        }()
        return ZStack {
            ControlGlyph(control: control, on: level > 0.005)
                .frame(width: 16, height: 16)
                .foregroundStyle(fillR > iconR + 8 ? Color.black.opacity(0.78) : Color.white.opacity(0.92))
                .offset(offset(a, iconR))
            // Yazı açık; dolgunun ulaştığı kısmı koyu (dolgu yazının ortasına gelince yazı yarı yarıya renk değiştirir)
            label(status, at: a, radius: textR).foregroundStyle(Color.white)
            if level > 0.005 {
                let fill = RingSlice(start: range.start, end: range.end, inner: sliceInner,
                                     outer: sliceInner + (sliceOuter - sliceInner) * CGFloat(level))
                label(status, at: a, radius: textR).foregroundStyle(Color.black.opacity(0.9))
                    .frame(width: outer * 2, height: outer * 2)
                    .mask(ZStack { fill.fill(); fill.stroke(style: StrokeStyle(lineWidth: round * 2, lineJoin: .round)) })
            }
        }
    }

    /// Dilim kenarındaki durum yazısı, tabanı göbeğe bakacak biçimde döndürülmüş
    private func label(_ status: String, at a: Double, radius: CGFloat) -> some View {
        RingLabel(text: status, size: 11)
            .fixedSize()
            .rotationEffect(.radians(.pi / 2 - a))
            .offset(offset(a, radius))
    }

    /// AirDrop seçimindeki seçenek; şu anki seçimin yanında işaret
    private func airDropOption(_ mode: AirDropMode, selected: Bool, width: Double) -> some View {
        let current: Bool = { if case .airDrop(let m) = state.value(.airDrop) { return m == mode }; return false }()
        return VStack(spacing: 3) {
            Image(systemName: current ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(selected ? Color.black.opacity(0.75) : (current ? Color.fingerGold : Color.white.opacity(0.4)))
            Text(mode.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.white.opacity(0.88))
        }
        .frame(width: width, height: labelHeight + 6)
    }
}

/// Dilim kenarındaki durum yazısı: "%" işareti küçük ve soluk, sayı rakam genişliği sabit (değer değişince kaymaz)
struct RingLabel: View {
    let text: String
    let size: CGFloat

    var body: some View {
        if text.hasPrefix("%") {
            Text("%").font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(.primary.opacity(0.8))
                + Text(text.dropFirst()).font(.system(size: size, weight: .bold).monospacedDigit())
        } else if text.hasSuffix("%") {
            // İngilizce gibi dillerde işaret sayının arkasında ("82%", Almancada "82 %")
            Text(text.dropLast()).font(.system(size: size, weight: .bold).monospacedDigit())
                + Text("%").font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(.primary.opacity(0.8))
        } else {
            Text(text).font(.system(size: size * 0.95, weight: .semibold)).tracking(0.2)
        }
    }
}

/// Apple Ayarlar'daki gibi küçük aç/kapa anahtarı
struct MiniSwitch: View {
    let on: Bool
    /// Sarı (seçili) dilimin üstünde: koyu renkler
    var onGold = false

    var body: some View {
        Capsule()
            .fill(on ? (onGold ? Color.black.opacity(0.75) : Color.fingerGold) : Color.white.opacity(onGold ? 0.35 : 0.2))
            .frame(width: 22, height: 13)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(on && onGold ? Color.fingerGold : .white)
                    .padding(1.5)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
            }
    }
}

/// Denetim Merkezi düğmesinin simgesi. Bluetooth ve AirDrop'un sistemde simgesi yok; Apple'ın
/// Denetim Merkezi'ndeki biçimleriyle burada çizilir (dolu şekil, her boyutta aynı kalınlık oranı).
struct ControlGlyph: View {
    let control: SystemControl
    var on = true

    var body: some View {
        if let drawn = DrawnGlyph(control: control) {
            drawn.aspectRatio(drawn.aspect, contentMode: .fit)
        } else {
            Image(systemName: control.symbol(on: on))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fontWeight(.semibold)
        }
    }
}

/// Elle çizilen düğme simgeleri; önizleme (`CommunityDemoView`) de aynı yolu kullanır
struct DrawnGlyph: Shape {
    let control: SystemControl

    init?(control: SystemControl) {
        guard control == .bluetooth || control == .airDrop else { return nil }
        self.control = control
    }

    /// En / boy oranı
    var aspect: CGFloat { control == .bluetooth ? 0.6 : 1 }

    func path(in r: CGRect) -> Path {
        control == .bluetooth ? Self.bluetooth(in: r) : Self.airDrop(in: r)
    }

    /// Bluetooth işareti: dikey gövde, sağda iki sivri uç, solda iki kuyruk; uçlar köşeli, birleşimler yuvarlak
    static func bluetooth(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let w = r.height * 0.115
        let inset = w / 2 / r.height
        var rune = Path()
        rune.move(to: p(0.1, 0.285))
        rune.addLine(to: p(0.86, 0.74))
        rune.addLine(to: p(0.5, 1 - inset))
        rune.addLine(to: p(0.5, inset))
        rune.addLine(to: p(0.86, 0.26))
        rune.addLine(to: p(0.1, 0.715))
        return rune.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    /// AirDrop işareti: ortada nokta, çevresinde altı açık iki halka
    static func airDrop(in r: CGRect) -> Path {
        let side = min(r.width, r.height)
        let c = CGPoint(x: r.midX, y: r.midY)
        let w = side * 0.1
        var shape = Path(ellipseIn: CGRect(x: c.x - side * 0.115, y: c.y - side * 0.115, width: side * 0.23, height: side * 0.23))
        // Alttaki boşluk: aşağı bakan 76°'lik kama (SwiftUI'de y aşağı, 90° = aşağı)
        for (radius, gap) in [(side * 0.29, 44.0), (side * 0.5 - w / 2, 38.0)] {
            var ring = Path()
            ring.addArc(center: c, radius: radius, startAngle: .degrees(90 + gap), endAngle: .degrees(90 - gap), clockwise: false)
            shape.addPath(ring.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round)))
        }
        return shape
    }
}

private extension Path {
    /// Merkez (0, 0) olarak çizilen yolu kutunun ortasına taşır
    func offsetToCenter() -> some Shape { CenteredPath(path: self) }
}

private struct CenteredPath: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path {
        path.offsetBy(dx: rect.midX, dy: rect.midY)
    }
}

/// Halka dilimi. Açılar radyan, 0 = sağ, saat yönünün tersi (matematikteki gibi).
private struct RingSlice: Shape {
    let start: Double
    let end: Double
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ a: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y - CGFloat(sin(a)) * r)
        }
        let steps = 24
        var p = Path()
        p.move(to: point(start, inner))
        for s in 0...steps { p.addLine(to: point(start + (end - start) * Double(s) / Double(steps), outer)) }
        for s in (0...steps).reversed() { p.addLine(to: point(start + (end - start) * Double(s) / Double(steps), inner)) }
        p.closeSubpath()
        return p
    }
}
