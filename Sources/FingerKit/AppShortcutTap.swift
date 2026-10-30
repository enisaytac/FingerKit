import AppKit
import CoreGraphics
import FingerKitCore

/// Uygulamaya özel kısayollar: öndeki uygulamanın listesindeki tuş birleşimi basılınca tuşu yutar
/// ve işini yapar (başka kısayol gönderir ya da menü maddesine basar). Listede olmayan tuşlar
/// olduğu gibi geçer.
///
/// Caps Lock + tuş satırları burada değil, Hyper Key'in yakalayıcısında yakalanır (`HyperKey`).
/// Yakalayıcı yalnız normal tetikli açık satır varken kurulur; liste boşken hiç çalışmaz.
final class AppShortcutTap {
    private let engine: Engine
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Yutulan tuşun bırakılışı da yutulsun
    private var swallowedKeys: Set<UInt16> = []

    init(engine: Engine) {
        self.engine = engine
    }

    var isActive: Bool { tap != nil }

    func update(_ on: Bool) {
        if on, tap == nil { start() } else if !on, tap != nil { stop() }
    }

    private func start() {
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: appShortcutCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.write("HATA: uygulama kısayolları için tuş yakalayıcı kurulamadı (izin yok?)")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("Uygulama kısayolları açık")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if tap != nil { Log.write("Uygulama kısayolları kapalı") }
        tap = nil
        source = nil
        swallowedKeys = []
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        // FingerKit'in kendi gönderdiği tuşlar (bir kısayolun işi) yeniden yakalanmaz
        if event.getIntegerValueField(.eventSourceUserData) == ClickInterceptor.replayMarker { return event }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard type == .keyDown else {
            return swallowedKeys.remove(keyCode) != nil ? nil : event
        }
        let mods = Modifiers(event.flags)
        // Caps Lock + tuş Hyper Key'de karşılanır
        guard mods != .hyper, let app = NSWorkspace.shared.frontmostApplication,
              let action = engine.settings.appShortcuts.action(keyCode: keyCode, modifiers: mods, app: app.bundleIdentifier)
        else { return event }
        swallowedKeys.insert(keyCode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { Self.perform(action, in: app) }
        }
        return nil
    }

    /// Satırın işini yapar (Hyper Key de kullanır)
    static func perform(_ action: AppAction, in app: NSRunningApplication) {
        switch action {
        case .shortcut(let shortcut):
            Log.write("Kısayol: \(app.localizedName ?? "?") → \(shortcut.display)")
            KeySender.send(shortcut, marked: true)
        case .menu(let path):
            MenuPresser.press(path, in: app)
        case .task(let task):
            TaskRunner.run(task, from: app.localizedName ?? "?")
        }
    }
}

extension Modifiers {
    init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskCommand) { insert(.command) }
    }
}

private let appShortcutCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<AppShortcutTap>.fromOpaque(userInfo).takeUnretainedValue()
    guard let out = tap.handle(type, event) else { return nil }
    return Unmanaged.passUnretained(out)
}
