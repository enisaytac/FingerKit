import AppKit
import ApplicationServices
import Observation
import ServiceManagement
import FingerKitCore

/// SwiftUI'de de "Gesture" adlı bir tür var; uygulama içinde bizimki kastedilir.
typealias Gesture = FingerKitCore.Gesture

/// Her şeyi birbirine bağlar: trackpad kareleri → hareket tanıma → ön plandaki uygulama → kısayol.
/// Tüm işler ana iş parçacığında yürür.
@Observable
final class Engine {
    static let shared = Engine()

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            syncHyper()
            syncClipboard()
            syncAppShortcuts()
        }
    }
    /// Kopyalananlar (ayrı dosyada: pano.json; görseller Pano klasöründe)
    var clipHistory: ClipboardHistory {
        didSet {
            guard clipHistory != oldValue else { return }
            do { try clipFile.save(clipHistory) } catch { Log.write("HATA: pano geçmişi kaydedilemedi: \(error)") }
            deleteUnusedImages(oldValue)
        }
    }
    /// Erişilebilirlik izni verildi mi (kısayol göndermek ve tıklamayı yakalamak için şart)
    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var trackpadFound = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Mac'in kendi trackpad hareketleri (çakışma uyarısı için; pencere açılınca yeniden okunur)
    private(set) var systemTrackpad = SystemTrackpad()

    /// Canlı çizim için son kare (yalnız pencere açıkken güncellenir)
    private(set) var liveTouches: [Touch] = []
    private(set) var liveAspect = 130.0 / 80.0
    /// Az önce tanınan hareket (pencerede kısa süre parlar)
    private(set) var highlighted: Gesture?
    private(set) var highlightCount = 0

    /// Yeni hareket eklenirken: bir sonraki tanınan hareket buraya gider, kısayol gönderilmez
    var recording: ((Gesture) -> Void)?

    /// İlk açılışta ya da izin eksikken pencere kendiliğinden açılır
    let showWindowAtLaunch: Bool

    @ObservationIgnored var liveViewVisible = false
    @ObservationIgnored private(set) var lastTwoFingerTapAt: CFTimeInterval = 0
    @ObservationIgnored private(set) var lastDoubleTapAt: CFTimeInterval = 0
    @ObservationIgnored private let file = SettingsFile.standard
    @ObservationIgnored private let clipFile = ClipboardFile.standard
    @ObservationIgnored private var clipWatcher: ClipboardWatcher?
    @ObservationIgnored private var shotWatcher: ScreenshotWatcher?
    @ObservationIgnored private var expireTimer: Timer?
    @ObservationIgnored private var recognizers: [Int: GestureRecognizer] = [:]
    @ObservationIgnored private var interceptor: ClickInterceptor?
    @ObservationIgnored private(set) var hyper: HyperKey!
    @ObservationIgnored private var appShortcutTap: AppShortcutTap?
    @ObservationIgnored private var termSignal: DispatchSourceSignal?
    @ObservationIgnored private var trustTimer: Timer?
    @ObservationIgnored private var highlightWork: DispatchWorkItem?
    @ObservationIgnored private var firstRun = false

    private init() {
        switch file.load() {
        case .loaded(let s):
            settings = s
        case .created(let s):
            settings = s
            firstRun = true
            Log.write("ilk açılış: boş ayar dosyası yazıldı")
        case .recovered(let s, let backup, let error):
            settings = s
            Log.write("HATA: ayar dosyası okunamadı (\(error)); yedeği: \(backup.lastPathComponent)")
        }
        clipHistory = ClipboardFile.standard.load()
        showWindowAtLaunch = firstRun || !AXIsProcessTrusted()
    }

    // MARK: - Açılış

    func start() {
        Log.write("FingerKit açıldı")
        let source = MultitouchSource.shared
        source.onFrame = { [weak self] id, frame in self?.handle(device: id, frame: frame) }
        startMultitouch()

        clipWatcher = ClipboardWatcher(folder: clipFile.imageFolder) { [weak self] item in self?.clipHistory.add(item) }
        shotWatcher = ScreenshotWatcher { [weak self] item in self?.clipHistory.add(item) }
        syncClipboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            // Sık açılan pencereler arkada bir kez çizilir (ilk açılışta donmasın; bkz. Araclar/akicilik-denetle.sh)
            if let self, self.settings.clipboard.enabled { ClipboardPicker.shared.warmUp(self) }
            if let self, self.settings.radial.enabled { RadialMenu.shared.warmUp(self) }
        }
        // Süresi dolan kopyalar açılışta ve saatte bir silinir
        expireClips()
        expireTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.expireClips() }
        interceptor = ClickInterceptor(engine: self)
        hyper = HyperKey(engine: self)
        appShortcutTap = AppShortcutTap(engine: self)
        if isTrusted {
            interceptor?.start()
            syncHyper()
            syncAppShortcuts()
        } else {
            // İzin yokken Caps Lock'a dokunulmaz; önceki çökmeden kalan eşleme varsa geri alınır
            hyper.update(false)
            requestAccessibility()
        }
        // Uykudan uyanınca dokunma aygıtları yeniden başlatılır (yoksa bazen veri kesilir)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.startMultitouch() }
        }
        // yap.sh ya da Etkinlik Monitörü kapatırken (SIGTERM) de Caps Lock eski hâline dönsün
        signal(SIGTERM, SIG_IGN)
        termSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSignal?.setEventHandler { NSApp.terminate(nil) }
        termSignal?.resume()
        if firstRun { setLaunchAtLogin(true) }
        refreshSystemTrackpad()
        AppUsage.shared.refresh()
        // Öne geçen uygulamanın menüsü arka planda okunur; daire açılınca kısayollar hazır olur
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, wantsRadialMenu,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            RadialMenu.shared.prefetch(app)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { RadialMenu.shared.forget(app) }
        }
    }

    // MARK: - Daire menü

    /// Sol alt köşe tıklaması daireyi açsın mı
    var wantsRadialMenu: Bool {
        settings.enabled && settings.radial.enabled && recording == nil && isTrusted
    }

    func refreshSystemTrackpad() {
        let domain = "com.apple.AppleMultitouchTrackpad" as CFString
        let read = SystemTrackpad { key in
            (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.intValue
        }
        if read != systemTrackpad { systemTrackpad = read }
    }

    func stop() {
        hyper?.stop()
        appShortcutTap?.stop()
        MultitouchSource.shared.stop()
        Log.write("FingerKit kapandı")
    }

    private func startMultitouch() {
        recognizers = [:]
        trackpadFound = MultitouchSource.shared.start()
        if !trackpadFound { Log.write("HATA: trackpad bulunamadı") }
    }

    // MARK: - İzin

    /// Sistem "FingerKit bu bilgisayarı denetlemek istiyor" penceresini açar; izin gelene kadar bekler.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        guard !isTrusted, trustTimer == nil else { return }
        Log.write("Erişilebilirlik izni bekleniyor")
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted() else { return }
            timer.invalidate()
            trustTimer = nil
            isTrusted = true
            Log.write("Erişilebilirlik izni verildi")
            interceptor?.start()
            syncHyper()
            syncAppShortcuts()
        }
    }

    /// Hyper Key, FingerKit ve Hyper ayarı ikisi de açıkken çalışır
    private func syncHyper() {
        guard let hyper, isTrusted else { return }
        hyper.update(settings.enabled && settings.hyper.enabled)
    }

    /// Uygulama kısayollarının yakalayıcısı yalnız normal tetikli açık satır varken kurulur
    private func syncAppShortcuts() {
        guard let appShortcutTap, isTrusted else { return }
        appShortcutTap.update(settings.enabled && settings.appShortcuts.hasPlainTriggers)
    }

    /// Pano, FingerKit ve pano ayarı ikisi de açıkken dinlenir (izin gerekmez)
    private func syncClipboard() {
        guard let clipWatcher, let shotWatcher else { return }
        let on = settings.enabled && settings.clipboard.enabled
        if on { clipWatcher.start() } else { clipWatcher.stop() }
        if on, settings.clipboard.screenshots { shotWatcher.start() } else { shotWatcher.stop() }
        expireClips()
    }

    /// Gün sınırını geçen, sabitlenmemiş kopyalar silinir
    private func expireClips() {
        var history = clipHistory
        if !history.expire(keepDays: settings.clipboard.keepDays).isEmpty { clipHistory = history }
    }

    /// FingerKit yapıştırmak için panoya bir şey koydu; geçmişe yeniden eklenmesin
    func markOwnPaste() {
        clipWatcher?.ownChange = NSPasteboard.general.changeCount
    }

    /// Listeden çıkan görsellerin FingerKit'in kendi klasöründeki dosyası silinir (ekran görüntülerine dokunulmaz)
    private func deleteUnusedImages(_ old: ClipboardHistory) {
        let folder = clipFile.imageFolder.path
        let kept = Set(clipHistory.items.compactMap(\.file))
        for file in Set(old.items.compactMap(\.file)).subtracting(kept) where file.hasPrefix(folder) {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Girişte başlatma

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("HATA: girişte başlatma \(on ? "açılamadı" : "kapatılamadı"): \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Log.write("girişte başlatma: \(launchAtLogin ? "açık" : "kapalı") (durum \(SMAppService.mainApp.status.rawValue))")
    }

    // MARK: - Hareketler

    private func handle(device id: Int, frame: TouchFrame) {
        recognizer(for: id).process(frame)
        if liveViewVisible {
            liveTouches = frame.touches
            if let d = MultitouchSource.shared.device(id) { liveAspect = d.widthMM / d.heightMM }
        }
    }

    private func recognizer(for id: Int) -> GestureRecognizer {
        if let r = recognizers[id] { return r }
        let device = MultitouchSource.shared.device(id)
        let r = GestureRecognizer(widthMM: device?.widthMM ?? 130, heightMM: device?.heightMM ?? 80)
        r.isWanted = { [weak self] in self?.isWanted($0) ?? false }
        r.onGesture = { [weak self] in self?.fire($0) }
        r.onTap = { [weak self] fingers in
            if fingers == 2 { self?.lastTwoFingerTapAt = CACurrentMediaTime() }
        }
        recognizers[id] = r
        return r
    }

    /// Tıklama anında en çok parmağın değdiği trackpad
    func clickContext() -> (GestureRecognizer, GestureRecognizer.ClickContext)? {
        recognizers.values
            .map { ($0, $0.clickContext()) }
            .max { $0.1.fingers < $1.1.fingers }
    }

    var frontBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// FingerKit penceresi öndeyken her hareket tanınır ama yalnız gösterilir.
    func isWanted(_ gesture: Gesture) -> Bool {
        if recording != nil || NSApp.isActive { return true }
        guard settings.enabled else { return false }
        return settings.shortcut(for: gesture, app: frontBundleID) != nil
    }

    func fire(_ gesture: Gesture) {
        flash(gesture)
        if gesture == .twoFingerDoubleTap {
            lastDoubleTapAt = CACurrentMediaTime()
            interceptor?.dropHeldRightClick()
        }
        if let record = recording {
            recording = nil
            Log.write("kayıt: \(gesture.name)")
            record(gesture)
            return
        }
        if NSApp.isActive {
            Log.write("\(gesture.name) (pencere önde, yalnız gösterildi)")
            return
        }
        let app = frontBundleID
        guard settings.enabled, let binding = settings.binding(for: gesture, app: app) else { return }
        if let task = binding.task {
            TaskRunner.run(task, from: "\(gesture.name) [\(app ?? "?")]")
            return
        }
        Log.write("\(gesture.name) → \(binding.shortcut.display) [\(app ?? "?")]")
        Toast.show(binding.shortcut.display, symbol: "hand.tap.fill")
        KeySender.send(binding.shortcut)
    }

    private func flash(_ gesture: Gesture) {
        highlighted = gesture
        highlightCount += 1
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.highlighted = nil }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    // MARK: - Ayar değişiklikleri

    private func saveSettings() {
        do {
            try file.save(settings)
        } catch {
            Log.write("HATA: ayarlar kaydedilemedi: \(error)")
        }
    }

    var settingsFileURL: URL { file.url }

    func profileIndex(_ bundleID: String) -> Int? {
        settings.apps.firstIndex { $0.bundleID == bundleID }
    }

    /// Aynı hareket o listede varsa kısayolu değişir, yoksa eklenir.
    func setBinding(_ gesture: Gesture, _ shortcut: Shortcut, task: ReadyTask? = nil, in bundleID: String) {
        guard let a = profileIndex(bundleID) else { return }
        if let b = settings.apps[a].bindings.firstIndex(where: { $0.gesture == gesture }) {
            settings.apps[a].bindings[b].shortcut = shortcut
            settings.apps[a].bindings[b].task = task
            settings.apps[a].bindings[b].enabled = true
        } else {
            settings.apps[a].bindings.append(GestureBinding(gesture: gesture, shortcut: shortcut, task: task))
        }
    }

    /// Düzenlenen satır yeni hareket/kısayolu alır; aynı hareket listede başka satırdaysa o satır silinir.
    func updateBinding(_ id: UUID, _ gesture: Gesture, _ shortcut: Shortcut, task: ReadyTask? = nil, in bundleID: String) {
        guard let a = profileIndex(bundleID),
              let b = settings.apps[a].bindings.firstIndex(where: { $0.id == id }) else {
            setBinding(gesture, shortcut, task: task, in: bundleID)
            return
        }
        var apps = settings.apps
        apps[a].bindings[b].gesture = gesture
        apps[a].bindings[b].shortcut = shortcut
        apps[a].bindings[b].task = task
        apps[a].bindings.removeAll { $0.id != id && $0.gesture == gesture }
        settings.apps = apps
    }

    func conflicts(_ gesture: Gesture, _ shortcut: Shortcut?, in bundleID: String, editing: UUID? = nil) -> [Conflict] {
        settings.conflicts(gesture: gesture, shortcut: shortcut, app: bundleID, editing: editing, system: systemTrackpad)
    }

    func removeBinding(_ id: UUID, in bundleID: String) {
        guard let a = profileIndex(bundleID) else { return }
        settings.apps[a].bindings.removeAll { $0.id == id }
    }

    /// Uygulamayı listeye ekler (zaten varsa dokunmaz); kimliğini döndürür.
    @discardableResult
    func addApp(at url: URL) -> String? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        if profileIndex(id) == nil {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            settings.apps.append(AppProfile(bundleID: id, name: name))
        }
        return id
    }

    func removeApp(_ bundleID: String) {
        guard bundleID != AppProfile.everywhere else { return }
        settings.apps.removeAll { $0.bundleID == bundleID }
    }
}
