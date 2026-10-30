import AppKit
import SwiftUI
import FingerKitCore

/// Tanıtım videosu, tek çekim: aynı masaüstü ve aynı Safari penceresi baştan sona durur, özellikler
/// art arda bu pencerede olur (sekmeler açılır kapanır, daire açılır, pencere yaslanır). Arada karartma yok.
/// Parmaklar alt ortadaki büyük trackpad çiziminde görünür ve imleçle eşzamanlıdır: imleç nereye giderse
/// parmak trackpad'in aynı yerindedir. Kısayol ekranın ortasında, açıklama trackpad'in üstünde.
/// Çizimler önizlemelerinkidir (`DemoPainter`); zaman çizelgesi, sahne durumu ve GitHub benzeri sayfa burada.
/// Kareleri `--videolari-ciz <klasör>` yazar; videoya `Araclar/gosteri/video.sh` çevirir.
@MainActor
struct PromoStory {
    enum Act {
        case middleClick, closeTab, reopenTab, brightness, screenshot, snapAll
        /// FingerKit penceresinde yeni hareket kaydedilir (4 parmak aşağı → ⌘M) ve hemen kullanılır
        case customGesture
        /// Her şey kararır; yalnız simge, ad, tek cümle ve imza
        case endCard
    }

    let acts: [Act]
    var leadIn = 0.5
    var tail = 0.4

    static let size = CGSize(width: 1280, height: 800)
    static let fps = 60.0
    static let green = Color(red: 0.2, green: 0.78, blue: 0.35)

    var duration: Double { leadIn + acts.map(Self.length).reduce(0, +) + tail }

    static func length(_ act: Act) -> Double {
        switch act {
        case .middleClick: 2.0
        case .closeTab, .reopenTab: 1.45
        case .brightness: 3.6
        case .screenshot: 3.4
        case .snapAll: 2.6
        case .customGesture: 4.9
        case .endCard: 3.0
        }
    }

    var pad: CGRect { CGRect(x: 440, y: 538, width: 400, height: 244) }

    // MARK: Sahne durumu

    private struct Tab { var site: Int; var width = 1.0 }
    private enum PointerStyle { case arrow, hand, cross }

    private struct World {
        var tabs: [Tab] = [Tab(site: 0), Tab(site: 1)]
        var active = 0.0
        /// Sekme değişirken gösterilen site (geçişin ortasında değişir)
        var pageSite: Int?
        var closed: (site: Int, index: Int)?
        var frame: CGRect
        var pointer: CGPoint
        var pointerStyle = PointerStyle.arrow
        var pointerAlpha = 1.0
        /// Pencere Dock'a küçülüyor (0-1)
        var minimize = 0.0
        var padAlpha = 1.0
        var endCard = 0.0
        // Yalnız o an süren işte
        var chip: (text: String, alpha: Double)?
        var caption: (text: String, alpha: Double)?
        var headline: (text: String, alpha: Double)?
        var fingers: [CGPoint] = []
        var fingerAlpha = 0.0
        var press = 0.0
        var ripples: [(CGPoint, Double)] = []
        var overlays: [(GraphicsContext) -> Void] = []
    }

    // MARK: Çizim

    func draw(_ ctx: inout GraphicsContext, at t: Double) {
        let base = painter(CommunityDemo(.keys([]), .snapAll), time: t)
        var w = World(frame: base.safariFrame, pointer: CGPoint(x: Self.size.width * 0.62, y: Self.size.height * 0.5))

        var start = leadIn
        for act in acts {
            let length = Self.length(act)
            let tau = t - start
            if tau < 0 { break }
            apply(act, tau: min(tau, length), length: length, live: tau < length, &w, base)
            start += length
        }

        base.drawWallpaper(&ctx)
        base.drawMenuBar(&ctx)
        base.drawDock(&ctx)
        if w.minimize < 1 {
            // Küçülürken pencere Dock'un sağ ucuna doğru gider
            let m = easeInOut(w.minimize)
            let dock = base.dockFrame
            let spot = CGRect(x: dock.maxX - 70, y: dock.minY + 6, width: 56, height: 35)
            var wc = ctx
            wc.opacity = 1 - 0.8 * m
            drawBrowser(&wc, base, w, frame: lerp(w.frame, spot, m))
        }
        for overlay in w.overlays { overlay(ctx) }
        drawPointer(&ctx, base, w)
        if let chip = w.chip, chip.alpha > 0 { drawChip(&ctx, chip.text, alpha: chip.alpha) }
        if let caption = w.caption, caption.alpha > 0 { drawLabel(&ctx, caption.text, alpha: caption.alpha, y: pad.minY - 44, size: 30) }
        if let headline = w.headline, headline.alpha > 0 { drawLabel(&ctx, headline.text, alpha: headline.alpha, y: 74, size: 38) }
        if w.padAlpha > 0 { drawPad(&ctx, w) }
        if w.endCard > 0 { drawEndCard(&ctx, alpha: w.endCard) }
    }

    private func painter(_ demo: CommunityDemo, time: Double, slice: String? = nil) -> DemoPainter {
        DemoPainter(demo: demo, chip: nil, caption: nil, slice: slice, time: time, timing: DemoTiming(demo),
                    size: Self.size, cursors: DemoCursors.shared)
    }

    private func safeIndex(_ active: Double, _ count: Int) -> Int { max(0, min(count - 1, Int(active.rounded()))) }

    /// İmlecin ekrandaki yeri → parmağın trackpad'deki yeri (ikisi hep aynı oranda: eşzamanlı)
    private func padPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x / Self.size.width, 0.08), 0.92), y: min(max(p.y / Self.size.height, 0.1), 0.9))
    }

    // MARK: İşler

    private func apply(_ act: Act, tau: Double, length L: Double, live: Bool, _ w: inout World, _ base: DemoPainter) {
        func ramp(_ a: Double, _ d: Double) -> Double { clamp((tau - a) / d) }
        func win(_ a: Double, _ b: Double, _ fade: Double = 0.14) -> Double { ramp(a, fade) * (1 - ramp(b, fade)) }
        func pulse(_ at: Double) -> Double { let d = (tau - at) / 0.16; return d < 0 || d > 1 ? 0 : sin(d * .pi) }
        func row(_ n: Int, _ c: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> [CGPoint] {
            (0..<n).map { CGPoint(x: c.x + (Double($0) - Double(n - 1) / 2) * 0.13, y: c.y) }
        }
        func say(_ chip: String?, _ caption: String, chipAt: Double, captionAt: Double) {
            guard live else { return }
            if let chip { w.chip = (chip, win(chipAt, L - 0.2)) }
            w.caption = (caption, win(captionAt, L - 0.08))
        }
        /// İmleç a anından d sürede hedefe gider; o sırada tek parmak trackpad'de onunla birlikte kayar
        func glide(to target: CGPoint, at a: Double, _ d: Double) {
            let k = easeInOut(ramp(a, d))
            w.pointer = lerp(w.pointer, target, k)
            if live, tau >= a - 0.08, tau <= a + d + 0.08 {
                w.fingers = [padPoint(w.pointer)]
                w.fingerAlpha = win(a - 0.08, a + d, 0.08)
                w.press = 0
            }
        }

        switch act {
        case .middleClick:
            // İmleç bağlantıya gider (parmak kayar), aynı yerde 3 parmakla bastırılır, bağlantı arka sekmede açılır
            let link = linkRect(in: base.pageRect(w.frame))
            let target = CGPoint(x: link.minX + link.width * 0.45, y: link.midY)
            glide(to: target, at: 0, 0.65)
            if live {
                if tau > 0.4 { w.pointerStyle = .hand }
                if tau > 0.75 {
                    w.fingers = row(3, padPoint(target))
                    w.fingerAlpha = win(0.75, L - 0.45, 0.08)
                    w.press = ramp(0.82, 0.07) * (1 - ramp(1.12, 0.1))
                    w.ripples = w.fingers.map { ($0, ramp(0.82, 0.45)) }
                }
            }
            let grow = easeOut(ramp(0.95, 0.3))
            if grow > 0 { w.tabs.append(Tab(site: 2, width: grow)) }
            say("Middle click", "3-finger click: open link in a new tab", chipAt: 0.82, captionAt: 0.9)

        case .closeTab:
            // 2 parmakla çift dokunma: öndeki sekme küçülüp kapanır, sağındaki öne gelir
            if live {
                w.fingers = row(2)
                w.fingerAlpha = win(0, L - 0.35, 0.1)
                w.press = max(pulse(0.28), pulse(0.52))
                w.ripples = w.fingers.flatMap { [($0, ramp(0.28, 0.45)), ($0, ramp(0.52, 0.45))] }
            }
            let i = safeIndex(w.active, w.tabs.count)
            let k = easeOut(ramp(0.6, 0.3))
            if k >= 1 {
                w.closed = (w.tabs[i].site, i)
                w.tabs.remove(at: i)
                w.active = Double(min(i, w.tabs.count - 1))
            } else if k > 0 {
                w.tabs[i].width = 1 - k
                let next = i + 1 < w.tabs.count ? i + 1 : i - 1
                if k > 0.5, next >= 0 { w.pageSite = w.tabs[next].site }
            }
            say("⌘W", "2-finger double tap: close tab", chipAt: 0.3, captionAt: 0.45)

        case .reopenTab:
            // 3 parmakla çift dokunma: kapanan sekme yerine geri gelir ve öne çıkar
            if live {
                w.fingers = row(3)
                w.fingerAlpha = win(0, L - 0.35, 0.1)
                w.press = max(pulse(0.28), pulse(0.52))
                w.ripples = w.fingers.flatMap { [($0, ramp(0.28, 0.45)), ($0, ramp(0.52, 0.45))] }
            }
            let k = easeOut(ramp(0.6, 0.3))
            if k > 0, let closed = w.closed {
                let at = min(closed.index, w.tabs.count)
                w.tabs.insert(Tab(site: closed.site, width: k), at: at)
                if k > 0.5 { w.active = Double(at) }
                if k >= 1 { w.closed = nil }
            }
            say("⇧⌘T", "3-finger double tap: reopen closed tab", chipAt: 0.3, captionAt: 0.45)

        case .brightness:
            // İmleç ortaya; sol alt köşeye tık → daire imlecin yerinde; imleç parlaklık dilimine;
            // basılı tutup sürükle: imleç çubuğun ucunu izler, ekran kısılır ve açılır
            let demo = CommunityDemo(.gesture(.cornerTapBottomLeft), .control(.brightness))
            let timing = DemoTiming(demo)
            let hold = timing.reset - 0.35 - timing.click
            let p = painter(demo, time: timing.click + ramp(1.3, 1.85) * hold, slice: SystemControl.brightness.title)
            // Büyük trackpad ekranın altını kapatıyor: daire biraz yukarıda açılır
            let lift = -pad.height * 0.55
            let center = CGPoint(x: p.radialCenter.x, y: p.radialCenter.y + lift)
            let lit = SystemControl.defaults.firstIndex(of: .brightness) ?? 2
            let mid = Angle.degrees(Double(lit) * 30 + 195).radians
            let level = p.sliderLevel
            let rest = 0.58
            func onSlider(_ v: Double) -> CGPoint {
                let r = p.radialRadius * (0.36 + 0.5 * v)
                return CGPoint(x: center.x + cos(mid) * r, y: center.y + sin(mid) * r)
            }
            glide(to: center, at: 0, 0.35)
            glide(to: onSlider(rest), at: 0.85, 0.35)
            if tau > 1.25 { w.pointer = onSlider(rest + (level - 0.82) * 1.1) }
            if live {
                let open = ease(ramp(0.5, 0.22)) * (1 - ease(ramp(L - 0.35, 0.22)))
                if open > 0 {
                    w.overlays.append { c in
                        var c = c
                        p.drawControlResult(&c, .brightness)
                        c.translateBy(x: 0, y: lift)
                        p.drawRadial(&c, center: p.radialCenter, progress: open, lit: tau > 1.0 ? lit : nil)
                    }
                }
                if tau > 0.4, tau < 0.8 {
                    // Köşeye bastırarak tıklama: imleç kıpırdamaz
                    w.fingers = [CGPoint(x: 0.09, y: 0.86)]
                    w.fingerAlpha = win(0.4, 0.78, 0.06)
                    w.press = ramp(0.46, 0.06) * (1 - ramp(0.62, 0.08))
                    w.ripples = [(w.fingers[0], ramp(0.46, 0.45)), (w.fingers[0], ramp(0.58, 0.45))]
                } else if tau > 1.25 {
                    // Basılı sürükleme: parmak imleçle birlikte
                    w.fingers = [padPoint(w.pointer)]
                    w.fingerAlpha = win(1.2, L - 0.4, 0.08)
                    w.press = tau < L - 0.5 ? 0.7 : 0
                }
            }
            say(nil, "Corner click → radial menu → drag brightness", chipAt: 0, captionAt: 0.6)

        case .screenshot:
            screenshot(tau: tau, length: L, live: live, &w, base)

        case .snapAll:
            // ⇪ + ← → ↑ ↓, sonra ⇪ + Boşluk. Klavye işi: trackpad bu sırada gizlenir
            let steps: [(String, SnapLayout)] = [("←", .left), ("→", .right), ("↑", .top), ("↓", .bottom), ("Space", .fill)]
            let step = 0.42
            var frame = w.frame
            var current = steps[0]
            for (i, s) in steps.enumerated() {
                let at = 0.25 + Double(i) * step
                guard tau >= at else { break }
                frame = lerp(frame, base.snapFrame(s.1), easeOut(ramp(at, 0.2)))
                current = s
            }
            w.frame = frame
            if live {
                w.padAlpha = 1 - win(0, L - 0.05, 0.2)
                w.chip = ("⇪ + \(current.0)", win(0.2, L - 0.25, 0.1))
                w.caption = ("Caps Lock + arrows: snap  ·  + Space: full screen", win(0.25, L - 0.1))
            }

        case .customGesture:
            customGesture(tau: tau, length: L, live: live, &w, base)

        case .endCard:
            w.endCard = ease(ramp(0, 0.7))
            w.padAlpha = 1 - ramp(0, 0.4)
            w.pointerAlpha = 0
        }
    }

    // MARK: Ekran görüntüsü

    /// 4 parmakla dokun → imleç artı işaretine döner → alanın köşesine gider → basılı sürükleyerek alan
    /// seçilir → bırakınca deklanşör → resim sağ alt köşeye uçar, bir süre durur, kayıp çıkar
    private func screenshot(tau: Double, length L: Double, live: Bool, _ w: inout World, _ base: DemoPainter) {
        func ramp(_ a: Double, _ d: Double) -> Double { clamp((tau - a) / d) }
        func win(_ a: Double, _ b: Double, _ fade: Double = 0.14) -> Double { ramp(a, fade) * (1 - ramp(b, fade)) }
        let f = w.frame
        let from = CGPoint(x: f.minX + f.width * 0.3, y: f.minY + f.height * 0.3)
        let to = CGPoint(x: f.minX + f.width * 0.72, y: f.minY + f.height * 0.7)
        let toStart = easeInOut(ramp(0.5, 0.4))
        let drag = easeInOut(ramp(1.0, 0.7))
        w.pointer = lerp(lerp(w.pointer, from, toStart), to, drag)
        guard live else { return }
        let shot = 1.78
        if tau > 0.45, tau < shot { w.pointerStyle = .cross }
        // Trackpad: 4 parmak dokunur; sonra tek parmak artıyı taşır, basılı sürükler
        if tau < 0.45 {
            w.fingers = (0..<4).map { CGPoint(x: 0.5 + (Double($0) - 1.5) * 0.13, y: 0.5) }
            w.fingerAlpha = win(0, 0.42, 0.08)
            let d = (tau - 0.15) / 0.16
            w.press = d < 0 || d > 1 ? 0 : sin(d * .pi)
            w.ripples = w.fingers.map { ($0, ramp(0.15, 0.45)) }
        } else if tau < shot + 0.05 {
            w.fingers = [padPoint(w.pointer)]
            w.fingerAlpha = win(0.45, shot, 0.08)
            w.press = tau > 0.95 && tau < shot ? 0.7 : 0
        }
        w.chip = ("⇧⌘4", win(0.15, 1.0, 0.12))
        w.caption = ("4-finger tap: screenshot", win(0.25, L - 0.08))

        let sel = CGRect(x: from.x, y: from.y, width: max(1, w.pointer.x - from.x), height: max(1, w.pointer.y - from.y))
        let shotSel = CGRect(x: from.x, y: from.y, width: to.x - from.x, height: to.y - from.y)
        let frame = w.frame
        let snapshot = w
        let padRect = pad
        w.overlays.append { c in
            var c = c
            if tau > 1.0, tau < shot {
                // Seçim: dışı hafif kararır, içi açık; köşede boyut yazısı
                var dim = Path(CGRect(origin: .zero, size: Self.size))
                dim.addRect(sel)
                c.fill(dim, with: .color(.black.opacity(0.28)), style: FillStyle(eoFill: true))
                c.fill(Path(sel), with: .color(.white.opacity(0.08)))
                c.stroke(Path(sel), with: .color(.white.opacity(0.9)), lineWidth: 1)
                let label = "\(Int(sel.width * 2)) × \(Int(sel.height * 2))"
                c.draw(Text(verbatim: label).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white),
                       at: CGPoint(x: sel.maxX + 10, y: sel.maxY + 14), anchor: .leading)
            }
            // Deklanşör
            let flash = clamp((tau - shot) / 0.06) * (1 - clamp((tau - shot - 0.08) / 0.14))
            if flash > 0 { c.fill(Path(CGRect(origin: .zero, size: Self.size)), with: .color(.white.opacity(0.7 * flash))) }
            guard tau > shot else { return }
            // Çekilen resim köşeye uçar (trackpad'in sağında), sonra sağa kayıp çıkar
            let fly = easeInOut(clamp((tau - shot - 0.05) / 0.5))
            let out = easeInOut(clamp((tau - (L - 0.45)) / 0.4))
            let tw = 230.0
            let th: Double = tw * Double(shotSel.height / shotSel.width)
            let cx: Double = Double(Self.size.width) - tw - 28 + out * (tw + 60)
            let cy: Double = Double(padRect.maxY) - th - 20
            let corner = CGRect(x: cx, y: cy, width: tw, height: th)
            let thumb = lerp(shotSel, corner, fly)
            var shadow = c
            shadow.addFilter(.shadow(color: .black.opacity(0.5), radius: 18, y: 6))
            shadow.fill(Path(roundedRect: thumb, cornerRadius: 8), with: .color(.white))
            var inside = c
            inside.clip(to: Path(roundedRect: thumb.insetBy(dx: 2, dy: 2), cornerRadius: 7))
            inside.translateBy(x: thumb.minX, y: thumb.minY)
            inside.scaleBy(x: thumb.width / shotSel.width, y: thumb.height / shotSel.height)
            inside.translateBy(x: -shotSel.minX, y: -shotSel.minY)
            base.drawWallpaper(&inside)
            drawBrowser(&inside, base, snapshot, frame: frame)
        }
    }

    // MARK: Kendi hareketini kur

    /// FingerKit penceresi: "Add gesture" → trackpad'de 4 parmak aşağı → ⌘M → Save; pencere kapanır,
    /// hareket yapılır, Safari Dock'a küçülür
    private func customGesture(tau: Double, length L: Double, live: Bool, _ w: inout World, _ base: DemoPainter) {
        func ramp(_ a: Double, _ d: Double) -> Double { clamp((tau - a) / d) }
        func win(_ a: Double, _ b: Double, _ fade: Double = 0.14) -> Double { ramp(a, fade) * (1 - ramp(b, fade)) }
        let swipe = { (a: Double) -> [CGPoint] in
            let y = 0.3 + 0.45 * easeInOut(ramp(a, 0.5))
            return (0..<4).map { CGPoint(x: 0.5 + (Double($0) - 1.5) * 0.13, y: y) }
        }
        let ui = settingsLayout
        w.minimize = ramp(3.65, 0.5)
        // İmleç "Add gesture"a, sonra "Save"e; parmak her seferinde onunla kayar
        let addAt = CGPoint(x: ui.add.midX + 30, y: ui.add.midY + 4)
        let saveAt = CGPoint(x: ui.save.maxX - 22, y: ui.save.midY + 6)
        let k1 = easeInOut(ramp(0.15, 0.4)), k2 = easeInOut(ramp(1.95, 0.4))
        w.pointer = lerp(lerp(w.pointer, addAt, k1), saveAt, k2)
        w.pointerAlpha = 1 - ramp(3.1, 0.2)
        guard live else { return }
        w.headline = ("Assign any shortcut to any gesture", win(0.05, 3.0, 0.25))
        let shown = ease(ramp(0.05, 0.3)) * (1 - ease(ramp(2.95, 0.25)))
        let state = SettingsState(
            appear: shown,
            addPressed: win(0.6, 0.72, 0.04),
            recording: tau > 0.72 && tau < 1.6,
            live: tau > 0.85 && tau < 1.55 ? swipe(0.9) : [],
            recognized: ramp(1.55, 0.15),
            fieldFocus: tau > 1.62 && tau < 1.8,
            shortcut: ramp(1.8, 0.1),
            savePressed: win(2.42, 2.54, 0.04),
            newRow: easeOut(ramp(2.5, 0.3)))
        if shown > 0 { w.overlays.append { c in var c = c; drawSettings(&c, state) } }
        if tau < 0.8 {
            w.fingers = [padPoint(w.pointer)]
            w.fingerAlpha = win(0.07, 0.78, 0.08)
            w.press = ramp(0.6, 0.04) * (1 - ramp(0.7, 0.04))
        } else if tau < 1.6 {
            w.fingers = swipe(0.9)
            w.fingerAlpha = win(0.82, 1.55, 0.08)
        } else if tau > 1.87, tau < 2.7 {
            w.fingers = [padPoint(w.pointer)]
            w.fingerAlpha = win(1.87, 2.65, 0.08)
            w.press = ramp(2.42, 0.04) * (1 - ramp(2.52, 0.04))
        } else if tau > 3.2 {
            // Kaydedilen hareket hemen kullanılır
            w.fingers = swipe(3.3)
            w.fingerAlpha = win(3.2, 4.0, 0.08)
        }
        if tau > 3.3 {
            w.chip = ("⌘M", win(3.4, L - 0.15))
            w.caption = ("4-finger swipe down → ⌘M: minimize window", win(3.4, L - 0.08))
        }
    }

    private struct SettingsState {
        var appear: Double
        var addPressed: Double
        var recording: Bool
        var live: [CGPoint]
        var recognized: Double
        var fieldFocus: Bool
        var shortcut: Double
        var savePressed: Double
        var newRow: Double
    }

    private var settingsLayout: (window: CGRect, add: CGRect, live: CGRect, field: CGRect, save: CGRect, list: CGRect) {
        let win = CGRect(x: Self.size.width / 2 - 390, y: 122, width: 780, height: 396)
        let list = CGRect(x: win.minX + 22, y: win.minY + 100, width: 420, height: win.height - 116)
        let add = CGRect(x: list.maxX - 140, y: win.minY + 54, width: 140, height: 32)
        let live = CGRect(x: win.minX + 470, y: win.minY + 58, width: 288, height: 150)
        let field = CGRect(x: live.minX, y: live.maxY + 62, width: live.width, height: 44)
        let save = CGRect(x: live.maxX - 120, y: field.maxY + 20, width: 120, height: 36)
        return (win, add, live, field, save, list)
    }

    /// FingerKit'in penceresi, gece teması ve yeşil vurguyla (gerçek pencerenin sade hali)
    private func drawSettings(_ ctx: inout GraphicsContext, _ st: SettingsState) {
        let ui = settingsLayout
        let green = Self.green
        var c = ctx
        c.opacity = st.appear
        let k = 0.96 + 0.04 * st.appear
        c.translateBy(x: ui.window.midX * (1 - k), y: ui.window.midY * (1 - k))
        c.scaleBy(x: k, y: k)
        let shape = Path(roundedRect: ui.window, cornerRadius: 14)
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.6), radius: 30, y: 12))
        shadow.fill(shape, with: .color(hex(0x1b1c1f)))
        c.stroke(shape, with: .color(.white.opacity(0.12)), lineWidth: 1)
        var x = ui.window.minX + 18
        for color in [hex(0xff5f57), hex(0xfebc2e), hex(0x28c840)] {
            c.fill(Path(ellipseIn: CGRect(x: x, y: ui.window.minY + 15, width: 12, height: 12)), with: .color(color))
            x += 20
        }
        func text(_ t: String, _ size: Double, _ weight: Font.Weight = .regular, _ color: Color = .white, at p: CGPoint, anchor: UnitPoint = .leading) {
            c.draw(Text(verbatim: t).font(.system(size: size, weight: weight)).foregroundStyle(color), at: p, anchor: anchor)
        }
        text("FingerKit", 14, .semibold, .white.opacity(0.8), at: CGPoint(x: ui.window.midX, y: ui.window.minY + 21), anchor: .center)
        text("Everywhere", 19, .bold, at: CGPoint(x: ui.list.minX, y: ui.add.midY))
        let addShape = Path(roundedRect: ui.add, cornerRadius: ui.add.height / 2)
        c.fill(addShape, with: .color(green))
        if st.addPressed > 0 { c.fill(addShape, with: .color(.black.opacity(0.2 * st.addPressed))) }
        text("+  Add gesture", 14, .semibold, hex(0x0b1a0f), at: CGPoint(x: ui.add.midX, y: ui.add.midY), anchor: .center)
        // Liste: yeni satır en üste girer, ötekiler aşağı kayar; yeni satır yeşil parlar
        let rows: [(String, String)] = [("4-finger swipe up", "⌃⌘F"), ("4-finger click", "⌘Q"), ("3-finger click", "Middle click"), ("Top-right corner tap", "⌃⌘Q")]
        let rowH = 48.0, gap = 8.0
        func row(_ r: CGRect, _ name: String, _ keys: String, glow: Double, alpha: Double) {
            var rc = c
            rc.opacity = st.appear * alpha
            let p = Path(roundedRect: r, cornerRadius: 11)
            rc.fill(p, with: .color(.white.opacity(0.055)))
            if glow > 0 {
                rc.fill(p, with: .color(green.opacity(0.22 * glow)))
                rc.stroke(p, with: .color(green.opacity(0.9 * glow)), lineWidth: 1.5)
            }
            rc.draw(Text(verbatim: name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white),
                    at: CGPoint(x: r.minX + 16, y: r.midY), anchor: .leading)
            let kr = CGRect(x: r.maxX - 128, y: r.midY - 14, width: 112, height: 28)
            rc.fill(Path(roundedRect: kr, cornerRadius: 8), with: .color(.white.opacity(0.09)))
            rc.draw(Text(verbatim: keys).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white), at: CGPoint(x: kr.midX, y: kr.midY))
        }
        var y = ui.list.minY + (rowH + gap) * st.newRow
        for (name, keys) in rows {
            let room: Double = Double(ui.list.maxY) - (y + rowH)
            let fade = clamp(room / 20 + 1)
            if fade > 0 { row(CGRect(x: ui.list.minX, y: y, width: ui.list.width, height: rowH), name, keys, glow: 0, alpha: fade) }
            y += rowH + gap
        }
        if st.newRow > 0 {
            row(CGRect(x: ui.list.minX, y: ui.list.minY, width: ui.list.width, height: rowH),
                "4-finger swipe down", "⌘M", glow: 1, alpha: st.newRow)
        }
        // Canlı trackpad kutusu: kayıtta yeşil çerçeve, parmaklar burada da görünür
        let liveShape = Path(roundedRect: ui.live, cornerRadius: 14)
        c.fill(liveShape, with: .color(.white.opacity(0.05)))
        c.stroke(liveShape, with: .color(st.recording ? green : .white.opacity(0.12)), lineWidth: st.recording ? 2 : 1)
        for p in st.live {
            let center = CGPoint(x: ui.live.minX + p.x * ui.live.width, y: ui.live.minY + p.y * ui.live.height)
            c.fill(Path(ellipseIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)), with: .color(Color.fingerGold))
        }
        let status = st.recognized > 0 ? "✓  4-finger swipe down" : (st.recording ? "Do the gesture on your trackpad…" : "Live trackpad")
        text(status, 15, .semibold, st.recognized > 0 ? green : .white.opacity(0.7), at: CGPoint(x: ui.live.midX, y: ui.live.maxY + 24), anchor: .center)
        let fieldShape = Path(roundedRect: ui.field, cornerRadius: 10)
        c.fill(fieldShape, with: .color(.white.opacity(0.07)))
        c.stroke(fieldShape, with: .color(st.fieldFocus || st.shortcut > 0 ? green : .white.opacity(0.12)), lineWidth: st.fieldFocus ? 2 : 1)
        if st.shortcut > 0 {
            text("⌘M", 20, .bold, at: CGPoint(x: ui.field.midX, y: ui.field.midY), anchor: .center)
        } else {
            text(st.fieldFocus ? "Press a shortcut…" : "Shortcut", 15, .medium, .white.opacity(0.5), at: CGPoint(x: ui.field.midX, y: ui.field.midY), anchor: .center)
        }
        let saveShape = Path(roundedRect: ui.save, cornerRadius: ui.save.height / 2)
        c.fill(saveShape, with: .color(st.shortcut > 0 ? green : .white.opacity(0.1)))
        if st.savePressed > 0 { c.fill(saveShape, with: .color(.black.opacity(0.2 * st.savePressed))) }
        text("Save", 15, .semibold, st.shortcut > 0 ? hex(0x0b1a0f) : .white.opacity(0.5), at: CGPoint(x: ui.save.midX, y: ui.save.midY), anchor: .center)
    }

    // MARK: Son kart

    /// Her şey kararır; ortada simge, ad, tek cümle, altında imza
    private func drawEndCard(_ ctx: inout GraphicsContext, alpha: Double) {
        let all = Path(CGRect(origin: .zero, size: Self.size))
        ctx.fill(all, with: .color(hex(0x08090a).opacity(alpha)))
        ctx.fill(all, with: .radialGradient(Gradient(colors: [Self.green.opacity(0.13 * alpha), .clear]),
                                            center: CGPoint(x: Self.size.width / 2, y: Self.size.height * 0.45),
                                            startRadius: 0, endRadius: 560))
        let content = clamp((alpha - 0.35) / 0.65)
        guard content > 0 else { return }
        var c = ctx
        c.opacity = content
        let cx = Self.size.width / 2, y = Self.size.height * 0.46 + 12 * (1 - content)
        if let icon = NSImage(contentsOfFile: "docs/icon.png") {
            let d = 128.0
            c.draw(Image(nsImage: icon), in: CGRect(x: cx - d / 2, y: y - 175, width: d, height: d))
        }
        c.draw(Text(verbatim: "FingerKit").font(.system(size: 68, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: cx, y: y))
        c.draw(Text(verbatim: "Free  ·  Open source  ·  Never connects to the internet")
                .font(.system(size: 23, weight: .medium)).foregroundStyle(.white.opacity(0.72)),
               at: CGPoint(x: cx, y: y + 58))
        var sig = c
        sig.opacity = content * clamp((alpha - 0.7) / 0.3)
        sig.draw(Text(verbatim: "Made by @enisaytac").font(.system(size: 17, weight: .medium)).foregroundStyle(Self.green.opacity(0.9)),
                 at: CGPoint(x: cx, y: y + 128))
    }

    // MARK: Pencere

    /// Safari penceresi: çerçeve önizlemeden, sekmeler ve GitHub benzeri sayfa burada
    private func drawBrowser(_ ctx: inout GraphicsContext, _ base: DemoPainter, _ w: World, frame f: CGRect) {
        let site = w.pageSite ?? w.tabs[safeIndex(w.active, w.tabs.count)].site
        base.drawSafari(&ctx, f, tabs: DemoPainter.Tabs(count: 0, active: 0), variant: site, chrome: true)
        var c = ctx
        c.clip(to: Path(roundedRect: f, cornerRadius: min(f.width * 0.014, 6)))
        if site == 0 {
            let page = base.pageRect(f)
            if page.height > 40 { drawRepoPage(&c, page) }
        }
        drawTabs(&c, base, w, frame: f)
    }

    /// Sayfadaki bağlantı: README'deki "Download the latest release"
    private func linkRect(in r: CGRect) -> CGRect {
        let u = r.width / 100
        return CGRect(x: r.minX + 5.5 * u, y: r.minY + 46 * u, width: 18.6 * u, height: 1.6 * u)
    }

    /// GitHub'daki depo sayfasına benzer (markasız): üst çubuk, depo adı, sekmeler, dosya listesi, README, Hakkında
    private func drawRepoPage(_ ctx: inout GraphicsContext, _ r: CGRect) {
        let u = r.width / 100
        let ink = hex(0x1f2328), muted = hex(0x59636e), border = hex(0xd1d9e0), linkBlue = hex(0x0969da)
        ctx.fill(Path(r), with: .color(.white))
        func text(_ t: String, _ size: Double, _ weight: Font.Weight = .regular, _ color: Color, at p: CGPoint, anchor: UnitPoint = .leading) {
            ctx.draw(Text(verbatim: t).font(.system(size: size, weight: weight)).foregroundStyle(color), at: p, anchor: anchor)
        }
        // Üst çubuk
        let header = CGRect(x: r.minX, y: r.minY, width: r.width, height: 6.2 * u)
        ctx.fill(Path(header), with: .color(hex(0xf6f8fa)))
        ctx.fill(Path(CGRect(x: r.minX, y: header.maxY - 1, width: r.width, height: 1)), with: .color(border))
        let logo = 3.4 * u
        ctx.fill(Path(ellipseIn: CGRect(x: r.minX + 2.5 * u, y: header.midY - logo / 2, width: logo, height: logo)), with: .color(ink))
        text("enisaytac", 1.75 * u, .regular, ink, at: CGPoint(x: r.minX + 7 * u, y: header.midY))
        text("/", 1.75 * u, .regular, muted, at: CGPoint(x: r.minX + 15.6 * u, y: header.midY))
        text("FingerKit", 1.75 * u, .semibold, ink, at: CGPoint(x: r.minX + 17.2 * u, y: header.midY))
        let search = CGRect(x: r.maxX - 30 * u, y: header.midY - 1.6 * u, width: 22 * u, height: 3.2 * u)
        ctx.stroke(Path(roundedRect: search, cornerRadius: 0.8 * u), with: .color(border), lineWidth: 1)
        text("Type / to search", 1.35 * u, .regular, muted, at: CGPoint(x: search.minX + 1.2 * u, y: search.midY))
        ctx.fill(Path(ellipseIn: CGRect(x: r.maxX - 5.5 * u, y: header.midY - 1.6 * u, width: 3.2 * u, height: 3.2 * u)), with: .color(hex(0x8250df)))
        // Depo sekmeleri
        let navY = header.maxY + 2.6 * u
        var nx = r.minX + 3 * u
        for (i, name) in ["Code", "Issues", "Pull requests", "Actions", "Releases"].enumerated() {
            text(name, 1.55 * u, i == 0 ? .semibold : .regular, i == 0 ? ink : muted, at: CGPoint(x: nx, y: navY))
            if i == 0 { ctx.fill(Path(roundedRect: CGRect(x: nx - 0.5 * u, y: navY + 2 * u, width: 6 * u, height: 0.35 * u), cornerRadius: 0.2 * u), with: .color(hex(0xfd8c73))) }
            nx += Double(name.count) * 1.05 * u + 3 * u
        }
        for (i, label) in ["★ Star  1.2k", "Fork  86"].enumerated() {
            let b = CGRect(x: r.maxX - (i == 0 ? 25 : 12) * u, y: navY - 1.6 * u, width: (i == 0 ? 11.5 : 9) * u, height: 3.2 * u)
            ctx.fill(Path(roundedRect: b, cornerRadius: 0.8 * u), with: .color(hex(0xf6f8fa)))
            ctx.stroke(Path(roundedRect: b, cornerRadius: 0.8 * u), with: .color(border), lineWidth: 1)
            text(label, 1.35 * u, .medium, ink, at: CGPoint(x: b.midX, y: b.midY), anchor: .center)
        }
        ctx.fill(Path(CGRect(x: r.minX, y: navY + 2.6 * u, width: r.width, height: 1)), with: .color(border))
        // Sol: dosya listesi
        let main = CGRect(x: r.minX + 3 * u, y: navY + 5 * u, width: 64 * u, height: r.maxY - navY - 5 * u)
        let branch = CGRect(x: main.minX, y: main.minY, width: 9 * u, height: 3 * u)
        ctx.fill(Path(roundedRect: branch, cornerRadius: 0.8 * u), with: .color(hex(0xf6f8fa)))
        ctx.stroke(Path(roundedRect: branch, cornerRadius: 0.8 * u), with: .color(border), lineWidth: 1)
        text("main", 1.35 * u, .semibold, ink, at: CGPoint(x: branch.midX, y: branch.midY), anchor: .center)
        let code = CGRect(x: main.maxX - 9 * u, y: main.minY, width: 9 * u, height: 3 * u)
        ctx.fill(Path(roundedRect: code, cornerRadius: 0.8 * u), with: .color(hex(0x1f883d)))
        text("<> Code", 1.35 * u, .semibold, .white, at: CGPoint(x: code.midX, y: code.midY), anchor: .center)
        let files = CGRect(x: main.minX, y: branch.maxY + 1.5 * u, width: main.width, height: 16 * u)
        ctx.stroke(Path(roundedRect: files, cornerRadius: 0.8 * u), with: .color(border), lineWidth: 1)
        let rows: [(String, String, String)] = [("Sources", "Faster clipboard", "2 hours ago"), ("docs", "Demo video", "1 hour ago"),
                                                ("README.md", "One-line install", "yesterday"), ("LICENSE", "MIT", "last week")]
        for (i, file) in rows.enumerated() {
            let y = files.minY + (Double(i) + 0.5) * files.height / 4
            if i > 0 { ctx.fill(Path(CGRect(x: files.minX, y: files.minY + Double(i) * files.height / 4, width: files.width, height: 1)), with: .color(border)) }
            let folder = !file.0.contains(".")
            ctx.fill(Path(roundedRect: CGRect(x: files.minX + 1.5 * u, y: y - 0.75 * u, width: 1.9 * u, height: 1.5 * u), cornerRadius: 0.3 * u),
                     with: .color(folder ? hex(0x54aeff) : muted.opacity(0.5)))
            text(file.0, 1.4 * u, .regular, ink, at: CGPoint(x: files.minX + 4.6 * u, y: y))
            text(file.1, 1.4 * u, .regular, muted, at: CGPoint(x: files.minX + 22 * u, y: y))
            text(file.2, 1.4 * u, .regular, muted, at: CGPoint(x: files.maxX - 1.5 * u, y: y), anchor: .trailing)
        }
        // README
        let readme = CGRect(x: main.minX, y: files.maxY + 1.8 * u, width: main.width, height: r.maxY - files.maxY + 10 * u)
        ctx.stroke(Path(roundedRect: readme, cornerRadius: 0.8 * u), with: .color(border), lineWidth: 1)
        text("FingerKit", 3 * u, .semibold, ink, at: CGPoint(x: readme.minX + 2.5 * u, y: readme.minY + 3.6 * u))
        ctx.fill(Path(CGRect(x: readme.minX + 2.5 * u, y: readme.minY + 6 * u, width: readme.width - 5 * u, height: 1)), with: .color(border))
        text("Trackpad gestures, Hyper Key and a radial menu for your Mac.", 1.45 * u, .regular, ink,
             at: CGPoint(x: readme.minX + 2.5 * u, y: readme.minY + 8.3 * u))
        let link = linkRect(in: r)
        text("Download the latest release", 1.45 * u, .semibold, linkBlue, at: CGPoint(x: link.minX, y: link.midY))
        ctx.fill(Path(CGRect(x: link.minX, y: link.midY + 1 * u, width: link.width, height: 1)), with: .color(linkBlue.opacity(0.6)))
        // Sağ: Hakkında
        let side = CGRect(x: main.maxX + 3.5 * u, y: main.minY, width: r.maxX - main.maxX - 6.5 * u, height: main.height)
        text("About", 1.65 * u, .semibold, ink, at: CGPoint(x: side.minX, y: side.minY + 1.4 * u))
        text("Gestures, Hyper Key, radial menu.", 1.35 * u, .regular, ink, at: CGPoint(x: side.minX, y: side.minY + 4.6 * u))
        text("No internet. No tracking.", 1.35 * u, .regular, ink, at: CGPoint(x: side.minX, y: side.minY + 6.8 * u))
        var tx = side.minX
        for topic in ["macos", "trackpad", "swift"] {
            let wdt = Double(topic.count) * 0.95 * u + 2 * u
            let pill = CGRect(x: tx, y: side.minY + 9.4 * u, width: wdt, height: 2.4 * u)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 1.2 * u), with: .color(hex(0xddf4ff)))
            text(topic, 1.2 * u, .semibold, linkBlue, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
            tx += wdt + 0.8 * u
        }
        for (i, item) in ["Readme", "MIT license", "1.2k stars"].enumerated() {
            text(item, 1.35 * u, .regular, muted, at: CGPoint(x: side.minX, y: side.minY + (14 + Double(i) * 2.6) * u))
        }
    }

    /// Sekme şeridi: her sekme kendi sitesinin renginde; açılan/kapanan sekmenin genişliği değişir
    private func drawTabs(_ ctx: inout GraphicsContext, _ base: DemoPainter, _ w: World, frame f: CGRect) {
        let strip = CGRect(x: f.minX, y: f.minY + base.barHeight(f), width: f.width, height: base.tabStripHeight(f))
        let activeSite = w.pageSite ?? w.tabs[safeIndex(w.active, w.tabs.count)].site
        let dark = DemoPainter.Site.at(activeSite).dark
        ctx.fill(Path(strip), with: .color(dark ? hex(0x1d1d20) : hex(0xe1e1e6)))
        let full = min(f.width / 4, Self.size.width * 0.16)
        var x = strip.minX + f.width * 0.01
        var rects: [CGRect] = []
        for tab in w.tabs {
            rects.append(CGRect(x: x, y: strip.minY + strip.height * 0.12, width: full * tab.width, height: strip.height * 0.76))
            x += full * tab.width + 1
        }
        let on = safeIndex(w.active, w.tabs.count)
        for (i, r) in rects.enumerated() where r.width > 1 {
            let site = DemoPainter.Site.at(w.tabs[i].site)
            let isOn = i == on
            let shape = Path(roundedRect: r, cornerRadius: r.height * 0.25)
            ctx.fill(shape, with: .color(dark ? (isOn ? hex(0x3a3a3e) : hex(0x2a2a2d)) : (isOn ? .white : hex(0xd3d3d9))))
            ctx.fill(shape, with: .color(site.color.opacity(isOn ? 0.28 : 0.5)))
            let icon = r.height * 0.5
            let iconRect = CGRect(x: r.minX + r.height * 0.3, y: r.midY - icon / 2, width: min(icon, r.width * 0.3), height: icon)
            ctx.fill(Path(roundedRect: iconRect, cornerRadius: icon * 0.25), with: .color(site.color))
            let bar = r.height * 0.2, bx = iconRect.maxX + r.height * 0.25
            ctx.fill(Path(roundedRect: CGRect(x: bx, y: r.midY - bar / 2, width: max(0, r.maxX - bx - r.height * 0.4), height: bar),
                          cornerRadius: bar / 2), with: .color(dark ? .white.opacity(isOn ? 0.6 : 0.35) : .black.opacity(isOn ? 0.45 : 0.3)))
        }
        let lo = Int(w.active.rounded(.down)), hi = min(rects.count - 1, lo + 1)
        if rects.indices.contains(lo) {
            let r = lerp(rects[lo], rects[hi], w.active - Double(lo))
            ctx.fill(Path(CGRect(x: r.minX, y: r.maxY - 1.5, width: r.width, height: 1.5)), with: .color(Color(red: 0.04, green: 0.52, blue: 1)))
        }
    }

    // MARK: İmleç, yazılar, trackpad

    private func drawPointer(_ ctx: inout GraphicsContext, _ base: DemoPainter, _ w: World) {
        guard w.pointerAlpha > 0 else { return }
        var c = ctx
        c.opacity = w.pointerAlpha
        let p = w.pointer
        switch w.pointerStyle {
        case .arrow:
            base.drawArrow(&c, at: p, scale: 1.1)
        case .hand:
            let cursors = DemoCursors.shared
            let s = 1.1
            c.draw(cursors.hand, in: CGRect(x: p.x - cursors.handHotSpot.x * s, y: p.y - cursors.handHotSpot.y * s,
                                            width: cursors.handSize.width * s, height: cursors.handSize.height * s))
        case .cross:
            // macOS ekran görüntüsü artısı: ince siyah çizgiler, beyaz kenar
            var plus = Path()
            plus.move(to: CGPoint(x: p.x - 11, y: p.y)); plus.addLine(to: CGPoint(x: p.x + 11, y: p.y))
            plus.move(to: CGPoint(x: p.x, y: p.y - 11)); plus.addLine(to: CGPoint(x: p.x, y: p.y + 11))
            c.stroke(plus, with: .color(.white), lineWidth: 3.2)
            c.stroke(plus, with: .color(.black), lineWidth: 1.4)
        }
    }

    private func drawChip(_ ctx: inout GraphicsContext, _ chip: String, alpha: Double) {
        let fs = 92.0 * (0.92 + 0.08 * alpha)
        let center = CGPoint(x: Self.size.width / 2, y: Self.size.height * 0.4)
        let text = ctx.resolve(Text(verbatim: chip).font(.system(size: fs, weight: .semibold)).foregroundStyle(.white))
        let ts = text.measure(in: Self.size)
        let box = CGRect(x: center.x - ts.width / 2 - fs * 0.5, y: center.y - ts.height / 2 - fs * 0.14,
                         width: ts.width + fs, height: ts.height + fs * 0.28)
        var c = ctx
        c.opacity = alpha
        let shape = Path(roundedRect: box, cornerRadius: fs * 0.28)
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 20, y: 8))
        shadow.fill(shape, with: .color(hex(0x0c0c0e).opacity(0.82)))
        c.stroke(shape, with: .color(.white.opacity(0.22)), lineWidth: 1)
        c.draw(text, at: center)
    }

    /// Alt yazı ve sondaki başlık aynı biçimde: yarı saydam koyu kapsül, ortalı, aynı yazı tipi
    private func drawLabel(_ ctx: inout GraphicsContext, _ label: String, alpha: Double, y: Double, size fs: Double) {
        let text = ctx.resolve(Text(verbatim: label).font(.system(size: fs, weight: .semibold)).foregroundStyle(.white))
        let ts = text.measure(in: Self.size)
        let box = CGRect(x: Self.size.width / 2 - ts.width / 2 - fs * 0.85, y: y - ts.height / 2 - fs * 0.38,
                         width: ts.width + fs * 1.7, height: ts.height + fs * 0.76)
        var c = ctx
        c.opacity = alpha
        c.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(.black.opacity(0.6)))
        c.draw(text, at: CGPoint(x: Self.size.width / 2, y: y))
    }

    /// Trackpad: koyu cam yüzey, altın sarısı parmaklar, basınca küçülür, çevresinde halka yayılır
    private func drawPad(_ ctx: inout GraphicsContext, _ w: World) {
        let r = pad
        var c = ctx
        c.opacity = w.padAlpha
        let shape = Path(roundedRect: r, cornerRadius: 26)
        var shadow = c
        shadow.addFilter(.shadow(color: .black.opacity(0.5), radius: 24, y: 8))
        shadow.fill(shape, with: .linearGradient(Gradient(colors: [hex(0x2a2a2f).opacity(0.94), hex(0x1c1c20).opacity(0.94)]),
                                                 startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        c.stroke(shape, with: .color(.white.opacity(0.16)), lineWidth: 1)
        let d = r.width * 0.11
        for (p, k) in w.ripples where k > 0 && k < 1 {
            let center = CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
            let rr = d / 2 + d * 0.7 * k
            c.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(Color.fingerGold.opacity(0.9 * (1 - k))), lineWidth: 2.5)
        }
        guard w.fingerAlpha > 0 else { return }
        var f = c
        f.opacity = w.padAlpha * w.fingerAlpha
        for p in w.fingers {
            let center = CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
            let rr = d / 2 * (1 - 0.15 * w.press)
            f.fill(Path(ellipseIn: CGRect(x: center.x - rr * 1.35, y: center.y - rr * 1.15, width: rr * 2.7, height: rr * 2.7)),
                   with: .radialGradient(Gradient(colors: [.black.opacity(0.35), .clear]), center: center, startRadius: rr * 0.8, endRadius: rr * 1.35))
            f.fill(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)),
                   with: .linearGradient(Gradient(colors: [Color.fingerGoldLight, Color.fingerGold, Color.fingerGoldDeep]),
                                         startPoint: CGPoint(x: center.x, y: center.y - rr), endPoint: CGPoint(x: center.x, y: center.y + rr)))
        }
    }
}

/// Tanıtım videoları; şimdilik bir tane
@MainActor
enum PromoStories {
    static let all: [(name: String, story: PromoStory)] = [
        // Önce trackpad hareketleri, sonra klavye; sonda kendi hareketini kurma ve son kart
        ("fingerkit-tanitim", PromoStory(acts: [.middleClick, .closeTab, .reopenTab, .brightness, .screenshot, .snapAll, .customGesture, .endCard])),
    ]

    /// Kareleri klasöre yazar: <klasör>/<ad>/0001.png… (1920×1200, 60 kare/sn)
    static func render(to dir: URL, only: String?) {
        for (name, story) in all where only == nil || name.hasPrefix(only!) {
            let folder = dir.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let count = Int(story.duration * PromoStory.fps)
            for i in 0..<count {
                let t = Double(i) / PromoStory.fps
                let view = Canvas { ctx, _ in story.draw(&ctx, at: t) }
                    .frame(width: PromoStory.size.width, height: PromoStory.size.height)
                    .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: folder.appendingPathComponent(String(format: "%04d.png", i + 1)))
            }
            print("VIDEO \(name): \(count) kare, \(String(format: "%.1f", story.duration)) sn")
        }
    }
}
