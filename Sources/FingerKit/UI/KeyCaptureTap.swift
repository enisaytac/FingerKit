import AppKit
import CoreGraphics

/// Kısayol kaydı sırasında tuş basışlarını sistemden önce yakalar. macOS'un kendi kısayolları
/// (⌘⇧4 ekran görüntüsü gibi) uygulamaya hiç ulaşmaz; bu yakalayıcı onları yutup kutuya verir.
/// Erişilebilirlik izni gerekir; kurulamazsa kutu yine normal dinlemeyle çalışır.
final class KeyCaptureTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate let handler: (NSEvent) -> Void

    init?(handler: @escaping (NSEvent) -> Void) {
        self.handler = handler
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: keyCaptureCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private let keyCaptureCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let capture = Unmanaged<KeyCaptureTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        capture.reenable()
        return Unmanaged.passUnretained(event)
    }
    // Yalnız FingerKit öndeyken; başka uygulamadaki yazma etkilenmesin
    guard type == .keyDown, NSApp.isActive, let nsEvent = NSEvent(cgEvent: event) else {
        return Unmanaged.passUnretained(event)
    }
    capture.handler(nsEvent)
    return nil
}
