import AppKit
import CoreGraphics
import FingerKitCore

/// Fare olaylarını sistemden önce görür (event tap; Erişilebilirlik izni gerekir).
///
/// 1. Trackpad'e 3-5 parmakla bastırma: hareket bağlıysa tıklama yutulur (altındaki şeye
///    tıklanmasın) ve kısayol gönderilir.
/// 2. "Dokunarak tıklama" açıkken 2 parmakla dokunmak sağ tık üretir. 2 parmak çift dokunma
///    bağlıysa bu sağ tık kısa süre bekletilir: ikinci dokunma gelirse atılır (sağ tık menüsü
///    açılmaz), gelmezse aynen geri gönderilir.
/// 3. Seçilen köşeye (varsayılan sol alt) tek parmakla tıklama daire menüyü açar; daire açıkken tıklamalar ona gider.
final class ClickInterceptor {
    private let engine: Engine
    private var tap: CFMachPort?
    private var swallowLeft = false
    private var swallowRight = false
    private var heldRight: [CGEvent] = []
    private var heldToken = 0
    /// Kendi gönderdiğimiz olayları (geri gönderilen sağ tık, kısayol yerine tıklama) tanımak için işaret
    static let replayMarker: Int64 = 0x746F_7563_686D_65

    init(engine: Engine) {
        self.engine = engine
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.write("tıklama yakalayıcı kurulamadı (izin yok?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("tıklama yakalayıcı çalışıyor")
        return true
    }

    /// 2 parmak çift dokunma çalıştı: bekletilen sağ tık atılır
    func dropHeldRightClick() {
        heldRight = []
        heldToken += 1
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return event }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event

        case .leftMouseDown:
            // Daire menü açıkken her tıklama dairenin: imlecin gösterdiği dilim seçilir
            if RadialMenu.shared.isShown {
                swallowLeft = true
                // İki parmakla tıklama bazen sağ tık değil sol tık olarak gelir (parmaklar aynı anda
                // değmeyince); daire açıkken o da sabitleme sayılır, dilimi açmaz
                let fingers = engine.clickContext()?.1.fingers ?? 0
                let twoFingers = fingers >= 2 || CACurrentMediaTime() - engine.lastTwoFingerTapAt < 0.3
                Log.write("daire açıkken tık: \(fingers) parmak\(twoFingers ? " → sabitleme" : "")")
                // Basış: dilim seçilir; yarım ay çubuğun üstündeyse sürükleme başlar (bırakınca biter)
                DispatchQueue.main.async { twoFingers ? RadialMenu.shared.rightClick() : RadialMenu.shared.mouseDown() }
                return nil
            }
            if let (recognizer, ctx) = engine.clickContext(), ctx.fingers == 1,
               engine.settings.radial.isCorner(x: ctx.x, y: ctx.y), engine.wantsRadialMenu {
                Log.write(String(format: "köşe tıklaması (%@, x %.2f, y %.2f) → daire menü", engine.settings.radial.corner.rawValue, ctx.x, ctx.y))
                recognizer.markClicked(consumed: true)
                swallowLeft = true
                DispatchQueue.main.async { [engine] in RadialMenu.shared.show(engine) }
                return nil
            }
            guard let (recognizer, ctx) = engine.clickContext(), ctx.fingers >= 3 else { return event }
            // 3 parmakla sürükleme açıkken parmaklar kayınca sistem kendisi "fare bas" üretir;
            // parmaklar kaydıysa bu bir sürüklemedir, dokunulmaz. Günlükte sürüklemeler 1,5 mm ve
            // üstünde, gerçek bastırmalar çoğunlukla 0,6 mm altında başladı.
            let isDrag = ctx.movement > 1.2
            let gesture = Gesture.click(fingers: ctx.fingers)
            let pressure = event.getDoubleValueField(.mouseEventPressure)
            let wanted = gesture.map(engine.isWanted) ?? false
            // FingerKit penceresi öndeyken bastırma yalnız gösterilir, tıklama geçer: başlıktan tutup
            // pencere 3 parmakla sürüklenebilsin. Hareket kaydı sırasında yine yutulur.
            let showOnly = NSApp.isActive && engine.recording == nil
            let note = isDrag ? " (sürükleme sayıldı)"
                : !wanted ? " (bu uygulamada bağlı hareket yok)"
                : showOnly ? " (pencere önde, tıklama geçti)" : ""
            Log.write(String(format: "bastırma: %d parmak, kayma %.1f mm, basınç %.2f [%@]%@",
                             ctx.fingers, ctx.movement, pressure, engine.frontBundleID ?? "?", note))
            guard let gesture, !isDrag, wanted, !showOnly else {
                recognizer.markClicked(consumed: false)
                if let gesture, !isDrag, showOnly { engine.fire(gesture) }
                return event
            }
            recognizer.markClicked(consumed: true)
            swallowLeft = true
            engine.fire(gesture)
            return nil

        case .leftMouseDragged:
            guard swallowLeft else { return event }
            // Daire açıkken basılı sürükleme ses/parlaklık çubuğunu değiştirir
            if RadialMenu.shared.isShown {
                let dx = CGFloat(event.getDoubleValueField(.mouseEventDeltaX))
                let dy = CGFloat(event.getDoubleValueField(.mouseEventDeltaY))
                DispatchQueue.main.async { RadialMenu.shared.drag(dx: dx, dy: dy) }
            }
            return nil

        case .scrollWheel:
            // Daire açıkken ses/parlaklık diliminde iki parmakla kaydırma değeri değiştirir
            return RadialMenu.shared.isShown && RadialMenu.shared.scroll(event) ? nil : event

        case .leftMouseUp:
            if swallowLeft {
                swallowLeft = false
                DispatchQueue.main.async { RadialMenu.shared.mouseUp() }
                return nil
            }
            return event

        case .rightMouseDown:
            // Daire açıkken sağ tık (2 parmak tıklama) imlecin gösterdiği dilimi sabitler
            if RadialMenu.shared.isShown {
                swallowRight = true
                DispatchQueue.main.async { RadialMenu.shared.rightClick() }
                return nil
            }
            // 2 parmakla bastırma: sistem bunu sağ tık yapar. Hareket bağlıysa sağ tık yutulur.
            // FingerKit penceresi öndeyken yalnız kayıt sırasında yakalanır, yoksa pencerede sağ tık kalmaz.
            if let (recognizer, ctx) = engine.clickContext(), ctx.fingers == 2 {
                let wanted = engine.recording != nil || (!NSApp.isActive && engine.isWanted(.twoFingerClick))
                Log.write(String(format: "bastırma: 2 parmak, kayma %.1f mm [%@]%@",
                                 ctx.movement, engine.frontBundleID ?? "?", wanted ? "" : " (sağ tık olarak geçti)"))
                guard wanted else {
                    recognizer.markClicked(consumed: false)
                    return event
                }
                recognizer.markClicked(consumed: true)
                swallowRight = true
                engine.fire(.twoFingerClick)
                return nil
            }
            let now = CACurrentMediaTime()
            // Yalnız az önce biten 2 parmak dokunuşundan gelen sağ tıklar (bastırarak sağ tık değil)
            guard engine.isWanted(.twoFingerDoubleTap), now - engine.lastTwoFingerTapAt < 0.25 else { return event }
            swallowRight = true
            if now - engine.lastDoubleTapAt < 0.4 {
                // Çift dokunmanın ikinci sağ tıkı
                heldRight = []
                return nil
            }
            heldRight = [event.copy()].compactMap { $0 }
            heldToken += 1
            let token = heldToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.replayHeld(token) }
            return nil

        case .rightMouseDragged:
            return swallowRight ? nil : event

        case .rightMouseUp:
            if swallowRight {
                swallowRight = false
                if !heldRight.isEmpty, let copy = event.copy() { heldRight.append(copy) }
                return nil
            }
            return event

        default:
            return event
        }
    }

    /// İkinci dokunma gelmedi: bekletilen sağ tık olduğu gibi geri gönderilir
    private func replayHeld(_ token: Int) {
        guard token == heldToken, !heldRight.isEmpty else { return }
        // Bırakma henüz gelmediyse gerçeği geçsin
        swallowRight = false
        for e in heldRight {
            e.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            e.post(tap: .cgSessionEventTap)
        }
        heldRight = []
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<ClickInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    guard let result = interceptor.handle(type, event) else { return nil }
    return Unmanaged.passUnretained(result)
}
