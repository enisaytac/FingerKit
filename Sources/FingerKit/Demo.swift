import AppKit
import SwiftUI
import FingerKitCore

/// Geliştirme: tanıtım çekimi için gösteri modu. `FINGERKIT_GOSTERI=a|b|c` verilince sahne
/// yazılımla oynatılır, bitince uygulama kapanır.
/// - Hayali dokunuşlar motora gerçek trackpad karesi gibi verilir (tanıyıcı aynen çalışır).
/// - Tıklama, imleç ve tuşlar sistem olayı olarak gönderilir (event tap'ler gerçek gibi görür).
/// - Ekranda küçük bir trackpad çizimi parmakları ve sahne yazısını gösterir.
/// Sahneler: a = TipTap ile sekme değiştirme, b = daire menü, c = ⇪ + V pano.
/// `FINGERKIT_GOSTERI_PAD=x,y`: trackpad çiziminin sol üst köşesi (ekran noktası, üstten).
@MainActor
enum Demo {
    /// Hayali aygıt numarası; gerçek trackpad'lerle karışmaz
    private static let device = -7
    private static let pad = DemoPad()
    private static var panel: NSPanel?

    static func run(_ scene: String) {
        Task { @MainActor in
            if scene == "c" { await fillClipboard() }
            showPad()
            print("GOSTERI_BASLADI")
            fflush(stdout)
            try? await Task.sleep(for: .seconds(1))
            switch scene {
            case "a": await tipTapScene()
            case "b": await radialScene()
            case "c": await clipboardScene()
            default: break
            }
            try? await Task.sleep(for: .seconds(1.2))
            print("GOSTERI_BITTI")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    // MARK: - Sahneler

    private static func tipTapScene() async {
        pad.caption = "Rest one finger, tap the other to the right"
        for _ in 0..<2 { await tipTap(right: true); await wait(0.9) }
        pad.caption = "Tap to the left: previous tab"
        for _ in 0..<2 { await tipTap(right: false); await wait(0.9) }
    }

    private static func radialScene() async {
        let start = mouse
        pad.caption = "Click the bottom-left corner"
        await cornerClick()
        await wait(0.9)
        guard RadialMenu.shared.isShown else { return }
        pad.caption = "Apps below"
        for i in 0..<RadialMenu.shared.demoCount(top: false) {
            if let p = RadialMenu.shared.demoPoint(top: false, index: i) { await moveMouse(to: p, seconds: 0.35) }
            await wait(0.15)
        }
        pad.caption = "Volume: press and drag"
        if let i = RadialMenu.shared.demoIndex(of: .volume), let p = RadialMenu.shared.demoPoint(top: true, index: i) {
            await moveMouse(to: p, seconds: 0.5)
            await wait(0.3)
            await drag(at: p, dy: [-70, 70])
        }
        pad.caption = "Shortcuts of the app in front"
        let first = RadialMenu.shared.demoIndex(of: nil) ?? 0
        if let p = RadialMenu.shared.demoPoint(top: true, index: first) {
            await moveMouse(to: p, seconds: 0.5)
            await wait(0.6)
            await click(at: p)
        }
        await wait(0.6)
        await moveMouse(to: start, seconds: 0.4)
        pad.touches = []
    }

    private static func clipboardScene() async {
        pad.caption = "⇪ + V: everything you copied"
        pad.keys = "⇪ + V"
        key(HyperKey.f18, down: true)
        await wait(0.12)
        key(9, down: true)
        key(9, down: false)
        await wait(0.1)
        key(HyperKey.f18, down: false)
        await wait(1.4)
        pad.keys = "↓"
        for _ in 0..<2 {
            key(125, down: true); key(125, down: false)
            await wait(0.8)
        }
        pad.keys = "↩"
        pad.caption = "Enter pastes it"
        key(36, down: true); key(36, down: false)
        await wait(1)
        pad.keys = nil
    }

    /// Pano geçmişi için örnek kopyalar (ekranda kişisel bilgi çıkmasın diye)
    private static func fillClipboard() async {
        let items = ["#34C759", "brew install --cask fingerkit",
                     "Meeting moved to Thursday 10:00", "https://github.com/enisaytac/FingerKit",
                     "Trackpad gestures, Hyper Key and a radial menu for your Mac."]
        for text in items {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            await wait(0.8)
        }
    }

    // MARK: - Parmaklar

    /// Bir parmak dururken diğeri yanına kısa dokunur
    private static func tipTap(right: Bool) async {
        let rest = CGPoint(x: 0.45, y: 0.42)
        let other = CGPoint(x: right ? 0.64 : 0.27, y: 0.47)
        await hold([1: rest], seconds: 0.35)
        await hold([1: rest, 2: other], seconds: 0.12)
        await hold([1: rest], seconds: 0.25)
        lift()
    }

    /// Sol alt köşeye tek parmakla tıklama (parmak değer, fare tıklaması gelir, parmak kalkar)
    private static func cornerClick() async {
        let p = CGPoint(x: 0.08, y: 0.09)
        await hold([1: p], seconds: 0.3)
        pad.pressed = true
        mouseButton(down: true, at: mouse)
        await hold([1: p], seconds: 0.1)
        mouseButton(down: false, at: mouse)
        pad.pressed = false
        await hold([1: p], seconds: 0.15)
        lift()
    }

    private static func hold(_ fingers: [Int32: CGPoint], seconds: Double) async {
        let end = CACurrentMediaTime() + seconds
        repeat {
            send(fingers)
            await wait(0.01)
        } while CACurrentMediaTime() < end
    }

    private static func lift() { send([:]) }

    private static func send(_ fingers: [Int32: CGPoint]) {
        let touches = fingers.sorted { $0.key < $1.key }.map { Touch(id: $0.key, x: $0.value.x, y: $0.value.y) }
        pad.touches = touches
        MultitouchSource.shared.onFrame?(device, TouchFrame(time: CACurrentMediaTime(), touches: touches))
    }

    // MARK: - Fare ve klavye

    /// İmlecin yeri (AppKit: sol alt köşe, y yukarı)
    private static var mouse: NSPoint { NSEvent.mouseLocation }

    /// AppKit noktası → CGEvent noktası (sol üst köşe, y aşağı)
    private static func cg(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }

    /// İmleç kayarken çizimde bir parmak da kayar (yalnız gösterilir, motora verilmez)
    private static func moveMouse(to target: NSPoint, seconds: Double) async {
        let from = mouse
        let finger = pad.touches.first.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: 0.5, y: 0.45)
        let steps = max(1, Int(seconds * 60))
        for s in 1...steps {
            // Yumuşak hızlanıp yavaşlama
            let t = Double(s) / Double(steps)
            let e = t * t * (3 - 2 * t)
            let p = NSPoint(x: from.x + (target.x - from.x) * e, y: from.y + (target.y - from.y) * e)
            showFinger(CGPoint(x: finger.x + (p.x - from.x) / 700, y: finger.y + (p.y - from.y) / 450))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cg(p), mouseButton: .left)?
                .post(tap: .cghidEventTap)
            await wait(1.0 / 60)
        }
    }

    private static func showFinger(_ p: CGPoint) {
        pad.touches = [Touch(id: 1, x: min(max(p.x, 0.08), 0.92), y: min(max(p.y, 0.1), 0.9))]
    }

    private static func mouseButton(down: Bool, at p: NSPoint) {
        CGEvent(mouseEventSource: nil, mouseType: down ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: cg(p), mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func click(at p: NSPoint) async {
        pad.pressed = true
        mouseButton(down: true, at: p)
        await wait(0.08)
        mouseButton(down: false, at: p)
        pad.pressed = false
    }

    /// Basılı sürükleme: `dy` parçaları sırayla (nokta, y aşağı doğru)
    private static func drag(at p: NSPoint, dy parts: [CGFloat]) async {
        pad.pressed = true
        mouseButton(down: true, at: p)
        for part in parts {
            let steps = 30
            for _ in 0..<steps {
                let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: cg(p), mouseButton: .left)
                e?.setDoubleValueField(.mouseEventDeltaY, value: Double(part) / Double(steps))
                e?.setDoubleValueField(.mouseEventDeltaX, value: 0)
                e?.post(tap: .cghidEventTap)
                if let f = pad.touches.first { showFinger(CGPoint(x: f.x, y: f.y - Double(part) / Double(steps) / 450)) }
                await wait(1.0 / 60)
            }
            await wait(0.3)
        }
        mouseButton(down: false, at: p)
        pad.pressed = false
    }

    private static func key(_ code: UInt16, down: Bool) {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    // MARK: - Trackpad çizimi

    private static func showPad() {
        let size = NSSize(width: 300, height: 236)
        let screen = NSScreen.screens.first?.frame ?? .zero
        var origin = NSPoint(x: screen.maxX - size.width - 24, y: 24)
        if let spec = ProcessInfo.processInfo.environment["FINGERKIT_GOSTERI_PAD"]?.split(separator: ","),
           spec.count == 2, let x = Double(spec[0]), let y = Double(spec[1]) {
            origin = NSPoint(x: x, y: screen.height - y - size.height)
        }
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSHostingView(rootView: DemoPadView(pad: pad))
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

@MainActor @Observable
final class DemoPad {
    var touches: [Touch] = []
    var caption = ""
    var keys: String?
    var pressed = false
}

/// Ekrandaki küçük trackpad: koyu yüzey, yeşil parmak noktaları, altta sahne yazısı
private struct DemoPadView: View {
    let pad: DemoPad
    private let green = Color(red: 0.2, green: 0.78, blue: 0.35)

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    if let keys = pad.keys {
                        Text(keys)
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
                            .transition(.scale.combined(with: .opacity))
                    }
                    ForEach(pad.touches, id: \.id) { t in
                        Circle()
                            .fill(green.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.white.opacity(pad.pressed ? 0.9 : 0), lineWidth: 3).scaleEffect(1.5))
                            .shadow(color: green.opacity(0.6), radius: 8)
                            .position(x: t.x * geo.size.width, y: (1 - t.y) * geo.size.height)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: pad.touches.map(\.id))
                .animation(.snappy(duration: 0.2), value: pad.keys)
            }
            .frame(width: 280, height: 175)
            Text(pad.caption)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.75)))
                .lineLimit(1)
                .opacity(pad.caption.isEmpty ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: pad.caption)
        }
        .frame(width: 300, height: 236)
    }
}
