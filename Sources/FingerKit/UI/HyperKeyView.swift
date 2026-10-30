import AppKit
import SwiftUI
import FingerKitCore
import UniformTypeIdentifiers

/// "Hyper Key" sekmesi: aç/kapa, uygulama açma listesi ve ekleme, pencere yaslama, pencere taşıma
struct HyperKeyView: View {
    @Environment(Engine.self) private var engine
    @State private var adding: HyperAddFlow?

    var body: some View {
        @Bindable var engine = engine
        VStack(spacing: 0) {
            header
            ScrollView {
                // Öneriler sayfayla birlikte kayar: açılınca sayfayı pencereden taşırmaz
                CommunitySection(page: .hyper)
                VStack(alignment: .leading, spacing: UIStyle.pad(16)) {
                    if !engine.settings.enabled, engine.settings.hyper.enabled {
                        SoftNotice(icon: "pause.circle.fill",
                                    text: String(localized: "FingerKit kapalı; Hiper Tuş de çalışmıyor. Sol üstteki düğmeden aç."))
                    }
                    if !engine.isTrusted {
                        SoftNotice(icon: "lock.fill",
                                    text: String(localized: "Erişilebilirlik izni gerekli. “İzleme Dörtgeni” sekmesinde sağdaki karttan izin ver."))
                    }
                    FeatureExplainer(
                        title: String(localized: "Süper tuş nedir?"),
                        lines: [String(localized: "Caps Lock'u basılı tutup bir harfe dokununca FingerKit o harfe bağlı işi yapar: uygulama açar, pencereyi yaslar ya da taşır."),
                                String(localized: "Hiçbir uygulama bu birleşimi kullanmaz; başka kısayolla çakışmaz."),
                                String(localized: "Caps Lock'a tek başına basınca eskisi gibi büyük harf kilidi açılır.")],
                        demo: CommunityDemo(.keys(["⇪", "S"]), .openApp(symbol: "safari.fill", hue: 0.58)),
                        chip: "⇪ + S", caption: String(localized: "⇪ + S: Safari açılır"))
                    SectionTitle(title: String(localized: "Uygulama açma"),
                                 detail: String(localized: "Caps Lock + harf: o uygulama açılır, açıksa öne gelir. Uygulama yerine hazır bir iş de seçebilirsin (pencereyi küçült, site aç, Kestirme…)."))
                    list
                    if adding != nil {
                        HyperAddCard(adding: $adding)
                    } else {
                        Button {
                            adding = HyperAddFlow()
                        } label: {
                            Label("Ekle", systemImage: "plus")
                        }
                        .buttonStyle(.softPrimary)
                    }
                    SectionTitle(title: String(localized: "Pencere yaslama"))
                    FeatureExplainer(
                        title: String(localized: "Caps Lock + ok: pencere ekranın yarısına"),
                        lines: [String(localized: "Öndeki pencere ekranın sol, sağ, üst ya da alt yarısını kaplar; iki pencere yan yana gelir."),
                                String(localized: "Caps Lock + Boşluk pencereyi bütün ekrana yayar.")],
                        demo: CommunityDemo(.keys(["⇪", "←"]), .snap(.left)),
                        chip: "⇪ + ←", caption: SnapLayout.left.title)
                    SnapSection()
                    SectionTitle(title: String(localized: "Pencere taşıma"))
                    FeatureExplainer(
                        title: String(localized: "Caps Lock + parmak kaydır: pencere taşınır"),
                        lines: [String(localized: "Caps Lock'u basılı tut, trackpad'de parmağını kaydır: imlecin altındaki pencere onunla gelir."),
                                String(localized: "Başlık çubuğunu aramak, tıklayıp sürüklemek gerekmez.")],
                        demo: CommunityDemo(.hyperDrag, .moveWindow),
                        chip: "⇪", caption: String(localized: "Pencere taşıma"))
                    MoveSection()
                    Text(String(localized: "Listede olmayan Hyper birleşimleri ⌘⌥⌃⇧ + tuş olarak olduğu gibi geçer; başka uygulamalar onları kullanabilir."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(UIStyle.pad(20))
                .frame(maxWidth: .infinity)
            }
            .opacity(engine.settings.hyper.enabled ? 1 : 0.5)
        }
    }

    private var header: some View {
        @Bindable var engine = engine
        return PageHeader(icon: "capslock.fill", title: "Hiper Tuş",
                          detail: String(localized: "Caps Lock başka bir tuşla birlikte basılınca ⌘⌥⌃⇧ hepsi birden olur. Tek basış eskisi gibi büyük harf kilidini açıp kapatır.")) {
            Toggle("", isOn: $engine.settings.hyper.enabled)
                .toggleStyle(.soft)
                .labelsHidden()
                .help(engine.settings.hyper.enabled ? String(localized: "Hiper Tuş açık") : String(localized: "Hiper Tuş kapalı; Caps Lock normal çalışır"))
        }
    }

    @ViewBuilder
    private var list: some View {
        let bindings = engine.settings.hyper.bindings
        if bindings.isEmpty {
            Text(String(localized: "Henüz kısayol yok. “Ekle”ye bas, bir harf ve bir uygulama seç.") + " " + String(localized: "Ya da yukarıdaki “Topluluğun sevdiği ayarlar”dan birini tek tıkla ekle."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CardStack {
                ForEach(bindings) { binding in
                    HyperRow(binding: binding, editing: adding?.editing == binding.id) {
                        adding = HyperAddFlow(key: (binding.keyCode, binding.key),
                                              app: binding.task == nil ? (binding.bundleID, binding.appName) : nil,
                                              task: binding.task, editing: binding.id)
                    }
                }
            }
        }
    }
}

/// Tek satır: ⇪ + tuş, uygulama simgesi ve adı, sil
private struct HyperRow: View {
    @Environment(Engine.self) private var engine
    let binding: HyperBinding
    let editing: Bool
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            HyperKeyCap(key: binding.key)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            if let task = binding.task {
                TaskChip(task: task)
            } else {
                BundleIcon(bundleID: binding.bundleID)
                    .frame(width: 24, height: 24)
                Text(binding.appName)
                    .fontWeight(.medium)
            }
            if binding.task == nil, NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) == nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(String(localized: "Bu uygulama bilgisayarda bulunamadı"))
            }
            if let snap = engine.settings.hyper.snap(for: binding.keyCode) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(String(localized: "⇪ + \(binding.key) pencereyi yaslıyor (\(snap.layout.title)); o satır açıkken bu uygulama açılmaz"))
            }
            Spacer()
            Button {
                remove()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.softQuiet)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            .help("Sil")
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(8))
        .rowHighlight(editing)
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(String(localized: "Düzenle")) { edit() }
            Button("Sil", role: .destructive) { remove() }
        }
    }

    private func remove() {
        engine.settings.hyper.bindings.removeAll { $0.id == binding.id }
    }
}

/// "⇪ + S" tuş çizimi; `listening` iken "tuşa bas…" yanıp söner
struct HyperKeyCap: View {
    let key: String?
    var listening = false

    var body: some View {
        HStack(spacing: 4) {
            cap("⇪")
            Text("+").foregroundStyle(.secondary)
            cap(key ?? (listening ? "…" : "?"))
        }
    }

    private func cap(_ text: String) -> some View {
        KeyCap(text: text, listening: listening && text != "⇪")
    }
}

/// Uygulamanın kendi simgesi
struct BundleIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "app.dashed")
        }
    }
}

// MARK: - Ekleme

/// Yeni kısayol ya da var olanı düzenleme: önce tuş, sonra uygulama
struct HyperAddFlow {
    var key: (code: UInt16, name: String)?
    var app: (bundleID: String, name: String)?
    /// Uygulama yerine hazır iş
    var task: ReadyTask?
    var editing: UUID?
}

private struct HyperAddCard: View {
    @Environment(Engine.self) private var engine
    /// Bağlantı (Binding) üzerinden: tuş beklerken seçilen uygulama kaybolmasın
    @Binding var adding: HyperAddFlow?
    private var flow: HyperAddFlow { adding ?? HyperAddFlow() }
    @State private var listening = false
    @State private var stopRecording: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(flow.editing == nil ? String(localized: "Yeni kısayol") : String(localized: "Kısayolu düzenle"))
                .font(.headline)

            step(1, String(localized: "Tuş")) {
                HStack(spacing: 10) {
                    HyperKeyCap(key: listening ? nil : flow.key?.name, listening: listening)
                    Button(listening ? String(localized: "Vazgeç") : (flow.key == nil ? String(localized: "Tuşa bas") : String(localized: "Değiştir"))) {
                        listening ? stopListening() : startListening()
                    }
                    if listening {
                        Text(String(localized: "Bir harfe bas (Caps Lock basılı ya da değil)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            step(2, String(localized: "Ne yapsın")) {
                HStack(spacing: 10) {
                    if let task = flow.task {
                        TaskChip(task: task)
                        Button(String(localized: "Uygulama aç")) { adding?.task = nil }
                            .buttonStyle(.softLink)
                    } else {
                        appMenu
                        Text(String(localized: "ya da")).foregroundStyle(.secondary)
                    }
                    TaskPicker { task in
                        adding?.task = task
                        adding?.app = nil
                    }
                }
            }

            if let key = flow.key, let dup = engine.settings.hyper.duplicate(of: key.code, editing: flow.editing) {
                Label(String(localized: "⇪ + \(key.name) zaten kullanılıyor (\(dup.display)). Kaydedersen onun yerine geçer."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let key = flow.key, let snap = engine.settings.hyper.snap(for: key.code) {
                Label(String(localized: "⇪ + \(key.name) pencereyi yaslıyor (\(snap.layout.title)). O satır açıkken uygulama açılmaz."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(String(localized: "Vazgeç")) { stopListening(); adding = nil }
                Spacer()
                Button("Kaydet") { save() }
                    .buttonStyle(.softPrimary)
                    .disabled(flow.key == nil || (flow.app == nil && flow.task == nil))
                    .pageShortcut(.defaultAction)
            }
        }
        .padding(UIStyle.pad(18))
        .surface(.raised)
        .onPageVisibility(show: { if flow.key == nil { startListening() } }, hide: { stopListening() })
    }

    private func step(_ n: Int, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 10) {
            StepNumber(n: n)
            Text(title)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }

    private var appMenu: some View {
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
            HStack(spacing: 6) {
                if let app = flow.app {
                    BundleIcon(bundleID: app.bundleID).frame(width: 18, height: 18)
                    Text(app.name)
                } else {
                    Text(String(localized: "Uygulama seç"))
                }
            }
        }
        .fixedSize()
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func pick(_ bundleID: String, _ name: String) {
        adding?.app = (bundleID, name)
    }

    private func pickFromDisk() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = String(localized: "Seç")
        panel.message = String(localized: "Hyper ile açılacak uygulamayı seç")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        pick(id, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }

    private func save() {
        guard let key = flow.key else { return }
        var binding: HyperBinding
        if let task = flow.task {
            binding = HyperBinding(keyCode: key.code, key: key.name, task: task)
        } else if let app = flow.app {
            binding = HyperBinding(keyCode: key.code, key: key.name, bundleID: app.bundleID, appName: app.name)
        } else {
            return
        }
        if let id = flow.editing { binding.id = id }
        engine.settings.hyper.set(binding)
        stopListening()
        adding = nil
    }

    private func startListening() {
        listening = true
        stopRecording = listenForKey(engine) { got($0) }
    }

    private func got(_ key: (UInt16, String)?) {
        stopListening()
        guard let key else { return }
        adding?.key = key
    }

    private func stopListening() {
        stopRecording?()
        stopRecording = nil
        listening = false
    }
}

/// Bir sonraki tuşu dinler (Esc → nil); dönen işlev dinlemeyi durdurur.
/// Hyper açıkken tuşlar onun yakalayıcısından gelir (Caps Lock basılıyken de);
/// kapalıyken pencerenin kendi tuş dinlemesi yeter.
func listenForKey(_ engine: Engine, _ got: @escaping ((UInt16, String)?) -> Void) -> () -> Void {
    if let hyper = engine.hyper, hyper.isActive {
        hyper.startRecording(got)
        return { hyper.stopRecording() }
    }
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        let name = Shortcut.specialKeyNames[event.keyCode]
            ?? (event.characters(byApplyingModifiers: []) ?? "?").uppercased(with: Locale(identifier: "tr_TR"))
        got(event.keyCode == 53 ? nil : (event.keyCode, name))
        return nil
    }
    return { if let monitor { NSEvent.removeMonitor(monitor) } }
}

// MARK: - Pencere yaslama

/// Beş yerleşim satırı: çizim, ad, tuş (tıklayınca yeni tuş kaydedilir), aç/kapa
private struct SnapSection: View {
    @Environment(Engine.self) private var engine
    @State private var listening: UUID?
    @State private var stopRecording: (() -> Void)?

    var body: some View {
        @Bindable var engine = engine
        VStack(alignment: .leading, spacing: 8) {
            CardStack {
                ForEach($engine.settings.hyper.snaps) { $snap in
                    SnapRow(snap: $snap, listening: listening == snap.id, warning: warning(for: snap)) {
                        listening == snap.id ? stopListening() : startListening(snap.id)
                    }
                }
            }
            Text(listening == nil
                 ? String(localized: "Öndeki pencere bulunduğu ekranda yerleşir; menü çubuğu ve Dock açıkta kalır. Tuşu değiştirmek için tuşa tıkla.")
                 : String(localized: "Yeni tuşa bas (Caps Lock basılı ya da değil). Esc vazgeçer."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPageVisibility(hide: { stopListening() })
    }

    private func warning(for snap: SnapBinding) -> String? {
        let hyper = engine.settings.hyper
        if let other = hyper.snapUsing(snap.keyCode, editing: snap.id) {
            return String(localized: "⇪ + \(snap.key) “\(other.layout.title)” için de kayıtlı; listede üstteki açık satır çalışır.")
        }
        if snap.enabled, let app = hyper.binding(for: snap.keyCode) {
            return String(localized: "⇪ + \(snap.key) \(app.appName)'yi de açıyor; bu satır açıkken uygulama açılmaz.")
        }
        return nil
    }

    private func startListening(_ id: UUID) {
        stopListening()
        listening = id
        stopRecording = listenForKey(engine) { key in
            stopListening()
            guard let key, let i = engine.settings.hyper.snaps.firstIndex(where: { $0.id == id }) else { return }
            engine.settings.hyper.snaps[i].keyCode = key.0
            engine.settings.hyper.snaps[i].key = key.1
        }
    }

    private func stopListening() {
        stopRecording?()
        stopRecording = nil
        listening = nil
    }
}

private struct SnapRow: View {
    @Binding var snap: SnapBinding
    let listening: Bool
    let warning: String?
    let record: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                SnapGlyph(layout: snap.layout)
                    .frame(width: 34, height: 22)
                Text(snap.layout.title)
                    .fontWeight(.medium)
                Spacer()
                Button(action: record) {
                    HyperKeyCap(key: listening ? nil : snap.key, listening: listening)
                }
                .buttonStyle(.plain)
                .help(listening ? String(localized: "Yeni tuşa bas; Esc vazgeçer") : String(localized: "Tıkla, yeni tuşa bas"))
                Toggle("", isOn: $snap.enabled)
                    .toggleStyle(.softSmall)
                    .labelsHidden()
                    .help(snap.enabled ? String(localized: "Açık") : String(localized: "Kapalı; Hyper + \(snap.key) olduğu gibi geçer"))
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(8))
        .opacity(snap.enabled ? 1 : 0.55)
    }
}

/// Tek satır: Caps Lock + parmak kaydırma pencereyi taşır
private struct MoveSection: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        @Bindable var engine = engine
        HStack(spacing: 12) {
            Image(systemName: "macwindow.and.cursorarrow")
                .font(.system(size: 18))
                .foregroundStyle(AnyShapeStyle(.secondary))
                .frame(width: 34, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Caps Lock basılıyken parmağını kaydır"))
                    .fontWeight(.medium)
                Text(String(localized: "İmlecin altındaki pencere öne gelir ve okla birlikte kayar; tıklamak gerekmez."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $engine.settings.hyper.move)
                .toggleStyle(.softSmall)
                .labelsHidden()
                .help(engine.settings.hyper.move ? String(localized: "Açık") : String(localized: "Kapalı; Caps Lock basılıyken ok yalnız oynar"))
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(8))
        .surface()
        .opacity(engine.settings.hyper.move ? 1 : 0.55)
    }
}

/// Ekran çerçevesi içinde pencerenin gideceği yer
private struct SnapGlyph: View {
    let layout: SnapLayout

    var body: some View {
        Canvas { ctx, size in
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
            ctx.fill(RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: screen), with: .color(.primary.opacity(0.1)))
            let inner = screen.insetBy(dx: 2.5, dy: 2.5)
            ctx.fill(RoundedRectangle(cornerRadius: 3, style: .continuous).path(in: layout.frame(in: inner)), with: .style(.tint))
        }
    }
}
