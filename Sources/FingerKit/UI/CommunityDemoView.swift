import AppKit
import SwiftUI
import FingerKitCore

/// Bir önerinin canlı örneği: Mac ekran kaydı gibi, GIF gibi kısa ve sık tekrar eder. Kutunun tamamı masaüstü
/// (duvar kâğıdı, menü çubuğu, Dock, tarayıcıda FingerKit'in sayfası). Ekran trackpad gibi davranır: büyük mavi
/// parmaklar hareketi yapar, aynı anda kısayol (⌘M) belirir, pencere hemen sonucu gösterir, altta tek cümle adı yazar.
/// Bir yeri işaretlemek gerekiyorsa (orta tık, daire menü, pencere taşıma) Mac'in kendi imleci de görünür.
/// Klavye kısayollarında parmak yerine yalnız tuşlar belirir. Fare üstündeyken oynar. Video değil, çizim.
struct CommunityDemoView: View {
    let demo: CommunityDemo
    /// Kısayol yazısı ("⌘M", "⇪ + S"); yoksa çıkmaz
    var chip: String?
    /// Altta tek cümle
    var caption: String?
    /// Daire menü örneklerinde seçilen dilimin adı (dairenin ortasında yazar)
    var slice: String?
    var playing: Bool
    /// Yalnız resme çizerken: döngüdeki sabit an (saniye)
    var frozenAt: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// Caps Lock + oklar paketinde her yön bu kadar sürer; yönler sırayla oynar
    static let snapStep = 2.6
    static let snapSteps: [(key: String, layout: SnapLayout)] = [("←", .left), ("→", .right), ("↑", .top), ("↓", .bottom)]

    var body: some View {
        Group {
            // Oynamayan örnek bir kez resme çizilir ve o resim gösterilir: sayfa kayarken ya da şerit
            // yana giderken her karede baştan çizmek takılma yapıyordu
            if frozenAt == nil && (!playing || reduceMotion) {
                DemoStill(demo: demo, chip: chip, caption: caption, slice: slice)
            } else {
                live
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: max(UIStyle.card - 8, 6), style: .continuous))
        .onChange(of: playing) { _, on in if on { start = Date() } }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var live: some View {
        let timing = DemoTiming(demo)
        let cursors = DemoCursors.shared
        let cycle = demo.effect == .snapAll ? Self.snapStep * Double(Self.snapSteps.count) : timing.cycle
        TimelineView(.animation(paused: !playing || reduceMotion)) { context in
            let time = frozenAt ?? (playing && !reduceMotion
                ? context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
                : timing.still)
            Canvas { ctx, size in
                if demo.effect == .snapAll {
                    // Dört yön sırayla: her biri tek tuşlu yaslama örneği gibi, biraz hızlı oynar
                    let moving = playing && !reduceMotion || frozenAt != nil
                    let i = moving ? min(Int(time / Self.snapStep), Self.snapSteps.count - 1) : 0
                    let step = Self.snapSteps[i]
                    let one = CommunityDemo(.keys(["⇪", step.key]), .snap(step.layout))
                    let local = moving ? (time - Double(i) * Self.snapStep) * (DemoTiming(one).cycle / Self.snapStep) : timing.still
                    DemoPainter(demo: one, chip: moving ? "⇪ + \(step.key)" : chip,
                                caption: moving ? "\(step.layout.title)  ·  \(i + 1)/\(Self.snapSteps.count)" : caption,
                                slice: nil, time: local, timing: DemoTiming(one), size: size, cursors: cursors).draw(&ctx)
                } else {
                    DemoPainter(demo: demo, chip: chip, caption: caption, slice: slice, time: time, timing: timing,
                                size: size, cursors: cursors).draw(&ctx)
                }
            }
        }
    }
}

/// Oynamayan örneğin duran karesi: boyut ve ekran çözünürlüğüne göre bir kez çizilip saklanır
private struct DemoStill: View {
    let demo: CommunityDemo
    let chip: String?
    let caption: String?
    let slice: String?
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { g in
            if let image = image(g.size) {
                Image(decorative: image, scale: scale)
                    .resizable()
            }
        }
    }

    @MainActor
    private func image(_ size: CGSize) -> CGImage? {
        let w = size.width.rounded(), h = size.height.rounded()
        guard w >= 1, h >= 1 else { return nil }
        let key = "\(demo.hashValue)|\(chip ?? "")|\(caption ?? "")|\(slice ?? "")|\(w)x\(h)@\(scale)" as NSString
        if let hit = Self.cache.object(forKey: key) { return (hit as! CGImage) }
        let view = CommunityDemoView(demo: demo, chip: chip, caption: caption, slice: slice,
                                     playing: false, frozenAt: DemoTiming(demo).still)
            .frame(width: w, height: h)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        Self.cache.setObject(image, forKey: key)
        return image
    }

    @MainActor private static let cache: NSCache<NSString, AnyObject> = {
        let cache = NSCache<NSString, AnyObject>()
        cache.countLimit = 200
        return cache
    }()
}

/// Bağlantı üstündeki el: Mac'in kendi imleç resmi, gerçek boyutuyla. Ok imlecinin resmi sistemden
/// alınamıyor (boş gelir); o yüzden ok, Mac'inkiyle aynı biçimde çizilir (`drawArrow`).
struct DemoCursors {
    var hand: Image
    var handSize: CGSize
    var handHotSpot: CGPoint

    @MainActor static let shared = DemoCursors(hand: Image(nsImage: NSCursor.pointingHand.image),
                                               handSize: NSCursor.pointingHand.image.size,
                                               handHotSpot: NSCursor.pointingHand.hotSpot)
}

/// Zamanlama (saniye). Döngü kısa (~4 sn), GIF gibi: parmaklar belirir → hemen hareket eder, kısayol aynı anda
/// çıkar → sonuç hızla (0,35 sn) gelir → alt yazı. İmleçli örneklerde önce imleç yerine gider, sonra tıklar.
struct DemoTiming {
    enum Mode { case gesture, keys, cursor, radial }
    var mode: Mode
    var cycle: Double
    var fingersIn: Double
    var fingersOut: Double
    var motionStart: Double
    var motionLength: Double
    var chipIn: Double
    var chipOut: Double
    var effectStart: Double
    var captionIn: Double
    var reset: Double
    /// Oynamıyorken gösterilen an: ne yapılacağı ve kısayol görünür
    var still: Double
    /// İmlecin hedefe (bağlantı, dilim) vardığı an
    var cursorArrive = 0.0
    /// İmlecin tıkladığı an (tık halkası)
    var click = Double.infinity
    /// Daire menünün açıldığı an
    var radialOpen = Double.infinity
    static let effectLength = 0.35

    init(_ demo: CommunityDemo) {
        switch demo.input {
        case .keys:
            mode = .keys
            cycle = 3.5; fingersIn = .infinity; fingersOut = .infinity; motionStart = 0.2; motionLength = 0.9
            chipIn = 0.2; chipOut = 2.4; effectStart = 0.65; captionIn = 0.85; reset = 2.8; still = 0.6
        case .hyperDrag:
            mode = .cursor
            cycle = 4.0; fingersIn = 0.2; fingersOut = 1.9; motionStart = 0.5; motionLength = 1.1
            chipIn = 0.2; chipOut = 2.9; effectStart = 0.5; captionIn = 1.2; reset = 3.2; still = 1.0
        case .gesture(.cornerTapBottomLeft):
            // Köşeye tık → daire imlecin yanında açılır → imleç dilime gider, dilim yanar → tık → sonuç
            mode = .radial
            cycle = 4.8; fingersIn = 0.1; fingersOut = 0.95; motionStart = 0.35; motionLength = 0.9
            radialOpen = 0.45; cursorArrive = 1.1; chipIn = 1.1; chipOut = 3.5
            reset = 4.0; still = 1.35
            if demo.effect == .radialMenu {
                effectStart = radialOpen; captionIn = 1.2
            } else {
                click = 1.55; effectStart = 1.65; captionIn = 1.9
            }
            if case .control(let control) = demo.effect {
                // Daire açık kalır; çubukta bas-sürükle, AirDrop'ta seçim halkası açılır, ikinci tık seçer
                cycle = 5.0; chipOut = 3.9; reset = 4.2
                if control.kind == .slider {
                    // Basılı tutulur: çubuk önce iner, sonra çıkar (azalıp çoğalır)
                    effectStart = 1.6; captionIn = 2.0
                    cycle = 6.6; chipOut = 5.6; reset = 5.8
                }
            }
        case .gesture where demo.effect == .newTabFromLink:
            // İmleç bağlantıya gelir, el olur → parmaklar tıklar, halka → yeni sekme büyüyerek açılır
            mode = .cursor
            cycle = 4.4; cursorArrive = 0.75; fingersIn = 0.8; click = 1.05; motionStart = 1.05; motionLength = 0.9
            chipIn = 1.05; effectStart = 1.2; captionIn = 1.5; fingersOut = 1.8; chipOut = 3.1; reset = 3.6; still = 1.3
        case .gesture:
            mode = .gesture
            cycle = 4.0; fingersIn = 0.15; fingersOut = 1.7; motionStart = 0.45; motionLength = 0.9
            chipIn = 0.45; chipOut = 2.9; effectStart = 0.7; captionIn = 1.1; reset = 3.3; still = 0.62
        }
    }
}

/// Bir anlık kareyi çizer. Ölçüler kutunun genişliğine (`W`) ve yüksekliğine (`H`) göre oranla verilir.
struct DemoPainter {
    let demo: CommunityDemo
    let chip: String?
    let caption: String?
    let slice: String?
    let time: Double
    let timing: DemoTiming
    let size: CGSize
    let cursors: DemoCursors

    // Sabit renkler: çizim açık ve koyu temada aynı görünür (gerçek bir ekran gibi)
    let orange = Color(red: 1, green: 149 / 255, blue: 0)
    let blue = Color(red: 0.04, green: 0.52, blue: 1)
    /// Parmak rengi: altın sarısı (üstte açık, altta koyu bal tonu)
    let gold = Color.fingerGold
    let goldLight = Color.fingerGoldLight
    let goldDeep = Color.fingerGoldDeep
    let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    let line = Color(red: 0.85, green: 0.85, blue: 0.87)
    /// Seçili dilim, odaklı alan: Mac'in vurgu rengi (tık halkası parmaklar gibi sarı)
    let accent = Color.accentColor

    var W: Double { size.width }
    var H: Double { size.height }

    // MARK: Zaman

    /// a anından itibaren `length` sürede 0'dan 1'e
    func ramp(_ a: Double, _ length: Double) -> Double { clamp((time - a) / length) }
    /// Belirir, durur, kaybolur
    func window(_ a: Double, _ b: Double, fade: Double = 0.3) -> Double { ramp(a, fade) * (1 - ramp(b, fade)) }

    var effectStart: Double { timing.effectStart }
    /// Ekrandaki sonuç: hızla gelir, sonda geri döner
    var effect: Double {
        easeOut(ramp(effectStart, DemoTiming.effectLength)) * (1 - ease(ramp(timing.reset, DemoTiming.effectLength)))
    }
    /// Parmakların yolu (0-1)
    var motion: Double { ramp(timing.motionStart, timing.motionLength) }

    // MARK: Yerleşim

    var menuBarHeight: Double { H * 0.042 }
    /// Menü çubuğunun altındaki masaüstü
    var desk: CGRect { CGRect(x: 0, y: menuBarHeight, width: W, height: H - menuBarHeight) }
    var safariFrame: CGRect { CGRect(x: W * 0.13, y: H * 0.09, width: W * 0.74, height: H * 0.74) }
    var dockIcon: Double { W * 0.042 }
    var dockFrame: CGRect {
        let gap = W * 0.009, pad = W * 0.008
        let width = dockIcon * 8 + gap * 7 + pad * 2
        let height = dockIcon + pad * 2
        return CGRect(x: (W - width) / 2, y: H * 0.988 - height, width: width, height: height)
    }

    // MARK: Çizim

    func draw(_ ctx: inout GraphicsContext) {
        // Ekran (masaüstü, pencere, imleç) değişen yere yakınlaşır; parmaklar, kısayol ve alt yazı yerinde kalır
        var screen = ctx
        let zoom = self.zoom
        if zoom.scale > 1 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            screen.translateBy(x: zoom.to.x, y: zoom.to.y)
            screen.scaleBy(x: zoom.scale, y: zoom.scale)
            screen.translateBy(x: -zoom.from.x, y: -zoom.from.y)
        }
        drawWallpaper(&screen)
        drawMenuBar(&screen)
        drawDock(&screen)
        drawScene(&screen)
        drawPointer(&screen)
        drawSpotlight(&ctx, zoom)
        drawInput(&ctx)
        drawChip(&ctx)
        drawCaption(&ctx)
    }

    // MARK: Odak: ne değişiyorsa o görünsün

    /// Sonucun ekranda değiştiği yer (yakınlaşılan alan) ve en çok ne kadar büyütüleceği; tüm ekranı
    /// değiştiren sonuçlarda (tam ekran, yaslama, kilit, uygulama açma…) yakınlaşma yok
    var focus: (rect: CGRect, maxZoom: Double)? {
        // Daire açılınca daireye yakınlaşılır: küçük önizlemede dilimler ve yazılar okunsun
        if timing.mode == .radial {
            let r = radialRadius * 1.04
            // Denetim Merkezi örneğinde yalnız üst yarıya (düğmelere) yakınlaşılır: ne yapıldığı net görünsün
            if case .control = demo.effect {
                return (CGRect(x: radialCenter.x - r, y: radialCenter.y - r, width: r * 2, height: r * 1.12), 2.8)
            }
            return (CGRect(x: radialCenter.x - r, y: radialCenter.y - r, width: r * 2, height: r * 2), 2.3)
        }
        let f = safariFrame
        let top = barHeight(f) + tabStripHeight(f)
        let page = pageRect(f)
        let content = CGRect(x: f.minX, y: f.minY + barHeight(f) * 0.8, width: f.width, height: f.height - barHeight(f) * 0.8)
        switch demo.effect {
        case .newTabFromLink, .closeTab, .quitGuard, .previousTab, .nextTab, .reopenTab, .newTab:
            return (CGRect(x: f.minX, y: f.minY, width: f.width * 0.62, height: top + page.height * 0.3), 1.6)
        case .addressBar:
            return (CGRect(x: f.minX + f.width * 0.22, y: f.minY, width: f.width * 0.56, height: barHeight(f) * 1.5), 2.2)
        case .copyText:
            let line = firstLine(in: page)
            return (CGRect(x: line.minX - page.width * 0.02, y: line.minY - page.height * 0.12,
                           width: page.maxX - line.minX, height: page.height * 0.3), 1.9)
        case .pasteText:
            let line = firstLine(in: page)
            return (CGRect(x: line.minX - line.height * 3, y: page.maxY - page.height * 0.36,
                           width: line.width + line.height * 6, height: page.height * 0.32), 2.0)
        case .pastePlain:
            let body = notesBody(content)
            return (CGRect(x: body.minX - body.width * 0.05, y: body.minY + body.height * 0.3, width: body.width * 1.1, height: body.height * 0.42), 2.0)
        case .app(let scene):
            let side = content.width * 0.22, cell = (content.width - side) / 4
            let editorX = content.minX + content.width * 0.27
            let editorW = content.maxX - editorX
            return switch scene {
            case .finderNewFolder:
                (CGRect(x: content.minX + side + cell * 0.6, y: content.minY + content.height * 0.06 + cell * 0.7, width: cell * 1.8, height: cell * 1.1), 1.9)
            case .finderHidden:
                (CGRect(x: content.minX + side + cell * 0.8, y: content.minY + content.height * 0.06 + cell * 0.75, width: cell * 3.2, height: cell), 1.6)
            case .finderGoTo:
                (CGRect(x: content.midX - content.width * 0.32, y: content.minY, width: content.width * 0.64, height: content.height * 0.36), 1.7)
            case .notesNew:
                (CGRect(x: content.minX, y: content.minY, width: content.width * 0.8, height: content.height * 0.4), 1.5)
            case .notesChecklist:
                (notesBody(content).insetBy(dx: -content.width * 0.03, dy: 0).divided(atDistance: content.height * 0.5, from: .minYEdge).slice, 1.6)
            case .codePalette:
                (CGRect(x: editorX + editorW * 0.15, y: content.minY, width: editorW * 0.7, height: content.height * 0.52), 1.6)
            case .codeTerminal:
                (CGRect(x: editorX, y: content.maxY - content.height * 0.5, width: editorW, height: content.height * 0.5), 1.4)
            case .codeSidebar:
                nil
            case .musicLike:
                (CGRect(x: content.minX, y: content.maxY - content.height * 0.22, width: content.width * 0.42, height: content.height * 0.22), 2.2)
            case .musicSearch:
                (CGRect(x: content.minX + content.width * 0.24, y: content.minY, width: content.width * 0.74, height: content.height * 0.6), 1.4)
            }
        default:
            return nil
        }
    }

    /// Yakınlaşmanın ne kadar ilerlediği (0-1): sonuçla birlikte gelir, sonuç geri dönmeden önce çıkar
    var zoomProgress: Double {
        guard focus != nil else { return 0 }
        if timing.mode == .radial {
            // Daireyle birlikte gelir, daire kapanırken çıkar
            let end = radialKeepsOpen ? timing.reset : timing.click + 0.05
            return ease(ramp(timing.radialOpen - 0.05, 0.45)) * (1 - ease(ramp(end - 0.1, 0.35)))
        }
        return ease(ramp(effectStart - 0.05, 0.4)) * (1 - ease(ramp(timing.reset - 0.4, 0.4)))
    }

    /// Ekranın hangi noktası (`from`) nereye (`to`) ne kadar büyüyerek gelir
    var zoom: (from: CGPoint, to: CGPoint, scale: Double, k: Double) {
        let k = zoomProgress
        guard let (rect, maxZoom) = focus, k > 0 else { return (.zero, .zero, 1, 0) }
        let radial = timing.mode == .radial
        let fit = max(1, min(maxZoom, W * (radial ? 0.94 : 0.8) / rect.width, H * (radial ? 0.88 : 0.52) / rect.height))
        let from = CGPoint(x: rect.midX, y: rect.midY)
        let target = CGPoint(x: W / 2, y: H * (radial ? 0.45 : 0.4))
        return (from, lerp(from, target, k), 1 + (fit - 1) * k, k)
    }

    /// Odak dışı kararır, odak alanı ince bir çerçeveyle ayrılır
    func drawSpotlight(_ ctx: inout GraphicsContext, _ zoom: (from: CGPoint, to: CGPoint, scale: Double, k: Double)) {
        guard zoom.k > 0, timing.mode != .radial, let (rect, _) = focus else { return }
        let r = CGRect(x: zoom.to.x + (rect.minX - zoom.from.x) * zoom.scale, y: zoom.to.y + (rect.minY - zoom.from.y) * zoom.scale,
                       width: rect.width * zoom.scale, height: rect.height * zoom.scale)
        let hole = Path(roundedRect: r, cornerRadius: W * 0.014)
        var dim = Path(CGRect(origin: .zero, size: size))
        dim.addPath(hole)
        ctx.fill(dim, with: .color(.black.opacity(0.55 * zoom.k)), style: FillStyle(eoFill: true))
        ctx.stroke(hole, with: .color(.white.opacity(0.55 * zoom.k)), lineWidth: 1)
    }

    /// Duvar kâğıdı: siyah; üstte çok hafif bir aydınlık, ekran boş görünmesin
    func drawWallpaper(_ ctx: inout GraphicsContext) {
        let all = Path(CGRect(origin: .zero, size: size))
        ctx.fill(all, with: .color(.black))
        ctx.fill(all, with: .radialGradient(Gradient(colors: [hex(0x1c1c20), .black]),
                                            center: CGPoint(x: W / 2, y: 0), startRadius: 0, endRadius: W * 0.75))
    }

    /// Menü çubuğu: yazılar küçük ölçekte okunmaz, onun yerine ince çizgiler
    func drawMenuBar(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: menuBarHeight)), with: .color(hex(0x1e1e32).opacity(0.35)))
        let h = max(0.8, menuBarHeight * 0.26)
        let y = menuBarHeight / 2 - h / 2
        var x = W * 0.016
        for (i, w) in [0.035, 0.026, 0.026, 0.032, 0.03, 0.034].enumerated() {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: W * w, height: h), cornerRadius: h / 2),
                     with: .color(.white.opacity(i == 0 ? 0.95 : 0.7)))
            x += W * w + W * 0.02
        }
        // Sağda pil ve saat
        let batt = CGRect(x: W * 0.84, y: menuBarHeight * 0.3, width: W * 0.022, height: menuBarHeight * 0.4)
        ctx.stroke(Path(roundedRect: batt, cornerRadius: 1), with: .color(.white.opacity(0.85)), lineWidth: 0.6)
        ctx.fill(Path(CGRect(x: batt.minX + 0.8, y: batt.minY + 0.8, width: batt.width * 0.6, height: batt.height - 1.6)),
                 with: .color(.white.opacity(0.85)))
        ctx.fill(Path(roundedRect: CGRect(x: W * 0.875, y: y, width: W * 0.1, height: h), cornerRadius: h / 2),
                 with: .color(.white.opacity(0.7)))
    }

    let dockColors: [(UInt32, UInt32)] = [
        (0x5ac8fa, 0x007aff), (0xffffff, 0xe6e6ea), (0xffd60a, 0xff9f0a), (0x34c759, 0x248a3d),
        (0xff6482, 0xff2d55), (0xbf5af2, 0x7d3cff), (0x1c1c1e, 0x050505), (0x98989d, 0x636366),
    ]

    func drawDock(_ ctx: inout GraphicsContext) {
        let dock = dockFrame
        let shape = Path(roundedRect: dock, cornerRadius: W * 0.016)
        ctx.fill(shape, with: .color(.white.opacity(0.22)))
        ctx.stroke(shape, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
        for (i, colors) in dockColors.enumerated() {
            let r = dockIconFrame(i)
            ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.22),
                     with: .linearGradient(Gradient(colors: [hex(colors.0), hex(colors.1)]),
                                           startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
    }

    func dockIconFrame(_ i: Int) -> CGRect {
        let dock = dockFrame
        let gap = W * 0.009, pad = W * 0.008
        return CGRect(x: dock.minX + pad + Double(i) * (dockIcon + gap), y: dock.minY + pad, width: dockIcon, height: dockIcon)
    }

    // MARK: Sahne

    func drawScene(_ ctx: inout GraphicsContext) {
        var frame = safariFrame
        var tabs = Tabs(count: 2, active: 0)
        var variant = 0
        var chrome = true

        switch demo.effect {
        case .newTabFromLink:
            tabs = Tabs(count: 2, active: 0, growing: effect)
        case .closeTab, .quitGuard:
            // Beyaz sekme kapanır, sağındaki koyu video sitesi öne gelir (Safari'deki gibi)
            tabs = Tabs(count: 3, active: 0, shrinking: effect)
            variant = effect > 0.5 ? 1 : 0
            if demo.effect == .quitGuard, time > effectStart - 0.35, time < effectStart {
                frame = frame.offsetBy(dx: sin(time * 90) * W * 0.006, dy: 0)
            }
        case .previousTab, .nextTab:
            // Beyaz ↔ koyu site: hangi sekmeye geçildiği ilk bakışta anlaşılır
            let from = demo.effect == .nextTab ? 0 : 1
            let target = demo.effect == .nextTab ? 1 : 0
            tabs = Tabs(count: 3, active: from, slideTo: Double(target), slide: effect)
            variant = effect > 0.5 ? target : from
        case .reopenTab:
            tabs = Tabs(count: 2, active: 0, growing: effect, growingActive: effect > 0.5)
            variant = effect > 0.5 ? 1 : 0
        case .newTab:
            // Boş sekme: başlangıç sayfası (sık ziyaret edilenler), adres çubuğu boş ve imleç yanıp söner
            tabs = Tabs(count: 2, active: 0, growing: effect, growingActive: effect > 0.5, growingSite: Site.startPage)
            variant = effect > 0.5 ? Site.startPage : 0
        case .fullScreen:
            frame = lerp(frame, CGRect(origin: .zero, size: size), effect)
            chrome = effect < 0.95
        case .snap(let layout):
            frame = lerp(frame, snapFrame(layout), effect)
        case .moveWindow:
            frame = movingFrame
        default:
            break
        }

        if case .app(let scene) = demo.effect {
            drawApp(&ctx, frame, scene)
        } else if demo.effect == .pastePlain {
            var c = ctx
            drawNotes(&c, frame, .notesChecklist, still: true)
        } else {
            drawSafari(&ctx, frame, tabs: tabs, variant: variant, chrome: chrome, focus: demo.effect == .addressBar ? effect : 0)
        }

        if timing.mode == .radial {
            let open = ease(ramp(timing.radialOpen, 0.25))
            let close = radialKeepsOpen ? ramp(timing.reset, 0.3) : ramp(timing.click + 0.05, 0.15)
            if open * (1 - close) > 0 {
                drawRadial(&ctx, center: radialCenter, progress: open * (1 - close),
                           lit: time > timing.cursorArrive - 0.1 ? litSlice : nil)
            }
        }

        switch demo.effect {
        case .screenshot:
            if effect > 0 { drawScreenshot(&ctx, frame: frame, tabs: tabs, variant: variant) }
        case .lock:
            if effect > 0 {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.85 * effect)))
                drawSymbol(&ctx, "lock.fill", at: CGPoint(x: W / 2, y: H * 0.42), size: W * 0.08, color: .white.opacity(effect))
            }
        case let .openApp(symbol, hue):
            if effect > 0 {
                // Uygulama Dock'tan büyüyerek gelir
                let from = dockIconFrame(3)
                let f = lerp(from, CGRect(x: W * 0.2, y: H * 0.14, width: W * 0.6, height: H * 0.64), effect)
                drawAppWindow(&ctx, f, symbol: symbol, hue: hue, opacity: min(1, effect * 2))
            }
        case .clipboardList:
            if effect > 0 { drawClipboard(&ctx, opacity: min(1, effect * 2), scale: 0.92 + 0.08 * effect) }
        case .pastePlain:
            drawPaste(&ctx, in: frame)
        case .copyText:
            drawCopy(&ctx, in: pageRect(frame))
        case .pasteText:
            drawPasteHere(&ctx, in: pageRect(frame))
        case .control(let control):
            drawControlResult(&ctx, control)
        default:
            break
        }
    }

    /// Denetim Merkezi düğmesinin ekrandaki sonucu: menü çubuğu simgesi, ses göstergesi, kararan ekran, koyu pencere
    func drawControlResult(_ ctx: inout GraphicsContext, _ control: SystemControl) {
        let k = effect
        let bar = CGPoint(x: W * 0.8, y: menuBarHeight / 2)
        let icon = menuBarHeight * 0.62
        switch control {
        case .bluetooth, .wifi:
            // Menü çubuğundaki simge söner
            let alpha = 0.95 - 0.7 * k
            if control == .bluetooth {
                let h = icon, w = h * 0.6
                ctx.fill(DrawnGlyph.bluetooth(in: CGRect(x: bar.x - w / 2, y: bar.y - h / 2, width: w, height: h)),
                         with: .color(.white.opacity(alpha)))
            } else {
                drawSymbol(&ctx, k > 0.5 ? "wifi.slash" : "wifi", at: bar, size: icon, color: .white.opacity(alpha))
            }
        case .focus:
            // Ay simgesi menü çubuğunda belirir, üstte "Rahatsız Etme" bildirimi kayar
            drawSymbol(&ctx, "moon.fill", at: bar, size: icon * 0.9, color: .white.opacity(0.95 * k))
            if k > 0 {
                let banner = CGRect(x: W * 0.66, y: menuBarHeight + H * 0.02 - H * 0.04 * (1 - k), width: W * 0.31, height: H * 0.09)
                ctx.opacity = k
                ctx.fill(Path(roundedRect: banner, cornerRadius: banner.height * 0.3), with: .color(hex(0x2c2c30).opacity(0.95)))
                drawSymbol(&ctx, "moon.fill", at: CGPoint(x: banner.minX + banner.height * 0.5, y: banner.midY), size: banner.height * 0.4, color: hex(0xbf5af2))
                ctx.draw(Text(SystemControl.focus.title).font(.system(size: banner.height * 0.3, weight: .semibold)).foregroundStyle(.white),
                         at: CGPoint(x: banner.minX + banner.height * 0.95, y: banner.midY), anchor: .leading)
                ctx.opacity = 1
            }
        case .darkMode:
            // Pencere koyulaşır
            if k > 0 {
                let f = safariFrame
                ctx.fill(Path(roundedRect: f, cornerRadius: W * 0.012), with: .color(hex(0x1c1c1e).opacity(0.88 * k)))
                bars(&ctx, x: f.minX + f.width * 0.08, y: f.minY + f.height * 0.3, widths: [0.5, 0.62, 0.4, 0.55].map { $0 * f.width },
                     height: f.height * 0.03, step: f.height * 0.08, color: .white.opacity(0.35 * k))
            }
        case .volume:
            // Mac'in ses göstergesi sağ üstte: hoparlör ve çubuk
            let a = window(timing.click, timing.reset, fade: 0.2)
            if a > 0 {
                let hud = CGRect(x: W * 0.7, y: menuBarHeight + H * 0.02, width: W * 0.27, height: H * 0.1)
                ctx.opacity = a
                ctx.fill(Path(roundedRect: hud, cornerRadius: hud.height * 0.3), with: .color(hex(0x2c2c30).opacity(0.95)))
                drawSymbol(&ctx, "speaker.wave.2.fill", at: CGPoint(x: hud.minX + hud.height * 0.45, y: hud.midY), size: hud.height * 0.32, color: .white)
                let track = CGRect(x: hud.minX + hud.height * 0.85, y: hud.midY - hud.height * 0.07, width: hud.width - hud.height * 1.1, height: hud.height * 0.14)
                ctx.fill(Path(roundedRect: track, cornerRadius: track.height / 2), with: .color(.white.opacity(0.25)))
                ctx.fill(Path(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * sliderLevel, height: track.height), cornerRadius: track.height / 2),
                         with: .color(.white))
                ctx.opacity = 1
            }
        case .brightness:
            // Ekran kısılır
            let dim = (0.82 - sliderLevel) * 0.9
            if dim > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(dim))) }
        case .airDrop:
            // Seçimden sonra telefon ekrana gelen dosyayı alır gibi: AirDrop simgesi parlar
            if k > 0 {
                let p = CGPoint(x: W * 0.84, y: menuBarHeight + H * 0.09)
                let d = W * 0.05 * (0.8 + 0.2 * k)
                ctx.fill(DrawnGlyph.airDrop(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(gold.opacity(k)))
            }
        case .screenMirroring:
            break
        }
    }

    /// Mac'teki gibi: seçim çizilir, deklanşör parlar, çekilen resim küçülerek sağ alt köşeye gider ve orada durur
    func drawScreenshot(_ ctx: inout GraphicsContext, frame: CGRect, tabs: Tabs, variant: Int) {
        let shotAt = effectStart + 0.55
        let sel = CGRect(x: W * 0.24, y: H * 0.22, width: W * 0.5, height: H * 0.42)
        if time < shotAt + 0.1 {
            let from = CGRect(x: sel.minX, y: sel.minY, width: 1, height: 1)
            let r = lerp(from, sel, clamp(ramp(effectStart, 0.45) * 1.1))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.18)))
            ctx.fill(Path(r), with: .color(.white.opacity(0.16)))
            ctx.stroke(Path(r), with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            drawSymbol(&ctx, "plus", at: CGPoint(x: r.maxX, y: r.maxY), size: W * 0.035, color: .white)
        }
        let flash = window(shotAt, shotAt + 0.12, fade: 0.07)
        if flash > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.75 * flash))) }
        guard time > shotAt else { return }
        let fly = ease(ramp(shotAt + 0.1, 0.5))
        let tw = W * 0.26
        let corner = CGRect(x: W - tw - W * 0.025, y: desk.maxY - tw * sel.height / sel.width - H * 0.2,
                            width: tw, height: tw * sel.height / sel.width)
        let thumb = lerp(sel, corner, fly)
        var c = ctx
        c.opacity = effect
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.5), radius: W * 0.02, y: W * 0.008))
        shadow.fill(Path(roundedRect: thumb, cornerRadius: W * 0.008), with: .color(.white))
        // İçinde çekilen alanın küçültülmüş hali
        var inside = c
        inside.clip(to: Path(roundedRect: thumb.insetBy(dx: 1.5, dy: 1.5), cornerRadius: W * 0.007))
        inside.translateBy(x: thumb.minX, y: thumb.minY)
        inside.scaleBy(x: thumb.width / sel.width, y: thumb.height / sel.height)
        inside.translateBy(x: -sel.minX, y: -sel.minY)
        drawWallpaper(&inside)
        drawSafari(&inside, frame, tabs: tabs, variant: variant, chrome: true)
    }

    /// Caps Lock + kaydır: küçük pencere parmakla birlikte sağ alta kayar
    var movingFrame: CGRect {
        let small = CGRect(x: W * 0.06, y: H * 0.1, width: W * 0.56, height: H * 0.56)
        return lerp(small, small.offsetBy(dx: W * 0.32, dy: H * 0.2), ease(motion) * (1 - ease(ramp(timing.reset, 0.4))))
    }

    func snapFrame(_ layout: SnapLayout) -> CGRect {
        let d = desk
        return switch layout {
        case .left: CGRect(x: 0, y: d.minY, width: W / 2, height: d.height)
        case .right: CGRect(x: W / 2, y: d.minY, width: W / 2, height: d.height)
        case .top: CGRect(x: 0, y: d.minY, width: W, height: d.height / 2)
        case .bottom: CGRect(x: 0, y: d.midY, width: W, height: d.height / 2)
        case .fill: d
        }
    }

    /// Sekme çubuğunun durumu
    struct Tabs {
        var count: Int
        var active: Int
        /// Sona eklenen sekme (0: yok, 1: tam boy)
        var growing = 0.0
        var growingActive = false
        /// Etkin sekme kapanıyor (0-1)
        var shrinking = 0.0
        var slideTo: Double? = nil
        var slide = 0.0
        /// Eklenen sekmenin sitesi (yoksa sırasındaki site)
        var growingSite: Int? = nil
    }

    func barHeight(_ f: CGRect) -> Double { min(f.height * 0.09, H * 0.075) }
    func tabStripHeight(_ f: CGRect) -> Double { min(f.height * 0.065, H * 0.05) }
    func pageRect(_ f: CGRect) -> CGRect {
        let top = barHeight(f) + tabStripHeight(f)
        return CGRect(x: f.minX, y: f.minY + top, width: f.width, height: f.height - top)
    }

    /// Safari'ye benzeyen pencere: kırmızı/sarı/yeşil düğmeler, adres çubuğu, sekmeler, FingerKit'in sayfası
    /// `focus`: adres çubuğu seçili (0-1): mavi çerçeve, adres seçili
    func drawSafari(_ ctx: inout GraphicsContext, _ f: CGRect, tabs: Tabs, variant: Int, chrome: Bool, focus: Double = 0) {
        let radius = chrome ? min(f.width * 0.014, 6) : 0
        let path = Path(roundedRect: f, cornerRadius: radius)
        let site = Site.at(variant)
        let dark = site.dark
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: W * 0.03, y: W * 0.012))
        shadow.fill(path, with: .color(dark ? hex(0x0f0f0f) : hex(0xfbfbfd)))
        var c = ctx
        c.clip(to: path)
        let barH = barHeight(f)
        c.fill(Path(CGRect(x: f.minX, y: f.minY, width: f.width, height: barH)), with: .color(dark ? hex(0x2a2a2d) : hex(0xececf0)))
        // Pencere düğmeleri
        let dot = barH * 0.3
        var x = f.minX + f.width * 0.02
        for color in [hex(0xff5f57), hex(0xfebc2e), hex(0x28c840)] {
            c.fill(Path(ellipseIn: CGRect(x: x, y: f.minY + barH / 2 - dot / 2, width: dot, height: dot)), with: .color(color))
            x += dot * 1.7
        }
        // Adres çubuğu
        let addr = CGRect(x: f.minX + f.width * 0.27, y: f.minY + barH * 0.22, width: f.width * 0.46, height: barH * 0.56)
        c.fill(Path(roundedRect: addr, cornerRadius: addr.height * 0.3), with: .color(dark ? hex(0x3a3a3e) : .white))
        c.stroke(Path(roundedRect: addr, cornerRadius: addr.height * 0.3), with: .color(dark ? hex(0x48484c) : hex(0xdedee3)), lineWidth: 0.5)
        let url = c.resolve(Text(verbatim: site.url).font(.system(size: max(3, addr.height * 0.55), weight: .medium))
            .foregroundStyle(focus > 0.5 ? ink : (dark ? hex(0xd0d0d4) : hex(0x555555))))
        if focus > 0 {
            // Seçili adres: Mac'teki gibi vurgu renginde çerçeve ve seçim
            let ts = url.measure(in: addr.size)
            c.fill(Path(roundedRect: CGRect(x: addr.midX - ts.width / 2 - 1, y: addr.midY - ts.height / 2, width: ts.width + 2, height: ts.height),
                        cornerRadius: 1.5), with: .color(accent.opacity(0.35 * focus)))
            c.stroke(Path(roundedRect: addr.insetBy(dx: -1, dy: -1), cornerRadius: addr.height * 0.32),
                     with: .color(accent.opacity(focus)), lineWidth: 1.6)
        }
        c.draw(url, at: CGPoint(x: addr.midX, y: addr.midY))
        if site.url.isEmpty, sin(time * 9) > 0 {
            c.fill(Path(CGRect(x: addr.minX + addr.width * 0.05, y: addr.minY + addr.height * 0.2, width: 1, height: addr.height * 0.6)),
                   with: .color(accent))
            c.stroke(Path(roundedRect: addr.insetBy(dx: -1, dy: -1), cornerRadius: addr.height * 0.32), with: .color(accent), lineWidth: 1.6)
        }
        drawTabs(&c, f, tabs: tabs, dark: dark)
        drawPage(&c, pageRect(f), variant: variant)
    }

    func drawTabs(_ ctx: inout GraphicsContext, _ f: CGRect, tabs: Tabs, dark: Bool) {
        let strip = CGRect(x: f.minX, y: f.minY + barHeight(f), width: f.width, height: tabStripHeight(f))
        ctx.fill(Path(strip), with: .color(dark ? hex(0x1d1d20) : hex(0xe1e1e6)))
        var widths = Array(repeating: 1.0, count: tabs.count)
        if tabs.shrinking > 0 { widths[tabs.active] = 1 - tabs.shrinking }
        if tabs.growing > 0 { widths.append(tabs.growing) }
        var active = Double(tabs.active)
        if tabs.shrinking >= 1 { active = Double(min(widths.count - 1, tabs.active + 1)) }
        if let to = tabs.slideTo { active += (to - active) * tabs.slide }
        if tabs.growingActive { active = Double(widths.count - 1) }
        let full = min(f.width / 4, W * 0.16)
        var tx = strip.minX + f.width * 0.01
        var positions: [CGRect] = []
        for w in widths {
            positions.append(CGRect(x: tx, y: strip.minY + strip.height * 0.12, width: full * w, height: strip.height * 0.76))
            tx += full * w + 1
        }
        // Her sekme ayrı bir site, kendi renginde: hangisinin açılıp kapandığı rengiyle anlaşılır
        for (i, r) in positions.enumerated() where r.width > 1 {
            let on = i == Int(active.rounded())
            let site = i == positions.count - 1 && tabs.growing > 0 && tabs.growingSite != nil
                ? Site.at(tabs.growingSite!) : Site.all[i % Site.all.count]
            let shape = Path(roundedRect: r, cornerRadius: r.height * 0.25)
            ctx.fill(shape, with: .color(dark ? (on ? hex(0x3a3a3e) : hex(0x2a2a2d)) : (on ? .white : hex(0xd3d3d9))))
            ctx.fill(shape, with: .color(site.color.opacity(on ? 0.28 : 0.5)))
            let icon = r.height * 0.5
            let iconRect = CGRect(x: r.minX + r.height * 0.3, y: r.midY - icon / 2, width: min(icon, r.width * 0.3), height: icon)
            ctx.fill(Path(roundedRect: iconRect, cornerRadius: icon * 0.25), with: .color(site.color))
            let bar = r.height * 0.2
            let bx = iconRect.maxX + r.height * 0.25
            ctx.fill(Path(roundedRect: CGRect(x: bx, y: r.midY - bar / 2, width: max(0, r.maxX - bx - r.height * 0.4), height: bar),
                          cornerRadius: bar / 2), with: .color(dark ? .white.opacity(on ? 0.6 : 0.35) : .black.opacity(on ? 0.45 : 0.3)))
        }
        // Etkin sekmenin altındaki çizgi kayarken
        if let lo = positions[safe: Int(active)], let hi = positions[safe: min(positions.count - 1, Int(active) + 1)] {
            let r = lerp(lo, hi, active - Double(Int(active)))
            ctx.fill(Path(CGRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1)), with: .color(blue))
        }
    }

    /// Önizlemedeki üç site: FingerKit'in sayfası (beyaz), koyu bir video sitesi, mavi bir haber sitesi.
    /// Sekme değişince ekran beyazdan siyaha döner; ne olduğu ilk bakışta anlaşılır. Markasız; adresler örnek alan adı.
    struct Site {
        var url: String
        var color: Color
        var dark = false
        static let all = [
            Site(url: "github.com/enisaytac/FingerKit", color: hex(0x1c1c1e)),
            Site(url: "video.example.com", color: hex(0xe5322d), dark: true),
            Site(url: "news.example.com", color: hex(0x2f6bff)),
        ]
        /// Yeni boş sekmenin başlangıç sayfası
        static let startPage = 3
        static let start = Site(url: "", color: hex(0x8e8e93))
        static func at(_ variant: Int) -> Site { variant == startPage ? start : all[variant % all.count] }
    }

    /// Sayfanın içi. `variant` sekmenin sitesi: 0 FingerKit, 1 koyu video sitesi, 2 mavi site.
    func drawPage(_ ctx: inout GraphicsContext, _ r: CGRect, variant: Int) {
        guard r.height > H * 0.12 else { return }
        if variant == Site.startPage { drawStartPage(&ctx, r); return }
        let site = Site.at(variant)
        if site.dark { drawVideoSite(&ctx, r, site: site); return }
        if variant % Site.all.count != 0 { drawColorSite(&ctx, r, site: site); return }
        let pad = r.width * 0.06
        let titleSize = max(4, min(W * 0.028, r.height * 0.075))
        let top = r.minY + r.height * 0.07
        let icon = CGRect(x: r.minX + pad, y: top, width: titleSize * 1.5, height: titleSize * 1.5)
        ctx.fill(Path(roundedRect: icon, cornerRadius: icon.width * 0.22),
                 with: .linearGradient(Gradient(colors: [hex(0x1c1c1e), hex(0x050505)]),
                                       startPoint: CGPoint(x: icon.midX, y: icon.minY), endPoint: CGPoint(x: icon.midX, y: icon.maxY)))
        drawLogo(&ctx, in: icon.insetBy(dx: icon.width * 0.2, dy: icon.width * 0.28))
        ctx.draw(Text(verbatim: "FingerKit").font(.system(size: titleSize, weight: .bold)).foregroundStyle(ink),
                 at: CGPoint(x: icon.maxX + titleSize * 0.5, y: icon.midY), anchor: .leading)
        let starText = ctx.resolve(Text("★ " + String(localized: "Yıldız ver")).font(.system(size: titleSize * 0.55, weight: .semibold))
            .foregroundStyle(ink))
        let textSize = starText.measure(in: CGSize(width: r.width, height: r.height))
        let star = CGRect(x: r.maxX - pad - textSize.width - titleSize * 0.9, y: icon.midY - titleSize * 0.55,
                          width: textSize.width + titleSize * 0.9, height: titleSize * 1.1)
        ctx.fill(Path(roundedRect: star, cornerRadius: star.height * 0.25), with: .color(hex(0xf6f6f8)))
        ctx.stroke(Path(roundedRect: star, cornerRadius: star.height * 0.25), with: .color(hex(0xd0d0d6)), lineWidth: 0.5)
        ctx.draw(starText, at: CGPoint(x: star.midX, y: star.midY))
        // Satırlar ve ekran görüntüsü yeri
        let h = max(0.8, r.height * 0.028)
        var y = icon.maxY + r.height * 0.07
        for w in [0.78, 0.7, 0.58] {
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + pad, y: y, width: (r.width - pad * 2) * w, height: h), cornerRadius: h / 2),
                     with: .color(line))
            y += h * 2.4
        }
        let shot = CGRect(x: r.minX + pad, y: y + h, width: r.width - pad * 2, height: max(0, r.maxY - y - h * 6))
        if shot.height > 4 {
            ctx.fill(Path(roundedRect: shot, cornerRadius: min(6, shot.height * 0.08)),
                     with: .linearGradient(Gradient(colors: [hex(0xe6e8f5), hex(0xf2eef9)]),
                                           startPoint: shot.origin, endPoint: CGPoint(x: shot.maxX, y: shot.maxY)))
        }
        if variant == 0, demo.effect == .newTabFromLink {
            // İmleç gelince bağlantı vurgulanır
            let link = linkRect(in: r)
            let hover = time >= timing.cursorArrive && time < timing.reset
            if hover {
                ctx.fill(Path(roundedRect: link.insetBy(dx: -r.width * 0.012, dy: -link.height * 1.6), cornerRadius: link.height * 1.2),
                         with: .color(blue.opacity(0.14)))
            }
            ctx.fill(Path(roundedRect: link, cornerRadius: link.height / 2), with: .color(hover ? hex(0x0060df) : blue))
        }
    }

    /// Boş sekme: açık gri zemin, ortada sık ziyaret edilenler (renkli kareler)
    func drawStartPage(_ ctx: inout GraphicsContext, _ r: CGRect) {
        ctx.fill(Path(r), with: .color(hex(0xf2f2f5)))
        let tile = min(r.width * 0.09, r.height * 0.16)
        let gap = tile * 0.45
        let total = tile * 6 + gap * 5
        let h = max(0.8, r.height * 0.025)
        ctx.fill(Path(roundedRect: CGRect(x: r.midX - total / 2, y: r.minY + r.height * 0.22, width: r.width * 0.16, height: h * 1.4),
                      cornerRadius: h), with: .color(ink.opacity(0.75)))
        for i in 0..<6 {
            let t = CGRect(x: r.midX - total / 2 + Double(i) * (tile + gap), y: r.minY + r.height * 0.34, width: tile, height: tile)
            ctx.fill(Path(roundedRect: t, cornerRadius: tile * 0.22),
                     with: .color(Color(hue: [0.58, 0.02, 0.33, 0.12, 0.75, 0.9][i], saturation: 0.55, brightness: 0.9)))
            ctx.fill(Path(roundedRect: CGRect(x: t.minX + tile * 0.15, y: t.maxY + tile * 0.25, width: tile * 0.7, height: h), cornerRadius: h / 2),
                     with: .color(line))
        }
    }

    /// Koyu video sitesi: siyah zemin, solda büyük oynatıcı (kırmızı ilerleme çubuğu), sağda küçük resim listesi
    func drawVideoSite(_ ctx: inout GraphicsContext, _ r: CGRect, site: Site) {
        ctx.fill(Path(r), with: .color(hex(0x0f0f0f)))
        let pad = r.width * 0.04
        let th = max(1, r.height * 0.03)
        let search = CGRect(x: r.midX - r.width * 0.2, y: r.minY + r.height * 0.05, width: r.width * 0.4, height: th * 2.2)
        ctx.fill(Path(roundedRect: search, cornerRadius: search.height / 2), with: .color(hex(0x222222)))
        ctx.fill(Path(roundedRect: CGRect(x: r.minX + pad, y: search.midY - th / 2, width: r.width * 0.1, height: th),
                      cornerRadius: th / 2), with: .color(.white.opacity(0.85)))
        let top = search.maxY + r.height * 0.06
        let player = CGRect(x: r.minX + pad, y: top, width: r.width * 0.6, height: min(r.width * 0.6 / 1.78, r.maxY - top - pad))
        ctx.fill(Path(roundedRect: player, cornerRadius: min(5, player.height * 0.05)),
                 with: .linearGradient(Gradient(colors: [hex(0x3b3b46), hex(0x1b1b22)]),
                                       startPoint: player.origin, endPoint: CGPoint(x: player.maxX, y: player.maxY)))
        let s = player.height * 0.14
        var play = Path()
        play.move(to: CGPoint(x: player.midX - s * 0.4, y: player.midY - s * 0.5))
        play.addLine(to: CGPoint(x: player.midX + s * 0.55, y: player.midY))
        play.addLine(to: CGPoint(x: player.midX - s * 0.4, y: player.midY + s * 0.5))
        play.closeSubpath()
        ctx.fill(play, with: .color(.white.opacity(0.9)))
        let bar = CGRect(x: player.minX, y: player.maxY - max(1, player.height * 0.025), width: player.width, height: max(1, player.height * 0.025))
        ctx.fill(Path(bar), with: .color(.white.opacity(0.25)))
        ctx.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * 0.38, height: bar.height)), with: .color(site.color))
        // Sağdaki liste
        let listX = player.maxX + pad
        var y = top
        let thumbH = player.height * 0.24
        for i in 0..<4 where y + thumbH <= player.maxY + 1 {
            let t = CGRect(x: listX, y: y, width: thumbH * 1.78, height: thumbH)
            ctx.fill(Path(roundedRect: t, cornerRadius: min(3, t.height * 0.1)),
                     with: .color(Color(hue: [0.62, 0.05, 0.75, 0.45][i], saturation: 0.35, brightness: 0.35)))
            let lx = t.maxX + pad * 0.5
            let lw = max(0, r.maxX - pad - lx)
            ctx.fill(Path(roundedRect: CGRect(x: lx, y: t.minY + t.height * 0.15, width: lw * 0.9, height: th * 0.7), cornerRadius: th * 0.35),
                     with: .color(.white.opacity(0.7)))
            ctx.fill(Path(roundedRect: CGRect(x: lx, y: t.minY + t.height * 0.5, width: lw * 0.6, height: th * 0.6), cornerRadius: th * 0.3),
                     with: .color(.white.opacity(0.3)))
            y += thumbH + pad * 0.5
        }
    }

    /// Renkli site: üstte site renginde başlık bandı, altında yazı satırları ve iki renkli görsel kutusu
    func drawColorSite(_ ctx: inout GraphicsContext, _ r: CGRect, site: Site) {
        let band = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.24)
        ctx.fill(Path(band), with: .color(site.color))
        let pad = r.width * 0.06
        let th = max(1.2, band.height * 0.16)
        ctx.fill(Path(roundedRect: CGRect(x: r.minX + pad, y: band.midY - th / 2, width: r.width * 0.3, height: th), cornerRadius: th / 2),
                 with: .color(.white.opacity(0.95)))
        ctx.fill(Path(roundedRect: CGRect(x: r.maxX - pad - r.width * 0.18, y: band.midY - th * 0.35, width: r.width * 0.18, height: th * 0.7),
                      cornerRadius: th * 0.35), with: .color(.white.opacity(0.6)))
        let h = max(0.8, r.height * 0.028)
        var y = band.maxY + r.height * 0.08
        let imageW = (r.width - pad * 3) * 0.42
        let image = CGRect(x: r.minX + pad, y: y, width: imageW, height: max(0, r.maxY - y - r.height * 0.08))
        ctx.fill(Path(roundedRect: image, cornerRadius: min(5, image.height * 0.08)), with: .color(site.color.opacity(0.22)))
        let textX = image.maxX + pad
        for w in [0.9, 0.75, 0.85, 0.6, 0.8] where y + h < r.maxY - r.height * 0.08 {
            ctx.fill(Path(roundedRect: CGRect(x: textX, y: y, width: (r.maxX - pad - textX) * w, height: h), cornerRadius: h / 2),
                     with: .color(line))
            y += h * 2.6
        }
    }

    /// Uygulamanın logosu: gerçek oranda trackpad, ince beyaz çizgi, eşit parmaklar
    func drawLogo(_ ctx: inout GraphicsContext, in r: CGRect) {
        let pad = CGRect(x: r.minX, y: r.midY - r.width / 3.2, width: r.width, height: r.width / 1.6)
        ctx.stroke(Path(roundedRect: pad, cornerRadius: pad.height * 0.16), with: .color(.white), lineWidth: max(0.5, r.width * 0.06))
        let d = pad.width * 0.13
        for i in 0..<3 {
            let x = pad.midX + (Double(i) - 1) * d * 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: pad.midY - d / 2, width: d, height: d)), with: .color(.white))
        }
    }

    /// Sayfadaki bağlantı satırı (orta tık örneği için)
    func linkRect(in r: CGRect) -> CGRect {
        CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.36, width: r.width * 0.32, height: max(0.9, r.height * 0.03))
    }

    func drawAppWindow(_ ctx: inout GraphicsContext, _ f: CGRect, symbol: String, hue: Double, opacity: Double) {
        var c = ctx
        c.opacity = opacity
        let path = Path(roundedRect: f, cornerRadius: min(6, f.width * 0.014))
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: W * 0.03, y: W * 0.012))
        shadow.fill(path, with: .color(hex(0xf7f7f9)))
        c.clip(to: path)
        let bar = CGRect(x: f.minX, y: f.minY, width: f.width, height: barHeight(f))
        c.fill(Path(bar), with: .color(hex(0xe6e6ea)))
        let tint = Color(hue: hue, saturation: hue == 0 ? 0 : 0.7, brightness: hue == 0 ? 0.2 : 0.85)
        drawSymbol(&c, symbol, at: CGPoint(x: f.midX, y: f.midY + bar.height / 2), size: min(f.width, f.height) * 0.32, color: tint)
    }

    // MARK: Uygulama sahneleri (daire menü kısayol önerileri)

    /// Pencere çerçevesi: gölge, başlık çubuğu, kırmızı/sarı/yeşil düğmeler; içerik alanını döner
    func drawWindow(_ ctx: inout GraphicsContext, _ f: CGRect, dark: Bool, bar barColor: UInt32) -> CGRect {
        let path = Path(roundedRect: f, cornerRadius: min(f.width * 0.014, 6))
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: W * 0.03, y: W * 0.012))
        shadow.fill(path, with: .color(dark ? hex(0x1e1e1e) : .white))
        ctx.clip(to: path)
        let barH = barHeight(f) * 0.8
        ctx.fill(Path(CGRect(x: f.minX, y: f.minY, width: f.width, height: barH)), with: .color(hex(barColor)))
        let dot = barH * 0.36
        var x = f.minX + f.width * 0.02
        for color in [hex(0xff5f57), hex(0xfebc2e), hex(0x28c840)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: f.minY + barH / 2 - dot / 2, width: dot, height: dot)), with: .color(color))
            x += dot * 1.7
        }
        return CGRect(x: f.minX, y: f.minY + barH, width: f.width, height: f.height - barH)
    }

    /// Yatay yazı çizgileri (sayfa yazısı yerine)
    func bars(_ ctx: inout GraphicsContext, x: Double, y: Double, widths: [Double], height h: Double, step: Double, color: Color) {
        for (i, w) in widths.enumerated() {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y + Double(i) * step, width: w, height: h), cornerRadius: h / 2), with: .color(color))
        }
    }

    func drawApp(_ ctx: inout GraphicsContext, _ f: CGRect, _ scene: CommunityDemo.AppScene) {
        var c = ctx
        switch scene {
        case .finderNewFolder, .finderGoTo, .finderHidden: drawFinder(&c, f, scene)
        case .notesNew, .notesChecklist: drawNotes(&c, f, scene)
        case .codePalette, .codeTerminal, .codeSidebar: drawCode(&c, f, scene)
        case .musicLike, .musicSearch: drawMusic(&c, f, scene)
        }
    }

    /// Finder: solda kenar çubuğu, sağda klasör simgeleri
    func drawFinder(_ ctx: inout GraphicsContext, _ f: CGRect, _ scene: CommunityDemo.AppScene) {
        let r = drawWindow(&ctx, f, dark: false, bar: 0xf3f3f5)
        let side = CGRect(x: r.minX, y: r.minY, width: r.width * 0.22, height: r.height)
        ctx.fill(Path(side), with: .color(hex(0xe9e9ee)))
        let h = max(0.8, r.height * 0.025)
        for i in 0..<6 {
            let y = side.minY + side.height * (0.1 + Double(i) * 0.1)
            ctx.fill(Path(roundedRect: CGRect(x: side.minX + side.width * 0.12, y: y - h, width: h * 2, height: h * 2), cornerRadius: h * 0.5),
                     with: .color(blue.opacity(0.8)))
            ctx.fill(Path(roundedRect: CGRect(x: side.minX + side.width * 0.3, y: y - h / 2, width: side.width * [0.5, 0.4, 0.55, 0.35, 0.45, 0.4][i], height: h),
                          cornerRadius: h / 2), with: .color(.black.opacity(0.3)))
        }
        let cols = 4.0
        let cell = (r.width - side.width) / cols
        func slot(_ i: Int) -> CGRect {
            CGRect(x: side.maxX + Double(i % 4) * cell, y: r.minY + r.height * 0.06 + Double(i / 4) * cell * 0.85, width: cell, height: cell * 0.85)
        }
        func folder(_ i: Int, opacity: Double, scale: Double = 1, renaming: Bool = false) {
            let s = slot(i)
            let size = cell * 0.42 * scale
            var c = ctx
            c.opacity = opacity
            drawSymbol(&c, "folder.fill", at: CGPoint(x: s.midX, y: s.minY + cell * 0.32), size: size, color: hex(0x1e9bf0))
            let name = CGRect(x: s.midX - cell * 0.25, y: s.minY + cell * 0.6, width: cell * 0.5, height: h * 1.6)
            if renaming {
                c.fill(Path(roundedRect: name.insetBy(dx: -h, dy: -h * 0.5), cornerRadius: h), with: .color(accent))
                c.fill(Path(roundedRect: name.insetBy(dx: name.width * 0.15, dy: h * 0.5), cornerRadius: h / 2), with: .color(.white))
            } else {
                c.fill(Path(roundedRect: name.insetBy(dx: name.width * 0.1, dy: h * 0.3), cornerRadius: h / 2), with: .color(.black.opacity(0.3)))
            }
        }
        for i in 0..<5 { folder(i, opacity: 1) }
        let k = effect
        switch scene {
        case .finderNewFolder:
            // Yeni klasör belirir, adı yazılmaya hazır (seçili)
            if k > 0 { folder(5, opacity: min(1, k * 2), scale: 0.6 + 0.4 * easeOut(k), renaming: k > 0.5) }
        case .finderHidden:
            // Gizli dosyalar soluk gelir
            for i in 5..<8 { folder(i, opacity: 0.45 * k) }
        case .finderGoTo:
            // Üstten "Klasöre git" kutusu iner, yol yazılıdır
            guard k > 0 else { break }
            let sheet = CGRect(x: r.midX - r.width * 0.3, y: r.minY - r.height * 0.3 + r.height * 0.32 * easeOut(k),
                               width: r.width * 0.6, height: r.height * 0.3)
            var shadow = ctx
            shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: W * 0.015, y: W * 0.005))
            shadow.fill(Path(roundedRect: sheet, cornerRadius: W * 0.01), with: .color(hex(0xf6f6f8)))
            let field = CGRect(x: sheet.minX + sheet.width * 0.08, y: sheet.minY + sheet.height * 0.22, width: sheet.width * 0.84, height: sheet.height * 0.28)
            ctx.fill(Path(roundedRect: field, cornerRadius: field.height * 0.25), with: .color(.white))
            ctx.stroke(Path(roundedRect: field.insetBy(dx: -1, dy: -1), cornerRadius: field.height * 0.28), with: .color(accent), lineWidth: 1.5)
            ctx.draw(Text(verbatim: "~/Library/").font(.system(size: max(4, field.height * 0.5), weight: .medium)).foregroundStyle(ink),
                     at: CGPoint(x: field.minX + field.width * 0.05, y: field.midY), anchor: .leading)
            let button = CGRect(x: sheet.maxX - sheet.width * 0.3, y: sheet.maxY - sheet.height * 0.34, width: sheet.width * 0.22, height: sheet.height * 0.2)
            ctx.fill(Path(roundedRect: button, cornerRadius: button.height * 0.3), with: .color(accent))
        default:
            break
        }
    }

    /// Notlar: solda not listesi (seçili satır sarı), sağda notun yazısı
    /// Notlar penceresinde notun yazı alanı (`content`: başlık çubuğunun altı)
    func notesBody(_ content: CGRect) -> CGRect {
        CGRect(x: content.minX + content.width * 0.37, y: content.minY + content.height * 0.08, width: content.width * 0.58, height: content.height * 0.84)
    }

    /// `still`: yalnız pencere, hiçbir şey değişmez (başka örneklerin arka planı)
    func drawNotes(_ ctx: inout GraphicsContext, _ f: CGRect, _ scene: CommunityDemo.AppScene, still: Bool = false) {
        let r = drawWindow(&ctx, f, dark: false, bar: 0xf5f5f3)
        let list = CGRect(x: r.minX, y: r.minY, width: r.width * 0.32, height: r.height)
        ctx.fill(Path(list), with: .color(hex(0xf7f7f5)))
        ctx.fill(Path(CGRect(x: list.maxX, y: list.minY, width: 0.6, height: list.height)), with: .color(line))
        let k = still ? 0 : effect
        let isNew = scene == .notesNew
        let rowH = r.height * 0.16
        let h = max(0.8, r.height * 0.026)
        let shift = isNew ? rowH * easeOut(k) : 0
        func row(_ y: Double, selected: Bool, fresh: Bool = false) {
            let rr = CGRect(x: list.minX + list.width * 0.05, y: y, width: list.width * 0.9, height: rowH * 0.88)
            if selected { ctx.fill(Path(roundedRect: rr, cornerRadius: rowH * 0.12), with: .color(hex(0xffd60a).opacity(0.55))) }
            bars(&ctx, x: rr.minX + rr.width * 0.08, y: rr.minY + rr.height * 0.28, widths: fresh ? [rr.width * 0.4] : [rr.width * 0.6, rr.width * 0.75],
                 height: h, step: h * 2.6, color: .black.opacity(fresh ? 0.25 : 0.4))
        }
        for i in 0..<5 { row(list.minY + list.height * 0.04 + Double(i) * rowH + shift, selected: i == 0 && !(isNew && k > 0.5)) }
        if isNew, k > 0 {
            row(list.minY + list.height * 0.04 - rowH + shift, selected: k > 0.5, fresh: true)
        }
        let body = notesBody(r)
        if isNew {
            // Gövde boşalır, yanıp sönen imleç
            var c = ctx
            c.opacity = 1 - k
            bars(&c, x: body.minX, y: body.minY, widths: [body.width * 0.45], height: h * 1.8, step: 0, color: ink.opacity(0.85))
            bars(&c, x: body.minX, y: body.minY + h * 5, widths: [0.9, 0.8, 0.95, 0.6].map { $0 * body.width }, height: h, step: h * 2.8, color: line)
            if k > 0.5, sin(time * 9) > 0 {
                ctx.fill(Path(CGRect(x: body.minX, y: body.minY - h * 0.4, width: 1.2, height: h * 2.6)), with: .color(hex(0xe0a800)))
            }
        } else {
            bars(&ctx, x: body.minX, y: body.minY, widths: [body.width * 0.45], height: h * 1.8, step: 0, color: ink.opacity(0.85))
            // Yapılacaklar: satırlar sağa kayar, başlarına yuvarlak gelir, ilk ikisi işaretli
            let indent = h * 4.5 * easeOut(k)
            for i in 0..<4 {
                let y = body.minY + h * 5 + Double(i) * h * 3.6
                if k > 0 {
                    let d = h * 2.4
                    let circle = CGRect(x: body.minX, y: y + h / 2 - d / 2, width: d, height: d)
                    var c = ctx
                    c.opacity = min(1, k * 2)
                    if i < 2, k > 0.7 {
                        c.fill(Path(ellipseIn: circle), with: .color(hex(0xffb800)))
                        drawSymbol(&c, "checkmark", at: CGPoint(x: circle.midX, y: circle.midY), size: d * 0.6, color: .white)
                    } else {
                        c.stroke(Path(ellipseIn: circle), with: .color(.black.opacity(0.35)), lineWidth: 0.8)
                    }
                }
                ctx.fill(Path(roundedRect: CGRect(x: body.minX + indent, y: y, width: body.width * [0.8, 0.65, 0.9, 0.55][i], height: h), cornerRadius: h / 2),
                         with: .color(line))
            }
        }
    }

    /// Kod düzenleyici (markasız, koyu): solda dosya listesi, ortada renkli kod satırları, altta mavi durum çubuğu
    func drawCode(_ ctx: inout GraphicsContext, _ f: CGRect, _ scene: CommunityDemo.AppScene) {
        let r = drawWindow(&ctx, f, dark: true, bar: 0x323233)
        let k = effect
        let status = r.height * 0.05
        ctx.fill(Path(CGRect(x: r.minX, y: r.maxY - status, width: r.width, height: status)), with: .color(hex(0x007acc)))
        let main = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - status)
        let activity = CGRect(x: main.minX, y: main.minY, width: main.width * 0.05, height: main.height)
        ctx.fill(Path(activity), with: .color(hex(0x333333)))
        let a = activity.width * 0.45
        for i in 0..<4 {
            ctx.fill(Path(roundedRect: CGRect(x: activity.midX - a / 2, y: activity.minY + activity.width * (0.4 + Double(i) * 1.1), width: a, height: a),
                          cornerRadius: a * 0.2), with: .color(.white.opacity(i == 0 ? 0.75 : 0.35)))
        }
        let sideW = main.width * 0.22 * (scene == .codeSidebar ? 1 - easeOut(k) : 1)
        let side = CGRect(x: activity.maxX, y: main.minY, width: sideW, height: main.height)
        let h = max(0.8, r.height * 0.022)
        if sideW > 1 {
            ctx.fill(Path(side), with: .color(hex(0x252526)))
            var c = ctx
            c.clip(to: Path(side))
            for i in 0..<7 {
                let y = side.minY + side.height * (0.08 + Double(i) * 0.08)
                c.fill(Path(roundedRect: CGRect(x: activity.maxX + main.width * 0.02, y: y, width: main.width * [0.12, 0.09, 0.14, 0.1, 0.13, 0.08, 0.11][i], height: h),
                            cornerRadius: h / 2), with: .color(.white.opacity(i == 2 ? 0.75 : 0.4)))
            }
        }
        let editor = CGRect(x: side.maxX, y: main.minY, width: main.maxX - side.maxX, height: main.height)
        ctx.fill(Path(editor), with: .color(hex(0x1e1e1e)))
        let tab = CGRect(x: editor.minX, y: editor.minY, width: editor.width * 0.24, height: editor.height * 0.07)
        ctx.fill(Path(CGRect(x: editor.minX, y: editor.minY, width: editor.width, height: tab.height)), with: .color(hex(0x252526)))
        ctx.fill(Path(tab), with: .color(hex(0x1e1e1e)))
        // Kod satırları: her satır birkaç renkli parça
        let palette: [UInt32] = [0xc586c0, 0x569cd6, 0x9cdcfe, 0xce9178, 0xdcdcaa, 0x6a9955]
        let rows: [[Double]] = [[0.08, 0.16], [0.05, 0.1, 0.2], [0.05, 0.22, 0.08], [0.05, 0.14], [0.08, 0.06, 0.18], [0.04], [0.08, 0.2], [0.05, 0.12, 0.1]]
        for (i, parts) in rows.enumerated() {
            var x = editor.minX + editor.width * (0.05 + (i % 3 == 0 ? 0 : 0.04))
            let y = tab.maxY + editor.height * 0.06 + Double(i) * h * 2.6
            for (j, w) in parts.enumerated() {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: editor.width * w, height: h), cornerRadius: h / 2),
                         with: .color(hex(palette[(i + j * 2) % palette.count]).opacity(0.9)))
                x += editor.width * w + h * 1.2
            }
        }
        guard k > 0 else { return }
        switch scene {
        case .codePalette:
            // Üstte komut kutusu: yazı alanı ve liste, ilk satır seçili
            let box = CGRect(x: editor.midX - editor.width * 0.3, y: editor.minY + editor.height * 0.02 + editor.height * 0.03 * easeOut(k),
                             width: editor.width * 0.6, height: editor.height * 0.46)
            var c = ctx
            c.opacity = min(1, k * 2)
            var shadow = c
            shadow.addFilter(.shadow(color: .black.opacity(0.6), radius: W * 0.015, y: W * 0.005))
            shadow.fill(Path(roundedRect: box, cornerRadius: W * 0.008), with: .color(hex(0x252526)))
            let input = CGRect(x: box.minX + box.width * 0.04, y: box.minY + box.height * 0.06, width: box.width * 0.92, height: box.height * 0.16)
            c.fill(Path(roundedRect: input, cornerRadius: 2), with: .color(hex(0x3c3c3c)))
            c.stroke(Path(roundedRect: input, cornerRadius: 2), with: .color(hex(0x007fd4)), lineWidth: 1)
            c.draw(Text(verbatim: ">").font(.system(size: max(4, input.height * 0.6), weight: .medium, design: .monospaced)).foregroundStyle(.white),
                   at: CGPoint(x: input.minX + input.height * 0.4, y: input.midY), anchor: .leading)
            for i in 0..<4 {
                let row = CGRect(x: box.minX + box.width * 0.02, y: input.maxY + box.height * (0.04 + Double(i) * 0.17), width: box.width * 0.96, height: box.height * 0.15)
                if i == 0 { c.fill(Path(roundedRect: row, cornerRadius: 2), with: .color(hex(0x04395e))) }
                c.fill(Path(roundedRect: CGRect(x: row.minX + row.width * 0.04, y: row.midY - h / 2, width: row.width * [0.5, 0.42, 0.6, 0.38][i], height: h),
                            cornerRadius: h / 2), with: .color(.white.opacity(i == 0 ? 0.85 : 0.5)))
            }
        case .codeTerminal:
            // Alttan terminal paneli açılır
            let ph = editor.height * 0.4 * easeOut(k)
            let panel = CGRect(x: editor.minX, y: editor.maxY - ph, width: editor.width, height: ph)
            ctx.fill(Path(panel), with: .color(hex(0x181818)))
            ctx.fill(Path(CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: 0.8)), with: .color(hex(0x3c3c3c)))
            var c = ctx
            c.clip(to: Path(panel))
            for i in 0..<3 {
                let y = panel.minY + editor.height * 0.07 + Double(i) * h * 2.6
                c.fill(Path(roundedRect: CGRect(x: panel.minX + editor.width * 0.04, y: y, width: h * 2, height: h), cornerRadius: h / 2), with: .color(hex(0x23d18b)))
                c.fill(Path(roundedRect: CGRect(x: panel.minX + editor.width * 0.04 + h * 3, y: y, width: editor.width * [0.3, 0.45, 0.2][i], height: h),
                            cornerRadius: h / 2), with: .color(.white.opacity(0.6)))
            }
            if sin(time * 9) > 0 {
                c.fill(Path(CGRect(x: panel.minX + editor.width * 0.04 + h * 3, y: panel.minY + editor.height * 0.07 + h * 7.8, width: h * 1.2, height: h * 1.6)),
                       with: .color(.white.opacity(0.8)))
            }
        default:
            break
        }
    }

    /// Müzik uygulaması (markasız, koyu): solda kitaplık, ortada albüm, altta çalan şarkı ve kalp
    func drawMusic(_ ctx: inout GraphicsContext, _ f: CGRect, _ scene: CommunityDemo.AppScene) {
        let r = drawWindow(&ctx, f, dark: true, bar: 0x000000)
        let green = hex(0x1ed760)
        let k = effect
        ctx.fill(Path(r), with: .color(.black))
        let player = CGRect(x: r.minX, y: r.maxY - r.height * 0.17, width: r.width, height: r.height * 0.17)
        let side = CGRect(x: r.minX + r.width * 0.01, y: r.minY, width: r.width * 0.22, height: player.minY - r.minY - r.height * 0.015)
        let main = CGRect(x: side.maxX + r.width * 0.01, y: r.minY, width: r.maxX - side.maxX - r.width * 0.02, height: side.height)
        ctx.fill(Path(roundedRect: side, cornerRadius: W * 0.008), with: .color(hex(0x121212)))
        ctx.fill(Path(roundedRect: main, cornerRadius: W * 0.008), with: .color(hex(0x121212)))
        let h = max(0.8, r.height * 0.024)
        for i in 0..<5 {
            let y = side.minY + side.height * (0.1 + Double(i) * 0.17)
            let s = side.height * 0.11
            ctx.fill(Path(roundedRect: CGRect(x: side.minX + side.width * 0.08, y: y, width: s, height: s), cornerRadius: s * 0.12),
                     with: .color(Color(hue: [0.7, 0.05, 0.55, 0.9, 0.3][i], saturation: 0.5, brightness: 0.7)))
            ctx.fill(Path(roundedRect: CGRect(x: side.minX + side.width * 0.08 + s * 1.3, y: y + s * 0.3, width: side.width * 0.4, height: h), cornerRadius: h / 2),
                     with: .color(.white.opacity(0.55)))
        }
        // Arama kutusu (üstte); aramada beyaz çerçeve, imleç, sonuçlar renkli kareler
        let searching = scene == .musicSearch ? k : 0
        let pill = CGRect(x: main.midX - main.width * (0.22 + 0.06 * searching), y: main.minY + main.height * 0.05,
                          width: main.width * (0.44 + 0.12 * searching), height: main.height * 0.1)
        ctx.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(hex(0x242424)))
        if searching > 0 {
            ctx.stroke(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(.white.opacity(searching)), lineWidth: 1.4)
            if sin(time * 9) > 0 {
                ctx.fill(Path(CGRect(x: pill.minX + pill.height * 1.1, y: pill.minY + pill.height * 0.25, width: 1.2, height: pill.height * 0.5)),
                         with: .color(.white))
            }
        }
        drawSymbol(&ctx, "magnifyingglass", at: CGPoint(x: pill.minX + pill.height * 0.6, y: pill.midY), size: pill.height * 0.45,
                   color: .white.opacity(0.7))
        let top = pill.maxY + main.height * 0.06
        let content = CGRect(x: main.minX + main.width * 0.05, y: top, width: main.width * 0.9, height: main.maxY - top - main.height * 0.05)
        var album = ctx
        album.opacity = 1 - searching
        let cover = CGRect(x: content.minX, y: content.minY, width: content.height * 0.62, height: content.height * 0.62)
        album.fill(Path(roundedRect: cover, cornerRadius: W * 0.005),
                   with: .linearGradient(Gradient(colors: [hex(0x7b3bd1), hex(0xe2577b)]), startPoint: cover.origin, endPoint: CGPoint(x: cover.maxX, y: cover.maxY)))
        bars(&album, x: cover.maxX + content.width * 0.05, y: cover.minY + cover.height * 0.45, widths: [content.width * 0.35, content.width * 0.2],
             height: h * 1.6, step: h * 3.2, color: .white.opacity(0.75))
        bars(&album, x: content.minX, y: cover.maxY + content.height * 0.12, widths: [0.7, 0.6].map { $0 * content.width }, height: h, step: h * 3,
             color: .white.opacity(0.35))
        if searching > 0 {
            var c = ctx
            c.opacity = searching
            let tw = (content.width - content.width * 0.06) / 4
            for i in 0..<8 {
                let t = CGRect(x: content.minX + Double(i % 4) * (tw + content.width * 0.02), y: content.minY + Double(i / 4) * (tw * 0.62 + content.width * 0.02),
                               width: tw, height: tw * 0.62)
                c.fill(Path(roundedRect: t, cornerRadius: W * 0.005),
                       with: .color(Color(hue: Double(i) / 8, saturation: 0.6, brightness: 0.8)))
            }
        }
        // Alttaki çalar: küçük kapak, şarkı adı, kalp, ortada oynat düğmesi
        let s = player.height * 0.56
        let small = CGRect(x: player.minX + player.width * 0.02, y: player.midY - s / 2, width: s, height: s)
        ctx.fill(Path(roundedRect: small, cornerRadius: s * 0.1),
                 with: .linearGradient(Gradient(colors: [hex(0x7b3bd1), hex(0xe2577b)]), startPoint: small.origin, endPoint: CGPoint(x: small.maxX, y: small.maxY)))
        bars(&ctx, x: small.maxX + s * 0.3, y: small.minY + s * 0.2, widths: [player.width * 0.12, player.width * 0.08], height: h, step: h * 2.6,
             color: .white.opacity(0.7))
        let heart = CGPoint(x: small.maxX + s * 0.3 + player.width * 0.15, y: player.midY)
        let liked = scene == .musicLike ? k : 0
        let pop = 1 + 0.35 * sin(min(1, liked) * .pi)
        drawSymbol(&ctx, liked > 0.3 ? "heart.fill" : "heart", at: heart, size: s * 0.5 * pop, color: liked > 0.3 ? green : .white.opacity(0.7))
        let play = player.height * 0.42
        ctx.fill(Path(ellipseIn: CGRect(x: player.midX - play / 2, y: player.midY - play / 2, width: play, height: play)), with: .color(.white))
        drawSymbol(&ctx, "pause.fill", at: CGPoint(x: player.midX, y: player.midY), size: play * 0.45, color: .black)
        ctx.fill(Path(roundedRect: CGRect(x: player.midX + play, y: player.midY - h / 2, width: player.width * 0.25, height: h), cornerRadius: h / 2),
                 with: .color(.white.opacity(0.25)))
    }

    /// Büyük pano: üç raf (görseller, yazılar, bağlantılar)
    func drawClipboard(_ ctx: inout GraphicsContext, opacity: Double, scale: Double) {
        var c = ctx
        c.opacity = opacity
        let full = CGRect(x: W * 0.12, y: H * 0.16, width: W * 0.76, height: H * 0.6)
        let box = full.insetBy(dx: full.width * (1 - scale) / 2, dy: full.height * (1 - scale) / 2)
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.5), radius: W * 0.03, y: W * 0.01))
        shadow.fill(Path(roundedRect: box, cornerRadius: W * 0.02), with: .color(hex(0x141416).opacity(0.94)))
        let rowH = box.height / 3
        let selected = time > effectStart + 0.9 ? 1 : 0
        for row in 0..<3 {
            let y = box.minY + Double(row) * rowH + rowH * 0.18
            let h = rowH * 0.64
            let w = row == 0 ? h * 1.4 : h * 2.2
            var x = box.minX + box.width * 0.04
            for i in 0..<6 where x + w < box.maxX - box.width * 0.02 {
                let card = CGRect(x: x, y: y, width: w, height: h)
                let fill: Color = row == 0
                    ? Color(hue: [0.58, 0.08, 0.9, 0.35, 0.13, 0.75][i], saturation: 0.45, brightness: 0.85)
                    : hex(0x26262a)
                c.fill(Path(roundedRect: card, cornerRadius: h * 0.12), with: .color(fill))
                if row > 0 {
                    let lh = max(0.6, h * 0.08)
                    for l in 0..<(row == 1 ? 3 : 1) {
                        c.fill(Path(roundedRect: CGRect(x: card.minX + w * 0.1, y: card.minY + h * (0.25 + Double(l) * 0.2),
                                                        width: w * [0.75, 0.6, 0.7][l], height: lh), cornerRadius: lh / 2),
                               with: .color(row == 2 ? blue.opacity(0.9) : .white.opacity(0.55)))
                    }
                }
                if row == 1, i == selected {
                    c.stroke(Path(roundedRect: card.insetBy(dx: -1, dy: -1), cornerRadius: h * 0.14), with: .color(orange), lineWidth: 1.2)
                }
                x += w + box.width * 0.02
            }
        }
    }

    /// FingerKit sayfasındaki ilk yazı satırı (drawPage ile aynı ölçü)
    func firstLine(in r: CGRect) -> CGRect {
        let titleSize = max(4, min(W * 0.028, r.height * 0.075))
        let y = r.minY + r.height * 0.07 + titleSize * 1.5 + r.height * 0.07
        let h = max(0.8, r.height * 0.028)
        return CGRect(x: r.minX + r.width * 0.06, y: y, width: (r.width - r.width * 0.12) * 0.78, height: h)
    }

    /// Kopyala: satır seçili (mavi zemin); dokununca satırın kopyası sağ üstteki pano simgesine uçar
    func drawCopy(_ ctx: inout GraphicsContext, in r: CGRect) {
        let line = firstLine(in: r)
        let sel = line.insetBy(dx: -line.height, dy: -line.height * 1.1)
        ctx.fill(Path(roundedRect: sel, cornerRadius: line.height * 0.6), with: .color(blue.opacity(0.28)))
        let target = CGPoint(x: r.maxX - r.width * 0.12, y: r.minY + r.height * 0.32)
        guard effect > 0 else { return }
        let fly = easeInOut(ramp(effectStart, 0.5))
        var c = ctx
        c.opacity = effect * (1 - 0.6 * fly)
        let w = line.width * (1 - 0.8 * fly)
        let ghost = CGRect(x: line.minX + (target.x - line.minX - w / 2) * fly, y: line.minY + (target.y - line.minY) * fly,
                           width: w, height: line.height * 1.6)
        c.fill(Path(roundedRect: ghost, cornerRadius: ghost.height / 2), with: .color(blue.opacity(0.7)))
        let pop = 1 + 0.25 * sin(clamp((time - effectStart - 0.45) / 0.25) * .pi)
        var badge = ctx
        badge.opacity = effect
        let b = W * 0.075 * pop
        badge.fill(Path(roundedRect: CGRect(x: target.x - b / 2, y: target.y - b / 2, width: b, height: b), cornerRadius: b * 0.25),
                   with: .color(hex(0x1c1c1e).opacity(0.9)))
        drawSymbol(&badge, "doc.on.clipboard.fill", at: target, size: b * 0.5, color: gold)
    }

    /// Yapıştır: boş satırda yanıp sönen imleç; dokununca kopyalanan yazı imlecin yerinden uzar
    func drawPasteHere(_ ctx: inout GraphicsContext, in r: CGRect) {
        let line = firstLine(in: r)
        let field = CGRect(x: line.minX - line.height, y: r.maxY - r.height * 0.3, width: line.width + line.height * 2, height: line.height * 5)
        ctx.fill(Path(roundedRect: field, cornerRadius: field.height * 0.25), with: .color(.white))
        ctx.stroke(Path(roundedRect: field, cornerRadius: field.height * 0.25), with: .color(effect > 0 ? accent : line_), lineWidth: 1)
        let x0 = field.minX + line.height * 1.5
        let text = CGRect(x: x0, y: field.midY - line.height * 0.6, width: line.width * 0.8 * effect, height: line.height * 1.2)
        if effect > 0 {
            ctx.fill(Path(roundedRect: text, cornerRadius: text.height / 2), with: .color(ink.opacity(0.7)))
        }
        if sin(time * 9) > 0 {
            ctx.fill(Path(CGRect(x: text.maxX + 1, y: field.minY + field.height * 0.2, width: 1.2, height: field.height * 0.6)), with: .color(accent))
        }
    }
    var line_: Color { hex(0xc7c7cc) }

    /// Biçimsiz yapıştırma (Notlar): web'den gelen pembe, iri, kalın yazı notun içine düşerken
    /// notun kendi sade yazısına döner; yazı gerçek harflerle çizilir ki ne değiştiği okunsun
    func drawPaste(_ ctx: inout GraphicsContext, in f: CGRect) {
        let content = CGRect(x: f.minX, y: f.minY + barHeight(f) * 0.8, width: f.width, height: f.height - barHeight(f) * 0.8)
        let body = notesBody(content)
        let h = max(0.8, content.height * 0.026)
        let spot = CGPoint(x: body.minX, y: body.minY + h * 5 + 4 * h * 3.6 + h * 0.5)
        let words = String(localized: "Web'den kopyalanan yazı")
        let k = effect
        if k < 1 {
            // Kopyalanan hali: sitedeki gibi pembe, kalın, iri, sarı vurgulu
            var c = ctx
            c.opacity = window(timing.chipIn, timing.reset) * (1 - k)
            let fancy = c.resolve(Text(verbatim: words).font(.system(size: h * 3, weight: .heavy, design: .serif)).foregroundStyle(hex(0xe0306a)))
            let ts = fancy.measure(in: size)
            let at = CGPoint(x: spot.x, y: spot.y - h * 5 * (1 - k))
            c.fill(Path(roundedRect: CGRect(x: at.x - h * 0.6, y: at.y - ts.height / 2, width: ts.width + h * 1.2, height: ts.height),
                        cornerRadius: h * 0.6), with: .color(hex(0xfff3a0)))
            c.draw(fancy, at: at, anchor: .leading)
        }
        if k > 0 {
            // Yapıştırılan hali: notun öbür satırlarıyla aynı boy ve renk
            var c = ctx
            c.opacity = k
            c.draw(Text(verbatim: words).font(.system(size: h * 2.2)).foregroundStyle(ink.opacity(0.8)), at: spot, anchor: .leading)
        }
    }

    // MARK: Daire menü

    var radialCenter: CGPoint { CGPoint(x: W / 2, y: H * 0.52) }
    var radialRadius: Double { H * 0.3 }
    /// Daire sonuçta açık kalır mı (daire örneği, Denetim Merkezi düğmeleri); kısayol ve uygulamada tıkla kapanır
    var radialKeepsOpen: Bool {
        if demo.effect == .radialMenu { return true }
        if case .control = demo.effect { return true }
        return false
    }
    /// Seçilen dilim: kısayollar üst yarıda, uygulamalar alt yarıda
    var litSlice: Int {
        switch demo.effect {
        case .openApp, .radialMenu: 8
        case .control(let control): Self.demoControls(control).firstIndex(of: control) ?? 0
        default: 3
        }
    }

    /// Örnek dairenin üst yarısındaki düğmeler: varsayılan dört, önerilen düğme listede yoksa beşinci
    static func demoControls(_ shown: SystemControl) -> [SystemControl] {
        SystemControl.defaults.contains(shown) ? SystemControl.defaults : SystemControl.defaults + [shown]
    }

    /// Örnekte düğmenin önceki ve sonraki hâli: aç/kapa (Bluetooth ve Wi-Fi söner, diğerleri açılır), çubuk değeri
    var controlBefore: Bool {
        guard case .control(let c) = demo.effect else { return false }
        return c == .bluetooth || c == .wifi
    }
    /// Basılı tutarken çubuk: %82'den %30'a iner, sonra %82'ye çıkar; bırakınca yerinde kalır
    var sliderLevel: Double {
        let hold = timing.reset - 0.35 - timing.click
        let p = easeInOut(ramp(timing.click, hold))
        return 0.56 + 0.26 * cos(2 * .pi * p)
    }
    /// Dilimin ortası (imlecin gittiği yer); 0-5 üst yarı soldan sağa, 6-11 alt yarı sağdan sola
    func slicePoint(_ i: Int, radius: Double) -> CGPoint {
        let mid = Angle.degrees(Double(i) * 30 + 195).radians
        return CGPoint(x: radialCenter.x + cos(mid) * radius * 0.68, y: radialCenter.y + sin(mid) * radius * 0.68)
    }

    /// Uygulamadaki daire gibi: koyu buzlu cam, ayrık dilimler, seçili dilim vurgu renginde, adı ortada
    func drawRadial(_ ctx: inout GraphicsContext, center: CGPoint, progress: Double, lit: Int?) {
        let radius = radialRadius * (0.8 + 0.2 * easeOut(progress))
        var c = ctx
        c.opacity = min(1, progress * 1.6)
        // Gerçek daire gibi: arkada daire yok, köşeleri yuvarlak ayrı dilimler
        let round = radius * 0.05
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.4), radius: W * 0.012, y: W * 0.005))
        for i in 0..<12 {
            let pad = 1.6 + Double(round / (radius * 0.62)) * 180 / .pi
            let a0 = Angle.degrees(Double(i) * 30 + 180 + pad), a1 = Angle.degrees(Double(i + 1) * 30 + 180 - pad)
            var slice = Path()
            slice.addArc(center: center, radius: radius * 0.94 - round, startAngle: a0, endAngle: a1, clockwise: false)
            slice.addArc(center: center, radius: radius * 0.31 + round, startAngle: a1, endAngle: a0, clockwise: true)
            slice.closeSubpath()
            let soft = slice.strokedPath(StrokeStyle(lineWidth: round * 2, lineJoin: .round)).union(slice)
            let on = i == lit
            // Ses/parlaklık dilimi seçilince zemini değil dolgusu sarı olur (uygulamadaki gibi): çubuğun inip çıkışı görünür
            let sliderSlice: Bool = {
                guard i < 6, case .control(let shown) = demo.effect, case let controls = Self.demoControls(shown), i < controls.count else { return false }
                return controls[i].kind == .slider
            }()
            if on, sliderSlice {
                shadow.fill(soft, with: .color(hex(0x34343a).opacity(0.96)))
            } else if on {
                var glow = c
                glow.addFilter(.shadow(color: gold.opacity(0.7), radius: W * 0.015))
                glow.fill(soft, with: .linearGradient(Gradient(colors: [goldDeep, gold, goldLight]),
                                                      startPoint: center, endPoint: slicePoint(i, radius: radius)))
            } else {
                shadow.fill(soft, with: .color(hex(0x1e1e22).opacity(0.94)))
            }
            let p = slicePoint(i, radius: radius)
            // Üst yarı kısayol (yazı çizgisi), alt yarı uygulama (renkli kare)
            let s = radius * 0.13
            if i < 6, case .control(let shown) = demo.effect, case let controls = Self.demoControls(shown), i < controls.count {
                drawDemoControl(&c, controls[i], at: p, size: s, lit: on, shown: shown, radius: radius, index: i)
            } else if i < 6 {
                c.fill(Path(roundedRect: CGRect(x: p.x - s * 0.6, y: p.y - s * 0.12, width: s * 1.2, height: s * 0.24), cornerRadius: s * 0.12),
                       with: .color(on ? ink.opacity(0.85) : .white.opacity(0.75)))
            } else {
                let k = on ? 1.25 : 1
                c.fill(Path(roundedRect: CGRect(x: p.x - s * k / 2, y: p.y - s * k / 2, width: s * k, height: s * k), cornerRadius: s * 0.24),
                       with: .color(Color(hue: Double(i) / 12, saturation: 0.6, brightness: 0.95)))
            }
        }
        // Ortada seçilen dilimin adı
        let hub = radius * 0.3
        c.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)), with: .color(hex(0x26262a)))
        if lit != nil, let slice, !slice.isEmpty {
            // Uzun ad satırlara bölünür (sözcük ortadan kesilmez), her satır ortalanır; sığmazsa küçülür.
            // Satırlar tek tek ortadan çizilir: kutuya çizince yazı sol üste yaslanıyordu.
            let base = max(4, radialRadius * 0.1)
            let box = CGSize(width: hub * 1.75, height: hub * 1.3)
            func width(_ t: String, _ fs: Double) -> Double {
                c.resolve(Text(verbatim: t).font(.system(size: fs, weight: .semibold))).measure(in: size).width
            }
            let words = slice.split(separator: " ").map(String.init)
            let longest = words.map { width($0, base) }.max() ?? 0
            let fs = longest > box.width ? base * box.width / longest : base
            var lines: [String] = []
            for word in words {
                if let last = lines.last, width(last + " " + word, fs) <= box.width {
                    lines[lines.count - 1] = last + " " + word
                } else {
                    lines.append(word)
                }
            }
            let lineHeight = fs * 1.2
            for (n, line) in lines.enumerated() {
                let y = center.y + (Double(n) - Double(lines.count - 1) / 2) * lineHeight
                c.draw(Text(verbatim: line).font(.system(size: fs, weight: .semibold)).foregroundStyle(.white),
                       at: CGPoint(x: center.x, y: y), anchor: .center)
            }
        }
    }

    /// Örnek dairede Denetim Merkezi dilimi, uygulamadaki gibi: ses ve parlaklık iç kenardan dolan çubuk,
    /// aç/kapa düğmeleri (Bluetooth, AirDrop…) açıkken dilimin tamamı dolu. İçte simge, dışta kutusuz durum yazısı.
    /// Yazı boyutları açılış büyümesinden etkilenmez (`radialRadius`), yazı titremez.
    func drawDemoControl(_ c: inout GraphicsContext, _ control: SystemControl, at p: CGPoint, size s: Double,
                                 lit: Bool, shown: SystemControl, radius: Double, index i: Int) {
        let changed = control == shown && time >= timing.click && time < timing.reset
        let on = control == shown && control.kind != .slider ? (changed ? !controlBefore : controlBefore) : true
        let level: Double = control.kind == .slider ? (control == shown ? sliderLevel : 0.6) : (on ? 1 : 0)
        let round = radius * 0.05
        let pad = 1.6 + Double(round / (radius * 0.62)) * 180 / .pi
        let a0 = Angle.degrees(Double(i) * 30 + 180 + pad), a1 = Angle.degrees(Double(i + 1) * 30 + 180 - pad)
        let r0 = radius * 0.31 + round, r1 = r0 + (radius * 0.94 - round - r0) * level
        var filled: Path?
        if level > 0.005 {
            var fill = Path()
            fill.addArc(center: radialCenter, radius: r1, startAngle: a0, endAngle: a1, clockwise: false)
            fill.addArc(center: radialCenter, radius: r0, startAngle: a1, endAngle: a0, clockwise: true)
            fill.closeSubpath()
            let soft = fill.strokedPath(StrokeStyle(lineWidth: round * 2, lineJoin: .round)).union(fill)
            filled = soft
            c.fill(soft, with: lit ? .linearGradient(Gradient(colors: [goldDeep, gold, goldLight]), startPoint: radialCenter, endPoint: p)
                                   : .linearGradient(Gradient(colors: [hex(0xf2f2f2), hex(0xcfcfd2)]), startPoint: radialCenter, endPoint: p))
        }
        let mid = Angle.degrees(Double(i) * 30 + 195).radians
        func at(_ k: Double) -> CGPoint { CGPoint(x: radialCenter.x + cos(mid) * radius * k, y: radialCenter.y + sin(mid) * radius * k) }
        let iconAt = at(0.43)
        let filledIcon = r1 > radius * 0.5
        let glyph = filledIcon ? ink.opacity(0.8) : Color.white.opacity(0.92)
        let g = radialRadius * 0.11
        if let drawn = DrawnGlyph(control: control) {
            let h = g * (control == .bluetooth ? 1.05 : 0.95), w = h * drawn.aspect
            c.fill(drawn.path(in: CGRect(x: iconAt.x - w / 2, y: iconAt.y - h / 2, width: w, height: h)), with: .color(glyph))
        } else {
            drawSymbol(&c, control.symbol(on: on), at: iconAt, size: g * 0.9, color: glyph)
        }
        // Durum: yüzde, Açık / Kapalı, AirDrop'ta Kişiler
        let status: String = switch control.kind {
        case .slider: level.formatted(.percent.precision(.fractionLength(0)))
        case .choice: on ? AirDropMode.contacts.short : AirDropMode.off.short
        default: on ? String(localized: "Açık") : String(localized: "Kapalı")
        }
        // Kutusuz, dilimin ortasında, tabanı göbeğe bakacak biçimde döndürülmüş. Dolgu yazının neresine
        // ulaştıysa o kısım koyu çizilir (yazı hep okunur, dolgu inip çıkarken yazı da onunla renk değiştirir).
        let fs = radialRadius * 0.08
        func label(_ ink: Color) -> Text {
            status.hasPrefix("%")
                ? Text(verbatim: "%").font(.system(size: fs * 0.8, weight: .semibold)).foregroundStyle(ink.opacity(0.8))
                    + Text(verbatim: String(status.dropFirst())).font(.system(size: fs, weight: .bold).monospacedDigit()).foregroundStyle(ink)
                : status.hasSuffix("%")
                ? Text(verbatim: String(status.dropLast())).font(.system(size: fs, weight: .bold).monospacedDigit()).foregroundStyle(ink)
                    + Text(verbatim: "%").font(.system(size: fs * 0.8, weight: .semibold)).foregroundStyle(ink.opacity(0.8))
                : Text(verbatim: status).font(.system(size: fs * 0.95, weight: .semibold)).foregroundStyle(ink)
        }
        // Dilimin içiyle dışı arasında tam ortada
        let tp = at(0.64)
        func draw(_ ctx: GraphicsContext, _ ink: Color) {
            var t = ctx
            t.translateBy(x: tp.x, y: tp.y)
            t.rotate(by: .radians(mid + .pi / 2))
            t.draw(label(ink), at: .zero)
        }
        draw(c, Color.white)
        if let filled {
            var d = c
            d.clip(to: filled)
            draw(d, ink.opacity(0.92))
        }
    }

    // MARK: İmleç

    /// İmlecin yeri ve bağlantı üstünde mi (el olur); imleçsiz örneklerde nil
    var pointer: (point: CGPoint, hand: Bool)? {
        switch timing.mode {
        case .cursor where demo.effect == .newTabFromLink:
            let link = linkRect(in: pageRect(safariFrame))
            let target = CGPoint(x: link.minX + link.width * 0.45, y: link.midY)
            let k = easeInOut(ramp(timing.cursorArrive - 0.6, 0.6))
            return (lerp(CGPoint(x: W * 0.66, y: H * 0.74), target, k), k >= 1 && time < timing.reset)
        case .cursor:
            // Pencere taşıma: imleç pencerenin üst kısmında, pencereyle birlikte kayar
            let f = movingFrame
            return (CGPoint(x: f.minX + f.width * 0.5, y: f.minY + f.height * 0.06), false)
        case .radial:
            let k = easeInOut(ramp(timing.cursorArrive - 0.4, 0.4))
            let atSlice = lerp(radialCenter, slicePoint(litSlice, radius: radialRadius), k)
            if case .control(let control) = demo.effect {
                if control.kind == .slider, time >= timing.click {
                    // Basılı tutup içe, sonra dışa sürükler: imleç çubuğun dolu ucunu izler
                    // Dilimin kenarına yakın: ortadaki yüzde yazısını örtmesin
                    let mid = Angle.degrees(Double(litSlice) * 30 + 195 - 9).radians
                    let r = radialRadius * (0.31 + 0.63 * sliderLevel - 0.1)
                    return (CGPoint(x: radialCenter.x + cos(mid) * r, y: radialCenter.y + sin(mid) * r), false)
                }
            }
            return (atSlice, false)
        default:
            return nil
        }
    }

    /// Mac'in gerçek imleci (bağlantı üstünde el)
    func drawPointer(_ ctx: inout GraphicsContext) {
        guard let (p, hand) = pointer else { return }
        // Tıklama gösterişsiz: imleç bir an hafifçe küçülür (halka yok, Mac'te de yok).
        // Ekranda hep aynı, gerçekçi boyut: yakınlaştırma imleci büyütmez.
        let press = time >= timing.click && time < timing.click + 0.14 ? 0.88 : 1
        let scale = 0.8 * min(1.3, max(1, W / 400)) * press / max(1, zoom.scale)
        if hand {
            ctx.draw(cursors.hand, in: CGRect(x: p.x - cursors.handHotSpot.x * scale, y: p.y - cursors.handHotSpot.y * scale,
                                              width: cursors.handSize.width * scale, height: cursors.handSize.height * scale))
        } else {
            drawArrow(&ctx, at: p, scale: scale)
        }
    }

    /// macOS ok imleci: siyah ok, beyaz kenar, hafif gölge (17x23 pt, uç noktası sol üstte)
    func drawArrow(_ ctx: inout GraphicsContext, at p: CGPoint, scale: Double) {
        let points: [(Double, Double)] = [(0, 0), (0, 16.2), (3.9, 12.5), (6.6, 18.8), (9.2, 17.7), (6.6, 11.6), (11.8, 11.6)]
        var arrow = Path()
        arrow.addLines(points.map { CGPoint(x: p.x + $0.0 * scale, y: p.y + $0.1 * scale) })
        arrow.closeSubpath()
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.4), radius: 1.2 * scale, y: 0.8 * scale))
        shadow.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 2.4 * scale, lineJoin: .round))
        ctx.fill(arrow, with: .color(.black))
    }

    func drawSymbol(_ ctx: inout GraphicsContext, _ name: String, at p: CGPoint, size: Double, color: Color) {
        ctx.draw(Text(Image(systemName: name)).font(.system(size: size)).foregroundStyle(color), at: p)
    }

    // MARK: Ortadaki kısayol ve alttaki cümle

    /// Kısayolun yeri: ortada; imleçli örneklerde imlecin üstüne binmesin diye yukarıda
    var chipCenter: (point: CGPoint, size: Double) {
        switch timing.mode {
        case .radial: (CGPoint(x: W * 0.84, y: H * 0.14), W * 0.095)
        case .cursor where demo.effect == .newTabFromLink: (CGPoint(x: W * 0.62, y: H * 0.36), W * 0.09)
        case .cursor: (CGPoint(x: W * 0.78, y: H * 0.18), W * 0.09)
        default: (CGPoint(x: W / 2, y: H / 2), W * 0.115)
        }
    }

    func drawChip(_ ctx: inout GraphicsContext) {
        guard let chip, !chip.isEmpty else { return }
        let a = window(timing.chipIn, timing.chipOut, fade: 0.2)
        guard a > 0 else { return }
        // Dairede kısayol yanda kalır, daireye binmez
        let k = timing.mode == .radial ? 0 : zoomProgress
        let center = lerp(chipCenter.point, CGPoint(x: W / 2, y: H * 0.7), k)
        let base = chipCenter.size * (1 - 0.25 * k)
        let fs = base * (0.92 + 0.08 * a)
        let text = ctx.resolve(Text(verbatim: chip).font(.system(size: fs, weight: .semibold)).foregroundStyle(.white))
        let ts = text.measure(in: size)
        let box = CGRect(x: center.x - ts.width / 2 - fs * 0.55, y: center.y - ts.height / 2 - fs * 0.15,
                         width: ts.width + fs * 1.1, height: ts.height + fs * 0.3)
        var c = ctx
        c.opacity = a
        let shape = Path(roundedRect: box, cornerRadius: fs * 0.3)
        c.fill(shape, with: .color(hex(0x0c0c0e).opacity(0.78)))
        c.stroke(shape, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
        c.draw(text, at: center)
    }

    func drawCaption(_ ctx: inout GraphicsContext) {
        guard let caption, !caption.isEmpty else { return }
        let a = window(timing.captionIn, timing.reset, fade: 0.25)
        guard a > 0 else { return }
        // Daireye yakınlaşılmışken alt yazı küçülüp en alta iner, dilimlere binmez; sonuçta yerine döner
        let k = timing.mode == .radial ? zoomProgress : 0
        let fs = max(9, W * (0.056 - 0.006 * k))
        let y = H * (0.855 + 0.07 * k)
        let text = ctx.resolve(Text(verbatim: caption).font(.system(size: fs, weight: .semibold)).foregroundStyle(.white))
        let ts = text.measure(in: CGSize(width: W * 0.88, height: H))
        let box = CGRect(x: W / 2 - ts.width / 2 - fs, y: y - ts.height / 2 - fs * 0.4,
                         width: ts.width + fs * 2, height: ts.height + fs * 0.8)
        var c = ctx
        c.opacity = a
        c.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(.black.opacity(0.6)))
        c.draw(text, in: CGRect(x: W / 2 - ts.width / 2, y: y - ts.height / 2, width: ts.width, height: ts.height))
    }

    // MARK: Parmaklar

    func drawInput(_ ctx: inout GraphicsContext) {
        switch demo.input {
        case .gesture(let g): drawGesture(&ctx, g)
        case .keys: break
        case .hyperDrag:
            let p = CGPoint(x: W * (0.34 + 0.32 * ease(motion)), y: H * (0.42 + 0.2 * ease(motion)))
            drawFinger(&ctx, p, alpha: fingerAlpha)
        }
    }

    /// Parmaklar belirir, hareket boyunca durur, sonra kaybolur
    var fingerAlpha: Double { window(timing.fingersIn, timing.fingersOut, fade: 0.2) * (1 - 0.85 * zoomProgress) }
    var fingerSize: Double { W * 0.075 }

    /// Altın sarısı, eşit, büyük parmak; çembersiz, katmanlı gölge, yukarıdan aşağı açık-koyu sarı geçiş,
    /// üstte hafif parlaklık; `press` basılınca küçülüp koyulaşır. `scale` ile büyütülebilir (köşe tıklaması).
    func drawFinger(_ ctx: inout GraphicsContext, _ p: CGPoint, alpha: Double, press: Double = 0, scale: Double = 1) {
        guard alpha > 0 else { return }
        let r = fingerSize / 2 * scale * (1 - 0.14 * press)
        var c = ctx
        c.opacity = alpha
        let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        // Gölge: bulanık filtre yerine iki yumuşak halka (her karede ucuz)
        for (grow, dy, o) in [(1.45, 0.16, 0.08), (1.15, 0.08, 0.16)] {
            let s = r * grow
            c.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s + r * dy * 2, width: s * 2, height: s * 2)),
                   with: .radialGradient(Gradient(colors: [.black.opacity(o * 2), .black.opacity(0)]),
                                         center: CGPoint(x: p.x, y: p.y + r * dy * 2), startRadius: r * 0.7, endRadius: s))
        }
        c.fill(dot, with: .linearGradient(Gradient(colors: [goldLight, gold, goldDeep.opacity(0.95 + 0.05 * press)]),
                                          startPoint: CGPoint(x: p.x, y: p.y - r), endPoint: CGPoint(x: p.x, y: p.y + r)))
        c.stroke(dot, with: .color(goldDeep.opacity(0.5)), lineWidth: max(0.5, r * 0.04))
        let gloss = CGRect(x: p.x - r * 0.62, y: p.y - r * 0.82, width: r * 1.24, height: r * 0.8)
        c.fill(Path(ellipseIn: gloss), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
            startPoint: CGPoint(x: gloss.midX, y: gloss.minY), endPoint: CGPoint(x: gloss.midX, y: gloss.maxY)))
    }

    /// Dokunuş: `at` anında hızla basılır, bırakılır (0-1-0)
    func tapPulse(_ at: Double) -> Double {
        let d = (time - at) / 0.18
        return d < 0 || d > 1 ? 0 : sin(d * .pi)
    }

    /// Bastırma ya da dokunuşta parmakların çevresinde yayılan halka
    func drawRipple(_ ctx: inout GraphicsContext, at p: CGPoint, start: Double, scale: Double = 1) {
        let k = ramp(start, 0.5)
        guard k > 0, k < 1 else { return }
        let r = fingerSize / 2 * scale + W * 0.05 * scale * k
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .color(gold.opacity(0.9 * (1 - k))), lineWidth: W * 0.005 * scale)
    }

    func drawGesture(_ ctx: inout GraphicsContext, _ g: Gesture) {
        let n = g.fingers
        let spacing = fingerSize + W * 0.026
        func row(_ center: CGPoint) -> [CGPoint] {
            (0..<n).map { i in CGPoint(x: center.x + (Double(i) - Double(n - 1) / 2) * spacing, y: center.y) }
        }
        let start = timing.motionStart
        // İmleçli örnekte parmaklar sağ altta: imleci ve bağlantıyı örtmesin
        let mid = timing.mode == .cursor ? CGPoint(x: W * 0.64, y: H * 0.66) : CGPoint(x: W / 2, y: H * 0.32)
        let tapY = mid.y
        switch g.shape {
        case .swipe(let dir):
            // Örnek sayfadaki gibi: üstten (%14) aşağıya (%62) yavaşça
            let k = easeInOut(motion)
            let top = H * 0.14 + fingerSize / 2, bottom = H * 0.62 + fingerSize / 2
            let center: CGPoint = switch dir {
            case .down: CGPoint(x: W / 2, y: top + (bottom - top) * k)
            case .up: CGPoint(x: W / 2, y: bottom - (bottom - top) * k)
            case .left: CGPoint(x: W * (0.62 - 0.24 * k), y: H * 0.36)
            case .right: CGPoint(x: W * (0.38 + 0.24 * k), y: H * 0.36)
            }
            for p in row(center) { drawFinger(&ctx, p, alpha: fingerAlpha) }
        case .click:
            let press = ramp(start, 0.12) * (1 - ramp(start + 0.45, 0.15))
            for p in row(mid) {
                drawFinger(&ctx, p, alpha: fingerAlpha, press: press)
                drawRipple(&ctx, at: p, start: start)
            }
        case .tap:
            for p in row(mid) {
                drawFinger(&ctx, p, alpha: fingerAlpha, press: tapPulse(start))
                drawRipple(&ctx, at: p, start: start)
            }
        case .doubleTap:
            for p in row(mid) {
                drawFinger(&ctx, p, alpha: fingerAlpha, press: max(tapPulse(start), tapPulse(start + 0.3)))
                drawRipple(&ctx, at: p, start: start)
                drawRipple(&ctx, at: p, start: start + 0.3)
            }
        case .tipTap(let side):
            let anchor = CGPoint(x: W / 2 + (side == .right ? -spacing / 2 : spacing / 2), y: tapY)
            drawFinger(&ctx, anchor, alpha: fingerAlpha)
            let other = CGPoint(x: anchor.x + (side == .right ? spacing : -spacing), y: tapY)
            let pulse = tapPulse(start)
            drawFinger(&ctx, other, alpha: fingerAlpha * (time < start ? 0 : (time > start + 0.6 ? 0 : 1)), press: pulse)
            drawRipple(&ctx, at: other, start: start)
        case .edgeSwipe(let edge):
            let k = easeInOut(motion)
            let e = fingerSize * 0.6
            let p: CGPoint = switch edge {
            case .left: CGPoint(x: e + W * 0.3 * k, y: H * 0.45)
            case .right: CGPoint(x: W - e - W * 0.3 * k, y: H * 0.45)
            case .top: CGPoint(x: W / 2, y: menuBarHeight + e + H * 0.4 * k)
            case .bottom: CGPoint(x: W / 2, y: H - e - H * 0.4 * k)
            }
            drawFinger(&ctx, p, alpha: fingerAlpha)
        case .cornerTap(let corner):
            // Daire menünün köşe tıklaması iri parmakla, iki halkayla: nereye basıldığı belli olsun
            let big = g == .cornerTapBottomLeft ? 1.6 : 1
            let ix = W * 0.1 * big, iy = H * 0.16 * big
            let p: CGPoint = switch corner {
            case .topLeft: CGPoint(x: ix, y: iy)
            case .topRight: CGPoint(x: W - ix, y: iy)
            case .bottomLeft: CGPoint(x: ix, y: H - iy)
            case .bottomRight: CGPoint(x: W - ix, y: H - iy)
            }
            // Daire menü bastırarak tıklamayla açılır; köşeler dokunmayla
            let isClick = g == .cornerTapBottomLeft
            let press = isClick ? ramp(start, 0.12) * (1 - ramp(start + 0.45, 0.15)) : tapPulse(start)
            drawFinger(&ctx, p, alpha: fingerAlpha, press: press, scale: big)
            drawRipple(&ctx, at: p, start: start, scale: big)
            if isClick { drawRipple(&ctx, at: p, start: start + 0.18, scale: big) }
        }
    }
}

extension CommunityPick {
    /// Daire menü örneğinde seçilen dilimin adı: sabitlenen kısayol ya da uygulama
    var demoSlice: String? {
        for change in changes {
            switch change {
            case let .radialShortcut(_, title, _): return title
            case let .radialApp(_, name): return name
            case let .radialControl(control): return control.title
            default: continue
            }
        }
        return nil
    }

    /// Önizlemenin ortasında beliren kısayol: önerinin gönderdiği tuşlar ya da basılan tuşlar
    var demoChip: String? {
        switch demo.input {
        case .keys(let keys):
            return keys.first == "⇪" ? "⇪ + " + keys.dropFirst().joined(separator: " ") : keys.joined()
        case .hyperDrag:
            return "⇪"
        case .gesture(let shown):
            // Önizlemede yapılan hareketin kısayolu (TipTap'te iki hareket var, gösterilen sağa dokunma)
            if case let .gesture(_, shortcut)? = changes.first(where: { if case .gesture(shown, _) = $0 { true } else { false } }) {
                return shortcut.display
            }
            for change in changes {
                switch change {
                case let .gesture(_, shortcut): return shortcut.display
                case let .radialShortcut(_, _, send): return send.display
                default: continue
                }
            }
            return nil
        }
    }
}

/// Geliştirme için: tüm örnekleri birkaç anda resme çizer (FingerKit --ornekleri-ciz <klasör>)
@MainActor
enum DemoSnapshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for pick in CommunityPick.all {
            let timing = DemoTiming(pick.demo)
            let moments = Array(Set([timing.still, timing.effectStart + 0.15, timing.effectStart + 0.5,
                                     timing.captionIn + 0.5, timing.reset - 0.2])).sorted()
            let strip = HStack(spacing: 6) {
                ForEach(moments, id: \.self) { t in
                    CommunityDemoView(demo: pick.demo, chip: pick.demoChip, caption: pick.title, slice: pick.demoSlice,
                                      playing: false, frozenAt: t)
                        .frame(width: 320)
                }
            }
            .padding(6)
            .background(Color.white)
            let renderer = ImageRenderer(content: strip)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: dir.appendingPathComponent("\(pick.id).png"))
        }
        renderWheels(to: dir)
    }

    /// Geliştirme için: adında `filter` geçen örneklerin döngüsünü 0,15 sn arayla kare kare çizer
    /// (FingerKit --kareleri-ciz <klasör> <ad parçası>); yazı kayması, taşma gibi şeyler böyle görülür
    static func frames(to dir: URL, matching filter: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for pick in CommunityPick.all where pick.id.contains(filter) {
            let timing = DemoTiming(pick.demo)
            let times = stride(from: 0.0, to: timing.cycle, by: 0.15).map { $0 }
            let grid = VStack(spacing: 4) {
                ForEach(0..<(times.count + 5) / 6, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(times.dropFirst(row * 6).prefix(6), id: \.self) { t in
                            CommunityDemoView(demo: pick.demo, chip: pick.demoChip, caption: pick.title, slice: pick.demoSlice,
                                              playing: false, frozenAt: t)
                                .frame(width: 320, height: 200)
                                .overlay(alignment: .topLeading) { Text(String(format: "%.2f", t)).font(.caption2).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .padding(4)
            .background(Color.white)
            let renderer = ImageRenderer(content: grid)
            renderer.scale = 2
            if let image = renderer.nsImage, let png = image.pngData() {
                try? png.write(to: dir.appendingPathComponent("\(pick.id)-kareler.png"))
            }
        }
    }

    private static func renderWheels(to dir: URL) {
        // Gerçek daire menü: bir kısayol ve bir uygulama seçiliyken
        let shortcuts = ["Yeni sekme", "Adres çubuğu", "Kapanan sekmeyi aç", "Yer imi ekle", "Okuma listesi", "Bul"].enumerated().map {
            RadialSlot(slot: $0.offset, item: RadialShortcut(title: $0.element, keys: "⌘T", action: .shortcut(Shortcut(keyCode: 17, modifiers: [.command], key: "T"))),
                       pinned: $0.offset == 0)
        }
        let apps = ["com.apple.finder", "com.apple.Notes", "com.apple.Terminal", "com.apple.systempreferences", "com.apple.mail", "com.apple.Music"]
            .enumerated().map { RadialSlot(slot: $0.offset, item: RadialApp(bundleID: $0.element, name: $0.element), pinned: false) }
        // Üçüncü ve dördüncü: Denetim Merkezi düğmeleriyle (ses çubuğu seçili; AirDrop seçimi açık)
        let wheels = HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { n in
                let pick: RadialPick? = [RadialPick.top(2), .bottom(1), .top(1), .top(2)][n]
                let state = RadialState()
                let _ = {
                    state.apps = apps; state.appName = "Safari"; state.pick = pick
                    if n >= 2 {
                        state.controls = SystemControl.defaults
                        state.shortcuts = Array(shortcuts.prefix(2))
                        state.values = [.bluetooth: .on(true), .volume: .level(0.62), .brightness: .level(0.35), .airDrop: .airDrop(.contacts)]
                        state.choosingAirDrop = n == 3
                    } else {
                        state.shortcuts = shortcuts
                    }
                }()
                RadialWheel(state: state, geometry: RadialMenu.geometry)
            }
        }
        .padding(20)
        .background(Color(white: 0.75))
        renderBoard(to: dir)
        let renderer = ImageRenderer(content: wheels)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("daire-gercek.png"))
        }
    }
}

/// Büyük panonun örnek görüntüsü (örnek kopyalarla; kullanıcının gerçek kopyaları çizilmez)
@MainActor
private func renderBoard(to dir: URL) {
    let state = BoardState()
    var h = ClipboardHistory()
    let icon = URL(fileURLWithPath: "docs/icon.png").path
    h.add(ClipItem(kind: .image, text: "Ekran Resmi", date: .now - 600, file: icon, hash: "ornek"))
    h.add("https://github.com/enisaytac/FingerKit", at: .now - 300)
    h.add("Toplantı yarın 10:00'da, ikinci kattaki odada.", at: .now - 200)
    h.add("https://www.apple.com/macos/", at: .now - 100)
    h.add("Kargo takip no: 1Z999AA10123456784", at: .now - 50)
    h.togglePin(h.items.first { $0.text.hasPrefix("Toplantı") }!.id)
    state.history = h
    state.cursor = state.firstCursor()
    let board = ClipboardBoard(state: state, pick: { _ in }, pin: { _ in }, readText: { _ in })
        .frame(width: 1040, height: 620)
    let renderer = ImageRenderer(content: board)
    renderer.scale = 1
    if let image = renderer.nsImage, let png = image.pngData() {
        try? png.write(to: dir.appendingPathComponent("pano-ornek.png"))
    }
}

// MARK: - Yardımcılar

func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
func ease(_ v: Double) -> Double { v * v * (3 - 2 * v) }
func easeOut(_ v: Double) -> Double { 1 - pow(1 - v, 3) }
/// Örnek sayfadaki cubic-bezier(.45,.05,.35,1)'e yakın: yavaş başlar, yumuşak durur
func easeInOut(_ v: Double) -> Double { v < 0.5 ? 4 * v * v * v : 1 - pow(-2 * v + 2, 3) / 2 }
func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
}
func lerp(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
           width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
}
extension Color {
    /// FingerKit'in parmak ve seçim rengi: güneş sarısının biraz koyusu; açığı üstte, koyusu altta kullanılır
    static let fingerGold = Color(nsColor: NSColor(srgbRed: CGFloat((ThemePalette.yellow >> 16) & 0xff) / 255,
                                                   green: CGFloat((ThemePalette.yellow >> 8) & 0xff) / 255,
                                                   blue: CGFloat(ThemePalette.yellow & 0xff) / 255, alpha: 1))
    static let fingerGoldLight = fingerGold.mix(with: .white, by: 0.3)
    static let fingerGoldDeep = fingerGold.mix(with: .black, by: 0.13)
}

func hex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
