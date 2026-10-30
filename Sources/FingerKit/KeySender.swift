import CoreGraphics
import FingerKitCore

/// Kısayolu, klavyeden basılmış gibi sisteme gönderir (Erişilebilirlik izni gerekir).
enum KeySender {
    /// `marked`: FingerKit'in yakalayıcıları (Hyper, uygulama kısayolları) bu tuşa dokunmaz
    static func send(_ shortcut: Shortcut, marked: Bool = false) {
        if let mouse = shortcut.mouse {
            click(mouse, flags: flags(shortcut.modifiers))
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else { return }
        var flags = flags(shortcut.modifiers)
        // Gerçek klavyede ok ve F tuşları bu işaretlerle gelir; bazı uygulamalar onlara bakar
        if shortcut.isArrow { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        if shortcut.isFunctionKey { flags.insert(.maskSecondaryFn) }
        down.flags = flags
        up.flags = flags
        if marked {
            down.setIntegerValueField(.eventSourceUserData, value: ClickInterceptor.replayMarker)
            up.setIntegerValueField(.eventSourceUserData, value: ClickInterceptor.replayMarker)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// ⌘V. İşaretli gönderilir: Caps Lock hâlâ basılıysa Hyper ona ⌘⌥⌃⇧ eklemesin.
    static func paste() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down) else { continue }
            e.flags = .maskCommand
            e.setIntegerValueField(.eventSourceUserData, value: ClickInterceptor.replayMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    private static func flags(_ modifiers: Modifiers) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    /// İmlecin olduğu yere tıklar. Olaylar işaretlidir; tıklama yakalayıcı onlara dokunmaz.
    private static func click(_ mouse: MouseButton, flags: CGEventFlags) {
        let at = CGEvent(source: nil)?.location ?? .zero
        let (downType, upType, button): (CGEventType, CGEventType, CGMouseButton) = switch mouse {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .center)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [downType, upType] {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: button) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: ClickInterceptor.replayMarker)
            e.post(tap: .cghidEventTap)
        }
    }
}
