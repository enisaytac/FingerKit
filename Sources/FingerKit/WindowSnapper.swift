import AppKit
import ApplicationServices
import FingerKitCore

/// Öndeki pencereyi Erişilebilirlik yoluyla yerleştirir (Hareketler için verilen izin yeter).
///
/// Erişilebilirlik koordinatları ana ekranın üst sol köşesinden başlar, y aşağı doğru artar;
/// NSScreen ise alt sol köşeden başlar. Ekran alanı önce birinciye çevrilir.
enum WindowSnapper {
    static func snap(_ layout: SnapLayout) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute),
              let position: CGPoint = value(window, kAXPositionAttribute),
              let size: CGSize = value(window, kAXSizeAttribute) else {
            Log.write("Yaslama: \(app.localizedName ?? "?") içinde öne çıkmış pencere yok")
            return
        }
        guard let screen = screen(containing: CGRect(origin: position, size: size)) else { return }
        let target = layout.frame(in: topLeft(screen.visibleFrame))

        // Bazı uygulamalar (Chrome, Electron) bu açıkken her adımı canlandırır ve yavaşlar
        let enhanced = "AXEnhancedUserInterface" as CFString
        var wasEnhanced: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, enhanced, &wasEnhanced)
        if (wasEnhanced as? Bool) == true { AXUIElementSetAttributeValue(appElement, enhanced, kCFBooleanFalse) }
        defer { if (wasEnhanced as? Bool) == true { AXUIElementSetAttributeValue(appElement, enhanced, kCFBooleanTrue) } }

        // Önce boyut (eski ekranda sığsın), sonra yer, sonra yine boyut (yeni ekranda sınır kalkmış olabilir)
        set(window, kAXSizeAttribute, target.size)
        set(window, kAXPositionAttribute, target.origin)
        set(window, kAXSizeAttribute, target.size)

        // Uygulama en küçük boyutun altına inmediyse pencere doğru kenara yapışık kalsın
        if let actual: CGSize = value(window, kAXSizeAttribute), actual != target.size {
            set(window, kAXPositionAttribute, layout.align(actual, to: target))
        }
        Log.write("Yaslama: \(layout.title) → \(app.localizedName ?? "?")")
    }

    /// Pencerenin en büyük kısmının durduğu ekran
    private static func screen(containing window: CGRect) -> NSScreen? {
        NSScreen.screens.max { area(topLeft($0.frame).intersection(window)) < area(topLeft($1.frame).intersection(window)) }
            ?? NSScreen.main
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    /// NSScreen alanını (alt sol başlangıç) Erişilebilirlik koordinatına (üst sol başlangıç) çevirir
    static func topLeft(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? r.height
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - Erişilebilirlik yardımcıları

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? T
    }

    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        guard let ref: AXValue = attribute(element, name) else { return nil }
        if T.self == CGPoint.self {
            var p = CGPoint.zero
            return AXValueGetValue(ref, .cgPoint, &p) ? p as? T : nil
        }
        var s = CGSize.zero
        return AXValueGetValue(ref, .cgSize, &s) ? s as? T : nil
    }

    static func set(_ element: AXUIElement, _ name: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(element, name as CFString, v) }
    }

    static func set(_ element: AXUIElement, _ name: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(element, name as CFString, v) }
    }
}
