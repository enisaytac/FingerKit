import Foundation

/// Bir trackpad'in karelerinden hareket çıkarır. Her trackpad için bir tane olur.
///
/// Bir "oturum" ilk parmağın değmesiyle başlar, son parmak kalkınca biter.
/// Kaydırmalar oturum sürerken (yol eşiği aşılınca) hemen, dokunmalar oturum bitince tanınır.
/// Bastırarak tıklama trackpad verisinde görünmez; onu uygulama tarafı fare olayından yakalar
/// ve `clickContext()` ile o anki parmak sayısını sorar.
public final class GestureRecognizer {
    public struct Tuning: Sendable {
        /// Kaydırma sayılması için parmakların ortak yolu (mm)
        public var swipeDistance = 12.0
        /// Kenardan kaydırmada içeri doğru yol (mm)
        public var edgeSwipeDistance = 10.0
        /// Kenar şeridinin genişliği (mm); kenardan kaydırma bu şeritte başlamalı
        public var edgeZone = 8.0
        /// Köşe karesinin kenarı (mm)
        public var cornerZone = 22.0
        /// Dokunma: ilk değişten son kalkışa en uzun süre (sn)
        public var tapMaxDuration = 0.35
        /// Dokunma: bir parmağın en çok kayabileceği yol (mm)
        public var tapMaxMovement = 3.0
        /// Çift dokunma: birinci dokunmanın bitişiyle ikincinin başlangıcı arası en çok (sn)
        public var doubleTapGap = 0.30
        /// TipTap: sabit parmağın, diğer parmak değmeden önce en az ne kadar durmuş olması (sn)
        public var tipTapRestTime = 0.15

        public init() {}
    }

    /// Tıklama anında trackpad'in durumu
    public struct ClickContext: Sendable {
        public var fingers: Int
        /// Parmak sayısı son değiştiğinden beri parmakların ortak yolu (mm);
        /// büyükse bu bir "3 parmakla sürükleme"dir, tıklama değil
        public var movement: Double
        /// Basılı parmakların ortası (0-1; x: 0 sol, y: 0 alt)
        public var x = 0.0
        public var y = 0.0
    }

    public let widthMM: Double
    public let heightMM: Double
    public var tuning = Tuning()

    /// Hareket bir kısayola bağlı mı? Bağlı değilse tanınsa bile yok sayılır; böylece
    /// örneğin boş duran 3 parmak kaydırma, 4 parmak kaydırmanın önüne geçmez.
    public var isWanted: (Gesture) -> Bool = { _ in true }
    /// Hareket tanındı
    public var onGesture: (Gesture) -> Void = { _ in }
    /// Kaç parmakla olursa olsun bir dokunma bitti (sağ tık ayıklaması için)
    public var onTap: (Int) -> Void = { _ in }
    /// Çift dokunma beklenirken tek dokunmayı ertelemek için zamanlayıcı kurar
    public var schedule: (Double, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Son karedeki tüm parmaklar (canlı çizim için)
    public private(set) var touches: [Touch] = []
    public var fingerCount: Int { session?.count ?? 0 }

    public init(widthMM: Double, heightMM: Double) {
        self.widthMM = widthMM
        self.heightMM = heightMM
    }

    // MARK: - Oturum

    private struct Finger {
        var startX: Double
        var startY: Double
        var startTime: Double
        var x: Double
        var y: Double
        var maxMove = 0.0
    }

    private final class Session {
        let startTime: Double
        var fingers: [Int32: Finger] = [:]
        var firstFinger: Finger?
        var count = 0
        var maxCount = 0
        var maxMove = 0.0
        /// Parmak sayısı son değiştiğindeki ağırlık merkezi; kaydırma yolu buradan ölçülür
        var anchor: (x: Double, y: Double)?
        /// Bir hareket çalıştı ya da tıklama yutuldu: bu oturumda başka hareket yok
        var done = false
        /// Dokunma sayılmaz (tıklandı ya da TipTap oldu)
        var noTap = false

        init(startTime: Double) { self.startTime = startTime }
    }

    private struct PendingTap {
        var fingers: Int
        var endTime: Double
        var token: Int
    }

    private var session: Session?
    private var pending: PendingTap?
    private var pendingToken = 0

    public func reset() {
        session = nil
        pending = nil
        touches = []
    }

    public func process(_ frame: TouchFrame) {
        touches = frame.touches
        let down = frame.touches.filter(\.isDown)
        if session == nil {
            guard !down.isEmpty else { return }
            session = Session(startTime: frame.time)
        }
        guard let s = session else { return }
        let t = frame.time

        let ids = Set(down.map(\.id))
        for (id, finger) in s.fingers where !ids.contains(id) {
            s.fingers[id] = nil
            fingerLifted(finger, at: t, remaining: down)
        }
        for touch in down {
            if var f = s.fingers[touch.id] {
                f.x = touch.x
                f.y = touch.y
                f.maxMove = max(f.maxMove, distance(f.startX, f.startY, touch.x, touch.y))
                s.fingers[touch.id] = f
                s.maxMove = max(s.maxMove, f.maxMove)
            } else {
                let f = Finger(startX: touch.x, startY: touch.y, startTime: t, x: touch.x, y: touch.y)
                s.fingers[touch.id] = f
                if s.firstFinger == nil { s.firstFinger = f }
            }
        }
        if down.count != s.count {
            s.count = down.count
            s.maxCount = max(s.maxCount, s.count)
            s.anchor = down.isEmpty ? nil : centroid(down)
        }

        if !s.done {
            detectSwipe(s, down)
            detectEdgeSwipe(s, down)
        }
        if down.isEmpty { endSession(s, at: t) }
    }

    // MARK: - Tıklama (uygulama tarafından fare olayıyla bildirilir)

    public func clickContext() -> ClickContext {
        guard let s = session, s.count > 0, let a = s.anchor else { return ClickContext(fingers: 0, movement: 0) }
        let c = centroid(touches.filter(\.isDown))
        return ClickContext(fingers: s.count, movement: distance(a.x, a.y, c.x, c.y), x: c.x, y: c.y)
    }

    /// Tıklama oldu: bu oturum artık dokunma sayılmaz. Tıklama bir harekete dönüştüyse
    /// (`consumed`) oturumda başka hareket de çalışmaz.
    public func markClicked(consumed: Bool) {
        session?.noTap = true
        if consumed { session?.done = true }
    }

    // MARK: - Tanıma

    private func detectSwipe(_ s: Session, _ down: [Touch]) {
        guard (3...5).contains(down.count), let a = s.anchor else { return }
        let c = centroid(down)
        let dx = (c.x - a.x) * widthMM
        let dy = (c.y - a.y) * heightMM
        guard max(abs(dx), abs(dy)) >= tuning.swipeDistance else { return }
        let direction: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
        guard let g = Gesture.swipe(fingers: down.count, direction), isWanted(g) else { return }
        s.done = true
        onGesture(g)
    }

    private func detectEdgeSwipe(_ s: Session, _ down: [Touch]) {
        guard s.maxCount == 1, down.count == 1, let f = s.fingers[down[0].id],
              let edge = edge(x: f.startX, y: f.startY) else { return }
        let dx = (f.x - f.startX) * widthMM
        let dy = (f.y - f.startY) * heightMM
        let inward: Double
        let sideways: Double
        switch edge {
        case .left: inward = dx; sideways = abs(dy)
        case .right: inward = -dx; sideways = abs(dy)
        case .bottom: inward = dy; sideways = abs(dx)
        case .top: inward = -dy; sideways = abs(dx)
        }
        guard inward >= tuning.edgeSwipeDistance, inward > sideways else { return }
        let g = Gesture.edgeSwipe(edge)
        guard isWanted(g) else { return }
        s.done = true
        onGesture(g)
    }

    /// TipTap: bir parmak dururken diğeri kısa bir dokunuşla kalktı.
    private func fingerLifted(_ f: Finger, at t: Double, remaining down: [Touch]) {
        guard let s = session, !s.done, s.count == 2, down.count == 1, let rest = s.fingers[down[0].id] else { return }
        guard t - f.startTime <= tuning.tapMaxDuration,
              f.maxMove <= tuning.tapMaxMovement,
              f.startTime - rest.startTime >= tuning.tipTapRestTime else { return }
        s.noTap = true
        let g: Gesture = f.startX < rest.x ? .tipTapLeft : .tipTapRight
        if isWanted(g) { onGesture(g) }
    }

    private func endSession(_ s: Session, at t: Double) {
        session = nil
        let isTap = !s.done && !s.noTap
            && t - s.startTime <= tuning.tapMaxDuration
            && s.maxMove <= tuning.tapMaxMovement
        let n = s.maxCount

        if let p = pending {
            pending = nil
            if isTap, n == p.fingers, s.startTime - p.endTime <= tuning.doubleTapGap {
                onTap(n)
                if let g = Gesture.doubleTap(fingers: n), isWanted(g) { onGesture(g) }
                return
            }
            emitSingleTap(p.fingers)
        }
        guard isTap else { return }
        onTap(n)

        if n == 1 {
            if let f = s.firstFinger, let c = corner(x: f.startX, y: f.startY) {
                let g = Gesture.cornerTap(c)
                if isWanted(g) { onGesture(g) }
            }
            return
        }
        if let d = Gesture.doubleTap(fingers: n), isWanted(d) {
            // İkinci dokunma gelebilir; tek dokunma kararı bekletilir
            pendingToken += 1
            let token = pendingToken
            pending = PendingTap(fingers: n, endTime: t, token: token)
            schedule(tuning.doubleTapGap) { [weak self] in self?.pendingExpired(token) }
        } else {
            emitSingleTap(n)
        }
    }

    private func pendingExpired(_ token: Int) {
        guard let p = pending, p.token == token else { return }
        // Süre içinde başlamış bir dokunuş sürüyorsa karar onun sonunda verilir
        if let s = session, s.startTime - p.endTime <= tuning.doubleTapGap { return }
        pending = nil
        emitSingleTap(p.fingers)
    }

    private func emitSingleTap(_ n: Int) {
        if let g = Gesture.tap(fingers: n), isWanted(g) { onGesture(g) }
    }

    // MARK: - Yardımcılar

    private func centroid(_ touches: [Touch]) -> (x: Double, y: Double) {
        guard !touches.isEmpty else { return (0, 0) }
        let n = Double(touches.count)
        return (touches.reduce(0) { $0 + $1.x } / n, touches.reduce(0) { $0 + $1.y } / n)
    }

    /// İki nokta arası (mm)
    private func distance(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let dx = (x2 - x1) * widthMM
        let dy = (y2 - y1) * heightMM
        return (dx * dx + dy * dy).squareRoot()
    }

    private func edge(x: Double, y: Double) -> Edge? {
        let zx = tuning.edgeZone / widthMM
        let zy = tuning.edgeZone / heightMM
        if x < zx { return .left }
        if x > 1 - zx { return .right }
        if y > 1 - zy { return .top }
        if y < zy { return .bottom }
        return nil
    }

    private func corner(x: Double, y: Double) -> Corner? {
        let zx = tuning.cornerZone / widthMM
        let zy = tuning.cornerZone / heightMM
        switch (x < zx, x > 1 - zx, y > 1 - zy, y < zy) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: return nil
        }
    }
}
