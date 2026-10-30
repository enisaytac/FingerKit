import AppKit
import ApplicationServices

/// Caps Lock basılıyken imleç kayınca altındaki pencereyi okla birlikte taşır.
///
/// Erişilebilirlik ve olay koordinatları aynı (ana ekranın üst sol köşesi başlangıç), çevirmeye gerek yok.
/// Ok ilk `threshold` noktayı geçmeden pencere oynamaz: Caps Lock + harf basarken eldeki titreme taşımasın.
final class WindowMover {
    private static let threshold: CGFloat = 6
    /// Masaüstü, Dock ve menü çubuğu da Erişilebilirlikte görünür; onlar taşınmaz
    private static let skipped: Set<String> = ["com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter"]

    private var start: CGPoint?
    private var window: AXUIElement?
    private var appElement: AXUIElement?
    private var windowStart = CGPoint.zero
    private var wasEnhanced = false
    /// Pencereyi kaydırmak bazı uygulamalarda yavaş; ayrı sırada yapılır ki tuş yakalayıcı (ve ok) beklemesin
    private let queue = DispatchQueue(label: "FingerKit.tasima", qos: .userInteractive)
    private let lock = NSLock()
    /// Bekleyen yer; sırada tek iş kalsın, hızlı kaydırmada yalnız son yer gider
    private var pending: CGPoint?
    /// Bu basılışta pencere bulunamadıysa her harekette yeniden aranmasın
    private var gaveUp = false

    /// Taşıma başladı mı (Caps Lock bırakılınca büyük harf kilidi değişmesin)
    var isMoving: Bool { window != nil }

    /// Caps Lock basıldı
    func begin(at point: CGPoint) {
        end()
        start = point
    }

    /// İmleç oynadı. Taşıma başladıysa true döner.
    @discardableResult
    func moved(to point: CGPoint) -> Bool {
        guard let start, !gaveUp else { return false }
        if window == nil {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.threshold else { return false }
            guard grab(at: start) else {
                Log.write("Taşıma: imlecin altında taşınacak pencere yok")
                gaveUp = true
                return false
            }
        }
        let target = CGPoint(x: windowStart.x + point.x - start.x, y: windowStart.y + point.y - start.y)
        lock.lock()
        let scheduled = pending != nil
        pending = target
        lock.unlock()
        if !scheduled, let window {
            queue.async { [weak self] in self?.flush(window) }
        }
        return true
    }

    /// Caps Lock bırakıldı
    func end() {
        if let window { queue.sync { flush(window) } }
        if let appElement, wasEnhanced {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        if window != nil { Log.write("Taşıma: bitti") }
        start = nil
        window = nil
        appElement = nil
        wasEnhanced = false
        gaveUp = false
    }

    private func flush(_ window: AXUIElement) {
        lock.lock()
        let target = pending
        pending = nil
        lock.unlock()
        if let target { WindowSnapper.set(window, kAXPositionAttribute, target) }
    }

    /// İmlecin altındaki pencereyi bulur ve öne getirir
    private func grab(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit, let window = Self.window(of: hit) else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              !Self.skipped.contains(app.bundleIdentifier ?? ""),
              let position: CGPoint = WindowSnapper.value(window, kAXPositionAttribute) else { return false }
        // Tam ekran pencere taşınamaz
        if let full: Bool = WindowSnapper.attribute(window, "AXFullScreen"), full { return false }

        let appElement = AXUIElementCreateApplication(pid)
        // Bazı uygulamalar (Chrome, Electron) bu açıkken her adımı canlandırır ve yavaşlar
        var enhanced: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &enhanced)
        wasEnhanced = (enhanced as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
        self.window = window
        self.appElement = appElement
        windowStart = position
        Log.write("Taşıma: \(app.localizedName ?? "?")")
        return true
    }

    /// Tıklanan öğenin penceresi (öğe pencerenin kendisi olabilir)
    private static func window(of element: AXUIElement) -> AXUIElement? {
        if let role: String = WindowSnapper.attribute(element, kAXRoleAttribute), role == kAXWindowRole {
            return element
        }
        guard let window: AXUIElement = WindowSnapper.attribute(element, kAXWindowAttribute),
              let role: String = WindowSnapper.attribute(window, kAXRoleAttribute), role == kAXWindowRole else { return nil }
        return window
    }
}
