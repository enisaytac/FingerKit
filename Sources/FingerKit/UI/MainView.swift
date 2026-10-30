import AppKit
import SwiftUI
import FingerKitCore

/// Pencerenin o anki durumu: seçili uygulama, arama, hareket ekleme adımları
@Observable
final class UIState {
    var selectedApp: String? = AppProfile.everywhere
    var search = ""
    var adding: AddFlow?
}

/// Yeni hareket ekleme ya da var olanı düzenleme: önce hareket, sonra kısayol
struct AddFlow: Equatable {
    var appID: String
    var gesture: Gesture?
    var shortcut: Shortcut?
    /// Kısayol yerine hazır iş seçildiyse (kısayolu varsa `shortcut` onun kısayoludur)
    var task: ReadyTask?
    /// Düzenlenen satır; nil ise yeni hareket
    var editing: UUID?
}

/// Bir sayfanın kendi AppKit katmanı. Aynı SwiftUI ağacında gizli tutulan sayfalar her canlandırma
/// karesinde çizim ve yerleşime katılıyordu (öneri şeridi kayarken 7 ms yerine 26 ms); ayrı katmanda
/// gizli sayfa uyur. Ortam (motor, tema, renk) olduğu gibi aktarılır, gizlenip açılırken kısa bir solma olur.
struct PageHost<Content: View>: NSViewRepresentable {
    let visible: Bool
    @ViewBuilder let content: () -> Content

    /// Sayfa burada yaşar; gizliyken pencereden çıkarılır (AppKit yerleşim ve fare izleme turlarına
    /// girmesin) ama silinmez, durumu ve kaydırma yeri korunur
    final class Coordinator {
        var host: NSHostingView<AnyView>?
        var visible = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let host = NSHostingView(rootView: root(context))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        context.coordinator.host = host
        container.addSubview(host)
        if !visible {
            // Arkada hazırlanan sayfa bir kez pencerede yerleşip çizilir, sonra çıkarılır:
            // ilk açılışı da hızlı olsun
            DispatchQueue.main.async {
                host.frame = container.bounds
                host.layoutSubtreeIfNeeded()
                host.display()
                if host.superview != nil, !context.coordinator.visible { host.removeFromSuperview() }
            }
        }
        context.coordinator.visible = visible
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let host = context.coordinator.host else { return }
        let wasVisible = context.coordinator.visible
        context.coordinator.visible = visible
        // Gizli sayfa güncellenmez (her sekme değişiminde beş sayfayı baştan karşılaştırmak yavaştı);
        // görünür olunca güncel ortamla (tema, renk) tazelenir
        if visible || wasVisible { host.rootView = root(context) }
        if visible, host.superview == nil {
            host.frame = container.bounds
            host.alphaValue = 0
            container.addSubview(host)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                host.animator().alphaValue = 1
            }
        } else if !visible, host.superview != nil {
            host.removeFromSuperview()
        }
    }

    private func root(_ context: Context) -> AnyView {
        var environment = context.environment
        environment.pageVisible = visible
        return AnyView(content().environment(\.self, environment))
    }
}

/// Açık sekme. @AppStorage değil: her sekme değişiminde ona bağlı bütün sayfalar yeniden çiziliyordu;
/// burada tutulur, son açık sekme ayrıca kaydedilir. Sayfalar içinden de sekme değiştirilebilir
/// (ör. "Daire menüyü aç" bağlantısı).
@Observable
final class TabState {
    var tab = MainTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .gestures {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }
}

/// Pencerenin üstündeki sekmeler
enum MainTab: String, CaseIterable {
    case gestures = "İzleme Dörtgeni"
    case hyper = "Hiper Tuş"
    case clipboard = "Pano"
    case shortcuts = "Kısayol Tuşları"
    case radial = "Daire menü"
}

/// Kısayollar sekmesinin durumu: sol sütun (uygulamalar) ile sağ taraf (kısayollar) paylaşır
@Observable
final class ShortcutsUIState {
    var selected: String?
    var adding: AppShortcutFlow?
}

/// Üstte sekmeler: "İzleme Dörtgeni" (trackpad hareketleri), "Hiper Tuş", "Pano", "Kısayol Tuşları" ve "Daire menü".
/// Bütün sekmeler aynı iskeleti paylaşır: solda hep aynı genişlikte bir sütun, sağda sayfa.
/// Sekme değişince sütun açılıp kapanmaz, üst çubuk kaymaz; yalnız içerik değişir.
/// Sağdaki sayfalar bir kez kurulur ve bellekte kalır (sekme değişince yalnız görünürlük değişir):
/// her açılışta sıfırdan kurmak 100-300 ms takılma yapıyordu. Her sayfa kendi katmanında (PageHost):
/// gizli sayfa çizilmez, yerleşime girmez; açık sayfadaki canlandırmalar onlar yüzünden ağırlaşmaz. Pencere açıldıktan sonra diğer sayfalar
/// sırayla arkada hazırlanır, ilk geçiş de akıcı olsun.
struct MainView: View {
    @Environment(Engine.self) private var engine
    /// Son açık sekme hatırlanır (TabState)
    @State private var tabs = TabState()
    private var tab: MainTab { tabs.tab }
    @State private var ui = UIState()
    @State private var shortcutsUI = ShortcutsUIState()
    @State private var radialUI = RadialUIState()
    @State private var columns = NavigationSplitViewVisibility.all
    /// Dar pencerede (ör. ekranın yarısına yaslanınca) soldaki sütun kendiliğinden gizlenir
    @State private var narrow = false
    /// Kurulmuş sayfalar
    @State private var built: Set<MainTab> = []

    var body: some View {
        @Bindable var engine = engine
        NavigationSplitView(columnVisibility: $columns) {
            ZStack {
                ForEach(MainTab.allCases.filter { built.contains($0) || $0 == tab }, id: \.self) { page in
                    PageHost(visible: page == tab) { sidebar(page) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .modifier(NightBackground(sidebar: true))
        } detail: {
            ZStack {
                ForEach(MainTab.allCases.filter { built.contains($0) || $0 == tab }, id: \.self) { page in
                    PageHost(visible: page == tab) { detail(page) }
                }
            }
            .modifier(NightBackground())
            .task { await prebuild() }
        }
        .animation(.easeInOut(duration: 0.18), value: tab)
        .onChange(of: tab) { built.insert($1) }
        .environment(tabs)
        .environment(ui)
        .environment(shortcutsUI)
        .environment(radialUI)
        .onGeometryChange(for: Bool.self) { $0.size.width < 940 } action: { isNarrow in
            guard isNarrow != narrow else { return }
            narrow = isNarrow
            withAnimation { columns = isNarrow ? .detailOnly : .all }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: $engine.settings.enabled) {
                    Text(engine.settings.enabled ? String(localized: "Açık") : String(localized: "Kapalı"))
                }
                .toggleStyle(.soft)
                .help(String(localized: "FingerKit'i açar ya da kapatır"))
            }
            ToolbarItem(placement: .principal) {
                TabBar(tab: $tabs.tab)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BackupButton()
            }
            ToolbarItem(placement: .primaryAction) {
                ThemeButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UpdateCheck.open()
                } label: {
                    Label(String(localized: "Güncellemeleri kontrol et"), systemImage: "arrow.down.circle")
                }
                .help(UpdateCheck.help)
            }
        }
        .navigationTitle("FingerKit")
        .frame(minWidth: 660, minHeight: 480)
        .background(WindowFrameMemory())
        .modifier(ThemeModifier())
        .task { await TabTimer.runIfAsked { tabs.tab = $0 } }
    }

    @ViewBuilder
    private func sidebar(_ page: MainTab) -> some View {
        switch page {
        case .gestures: AppSidebar()
        case .shortcuts: AppShortcutsView(part: .sidebar)
        case .radial: RadialAppSidebar()
        default: PageGuide(tab: page)
        }
    }

    @ViewBuilder
    private func detail(_ page: MainTab) -> some View {
        switch page {
        case .gestures: GesturesPage()
        case .hyper: HyperKeyView()
        case .clipboard: ClipboardView()
        case .shortcuts: AppShortcutsView(part: .detail)
        case .radial: RadialMenuView()
        }
    }

    /// Açık sekme hemen, diğerleri pencere ekrana geldikten sonra birer birer arkada kurulur
    private func prebuild() async {
        built.insert(tab)
        try? await Task.sleep(for: .milliseconds(700))
        for page in MainTab.allCases where !built.contains(page) {
            built.insert(page)
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

/// Geliştirme: FINGERKIT_SEKME_OLC verilince sekmeler sırayla açılır, her geçişte ana iş parçacığının
/// en uzun donma süresi yazdırılır (takılma ölçümü; akıcı sayılması için ~16 ms).
@MainActor
enum TabTimer {
    static let stripStep = Notification.Name("FingerKitStripStep")

    /// Ana iş parçacığının `ms` süre içindeki en uzun donması (milisaniye)
    static func worstGap(during ms: Int, _ action: () -> Void) async -> Double {
        var last = CACurrentMediaTime(), worst = 0.0
        let timer = Timer(timeInterval: 0.001, repeats: true) { _ in
            let now = CACurrentMediaTime()
            worst = max(worst, now - last)
            last = now
        }
        RunLoop.main.add(timer, forMode: .common)
        last = CACurrentMediaTime()
        action()
        try? await Task.sleep(for: .milliseconds(ms))
        timer.invalidate()
        return worst * 1000
    }

    static func runIfAsked(_ set: @escaping (MainTab) -> Void) async {
        let env = ProcessInfo.processInfo.environment
        // FINGERKIT_SERIT_OLC: öneri şeridi açıkken kart kaydırma
        if env["FINGERKIT_SERIT_OLC"] != nil {
            set(.hyper)
            try? await Task.sleep(for: .seconds(4))
            var gaps: [String] = []
            for _ in 0..<10 {
                let ms = await worstGap(during: 600) { NotificationCenter.default.post(name: stripStep, object: nil) }
                gaps.append(String(format: "%.0f", ms))
            }
            print("SERIT: \(gaps.joined(separator: " ")) ms")
            fflush(stdout)
            exit(0)
        }
        // FINGERKIT_PENCERE_RESMI=<klasör>: her sekmeyi açıp pencerenin resmini kaydeder (ekran kilitliyken de)
        if let dir = env["FINGERKIT_PENCERE_RESMI"] {
            try? await Task.sleep(for: .seconds(4))
            for tab in MainTab.allCases {
                set(tab)
                try? await Task.sleep(for: .seconds(1.2))
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView is NSHostingView<AnyView> == false && $0.title == "FingerKit" })?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(MainTab.allCases.firstIndex(of: tab)!).png"))
            }
            exit(0)
        }
        guard env["FINGERKIT_SEKME_OLC"] != nil else { return }
        try? await Task.sleep(for: .seconds(4))
        var results: [MainTab: [Double]] = [:]
        for _ in 0..<4 {
            for tab in MainTab.allCases {
                var last = CACurrentMediaTime(), worst = 0.0
                let timer = Timer(timeInterval: 0.001, repeats: true) { _ in
                    let now = CACurrentMediaTime()
                    worst = max(worst, now - last)
                    last = now
                }
                RunLoop.main.add(timer, forMode: .common)
                last = CACurrentMediaTime()
                set(tab)
                try? await Task.sleep(for: .milliseconds(700))
                timer.invalidate()
                results[tab, default: []].append(worst * 1000)
            }
        }
        for tab in MainTab.allCases {
            let ms = results[tab, default: []].map { String(format: "%.0f", $0) }.joined(separator: " ")
            print("SEKME \(tab.rawValue): \(ms) ms")
        }
        fflush(stdout)
        exit(0)
    }
}

/// Pencerenin boyutu ve yeri hatırlanır: kullanıcı büyütüp küçültünce bir sonraki açılışta öyle gelir.
/// İlk açılışta FingerKitApp'teki varsayılan boyut (1180x760) kullanılır.
private struct WindowFrameMemory: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Watcher() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Watcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.frameAutosaveName.isEmpty else { return }
            // Kayıt varsa ad verilir verilmez pencere o boyuta gelir; yoksa şimdiki boyut kaydedilir
            window.setFrameAutosaveName("FingerKitAnaPencere")
        }
    }
}

/// Hareketler sekmesinin sağ tarafı: ortada hareketler, sağda canlı trackpad
private struct GesturesPage: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 0) {
            GestureList()
                .frame(minWidth: 400, maxWidth: .infinity)
            LivePanel()
                .frame(width: 320)
                .modifier(NightBackground(sidebar: true))
        }
        .onAppear { engine.refreshSystemTrackpad() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            engine.refreshSystemTrackpad()
        }
    }
}

/// Kendi uygulama listesi olmayan sekmelerde sol sütun: sayfanın ne yaptığını kısa ve sade anlatır
private struct PageGuide: View {
    @Environment(Engine.self) private var engine
    let tab: MainTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIStyle.pad(14)) {
                SectionIcon(symbol: icon, size: 32)
                Text(LocalizedStringKey(tab.rawValue))
                    .font(.title3.weight(.semibold))
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIStyle.pad(18))
        }
    }

    private var icon: String {
        switch tab {
        case .hyper: "capslock.fill"
        default: "doc.on.clipboard"
        }
    }

    private var lines: [String] {
        switch tab {
        case .hyper: [
            String(localized: "Caps Lock'u süper tuşa çevirir."),
            String(localized: "Caps Lock'u basılı tut, bir harfe dokun: o uygulama açılır."),
            String(localized: "Ok tuşuna dokun: pencere ekranın o yarısına yaslanır."),
            String(localized: "Basılı tutup parmağını kaydır: pencere taşınır."),
            String(localized: "Tek başına basınca eskisi gibi büyük harf kilidi."),
        ]
        default: [
            String(localized: "Kopyaladığın yazıları, görselleri, bağlantıları ve ekran görüntülerini hatırlar."),
            String(localized: "⇪ + \(engine.settings.clipboard.key): panoyu açar. Birine tıkla, yapıştırılır."),
            String(localized: "Önemli olanı sabitle; süre dolsa da silinmez."),
            String(localized: "Kopyalar yalnız bu Mac'te durur."),
        ]
        }
    }
}

/// "Güncellemeleri kontrol et": FingerKit internete bağlanmaz; sürümler sayfası tarayıcıda açılır,
/// yeni sürüm var mı oradan bakılır.
enum UpdateCheck {
    static let releases = URL(string: "https://github.com/enisaytac/FingerKit/releases/latest")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var help: String {
        String(localized: "Sürümler sayfasını tarayıcıda açar (sende sürüm \(version)). FingerKit'in kendisi internete bağlanmaz.")
    }

    static func open() {
        NSWorkspace.shared.open(releases)
    }
}

/// Üstteki sekmeler: her sekme kendi adı kadar yer kaplar, üst çubuğa sığar (hazır bölmeli seçici
/// her bölmeyi en uzun ad kadar genişletiyordu).
private struct TabBar: View {
    @Binding var tab: MainTab

    var body: some View {
        SoftSegmented(selection: $tab, options: MainTab.allCases.map { ($0, $0.rawValue) })
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Bölüm"))
    }
}
