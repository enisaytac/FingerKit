import AppKit
import SwiftUI
import FingerKitCore

/// Kısayolu gösteren kutucuk. Tıklayınca (ya da `autoStart` ile) dinlemeye başlar,
/// basılan ilk tuş birleşimini kaydeder. ⌘ gibi bir tuş basılıyken tıklamak (ya da orta tık)
/// fare tıklaması olarak kaydedilir. Esc vazgeçer.
struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    var autoStart = false
    @State private var listening = false
    @State private var heldModifiers: Modifiers = []
    @State private var monitor: Any?
    @State private var keyTap: KeyCaptureTap?

    var body: some View {
        Button {
            listening ? stop() : start()
        } label: {
            Text(label)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(listening ? AnyShapeStyle(.tint) : AnyShapeStyle(shortcut == nil ? .secondary : .primary))
                .frame(minWidth: 84, minHeight: UIStyle.control - 4)
                .padding(.horizontal, 12)
                .background(RoundedRectangle.small.fill(listening ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color.fieldFill)))
        }
        .buttonStyle(.plain)
        .help(listening ? String(localized: "Tuş birleşimini bas ya da ⌘ basılıyken tıkla · Esc: vazgeç") : (shortcut.map { String(localized: "\($0.spoken) · değiştirmek için tıkla") } ?? String(localized: "Kısayol kaydetmek için tıkla")))
        .onAppear { if autoStart { start() } }
        .onPageVisibility(hide: { stop() })
    }

    private var label: String {
        if listening { return heldModifiers.isEmpty ? String(localized: "Tuşlara bas…") : heldModifiers.symbols + "…" }
        guard let shortcut, !shortcut.isNone else { return String(localized: "Kısayol kaydet") }
        return shortcut.display
    }

    private func start() {
        guard monitor == nil else { return }
        listening = true
        heldModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .otherMouseDown]) { event in
            let mods = Modifiers(event.modifierFlags)
            switch event.type {
            case .flagsChanged:
                heldModifiers = mods
                return event
            case .leftMouseDown where !mods.isEmpty:
                shortcut = Shortcut(mouse: .left, modifiers: mods)
                stop()
                return nil
            case .otherMouseDown where event.buttonNumber == 2:
                shortcut = Shortcut(mouse: .middle, modifiers: mods)
                stop()
                return nil
            case .leftMouseDown, .otherMouseDown:
                return event
            default:
                break
            }
            captureKey(event)
            return nil
        }
        // Sistem kısayolları (⌘⇧4 gibi) uygulamaya ulaşmaz; önceden yakala
        keyTap = KeyCaptureTap { event in captureKey(event) }
    }

    private func captureKey(_ event: NSEvent) {
        let mods = Modifiers(event.modifierFlags)
        if !(event.keyCode == 53 && mods.isEmpty) {
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods, key: Self.keyName(event))
        }
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        keyTap?.stop()
        keyTap = nil
        listening = false
        heldModifiers = []
    }

    private static func keyName(_ event: NSEvent) -> String {
        if let special = Shortcut.specialKeyNames[event.keyCode] { return special }
        let raw = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
        return raw.uppercased(with: Locale(identifier: "tr_TR"))
    }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
