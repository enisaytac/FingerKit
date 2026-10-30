import AppKit
import SwiftUI

/// Menü çubuğu simgesine sağ tıklayınca açılan küçük yumuşak pencere (Mac'in menüsü yerine; Denetim Merkezi gibi).
/// Maddeler ve kısayollar eski menüyle aynı. Dışarı tıklayınca, Esc'te ya da bir madde seçilince kapanır.
final class StatusPanel: NSObject, NSWindowDelegate {
    static let shared = StatusPanel()

    private var panel: StatusPanelWindow?
    private var outsideClick: Any?
    private let model = StatusPanelModel()

    var isShown: Bool { panel?.isVisible == true }

    func toggle(below button: NSStatusBarButton, actions: StatusPanelActions) {
        if isShown { close(); return }
        show(below: button, actions: actions)
    }

    func show(below button: NSStatusBarButton, actions: StatusPanelActions) {
        model.actions = actions
        model.refresh()
        let panel = self.panel ?? make()
        self.panel = panel
        // Boyut içeriğe göre (madde sayısı ve yönün boşlukları)
        let host = panel.contentView as? NSHostingView<StatusPanelView>
        var size = host.map { NSHostingController(rootView: $0.rootView).sizeThatFits(in: NSSize(width: 400, height: 2000)) } ?? .zero
        if size.width < 10 || size.height < 10 { size = NSSize(width: 300 + StatusPanelView.margin * 2, height: 520) }
        // Simgenin altına, sağ kenarı simgeyle hizalı; ekrandan taşmaz
        let anchor = button.window?.frame ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        let y = anchor.minY - size.height + StatusPanelView.margin - 4
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.1; panel.animator().alphaValue = 1 }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.close() }
        }
    }

    func close() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; panel.animator().alphaValue = 0 }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func make() -> StatusPanelWindow {
        let panel = StatusPanelWindow(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: StatusPanelView(model: model, close: { [weak self] in self?.close() }))
        panel.contentView = host
        return panel
    }
}

/// Tuş alabilen kenarsız pencere (Esc, ⌘Q)
private final class StatusPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Pencerenin maddeleri; AppDelegate doldurur
struct StatusPanelActions {
    var openMain: () -> Void
    var revealSettings: () -> Void
    var exportSettings: () -> Void
    var importSettings: () -> Void
    var openLog: () -> Void
    var checkUpdates: () -> Void
    var quit: () -> Void
}

@Observable
final class StatusPanelModel {
    var actions: StatusPanelActions?
    var launchAtLogin = false

    func refresh() { launchAtLogin = Engine.shared.launchAtLogin }
}

struct StatusPanelView: View {
    /// Gölge için pencerenin kenarında bırakılan boşluk
    static let margin: CGFloat = 22

    let model: StatusPanelModel
    let close: () -> Void
    @AppStorage("theme") private var theme = AppTheme.night

    private var engine: Engine { .shared }

    var body: some View {
        let shape = RoundedRectangle.panel
        VStack(alignment: .leading, spacing: UIStyle.pad(4)) {
            header
                .padding(.bottom, UIStyle.pad(6))
            item(String(localized: "Pencereyi aç"), "macwindow") { model.actions?.openMain() }
            toggleRow(String(localized: "Ekran bildirimi"), "text.bubble",
                      Binding(get: { engine.settings.notify }, set: { engine.settings.notify = $0 }))
            toggleRow(String(localized: "Bilgisayar açılınca başlat"), "power",
                      Binding(get: { model.launchAtLogin }, set: { on in
                          engine.setLaunchAtLogin(on)
                          model.refresh()
                      }))
            group {
                item(String(localized: "Ayar dosyasını Finder'da göster"), "folder") { model.actions?.revealSettings() }
                item(String(localized: "Ayarları dosyaya kaydet…"), "square.and.arrow.up") { model.actions?.exportSettings() }
                item(String(localized: "Ayarları dosyadan içe al…"), "square.and.arrow.down") { model.actions?.importSettings() }
                item(String(localized: "Günlüğü aç"), "doc.text") { model.actions?.openLog() }
                item(String(localized: "Güncellemeleri kontrol et…"), "arrow.down.circle") { model.actions?.checkUpdates() }
            }
            item(String(localized: "FingerKit'ten çık"), "power.circle", key: "⌘Q") { model.actions?.quit() }
                .keyboardShortcut("q", modifiers: .command)
                .padding(.top, UIStyle.pad(6))
        }
        .padding(UIStyle.pad(10))
        .frame(width: 300)
        .background {
            shape.fill(Color.page)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 7)
        }
        .padding(Self.margin)
        .background {
            // Esc kapatır
            Button("", action: close).keyboardShortcut(.cancelAction).opacity(0)
        }
        .modifier(ThemeModifier())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppDelegate.menuBarIcon(enabled: engine.settings.enabled))
                .renderingMode(.template)
                .foregroundStyle(engine.settings.enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.fieldFill))
            VStack(alignment: .leading, spacing: 1) {
                Text("FingerKit")
                    .font(.headline)
                Text(engine.settings.enabled ? String(localized: "Açık") : String(localized: "Kapalı"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { engine.settings.enabled }, set: { engine.settings.enabled = $0 }))
                .toggleStyle(.soft)
                .labelsHidden()
                .help(String(localized: "FingerKit'i açar ya da kapatır"))
        }
        .padding(UIStyle.pad(10))
        .surface(.card)
    }

    /// Bir grup madde: kendi yumuşak çukurunda
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 4)
            .padding(.top, UIStyle.pad(4))
    }

    private func item(_ title: String, _ symbol: String, key: String? = nil, _ action: @escaping () -> Void) -> some View {
        PanelRow {
            close()
            // Pencere kapandıktan sonra (kaydet/aç pencereleri öne gelsin)
            DispatchQueue.main.async(execute: action)
        } label: {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            if let key {
                Text(key)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleRow(_ title: String, _ symbol: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Toggle(isOn: isOn) { Text(title) }
                .toggleStyle(SoftToggleStyle(small: true, spread: true))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
    }
}

/// Penceredeki madde: üstüne gelince hap biçimli ton
private struct PanelRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        let height: CGFloat = 32
        Button(action: action) {
            HStack(spacing: 9) { label() }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: min(UIStyle.small + 3, height / 2), style: .continuous)
                        .fill(hovering ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
