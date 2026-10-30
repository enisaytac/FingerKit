import AppKit
import ApplicationServices
import FingerKitCore

/// Uygulamanın menü çubuğunu Erişilebilirlik yoluyla okur ve bir maddeye basar
/// (Hareketler için verilen izin yeter). Menü yolu üst menüden başlar: ["Dosya", "Yeni"].
enum MenuPresser {
    /// Menü ağacındaki bir madde; alt menüsü yoksa `children` boş
    struct Item: Identifiable, Hashable {
        let path: [String]
        let children: [Item]
        var id: [String] { path }
        var title: String { path.last ?? "" }
    }

    /// Erişilebilirlik çağrıları ana iş parçacığını (ve tuş yakalayıcıyı) bekletmesin
    private static let queue = DispatchQueue(label: "FingerKit.menu")

    /// Öndeki uygulamada yolu bulup basar. Yol tutmazsa (menü adı değişmişse) son ada göre arar.
    static func press(_ path: [String], in app: NSRunningApplication) {
        queue.async {
            let name = app.localizedName ?? "?"
            guard let bar = menuBar(app) else {
                Log.write("Kısayol: \(name) menüsü okunamadı")
                return
            }
            guard let item = find(path, under: bar) ?? findTitle(path.last ?? "", under: bar, depth: 0) else {
                Log.write("Kısayol: \(name) menüsünde \(path.joined(separator: " › ")) bulunamadı")
                return
            }
            if let enabled: Bool = WindowSnapper.attribute(item, kAXEnabledAttribute), !enabled {
                Log.write("Kısayol: \(path.joined(separator: " › ")) şu an soluk (kullanılamaz)")
                return
            }
            let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
            Log.write("Kısayol: \(name) → \(path.joined(separator: " › "))\(result == .success ? "" : " (HATA \(result.rawValue))")")
        }
    }

    /// Menü ağacı (Apple menüsü hariç, en çok 3 kat). Uygulama açık değilse nil.
    static func read(bundleID: String, done: @escaping ([Item]?) -> Void) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            done(nil)
            return
        }
        queue.async {
            let items = menuBar(app).map { bar in Array(tree(bar, path: [], depth: 0).dropFirst()) }
            DispatchQueue.main.async { done(items) }
        }
    }

    /// Kısayolu olan menü maddeleri (Apple ve uygulama menüsü hariç, alt menülerde bir kat).
    /// Büyük menülerde zaman alır; basma sırasını bekletmesin diye ayrı sırada okunur.
    static func shortcutEntries(of app: NSRunningApplication, done: @escaping ([MenuShortcutEntry]) -> Void) {
        readQueue.async {
            var result: [MenuShortcutEntry] = []
            if let bar = menuBar(app) {
                // İlk ikisi Apple menüsü ve uygulama menüsü (Ayarlar, Gizle, Çık)
                for top in entries(bar).dropFirst(2) {
                    let t = title(top)
                    if !t.isEmpty { collectShortcuts(top, path: [t], depth: 0, into: &result) }
                }
            }
            DispatchQueue.main.async { done(result) }
        }
    }

    private static let readQueue = DispatchQueue(label: "FingerKit.menu-read", qos: .utility)

    private static func collectShortcuts(_ element: AXUIElement, path: [String], depth: Int, into result: inout [MenuShortcutEntry]) {
        let names = [kAXTitleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                     kAXMenuItemCmdGlyphAttribute, kAXMenuItemCmdVirtualKeyAttribute] as CFArray
        for item in entries(element) {
            // Bilgiler tek çağrıda (her çağrı uygulamaya gidip gelir)
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, names, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let values = raw as? [Any], values.count == 5,
                  let t = (values[0] as? String)?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { continue }
            if let key = MenuShortcutEntry.keyName(char: values[1] as? String,
                                                   glyph: (values[3] as? NSNumber)?.intValue,
                                                   virtualKey: (values[4] as? NSNumber)?.intValue) {
                let mods = (values[2] as? NSNumber)?.intValue ?? 0
                result.append(MenuShortcutEntry(path: path + [t], keys: MenuShortcutEntry.keys(key: key, modifiers: mods)))
            } else if depth < 1 {
                collectShortcuts(item, path: path + [t], depth: depth + 1, into: &result)
            }
        }
    }

    // MARK: - Ağaç

    private static func menuBar(_ app: NSRunningApplication) -> AXUIElement? {
        WindowSnapper.attribute(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute)
    }

    /// Bir menü öğesinin altındaki maddeler: menü çubuğu öğesi ya da madde → AXMenu → maddeler
    private static func entries(_ element: AXUIElement) -> [AXUIElement] {
        let children: [AXUIElement] = WindowSnapper.attribute(element, kAXChildrenAttribute) ?? []
        if let role: String = WindowSnapper.attribute(element, kAXRoleAttribute), role == kAXMenuBarRole {
            return children
        }
        // Madde ya da menü çubuğu öğesi: tek çocuğu AXMenu'dür
        return children.flatMap { child -> [AXUIElement] in
            WindowSnapper.attribute(child, kAXChildrenAttribute) ?? []
        }
    }

    private static func title(_ element: AXUIElement) -> String {
        (WindowSnapper.attribute(element, kAXTitleAttribute) as String?)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func tree(_ element: AXUIElement, path: [String], depth: Int) -> [Item] {
        guard depth < 3 else { return [] }
        return entries(element).compactMap { child in
            let t = title(child)
            guard !t.isEmpty else { return nil }  // ayırıcı çizgiler
            let p = path + [t]
            return Item(path: p, children: tree(child, path: p, depth: depth + 1))
        }
    }

    private static func find(_ path: [String], under element: AXUIElement) -> AXUIElement? {
        guard let first = path.first, let child = entries(element).first(where: { title($0) == first }) else { return nil }
        return path.count == 1 ? child : find(Array(path.dropFirst()), under: child)
    }

    private static func findTitle(_ name: String, under element: AXUIElement, depth: Int) -> AXUIElement? {
        guard !name.isEmpty, depth < 3 else { return nil }
        for child in entries(element) {
            if title(child) == name, depth > 0 { return child }
            if let found = findTitle(name, under: child, depth: depth + 1) { return found }
        }
        return nil
    }
}
