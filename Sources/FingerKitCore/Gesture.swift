public enum Direction: String, Sendable {
    case up, down, left, right
}

public enum Edge: Sendable {
    case left, right, top, bottom
}

public enum Corner: Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public enum Side: Sendable {
    case left, right
}

/// FingerKit'in tanıdığı trackpad hareketleri. Ayar dosyasında bu adlarla (rawValue) yazılır.
public enum Gesture: String, Codable, CaseIterable, Identifiable, Sendable {
    case fourFingerSwipeUp, fourFingerSwipeDown, fourFingerSwipeLeft, fourFingerSwipeRight
    case threeFingerSwipeUp, threeFingerSwipeDown, threeFingerSwipeLeft, threeFingerSwipeRight
    case twoFingerClick, threeFingerClick, fourFingerClick, fiveFingerClick
    case threeFingerTap, fourFingerTap, fiveFingerTap
    case twoFingerDoubleTap, threeFingerDoubleTap
    case tipTapLeft, tipTapRight
    case edgeSwipeFromLeft, edgeSwipeFromRight, edgeSwipeFromTop, edgeSwipeFromBottom
    case cornerTapTopLeft, cornerTapTopRight, cornerTapBottomLeft, cornerTapBottomRight

    public var id: String { rawValue }

    public enum Shape: Equatable, Sendable {
        case swipe(Direction)
        case click
        case tap
        case doubleTap
        case tipTap(Side)
        case edgeSwipe(Edge)
        case cornerTap(Corner)
    }

    /// Hareket listesinde gruplamak için
    public enum Group: String, CaseIterable, Sendable {
        case swipe = "Kaydırma"
        case click = "Bastırarak tıklama"
        case tap = "Dokunma"
        case oneFinger = "Tek parmak"

        /// Ekranda görünen ad, Mac'in diline göre
        public var title: String {
            switch self {
            case .swipe: String(localized: "Kaydırma")
            case .click: String(localized: "Bastırarak tıklama")
            case .tap: String(localized: "Dokunma")
            case .oneFinger: String(localized: "Tek parmak")
            }
        }
    }

    public var fingers: Int {
        switch self {
        case .fourFingerSwipeUp, .fourFingerSwipeDown, .fourFingerSwipeLeft, .fourFingerSwipeRight,
             .fourFingerClick, .fourFingerTap:
            return 4
        case .threeFingerSwipeUp, .threeFingerSwipeDown, .threeFingerSwipeLeft, .threeFingerSwipeRight,
             .threeFingerClick, .threeFingerTap, .threeFingerDoubleTap:
            return 3
        case .fiveFingerClick, .fiveFingerTap:
            return 5
        case .twoFingerClick, .twoFingerDoubleTap, .tipTapLeft, .tipTapRight:
            return 2
        case .edgeSwipeFromLeft, .edgeSwipeFromRight, .edgeSwipeFromTop, .edgeSwipeFromBottom,
             .cornerTapTopLeft, .cornerTapTopRight, .cornerTapBottomLeft, .cornerTapBottomRight:
            return 1
        }
    }

    public var shape: Shape {
        switch self {
        case .fourFingerSwipeUp, .threeFingerSwipeUp: return .swipe(.up)
        case .fourFingerSwipeDown, .threeFingerSwipeDown: return .swipe(.down)
        case .fourFingerSwipeLeft, .threeFingerSwipeLeft: return .swipe(.left)
        case .fourFingerSwipeRight, .threeFingerSwipeRight: return .swipe(.right)
        case .twoFingerClick, .threeFingerClick, .fourFingerClick, .fiveFingerClick: return .click
        case .threeFingerTap, .fourFingerTap, .fiveFingerTap: return .tap
        case .twoFingerDoubleTap, .threeFingerDoubleTap: return .doubleTap
        case .tipTapLeft: return .tipTap(.left)
        case .tipTapRight: return .tipTap(.right)
        case .edgeSwipeFromLeft: return .edgeSwipe(.left)
        case .edgeSwipeFromRight: return .edgeSwipe(.right)
        case .edgeSwipeFromTop: return .edgeSwipe(.top)
        case .edgeSwipeFromBottom: return .edgeSwipe(.bottom)
        case .cornerTapTopLeft: return .cornerTap(.topLeft)
        case .cornerTapTopRight: return .cornerTap(.topRight)
        case .cornerTapBottomLeft: return .cornerTap(.bottomLeft)
        case .cornerTapBottomRight: return .cornerTap(.bottomRight)
        }
    }

    public var group: Group {
        switch shape {
        case .swipe: return .swipe
        case .click: return .click
        case .tap, .doubleTap, .tipTap: return .tap
        case .edgeSwipe, .cornerTap: return .oneFinger
        }
    }

    /// Ekranda görünen ad, Mac'in diline göre
    public var name: String {
        switch shape {
        case .swipe(.up): return String(localized: "\(fingers) parmak yukarı kaydır")
        case .swipe(.down): return String(localized: "\(fingers) parmak aşağı kaydır")
        case .swipe(.left): return String(localized: "\(fingers) parmak sola kaydır")
        case .swipe(.right): return String(localized: "\(fingers) parmak sağa kaydır")
        case .click: return String(localized: "\(fingers) parmakla tıkla")
        case .tap: return String(localized: "\(fingers) parmakla dokun")
        case .doubleTap: return String(localized: "\(fingers) parmakla çift dokun")
        case .tipTap(.left): return String(localized: "TipTap sol")
        case .tipTap(.right): return String(localized: "TipTap sağ")
        case .edgeSwipe(.left): return String(localized: "Sol kenardan kaydır")
        case .edgeSwipe(.right): return String(localized: "Sağ kenardan kaydır")
        case .edgeSwipe(.top): return String(localized: "Üst kenardan kaydır")
        case .edgeSwipe(.bottom): return String(localized: "Alt kenardan kaydır")
        case .cornerTap(.topLeft): return String(localized: "Sol üst köşeye dokun")
        case .cornerTap(.topRight): return String(localized: "Sağ üst köşeye dokun")
        case .cornerTap(.bottomLeft): return String(localized: "Sol alt köşeye dokun")
        case .cornerTap(.bottomRight): return String(localized: "Sağ alt köşeye dokun")
        }
    }

    /// Nasıl yapılır, tek cümle
    public var hint: String {
        switch shape {
        case .swipe: return String(localized: "\(fingers) parmağı birlikte kaydır")
        case .click: return String(localized: "\(fingers) parmakla tık sesi gelene kadar bastır")
        case .tap: return String(localized: "\(fingers) parmakla bastırmadan dokunup kaldır")
        case .doubleTap: return String(localized: "\(fingers) parmakla art arda iki kez dokun")
        case .tipTap(.left): return String(localized: "Bir parmak dururken başka parmakla soluna dokun")
        case .tipTap(.right): return String(localized: "Bir parmak dururken başka parmakla sağına dokun")
        case .edgeSwipe: return String(localized: "Tek parmakla kenardan başlayıp içeri kaydır")
        case .cornerTap: return String(localized: "Tek parmakla köşeye dokun")
        }
    }

    public static func swipe(fingers: Int, _ direction: Direction) -> Gesture? {
        allCases.first { $0.fingers == fingers && $0.shape == .swipe(direction) }
    }

    public static func click(fingers: Int) -> Gesture? {
        allCases.first { $0.fingers == fingers && $0.shape == .click }
    }

    public static func tap(fingers: Int) -> Gesture? {
        allCases.first { $0.fingers == fingers && $0.shape == .tap }
    }

    public static func doubleTap(fingers: Int) -> Gesture? {
        allCases.first { $0.fingers == fingers && $0.shape == .doubleTap }
    }

    public static func edgeSwipe(_ edge: Edge) -> Gesture {
        allCases.first { $0.shape == .edgeSwipe(edge) }!
    }

    public static func cornerTap(_ corner: Corner) -> Gesture {
        allCases.first { $0.shape == .cornerTap(corner) }!
    }
}
