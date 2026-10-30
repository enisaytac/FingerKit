import SwiftUI
import FingerKitCore

/// Hareketin küçük çizimi: trackpad çerçevesi, parmaklar ve yön oku
struct GestureGlyph: View {
    let gesture: Gesture

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
            // Trackpad: çizgisiz, yumuşak köşeli ton
            ctx.fill(RoundedRectangle(cornerRadius: min(UIStyle.small * 0.75, size.height * 0.3), style: .continuous).path(in: rect),
                     with: .color(.primary.opacity(0.1)))

            let accent = GraphicsContext.Shading.style(.tint)
            let muted = GraphicsContext.Shading.color(.secondary.opacity(0.6))
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.09
            let gap = r * 2.7

            func dot(_ p: CGPoint, _ shade: GraphicsContext.Shading = accent, ring: Bool = false) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: shade)
                if ring {
                    let R = r * 1.9
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - R, y: p.y - R, width: R * 2, height: R * 2)), with: shade, lineWidth: 1)
                }
            }
            /// n parmak, merkez etrafında yatay ya da dikey sırada
            func row(_ n: Int, at c: CGPoint, vertical: Bool = false) -> [CGPoint] {
                (0..<n).map { i in
                    let o = (Double(i) - Double(n - 1) / 2) * gap
                    return vertical ? CGPoint(x: c.x, y: c.y + o) : CGPoint(x: c.x + o, y: c.y)
                }
            }
            func arrow(from a: CGPoint, to b: CGPoint) {
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head = r * 2.2
                line.move(to: CGPoint(x: b.x - head * cos(angle - .pi / 5), y: b.y - head * sin(angle - .pi / 5)))
                line.addLine(to: b)
                line.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 5), y: b.y - head * sin(angle + .pi / 5)))
                ctx.stroke(line, with: accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }

            let n = gesture.fingers
            switch gesture.shape {
            case .swipe(let d):
                let len = size.height * 0.28
                let (dx, dy): (CGFloat, CGFloat) = switch d {
                case .up: (0, -1)
                case .down: (0, 1)
                case .left: (-1, 0)
                case .right: (1, 0)
                }
                let start = CGPoint(x: mid.x - dx * len * 0.9, y: mid.y - dy * len * 0.9)
                for p in row(n, at: start, vertical: dx != 0) { dot(p) }
                arrow(from: CGPoint(x: start.x + dx * r * 2, y: start.y + dy * r * 2),
                      to: CGPoint(x: mid.x + dx * len * 1.3, y: mid.y + dy * len * 1.3))
            case .tap:
                for p in row(n, at: mid) { dot(p) }
            case .doubleTap:
                for p in row(n, at: mid) { dot(p, ring: true) }
            case .click:
                let c = CGPoint(x: mid.x, y: mid.y - r)
                for p in row(n, at: c) { dot(p) }
                var bar = Path()
                bar.move(to: CGPoint(x: c.x - gap * 1.4, y: c.y + r * 2.6))
                bar.addLine(to: CGPoint(x: c.x + gap * 1.4, y: c.y + r * 2.6))
                ctx.stroke(bar, with: accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            case .tipTap(let side):
                let s: CGFloat = side == .left ? -1 : 1
                dot(CGPoint(x: mid.x - s * gap * 0.6, y: mid.y), muted)
                dot(CGPoint(x: mid.x + s * gap * 0.9, y: mid.y), ring: true)
            case .edgeSwipe(let e):
                let inset = r * 1.6
                let (a, b): (CGPoint, CGPoint) = switch e {
                case .left: (CGPoint(x: inset, y: mid.y), CGPoint(x: mid.x + gap, y: mid.y))
                case .right: (CGPoint(x: size.width - inset, y: mid.y), CGPoint(x: mid.x - gap, y: mid.y))
                case .top: (CGPoint(x: mid.x, y: inset), CGPoint(x: mid.x, y: mid.y + gap * 0.8))
                case .bottom: (CGPoint(x: mid.x, y: size.height - inset), CGPoint(x: mid.x, y: mid.y - gap * 0.8))
                }
                dot(a)
                arrow(from: a, to: b)
            case .cornerTap(let c):
                let inset = r * 2.4
                let p: CGPoint = switch c {
                case .topLeft: CGPoint(x: inset, y: inset)
                case .topRight: CGPoint(x: size.width - inset, y: inset)
                case .bottomLeft: CGPoint(x: inset, y: size.height - inset)
                case .bottomRight: CGPoint(x: size.width - inset, y: size.height - inset)
                }
                dot(p, ring: true)
            }
        }
        .accessibilityLabel(gesture.name)
    }
}
