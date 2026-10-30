import Foundation

/// Mac'in kendi trackpad hareketlerinden FingerKit'le çakışabilenler
/// (Sistem Ayarları › Trackpad; com.apple.AppleMultitouchTrackpad).
public struct SystemTrackpad: Equatable, Sendable {
    public var threeFingerDrag = false
    public var threeFingerHorizontalSwipe = false
    public var fourFingerHorizontalSwipe = false
    public var threeFingerVerticalSwipe = false
    public var fourFingerVerticalSwipe = false
    public var threeFingerTapLookUp = false
    public var smartZoom = false
    public var twoFingerRightClick = false
    /// "Sol alt köşeye tıklama = sağ tık" açık (daire menüyle aynı köşe)
    public var leftCornerRightClick = false
    /// "Sağ alt köşeye tıklama = sağ tık" açık
    public var rightCornerRightClick = false

    public init() {}

    /// Ayar dosyasındaki değerlerden (sayılar: 0 kapalı; kaydırmada 2 = o parmak sayısıyla açık)
    public init(_ value: (String) -> Int?) {
        threeFingerDrag = value("TrackpadThreeFingerDrag") == 1
        threeFingerHorizontalSwipe = value("TrackpadThreeFingerHorizSwipeGesture") == 2
        fourFingerHorizontalSwipe = value("TrackpadFourFingerHorizSwipeGesture") == 2
        threeFingerVerticalSwipe = value("TrackpadThreeFingerVertSwipeGesture") == 2
        fourFingerVerticalSwipe = value("TrackpadFourFingerVertSwipeGesture") == 2
        threeFingerTapLookUp = value("TrackpadThreeFingerTapGesture") == 2
        smartZoom = value("TrackpadTwoFingerDoubleTapGesture") == 1
        twoFingerRightClick = value("TrackpadRightClick") == 1
        leftCornerRightClick = value("TrackpadCornerSecondaryClick") == 1
        rightCornerRightClick = value("TrackpadCornerSecondaryClick") == 2
    }

    /// Bu hareket Mac'in bir hareketiyle çakışıyorsa açıklaması
    public func conflict(with gesture: Gesture) -> String? {
        switch (gesture.shape, gesture.fingers) {
        case (.swipe, 3) where threeFingerDrag:
            return String(localized: "Mac'te 3 parmakla sürükleme açık: 3 parmak kaydırınca altındaki şey de sürüklenir.")
        case (.swipe(.left), 3), (.swipe(.right), 3):
            return threeFingerHorizontalSwipe ? String(localized: "Mac'te 3 parmak sola/sağa kaydırma tam ekran uygulamalar arasında geçer.") : nil
        case (.swipe(.left), 4), (.swipe(.right), 4):
            return fourFingerHorizontalSwipe ? String(localized: "Mac'te 4 parmak sola/sağa kaydırma tam ekran uygulamalar arasında geçer.") : nil
        case (.swipe, 3):
            return threeFingerVerticalSwipe ? String(localized: "Mac'te 3 parmak yukarı/aşağı kaydırma Mission Control'ü açar.") : nil
        case (.swipe, 4):
            return fourFingerVerticalSwipe ? String(localized: "Mac'te 4 parmak yukarı/aşağı kaydırma Mission Control'ü açar.") : nil
        case (.tap, 3):
            return threeFingerTapLookUp ? String(localized: "Mac'te 3 parmakla dokunma sözcük arama (Sözlük) penceresini açar.") : nil
        case (.doubleTap, 2):
            return smartZoom ? String(localized: "Mac'te 2 parmakla çift dokunma Akıllı Büyütme'yi çalıştırır.") : nil
        case (.click, 2):
            return twoFingerRightClick ? String(localized: "2 parmakla tıklama Mac'te sağ tıktır; bu hareket sağ tıkın yerine geçer.") : nil
        default:
            return nil
        }
    }
}

/// Bir hareket satırıyla ilgili uyarı
public struct Conflict: Hashable, Sendable {
    public enum Kind: Sendable {
        /// Aynı listede aynı hareket bir kez daha var
        case duplicate
        /// Aynı hareket hem "Her yerde" hem bir uygulamada var; uygulamadaki geçerli olur
        case override
        /// Mac'in kendi hareketiyle çakışma
        case system
        /// Aynı kısayol başka bir harekette de var
        case sameShortcut
    }

    public var kind: Kind
    public var message: String
}

extension Settings {
    /// `app` listesine `gesture` → `shortcut` eklenir (ya da `editing` satırı böyle değişir) ise
    /// çıkacak uyarılar. Kapalı satırlar da sayılır: açılınca yine çakışırlar.
    public func conflicts(gesture: Gesture, shortcut: Shortcut?, app: String,
                          editing: UUID? = nil, system: SystemTrackpad) -> [Conflict] {
        var result: [Conflict] = []
        guard let profile = apps.first(where: { $0.bundleID == app }) else { return result }
        let others = profile.bindings.filter { $0.id != editing }

        if let same = others.first(where: { $0.gesture == gesture }) {
            result.append(Conflict(kind: .duplicate,
                                   message: String(localized: "Bu listede “\(gesture.name)” zaten var (\(same.shortcut.display)). Kaydedersen o satırın yerine geçer.")))
        }

        if profile.isEverywhere {
            let names = apps.filter { !$0.isEverywhere && $0.bindings.contains { $0.gesture == gesture } }.map(\.name)
            if !names.isEmpty {
                result.append(Conflict(kind: .override,
                                       message: String(localized: "\(names.joined(separator: ", ")) öndeyken bu değil, o uygulamanın listesindeki kısayol çalışır.")))
            }
        } else if let everywhere = apps.first(where: \.isEverywhere)?.bindings.first(where: { $0.gesture == gesture }) {
            result.append(Conflict(kind: .override,
                                   message: String(localized: "“Her yerde” listesinde bu hareket \(everywhere.shortcut.display) yapıyor; \(profile.title) öndeyken bunun yerine bu satır çalışır.")))
        }

        if let message = system.conflict(with: gesture) {
            result.append(Conflict(kind: .system, message: message))
        }

        if let shortcut, !shortcut.isNone {
            var pool = others.filter { $0.gesture != gesture }
            if !profile.isEverywhere, let everywhere = apps.first(where: \.isEverywhere) {
                pool += everywhere.bindings.filter { $0.gesture != gesture }
            }
            if let same = pool.first(where: { $0.shortcut == shortcut }) {
                result.append(Conflict(kind: .sameShortcut,
                                       message: String(localized: "\(shortcut.display) kısayolu “\(same.gesture.name)” hareketinde de var.")))
            }
        }
        return result
    }
}
