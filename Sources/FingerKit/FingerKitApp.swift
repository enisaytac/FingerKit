import AppKit
import SwiftUI

@main
struct FingerKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let engine: Engine

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--ornekleri-ciz"), i + 1 < args.count {
            DemoSnapshots.render(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--kareleri-ciz"), i + 2 < args.count {
            DemoSnapshots.frames(to: URL(fileURLWithPath: args[i + 1]), matching: args[i + 2])
            exit(0)
        }
        if let i = args.firstIndex(of: "--videolari-ciz"), i + 1 < args.count {
            PromoStories.render(to: URL(fileURLWithPath: args[i + 1]), only: i + 2 < args.count && !args[i + 2].hasPrefix("-") ? args[i + 2] : nil)
            exit(0)
        }
        if let i = args.firstIndex(of: "--gorselleri-ciz"), i + 1 < args.count {
            PromoImages.render(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        engine = Engine.shared
    }

    var body: some Scene {
        Window("FingerKit", id: "main") {
            MainView()
                .environment(engine)
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Menü çubuğu simgesi ekrana gelince SwiftUI'nin pencere açma yolu buraya bağlanır
    var openMain: (() -> Void)? {
        didSet { if wantsWindow, openMain != nil { showMain() } }
    }
    private var wantsWindow = false

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Engine.shared.start()
        setUpStatusItem()
        // Simgeye tıklayarak açıldıysa pencere gelir; bilgisayar açılışında sessiz başlar
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        Log.write("açılış: \(atLogin ? "bilgisayar açılışında" : "elle")")
        if let scene = ProcessInfo.processInfo.environment["FINGERKIT_GOSTERI"] {
            Demo.run(scene)
            return
        }
        if !atLogin || Engine.shared.showWindowAtLaunch { showMain() }
        // Geliştirme: boş klasörle (FINGERKIT_KLASOR) açılınca panoyu ya da daireyi hemen göster, ekran görüntüsü alınsın
        if ProcessInfo.processInfo.environment["FINGERKIT_KLASOR"] != nil {
            let args = CommandLine.arguments
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if args.contains("--pano-ac") { ClipboardPicker.shared.show(.shared) }
                // Pano açılışının takılması: 5 kez açılıp kapanır, her açılışta en uzun donma (ms)
                if args.contains("--pano-olc") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        var gaps: [String] = []
                        for _ in 0..<5 {
                            let ms = await TabTimer.worstGap(during: 700) { ClipboardPicker.shared.show(.shared) }
                            gaps.append(String(format: "%.0f", ms))
                            ClipboardPicker.shared.close()
                            try? await Task.sleep(for: .milliseconds(300))
                        }
                        print("PANO: \(gaps.joined(separator: " ")) ms")
                        exit(0)
                    }
                }
                // Daire menü açılışının takılması: aynı biçimde
                if args.contains("--daire-olc") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        var gaps: [String] = []
                        for _ in 0..<5 {
                            let ms = await TabTimer.worstGap(during: 700) { RadialMenu.shared.show(.shared) }
                            gaps.append(String(format: "%.0f", ms))
                            RadialMenu.shared.close()
                            try? await Task.sleep(for: .milliseconds(300))
                        }
                        print("DAIRE: \(gaps.joined(separator: " ")) ms")
                        exit(0)
                    }
                }
                if args.contains("--daire-ac") { RadialMenu.shared.show(.shared) }
                if args.contains("--menu-ac") { self.showStatusPanel() }
                if args.contains("--bildirim-ac") {
                    Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
                        Toast.show(String(localized: "Pencereyi küçült") + " · ⌘M", symbol: "arrow.down.right.and.arrow.up.left")
                    }
                }
            }
        }
    }

    /// Uygulama zaten açıkken simgesine yeniden tıklanınca
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return false
    }

    func showMain() {
        guard let openMain else { wantsWindow = true; return }
        wantsWindow = false
        openMain()
        NSApp.activate()
    }

    /// Pencere kapanınca uygulama menü çubuğunda yaşamaya devam eder
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shared.stop()
    }
}

/// Menü çubuğu simgesine gömülü görünmez görünüm: SwiftUI'nin pencere açma yolunu uygulamaya verir
struct OpenWindowBridge: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear { delegate.openMain = { openWindow(id: "main") } }
    }
}

// MARK: - Menü çubuğu simgesi (sol tık: pencere, sağ tık: küçük pencere)

extension AppDelegate {
    private var engine: Engine { .shared }

    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let bridge = NSHostingView(rootView: OpenWindowBridge(delegate: self))
        bridge.frame = .zero
        button.addSubview(bridge)
        updateIcon()
    }

    /// Açık/kapalı değişince simge kendiliğinden güncellenir
    private func updateIcon() {
        let enabled = withObservationTracking {
            engine.settings.enabled
        } onChange: {
            DispatchQueue.main.async { [weak self] in self?.updateIcon() }
        }
        statusItem.button?.image = Self.menuBarIcon(enabled: enabled)
    }

    /// Logonun menü çubuğu hâli: trackpad çerçevesi ve eşkenar üçgen üç parmak (şablon resim, menü çubuğunun rengini alır).
    /// Kapalıyken parmaklar içi boş halka olur.
    static func menuBarIcon(enabled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            let pad = NSRect(x: 1.5, y: 2.5, width: 19, height: 11.9)
            let frame = NSBezierPath(roundedRect: pad, xRadius: 2.2, yRadius: 2.2)
            frame.lineWidth = 1.3
            NSColor.black.setStroke()
            frame.stroke()
            NSColor.black.setFill()
            // Üçgenin kenarı 3,6; ağırlık merkezi trackpad'in ortasında, tepe yukarıda
            let side = 3.6, r = side / 3.0.squareRoot(), cx = pad.midX, cy = pad.midY
            for (x, y) in [(cx, cy - r), (cx - side / 2, cy + r / 2), (cx + side / 2, cy + r / 2)] {
                let dot = NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: y - 1.25, width: 2.5, height: 2.5))
                if enabled {
                    dot.fill()
                } else {
                    dot.lineWidth = 0.8
                    dot.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "FingerKit"
        return image
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusPanel()
        } else {
            StatusPanel.shared.close()
            showMain()
        }
    }

    /// Mac'in menüsü yerine kendi çizdiğimiz yumuşak pencere; maddeler aynı
    func showStatusPanel() {
        guard let button = statusItem.button else { return }
        let engine = engine
        StatusPanel.shared.toggle(below: button, actions: StatusPanelActions(
            openMain: { [weak self] in self?.showMain() },
            revealSettings: { NSWorkspace.shared.activateFileViewerSelecting([engine.settingsFileURL]) },
            exportSettings: { SettingsBackup.export(engine) },
            importSettings: { SettingsBackup.importFile(engine) },
            openLog: { NSWorkspace.shared.open(Log.url) },
            checkUpdates: { UpdateCheck.open() },
            quit: { NSApp.terminate(nil) }
        ))
    }
}
