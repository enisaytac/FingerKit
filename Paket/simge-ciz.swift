// FingerKit simgesini çizer: swift Paket/simge-ciz.swift <çıkış klasörü (.iconset)> [parmak sayısı: 3 ya da 4]
// Sonra: iconutil -c icns <klasör> -o Paket/FingerKit.icns
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let fingerCount = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 3 : 3

/// Parmak merkezleri (100'lük çizimde). Üç parmak: kenarı 12 olan eşkenar üçgen, tepesi yukarıda,
/// ağırlık merkezi trackpad'in tam ortasında (50; 50,4); parmaklar arası boşluk her yerde 4,8.
func fingers(_ n: Int) -> [(CGFloat, CGFloat)] {
    guard n == 3 else { return [(35.5, 53.0), (45.2, 49.0), (54.8, 49.0), (64.5, 53.0)] }
    let side: CGFloat = 12, cx: CGFloat = 50, cy: CGFloat = 28.5 + 43.75 / 2
    let r = side / sqrt(3)
    return [(cx, cy - r), (cx - side / 2, cy + r / 2), (cx + side / 2, cy + r / 2)]
}
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Gece logosu (C11 b): siyah zemin, tam opak beyaz çizim. Ölçüler 100'lük çizimden (seçenek sayfası):
    // zemin 4-96 (köşe 22), trackpad 70 x 43,75 (oran 1,6, köşe 6, çizgi 1,6), dört eşit parmak (yarıçap 3,6).
    // macOS simge ızgarası 1024'te 824'lük yuvarlak kare; çizim bu kareye oranla yerleşir.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let u = body.width / 92
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: body.minX + (x - 4) * u, y: body.maxY - (y - 4) * u) }
    let shape = NSBezierPath(roundedRect: body, xRadius: 22 * u, yRadius: 22 * u)
    NSGradient(starting: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1),
               ending: NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1))!
        .draw(in: shape, angle: -90)

    // Trackpad: ince beyaz çerçeve; küçük boyutta çizgi kaybolmasın diye en az 1 piksel
    let corner = p(15, 28.5 + 43.75)
    let pad = NSRect(x: corner.x, y: corner.y, width: 70 * u, height: 43.75 * u)
    let padPath = NSBezierPath(roundedRect: pad, xRadius: 6 * u, yRadius: 6 * u)
    NSColor.white.setStroke()
    padPath.lineWidth = max(1, 1.6 * u)
    padPath.stroke()

    // Dört eşit parmak (dıştakiler biraz aşağıda, gerçek el gibi) ya da üçgen üç parmak
    NSColor.white.setFill()
    for (x, y) in fingers(fingerCount) {
        let c = p(x, y), r = max(0.8, 3.6 * u)
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
