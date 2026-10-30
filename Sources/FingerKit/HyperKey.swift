import AppKit
import CoreGraphics
import IOKit
import IOKit.hidsystem
import FingerKitCore

/// Caps Lock → Hyper.
///
/// 1. macOS'un kendi tuş eşleme aracı (`hidutil`) Caps Lock'u kullanılmayan F18'e çevirir.
///    Böylece sistem büyük harf kilidini kendisi açıp kapatmaz; karar FingerKit'te olur.
/// 2. Tuş yakalayıcı (event tap) F18 basılıyken gelen tuşları görür: listedeki tuşsa pencereyi
///    yaslar, pano listesini gösterir, uygulamaya özel kısayolu çalıştırır ya da uygulamayı açar ve tuşu yutar, değilse tuşa ⌘⌥⌃⇧ ekleyip geçirir.
/// 3. F18 tek başına basılıp bırakılırsa büyük harf kilidi (ışığıyla birlikte) açılıp kapanır.
/// 4. F18 basılıyken imleç kayarsa altındaki pencere taşınır (`WindowMover`).
///
/// Eşleme FingerKit kapanınca ya da Hyper kapatılınca geri alınır. FingerKit çökerse eşleme
/// bilgisayar yeniden başlayana kadar kalır; FingerKit yeniden açılınca kendini düzeltir.
final class HyperKey {
    static let f18: UInt16 = 79
    /// HID kullanım numaraları (hidutil bunları ister): klavye sayfası 7, Caps Lock 0x39, F18 0x6D
    private static let capsUsage: UInt64 = 0x7_0000_0039
    private static let f18Usage: UInt64 = 0x7_0000_006D

    private let engine: Engine
    private let mover = WindowMover()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isActive = false

    private var hyperDown = false
    /// Hyper basılıyken başka tuşa basıldı mı (bırakınca büyük harf kilidi değişmesin)
    private var usedAsHyper = false
    /// Uygulama açan tuşun bırakılışı da yutulsun
    private var swallowedKeys: Set<UInt16> = []

    /// Arayüzde "tuşa bas" beklenirken: bir sonraki tuş buraya gider (Esc → nil)
    var recording: ((UInt16, String)?) -> Void = { _ in }
    private var isRecording = false

    init(engine: Engine) {
        self.engine = engine
    }

    // MARK: - Aç / kapat

    /// Ayara göre açar ya da kapatır; zaten o durumdaysa dokunmaz
    func update(_ on: Bool) {
        if on, !isActive { start() } else if !on, isActive || hasMapping { stop() }
    }

    private func start() {
        guard installTap() else { return }
        setMapping(true)
        isActive = true
        Log.write("Hyper Key açık (Caps Lock → F18)")
    }

    func stop() {
        setMapping(false)
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        hyperDown = false
        mover.end()
        if isActive { Log.write("Hyper Key kapalı (Caps Lock eski hâlinde)") }
        isActive = false
    }

    private func installTap() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .mouseMoved]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: hyperCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.write("HATA: Hyper Key tuş yakalayıcısı kurulamadı (izin yok?)")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Arayüzden tuş kaydı

    func startRecording(_ handler: @escaping ((UInt16, String)?) -> Void) {
        recording = handler
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
        recording = { _ in }
    }

    // MARK: - Tuşlar

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        if type == .mouseMoved {
            if hyperDown, engine.settings.hyper.move, !isRecording, mover.moved(to: event.location) {
                usedAsHyper = true
            }
            return event
        }
        // FingerKit'in kendi gönderdiği tuşlar (pano yapıştırma) olduğu gibi geçer
        if event.getIntegerValueField(.eventSourceUserData) == ClickInterceptor.replayMarker { return event }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown = type == .keyDown

        if keyCode == Self.f18 {
            if isDown {
                // Basılı tutunca gelen tekrarlar da yutulur
                if !hyperDown {
                    hyperDown = true
                    usedAsHyper = false
                    mover.begin(at: event.location)
                }
            } else {
                if hyperDown, !usedAsHyper, !isRecording { toggleCapsLock() }
                hyperDown = false
                mover.end()
            }
            return nil
        }

        if isRecording, isDown {
            let name = keyName(event, keyCode)
            let handler = recording
            stopRecording()
            DispatchQueue.main.async { handler(keyCode == 53 ? nil : (keyCode, name)) }
            if hyperDown { usedAsHyper = true }
            swallowedKeys.insert(keyCode)
            return nil
        }

        if !isDown, swallowedKeys.remove(keyCode) != nil { return nil }
        guard hyperDown else { return event }

        if isDown {
            usedAsHyper = true
            // Öndeki uygulamaya özel Caps Lock + tuş satırı genel satırlardan önce gelir
            if let app = NSWorkspace.shared.frontmostApplication,
               let action = engine.settings.appShortcuts.action(keyCode: keyCode, modifiers: .hyper, app: app.bundleIdentifier) {
                swallowedKeys.insert(keyCode)
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { AppShortcutTap.perform(action, in: app) }
                }
                return nil
            }
            let clip = engine.settings.clipboard
            if clip.enabled, keyCode == clip.keyCode {
                swallowedKeys.insert(keyCode)
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { ClipboardPicker.shared.show(self.engine) }
                }
                return nil
            }
            if let snap = engine.settings.hyper.snap(for: keyCode) {
                swallowedKeys.insert(keyCode)
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async {
                        Toast.show(snap.layout.title, symbol: ReadyTask.snap(snap.layout).symbol)
                        WindowSnapper.snap(snap.layout)
                    }
                }
                return nil
            }
            if let binding = engine.settings.hyper.binding(for: keyCode) {
                swallowedKeys.insert(keyCode)
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { self.open(binding) }
                }
                return nil
            }
        }
        // Listede yok: ⌘⌥⌃⇧ + tuş olarak geçer
        event.flags.formUnion([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return event
    }

    private func keyName(_ event: CGEvent, _ keyCode: UInt16) -> String {
        if let special = Shortcut.specialKeyNames[keyCode] { return special }
        let raw = NSEvent(cgEvent: event)?.characters(byApplyingModifiers: []) ?? "?"
        return raw.uppercased(with: Locale(identifier: "tr_TR"))
    }

    private func open(_ binding: HyperBinding) {
        if let task = binding.task {
            TaskRunner.run(task, from: "Hyper+\(binding.key)")
        } else {
            Toast.show(binding.appName, symbol: "app.badge")
            AppLauncher.open(binding.bundleID, name: binding.appName, from: "Hyper+\(binding.key)")
        }
    }

    // MARK: - Büyük harf kilidi

    private func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            Log.write("HATA: büyük harf kilidi değiştirilemedi")
            return
        }
        defer { IOServiceClose(connect) }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !on)
    }

    // MARK: - hidutil eşlemesi

    /// Şu anki eşlemelerde Caps Lock → F18 var mı
    private var hasMapping: Bool {
        Self.currentMappings().contains { $0.src == Self.capsUsage && $0.dst == Self.f18Usage }
    }

    /// Kullanıcının başka eşlemeleri varsa korunur; yalnız Caps Lock satırı eklenir/çıkarılır.
    private func setMapping(_ on: Bool) {
        // Deneme kopyası (FINGERKIT_KLASOR) eşlemeye dokunmaz: kapanırken asıl FingerKit'in eşlemesini silmesin
        if ProcessInfo.processInfo.environment["FINGERKIT_KLASOR"] != nil { return }
        var pairs = Self.currentMappings().filter { $0.src != Self.capsUsage }
        if on { pairs.append((Self.capsUsage, Self.f18Usage)) }
        let items = pairs.map {
            #"{"HIDKeyboardModifierMappingSrc":\#($0.src),"HIDKeyboardModifierMappingDst":\#($0.dst)}"#
        }
        let json = #"{"UserKeyMapping":[\#(items.joined(separator: ","))]}"#
        if Self.hidutil(["property", "--set", json]) == nil {
            Log.write("HATA: hidutil eşlemesi \(on ? "uygulanamadı" : "geri alınamadı")")
        }
    }

    private static func currentMappings() -> [(src: UInt64, dst: UInt64)] {
        guard let out = hidutil(["property", "--get", "UserKeyMapping"]) else { return [] }
        // Çıktı: { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; }
        func values(_ name: String) -> [UInt64] {
            let regex = try! NSRegularExpression(pattern: name + #"\s*=\s*(\d+)"#)
            return regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).compactMap {
                Range($0.range(at: 1), in: out).flatMap { UInt64(out[$0]) }
            }
        }
        return Array(zip(values("HIDKeyboardModifierMappingSrc"), values("HIDKeyboardModifierMappingDst")))
    }

    @discardableResult
    private static func hidutil(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

private let hyperCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let hyper = Unmanaged<HyperKey>.fromOpaque(userInfo).takeUnretainedValue()
    guard let out = hyper.handle(type, event) else { return nil }
    return Unmanaged.passUnretained(out)
}
