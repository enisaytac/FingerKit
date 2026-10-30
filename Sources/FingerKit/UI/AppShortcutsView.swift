import AppKit
import SwiftUI
import FingerKitCore
import UniformTypeIdentifiers

/// "Kısayollar" sekmesi: solda uygulamalar, sağda seçili uygulamanın kısayolları ve ekleme kartı.
/// İki parça ana pencerenin ortak iskeletine ayrı ayrı yerleşir; durumu ShortcutsUIState taşır.
struct AppShortcutsView: View {
    enum Part { case sidebar, detail }
    let part: Part
    @Environment(Engine.self) private var engine
    @Environment(ShortcutsUIState.self) private var state
    @Environment(TabState.self) private var tabs

    private var selected: String? {
        get { state.selected }
        nonmutating set { state.selected = newValue }
    }
    private var adding: AppShortcutFlow? {
        get { state.adding }
        nonmutating set { state.adding = newValue }
    }

    var body: some View {
        switch part {
        case .sidebar:
            sidebar
                .onAppear { if selected == nil { selected = engine.settings.appShortcuts.apps.first?.bundleID } }
                .onChange(of: state.selected) { adding = nil }
        case .detail:
            detail
        }
    }

    // MARK: - Sol sütun

    private var sidebar: some View {
        return SidebarScroll {
            SidebarHeader(title: String(localized: "Uygulamalar"))
            ForEach(engine.settings.appShortcuts.apps) { app in
                SidebarRow(selected: state.selected == app.bundleID) { state.selected = app.bundleID } label: {
                    BundleIcon(bundleID: app.bundleID)
                        .frame(width: 20, height: 20)
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(app.shortcuts.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button(String(localized: "Listeden kaldır"), role: .destructive) { removeApp(app.bundleID) }
                }
            }
        }
        .overlay {
            if engine.settings.appShortcuts.apps.isEmpty {
                Text(String(localized: "Henüz uygulama yok.\nAşağıdan ekle."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            AppPickerMenu(title: String(localized: "Uygulama ekle"), exclude: Set(engine.settings.appShortcuts.apps.map(\.bundleID))) { id, name in
                if !engine.settings.appShortcuts.apps.contains(where: { $0.bundleID == id }) {
                    engine.settings.appShortcuts.apps.append(AppShortcutProfile(bundleID: id, name: name))
                }
                selected = id
            }
            .padding(12)
        }
    }

    private func removeApp(_ id: String) {
        engine.settings.appShortcuts.apps.removeAll { $0.bundleID == id }
        if selected == id { selected = engine.settings.appShortcuts.apps.first?.bundleID }
    }

    // MARK: - Sağ taraf

    private var detail: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                // Öneriler sayfayla birlikte kayar: açılınca sayfayı pencereden taşırmaz
                CommunitySection(page: .shortcuts)
                VStack(alignment: .leading, spacing: UIStyle.pad(16)) {
                    if !engine.settings.enabled, engine.settings.appShortcuts.enabled {
                        SoftNotice(icon: "exclamationmark.circle.fill", text: String(localized: "FingerKit kapalı; kısayollar çalışmıyor. Sol üstteki düğmeden aç."))
                    }
                    if !engine.isTrusted {
                        SoftNotice(icon: "exclamationmark.circle.fill", text: String(localized: "Erişilebilirlik izni gerekli. “İzleme Dörtgeni” sekmesinde sağdaki karttan izin ver."))
                    }
                    FeatureExplainer(
                        title: String(localized: "Denetim Merkezi dairede"),
                        lines: [String(localized: "Trackpad'in sol alt köşesine tıkla: dairenin üst yarısında Bluetooth, ses, parlaklık ve AirDrop; yanında öndeki uygulamanın en sevilen kısayolları."),
                                String(localized: "Bluetooth ve AirDrop'a tıkla: açılır ya da kapanır. Ses ve parlaklıkta dilime bas, sürükle.")],
                        demo: CommunityDemo(.gesture(.cornerTapBottomLeft), .control(.airDrop)),
                        caption: String(localized: "Dairede AirDrop seçimi"), slice: SystemControl.airDrop.title,
                        badge: String(localized: "Yeni"),
                        link: (String(localized: "Daire menüyü aç"), { tabs.tab = .radial }))
                    FeatureExplainer(
                        title: String(localized: "Bir uygulamaya özel kısayol"),
                        lines: [String(localized: "Yalnız o uygulama öndeyken çalışır: bir tuş birleşimi başka kısayola, menü maddesine ya da hazır işe gider."),
                                String(localized: "Örnek: Chrome'da ⌘Q yanlışlıkla bütün pencereleri kapatmasın, yalnız sekmeyi kapatsın.")],
                        demo: CommunityDemo(.keys(["⌘", "Q"]), .quitGuard),
                        chip: "⌘Q → ⌘W", caption: String(localized: "Yalnız sekme kapanır"))
                    if let app = engine.settings.appShortcuts.apps.first(where: { $0.bundleID == selected }) {
                        appSection(app)
                    } else {
                        Text(String(localized: "Bir uygulama öndeyken bir tuş birleşimi başka bir kısayol gönderebilir ya da o uygulamanın menüsünden bir maddeyi seçebilir. Başka uygulamalarda tuş eskisi gibi kalır.\n\nBaşlamak için soldan bir uygulama ekle.") + " " + String(localized: "Ya da yukarıdaki “Topluluğun sevdiği ayarlar”dan birini tek tıkla ekle."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(UIStyle.pad(20))
                .frame(maxWidth: .infinity)
            }
            .opacity(engine.settings.appShortcuts.enabled ? 1 : 0.5)
        }
    }

    private var header: some View {
        @Bindable var engine = engine
        return PageHeader(icon: "command.square.fill",
                          title: String(localized: "Uygulama kısayolları"),
                          detail: String(localized: "Bir tuş birleşimi yalnız seçtiğin uygulamada başka iş yapar.")) {
            Toggle("", isOn: $engine.settings.appShortcuts.enabled)
                .toggleStyle(.soft)
                .labelsHidden()
                .help(engine.settings.appShortcuts.enabled ? String(localized: "Uygulama kısayolları açık") : String(localized: "Uygulama kısayolları kapalı; tuşlar olduğu gibi geçer"))
        }
    }

    @ViewBuilder
    private func appSection(_ app: AppShortcutProfile) -> some View {
        HStack(spacing: 8) {
            BundleIcon(bundleID: app.bundleID).frame(width: 22, height: 22)
            Text(app.name).font(.headline)
        }
        if app.shortcuts.isEmpty {
            Text(String(localized: "Bu uygulamada henüz kısayol yok. “Ekle”ye bas, önce tuşu sonra ne yapacağını seç."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CardStack {
                ForEach(app.shortcuts) { item in
                    AppShortcutRow(item: item, bundleID: app.bundleID, editing: adding?.editing == item.id) {
                        adding = AppShortcutFlow(trigger: item.trigger, action: item.action, editing: item.id)
                    }
                }
            }
        }
        if adding != nil {
            AppShortcutCard(adding: Bindable(state).adding, app: app)
        } else {
            Button {
                adding = AppShortcutFlow()
            } label: {
                Label("Ekle", systemImage: "plus")
            }
            .buttonStyle(.softPrimary)
        }
    }
}

// MARK: - Satır

/// Tek satır: tetik → iş, aç/kapa, sil
private struct AppShortcutRow: View {
    @Environment(Engine.self) private var engine
    let item: AppShortcut
    let bundleID: String
    let editing: Bool
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            KeyCap(text: item.trigger.triggerDisplay)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            switch item.action {
            case .shortcut(let s):
                KeyCap(text: s.display)
            case .menu(let path):
                Label(path.joined(separator: " › "), systemImage: "filemenu.and.selection")
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .task(let task):
                Label(task.label, systemImage: task.symbol)
                    .lineLimit(1)
            }
            if item.trigger.isHyper, !engine.settings.hyper.enabled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(String(localized: "Hiper Tuş kapalı; Caps Lock + tuş satırları çalışmaz"))
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.softQuiet)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            .help("Sil")
            Toggle("", isOn: enabled)
                .toggleStyle(.softSmall)
                .labelsHidden()
                .help(item.enabled ? String(localized: "Açık") : String(localized: "Kapalı; tuş olduğu gibi geçer"))
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(8))
        .opacity(item.enabled ? 1 : 0.55)
        .rowHighlight(editing)
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(String(localized: "Düzenle")) { edit() }
            Button("Sil", role: .destructive) { remove() }
        }
    }

    private var index: (Int, Int)? {
        let apps = engine.settings.appShortcuts.apps
        guard let a = apps.firstIndex(where: { $0.bundleID == bundleID }),
              let i = apps[a].shortcuts.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (a, i)
    }

    private var enabled: Binding<Bool> {
        Binding {
            item.enabled
        } set: { on in
            guard let (a, i) = index else { return }
            engine.settings.appShortcuts.apps[a].shortcuts[i].enabled = on
        }
    }

    private func remove() {
        guard let (a, i) = index else { return }
        engine.settings.appShortcuts.apps[a].shortcuts.remove(at: i)
    }
}

// MARK: - Ekleme kartı

/// Yeni kısayol ya da var olanı düzenleme: önce tetik, sonra iş
struct AppShortcutFlow {
    enum TriggerKind: String, CaseIterable { case keys = "Tuş birleşimi", hyper = "Caps Lock + tuş" }
    enum ActionKind: String, CaseIterable { case shortcut = "Kısayol gönder", menu = "Menü maddesi", task = "Hazır iş" }

    var triggerKind = TriggerKind.keys
    var trigger: Shortcut?
    var actionKind = ActionKind.menu
    var sendShortcut: Shortcut?
    var menuPath: [String]?
    var task: ReadyTask?
    var editing: UUID?

    init() {}

    init(trigger: Shortcut, action: AppAction, editing: UUID) {
        triggerKind = trigger.isHyper ? .hyper : .keys
        self.trigger = trigger
        switch action {
        case .shortcut(let s):
            actionKind = .shortcut
            sendShortcut = s
        case .menu(let path):
            actionKind = .menu
            menuPath = path
        case .task(let t):
            actionKind = .task
            task = t
        }
        self.editing = editing
    }

    var action: AppAction? {
        switch actionKind {
        case .shortcut: sendShortcut.map { .shortcut($0) }
        case .menu: menuPath.map { .menu($0) }
        case .task: task.map { .task($0) }
        }
    }
}

private struct AppShortcutCard: View {
    @Environment(Engine.self) private var engine
    @Binding var adding: AppShortcutFlow?
    let app: AppShortcutProfile
    private var flow: AppShortcutFlow { adding ?? AppShortcutFlow() }
    @State private var listening = false
    @State private var stopRecording: (() -> Void)?
    /// Uygulamanın okunan menüsü (nil: henüz okunmadı)
    @State private var menu: [MenuPresser.Item]?
    @State private var menuMissing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(flow.editing == nil ? String(localized: "Yeni kısayol") : String(localized: "Kısayolu düzenle"))
                .font(.headline)

            step(1, String(localized: "Tuş")) {
                VStack(alignment: .leading, spacing: 8) {
                    SoftSegmented(selection: triggerKind, options: AppShortcutFlow.TriggerKind.allCases.map { ($0, $0.rawValue) })
                    triggerInput
                }
            }

            step(2, String(localized: "Ne yapsın")) {
                VStack(alignment: .leading, spacing: 8) {
                    SoftSegmented(selection: binding(\.actionKind), options: AppShortcutFlow.ActionKind.allCases.map { ($0, $0.rawValue) })
                    switch flow.actionKind {
                    case .shortcut: ShortcutField(shortcut: binding(\.sendShortcut))
                    case .menu: menuInput
                    case .task:
                        HStack(spacing: 10) {
                            if let task = flow.task { TaskChip(task: task) }
                            TaskPicker(title: flow.task == nil ? String(localized: "Hazır iş seç") : String(localized: "Değiştir")) { adding?.task = $0 }
                        }
                    }
                }
            }

            ForEach(warnings, id: \.self) { text in
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(String(localized: "Vazgeç")) { stopListening(); adding = nil }
                Spacer()
                Button("Kaydet") { save() }
                    .buttonStyle(.softPrimary)
                    .disabled(flow.trigger?.isValidTrigger != true || flow.action == nil)
                    .pageShortcut(.defaultAction)
            }
        }
        .padding(UIStyle.pad(18))
        .surface(.raised)
        .onPageVisibility(hide: { stopListening() })
    }

    private func step(_ n: Int, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StepNumber(n: n)
            Text(title)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }

    private func binding<T>(_ path: WritableKeyPath<AppShortcutFlow, T>) -> Binding<T> {
        Binding { flow[keyPath: path] } set: { adding?[keyPath: path] = $0 }
    }

    /// Tür değişince önceki tuş silinir (biri öbürüne uymaz)
    private var triggerKind: Binding<AppShortcutFlow.TriggerKind> {
        Binding { flow.triggerKind } set: { kind in
            guard kind != flow.triggerKind else { return }
            stopListening()
            adding?.triggerKind = kind
            adding?.trigger = nil
        }
    }

    @ViewBuilder
    private var triggerInput: some View {
        if flow.triggerKind == .keys {
            ShortcutField(shortcut: binding(\.trigger))
        } else {
            HStack(spacing: 10) {
                HyperKeyCap(key: listening ? nil : flow.trigger?.key, listening: listening)
                Button(listening ? String(localized: "Vazgeç") : (flow.trigger == nil ? String(localized: "Tuşa bas") : String(localized: "Değiştir"))) {
                    listening ? stopListening() : startListening()
                }
            }
        }
    }

    @ViewBuilder
    private var menuInput: some View {
        HStack(spacing: 8) {
            if let menu, !menu.isEmpty {
                Menu {
                    MenuTreeItems(items: menu) { adding?.menuPath = $0 }
                } label: {
                    Text(flow.menuPath?.joined(separator: " › ") ?? String(localized: "Menüden seç"))
                }
                .fixedSize()
            } else {
                if let path = flow.menuPath {
                    Text(path.joined(separator: " › "))
                        .fontWeight(.medium)
                }
                Button(flow.menuPath == nil ? String(localized: "Menüyü oku") : String(localized: "Değiştir")) { readMenu() }
            }
        }
        if menuMissing {
            HStack(spacing: 8) {
                Text(String(localized: "\(app.name) açık değil; menüsü okunamıyor."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Aç")) { openApp() }
                    .controlSize(.small)
            }
        }
    }

    private var warnings: [String] {
        guard let trigger = flow.trigger else { return [] }
        var out: [String] = []
        if !trigger.isValidTrigger {
            out.append(trigger.mouse != nil
                ? String(localized: "Tetik fare tıklaması olamaz; bir tuş birleşimine bas.")
                : String(localized: "Tek başına harf her yazışta tetiklenir; ⌘, ⌥, ⌃ ya da ⇧ ile birlikte bas."))
        }
        if let dup = engine.settings.appShortcuts.duplicate(of: trigger, in: app.bundleID, editing: flow.editing) {
            out.append(String(localized: "\(trigger.triggerDisplay) bu uygulamada zaten var (\(dup.action.display)). Kaydedersen onun yerine geçer."))
        }
        if trigger.isHyper {
            let hyper = engine.settings.hyper
            if !hyper.enabled {
                out.append(String(localized: "Hiper Tuş kapalı; bu satır o açılınca çalışır."))
            }
            if let snap = hyper.snap(for: trigger.keyCode) {
                out.append(String(localized: "⇪ + \(trigger.key) her yerde pencereyi yaslıyor (\(snap.layout.title)); \(app.name)'de bunun yerine bu kısayol çalışır."))
            } else if let open = hyper.binding(for: trigger.keyCode) {
                out.append(String(localized: "⇪ + \(trigger.key) her yerde \(open.appName)'yi açıyor; \(app.name)'de bunun yerine bu kısayol çalışır."))
            }
            let clip = engine.settings.clipboard
            if clip.enabled, clip.keyCode == trigger.keyCode {
                out.append(String(localized: "⇪ + \(trigger.key) pano listesini açıyor; \(app.name)'de bunun yerine bu kısayol çalışır."))
            }
        }
        return out
    }

    private func readMenu() {
        menuMissing = false
        MenuPresser.read(bundleID: app.bundleID) { items in
            menu = items
            menuMissing = items == nil
        }
    }

    private func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            // Menü çubuğu uygulama açıldıktan biraz sonra hazır olur
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { readMenu() }
        }
    }

    private func save() {
        guard let trigger = flow.trigger, trigger.isValidTrigger, let action = flow.action else { return }
        var item = AppShortcut(trigger: trigger, action: action)
        if let id = flow.editing {
            item.id = id
            item.enabled = app.shortcuts.first { $0.id == id }?.enabled ?? true
        }
        engine.settings.appShortcuts.set(item, in: app.bundleID, name: app.name)
        stopListening()
        adding = nil
    }

    private func startListening() {
        listening = true
        stopRecording = listenForKey(engine) { key in
            stopListening()
            guard let key else { return }
            adding?.trigger = Shortcut(keyCode: key.0, modifiers: .hyper, key: key.1)
        }
    }

    private func stopListening() {
        stopRecording?()
        stopRecording = nil
        listening = false
    }
}

/// Okunan menü ağacı iç içe menü olarak; yaprağa tıklayınca yolu verir
private struct MenuTreeItems: View {
    let items: [MenuPresser.Item]
    let pick: ([String]) -> Void

    var body: some View {
        ForEach(items) { item in
            if item.children.isEmpty {
                Button(item.title) { pick(item.path) }
            } else {
                Menu(item.title) {
                    MenuTreeItems(items: item.children, pick: pick)
                }
            }
        }
    }
}

/// "Uygulama ekle": açık uygulamalardan seç ya da Uygulamalar klasöründen bul
struct AppPickerMenu: View {
    let title: String
    let exclude: Set<String>
    var message = String(localized: "Kısayollarını ayarlamak istediğin uygulamayı seç")
    let pick: (String, String) -> Void

    var body: some View {
        Menu {
            Section(String(localized: "Açık uygulamalar")) {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? "?") {
                        if let id = app.bundleIdentifier { pick(id, app.localizedName ?? id) }
                    }
                }
            }
            Divider()
            Button(String(localized: "Başka bir uygulama seç…")) { pickFromDisk() }
        } label: {
            Label(title, systemImage: "plus")
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { !exclude.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func pickFromDisk() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Ekle"
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        pick(id, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }
}
