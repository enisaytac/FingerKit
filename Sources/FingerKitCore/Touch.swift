/// Trackpad'deki bir parmağın tek karedeki hali.
public struct Touch: Equatable, Sendable {
    public var id: Int32
    /// 0 = sol kenar, 1 = sağ kenar
    public var x: Double
    /// 0 = alt kenar, 1 = üst kenar
    public var y: Double
    /// Temas büyüklüğü (canlı çizimde nokta boyu için)
    public var size: Double
    /// MultitouchSupport'un durum numarası: 3 = değdi, 4 = basılı; diğerleri yaklaşma/kalkma
    public var state: Int32

    public init(id: Int32, x: Double, y: Double, size: Double = 1, state: Int32 = 4) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
        self.state = state
    }

    public var isDown: Bool { state == 3 || state == 4 }
}

/// Trackpad'in tek karesi (saniyede ~100 kez gelir).
public struct TouchFrame: Sendable {
    /// Saniye; yalnız farkları kullanılır
    public var time: Double
    public var touches: [Touch]

    public init(time: Double, touches: [Touch]) {
        self.time = time
        self.touches = touches
    }
}
