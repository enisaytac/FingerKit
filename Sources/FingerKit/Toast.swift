import AppKit
import SwiftUI

/// Ekran bildirimi: hareket ya da tuş çalışınca ekranın ortasında kısa süre (~1 sn) koyu yuvarlak kutuda ne yapıldığı
/// yazar ("Pencereyi küçült · ⌘M"). Tıklamaları geçirir, odak çalmaz. Ayarlardan kapatılabilir (varsayılan açık).
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hide: DispatchWorkItem?
    private static let model = ToastModel()

    nonisolated static func show(_ text: String, symbol: String) {
        DispatchQueue.main.async { present(text, symbol: symbol) }
    }

    private static func present(_ text: String, symbol: String) {
        let engine = Engine.shared
        guard engine.settings.enabled, engine.settings.notify else { return }
        model.text = text
        model.symbol = symbol
        let panel = self.panel ?? make()
        self.panel = panel
        let size = NSSize(width: 420, height: 120)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.22, width: size.width, height: size.height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        hide?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }, completionHandler: { panel.orderOut(nil) })
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
        return panel
    }
}

@Observable
final class ToastModel {
    var text = ""
    var symbol = ""
}

private struct ToastView: View {
    let model: ToastModel

    var body: some View {
        let shape = RoundedRectangle.panel
        HStack(spacing: 12) {
            Image(systemName: model.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, UIStyle.pad(22))
        .padding(.vertical, UIStyle.pad(14))
        .background {
            shape.fill(Color(white: 0.11).opacity(0.94))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}
