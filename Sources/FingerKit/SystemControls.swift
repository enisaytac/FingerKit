import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import FingerKitCore

/// Denetim Merkezi düğmelerini okur ve değiştirir. Yollar notlar/denetim-merkezi-yollari.md'de:
/// ses, parlaklık, Bluetooth, Wi-Fi ve koyu görünüm doğrudan; Odak, AirDrop ve ekran yansıtma
/// Denetim Merkezi'ndeki düğmeye Erişilebilirlik ile basarak (Apple bunlara yol açmıyor).
enum SystemControls {
    // MARK: - Okuma

    static func value(_ control: SystemControl) -> ControlValue {
        switch control {
        case .volume: volume().map { .level($0) } ?? .unknown
        case .brightness: brightness().map { .level($0) } ?? .unknown
        case .bluetooth: bluetooth().map { .on($0) } ?? .unknown
        case .wifi: CWWiFiClient.shared().interface().map { .on($0.powerOn()) } ?? .unknown
        case .darkMode: .on(UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark")
        case .focus: focus().map { .on($0) } ?? .unknown
        case .airDrop: .airDrop(AirDropMode(discoverable: UserDefaults(suiteName: "com.apple.sharingd")?.string(forKey: "DiscoverableMode")))
        case .screenMirroring: .unknown
        }
    }

    // MARK: - Değiştirme

    /// Aç/kapa düğmesi: yeni durumu döner (Odak gibi Denetim Merkezi üzerinden gidenler sonra okunur)
    static func toggle(_ control: SystemControl, from current: ControlValue, done: @escaping (ControlValue) -> Void) {
        let on = !current.isOn
        switch control {
        case .bluetooth:
            setBluetooth(on)
            done(value(.bluetooth))
        case .wifi:
            do { try CWWiFiClient.shared().interface()?.setPower(on) } catch { Log.write("HATA: Wi-Fi: \(error.localizedDescription)") }
            done(value(.wifi))
        case .darkMode:
            setDarkMode(on)
            done(.on(on))
        case .focus:
            ControlCenter.press(.focus) { ok in
                done(ok ? .on(on) : value(.focus))
            }
        default:
            done(current)
        }
    }

    static func setLevel(_ control: SystemControl, _ level: Double) {
        switch control {
        case .volume: setVolume(level)
        case .brightness: setBrightness(level)
        default: break
        }
    }

    static func setAirDrop(_ mode: AirDropMode, done: @escaping (Bool) -> Void) {
        ControlCenter.airDrop(mode, done: done)
    }

    // MARK: - Ses (CoreAudio, varsayılan çıkış aygıtı)

    private static func outputDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    static func volume() -> Double? {
        guard let device = outputDevice() else { return nil }
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &level) == noErr else { return nil }
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted) == noErr, muted != 0 { return 0 }
        return Double(level)
    }

    private static func setVolume(_ level: Double) {
        guard let device = outputDevice() else { return }
        var value = Float32(level)
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        // Sessizdeyken çubuk kaldırılınca ses geri gelir; en alta inince susar. Sessizlik yalnız değişince
        // yazılır: sürüklerken her karede aygıta (özellikle Bluetooth kulaklığa) gereksiz komut gitmesin
        let wantMuted = UInt32(level <= 0.001 ? 1 : 0)
        guard AudioObjectHasProperty(device, &muteAddress) else { return }
        var current = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &current) == noErr, current == wantMuted { return }
        var muted = wantMuted
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, size, &muted)
    }

    // MARK: - Parlaklık (DisplayServices, yerleşik ekran)

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    /// Yerleşik ekran; yoksa ana ekran
    private static var builtInDisplay: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count = UInt32(0)
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static func brightness() -> Double? {
        guard let sym = dlsym(displayServices, "DisplayServicesGetBrightness") else { return nil }
        var level: Float = 0
        guard unsafeBitCast(sym, to: GetBrightness.self)(builtInDisplay, &level) == 0 else { return nil }
        return Double(level)
    }

    private static func setBrightness(_ level: Double) {
        guard let sym = dlsym(displayServices, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(sym, to: SetBrightness.self)(builtInDisplay, Float(max(level, 0.01)))
    }

    // MARK: - Bluetooth (IOBluetooth; blueutil'in kullandığı yol)

    private typealias GetPower = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Int32
    private static let ioBluetooth = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)

    static func bluetooth() -> Bool? {
        guard let sym = dlsym(ioBluetooth, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(sym, to: GetPower.self)() != 0
    }

    private static func setBluetooth(_ on: Bool) {
        guard let sym = dlsym(ioBluetooth, "IOBluetoothPreferenceSetControllerPowerState") else { return }
        _ = unsafeBitCast(sym, to: SetPower.self)(on ? 1 : 0)
        // Değişiklik denetleyiciye bir an sonra geçer; okumadan önce kısa bekleme
        for _ in 0..<20 where bluetooth() != on { usleep(25_000) }
    }

    // MARK: - Koyu görünüm (Sistem Olayları; ilk seferde Mac Otomasyon izni sorar)

    private static func setDarkMode(_ on: Bool) {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Log.write("HATA: koyu görünüm: \(error[NSAppleScript.errorMessage] ?? error)") }
    }

    // MARK: - Odak (durum dosyası)

    /// Rahatsız Etme açıksa durum dosyasında bir "assertion" kaydı olur
    private static func focus() -> Bool? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["data"] as? [[String: Any]])?.first else { return nil }
        return ((first["storeAssertionRecords"] as? [Any])?.isEmpty == false)
    }
}

/// Denetim Merkezi'ni Erişilebilirlik ile açıp içindeki düğmeye basar, sonra kapatır.
/// Düğmeler sabit kimlikle bulunur (macOS 15'te denendi); bulunamazsa açıklama adıyla aranır (macOS 14/26, denenmedi).
enum ControlCenter {
    private static let queue = DispatchQueue(label: "fingerkit.controlcenter")
    /// Denetim Merkezi açıkken daire kapanmasın diye
    nonisolated(unsafe) static var isBusy = false

    enum Target {
        case focus, airDrop, screenMirroring

        var ids: [String] {
            switch self {
            case .focus: ["controlcenter-focus-modes"]
            case .airDrop: ["controlcenter-airdrop"]
            case .screenMirroring: ["controlcenter-screen-mirroring"]
            }
        }

        /// Kimlik tutmazsa açıklamanın başı (Türkçe ve İngilizce)
        var names: [String] {
            switch self {
            case .focus: ["Odak", "Focus"]
            case .airDrop: ["AirDrop"]
            case .screenMirroring: ["Ekran Yansıtma", "Screen Mirroring"]
            }
        }
    }

    /// Düğmeye basar (Odak aç/kapa)
    static func press(_ target: Target, done: @escaping (Bool) -> Void) {
        run(close: true, done: done) { window in
            guard let button = find(target, in: window) else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
    }

    /// AirDrop'un ayrıntısını açar, seçeneğe basar
    static func airDrop(_ mode: AirDropMode, done: @escaping (Bool) -> Void) {
        let current = AirDropMode(discoverable: UserDefaults(suiteName: "com.apple.sharingd")?.string(forKey: "DiscoverableMode"))
        run(close: true, done: done) { window in
            guard let module = find(.airDrop, in: window), showDetail(module) else { return false }
            let id: String
            switch mode {
            case .everyone: id = "airdrop-mode-everyone"
            case .contacts: id = "airdrop-mode-contactsOnly"
            case .off:
                // Kapatmak: üstteki AirDrop anahtarı (zaten kapalıysa dokunulmaz)
                guard current != .off else { return true }
                id = "airdrop-header"
            }
            guard let option = waitFor(id, in: window) else { return false }
            return AXUIElementPerformAction(option, kAXPressAction as CFString) == .success
        }
    }

    /// Ekran yansıtma listesini açık bırakır; kullanıcı aygıtı kendisi seçer
    static func showScreenMirroring() {
        run(close: false, done: { _ in }) { window in
            guard let module = find(.screenMirroring, in: window) else { return false }
            return showDetail(module)
        }
    }

    // MARK: - Ağaç

    private static func run(close: Bool, done: @escaping (Bool) -> Void, _ work: @escaping (AXUIElement) -> Bool) {
        isBusy = true
        queue.async {
            let ok = open().map { window in
                let ok = work(window)
                if close {
                    usleep(120_000)
                    toggleMenu()
                }
                return ok
            } ?? false
            if !ok { Log.write("HATA: Denetim Merkezi'nde düğme bulunamadı (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))") }
            DispatchQueue.main.async {
                isBusy = false
                done(ok)
            }
        }
    }

    private static var app: AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    private static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(e, name as CFString, &value)
        return value
    }

    private static func window() -> AXUIElement? {
        guard let app else { return nil }
        return (attr(app, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    /// Menü çubuğundaki Denetim Merkezi simgesine basar (açar ya da kapatır)
    private static func toggleMenu() {
        guard let app,
              let bar = (attr(app, kAXChildrenAttribute) as? [AXUIElement])?.first(where: { attr($0, kAXRoleAttribute) as? String == kAXMenuBarRole }),
              let item = (attr(bar, kAXChildrenAttribute) as? [AXUIElement])?
                .first(where: { attr($0, "AXIdentifier") as? String == "com.apple.menuextra.controlcenter" })
        else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    /// Açık değilse açar; pencere gelene kadar en çok 1 sn bekler
    private static func open() -> AXUIElement? {
        if let w = window() { return w }
        toggleMenu()
        for _ in 0..<40 {
            usleep(25_000)
            if let w = window(), (attr(w, kAXChildrenAttribute) as? [AXUIElement])?.isEmpty == false { return w }
        }
        return nil
    }

    private static func find(_ target: Target, in root: AXUIElement) -> AXUIElement? {
        for id in target.ids { if let e = search(root, { attr($0, "AXIdentifier") as? String == id }) { return e } }
        return search(root) { e in
            let desc = attr(e, kAXDescriptionAttribute) as? String ?? ""
            return target.names.contains { desc.hasPrefix($0) }
        }
    }

    private static func waitFor(_ id: String, in root: AXUIElement) -> AXUIElement? {
        for _ in 0..<40 {
            if let e = search(root, { attr($0, "AXIdentifier") as? String == id }) { return e }
            usleep(25_000)
        }
        return nil
    }

    private static func search(_ e: AXUIElement, depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(e) { return e }
        guard depth < 8 else { return nil }
        for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let found = search(child, depth: depth + 1, match) { return found }
        }
        return nil
    }

    /// "Ayrıntıları göster" eylemi: adı dile göre değişir, "Name:" ile başlayan eylem seçilir
    private static func showDetail(_ e: AXUIElement) -> Bool {
        var names: CFArray?
        AXUIElementCopyActionNames(e, &names)
        guard let action = (names as? [String])?.first(where: { $0.hasPrefix("Name:") }) else { return false }
        return AXUIElementPerformAction(e, action as CFString) == .success
    }
}
