import AppKit
import SwiftUI
import FingerKitCore

/// GitHub sayfasının resimleri: üst şerit (koyu ve açık tema), özellik görselleri, sosyal önizleme.
/// Özellik görselleri tanıtım videosunun anlarıdır (`PromoStory`); pano videoda yok, önizleme çiziminden gelir.
/// `--gorselleri-ciz <klasör>` yazar; betik `Araclar/gosteri/gorseller.sh` docs/'a koyar.
@MainActor
enum PromoImages {
    static let tagline = "Trackpad gestures, Hyper Key and a radial menu for your Mac."
    static let promise = "Free  ·  Open source  ·  Never connects to the internet"
    static let night = Color(red: 0.03, green: 0.035, blue: 0.04)

    /// Videodaki an (saniye) → resim adı
    static let moments: [(name: String, time: Double)] = [
        ("feature-gestures", 3.3),
        ("feature-radial", 6.75),
        ("feature-snap", 12.9),
        ("feature-screenshot", 10.4),
        ("feature-custom", 17.75),
    ]

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let story = PromoStories.all[0].story
        let size = PromoStory.size
        for (name, t) in moments {
            write(Canvas { ctx, _ in story.draw(&ctx, at: t) }.frame(width: size.width, height: size.height),
                  scale: 1, to: dir.appendingPathComponent("\(name).png"))
        }
        if let pick = CommunityPick.all.first(where: { $0.id == "clipboard-v" }) {
            let timing = DemoTiming(pick.demo)
            // Kısayol yazısı kalktıktan sonra, liste açıkken (yazı README'de)
            let painter = DemoPainter(demo: pick.demo, chip: nil, caption: nil, slice: nil,
                                      time: (max(timing.chipOut, timing.effectStart + 1) + timing.reset) / 2, timing: timing, size: size, cursors: DemoCursors.shared)
            write(Canvas { ctx, _ in painter.draw(&ctx) }.frame(width: size.width, height: size.height),
                  scale: 1, to: dir.appendingPathComponent("feature-clipboard.png"))
        }
        write(banner(dark: true), scale: 2, to: dir.appendingPathComponent("banner-dark.png"))
        write(banner(dark: false), scale: 2, to: dir.appendingPathComponent("banner-light.png"))
        write(social(story), scale: 1, to: dir.appendingPathComponent("social-preview.png"))
        print("GÖRSELLER: \(dir.path)")
    }

    private static func write(_ view: some View, scale: Double, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private static var icon: Image? {
        NSImage(contentsOfFile: "docs/icon.png").map { Image(nsImage: $0) }
    }

    /// Üst şerit 1280×360: simge, ad, tek cümle, söz. Koyu: gece zemin + yeşil ışık; açık: beyaz zemin + yeşil çizgi
    private static func banner(dark: Bool) -> some View {
        let ink = dark ? Color.white : Color(red: 0.12, green: 0.14, blue: 0.16)
        return ZStack {
            if dark {
                night
                RadialGradient(colors: [PromoStory.green.opacity(0.22), .clear], center: UnitPoint(x: 0.27, y: 0.5),
                               startRadius: 0, endRadius: 520)
            } else {
                Color.white
                RadialGradient(colors: [PromoStory.green.opacity(0.12), .clear], center: UnitPoint(x: 0.27, y: 0.5),
                               startRadius: 0, endRadius: 520)
            }
            HStack(spacing: 44) {
                icon?.resizable().frame(width: 200, height: 200)
                    .shadow(color: PromoStory.green.opacity(dark ? 0.35 : 0.2), radius: 30)
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: "FingerKit").font(.system(size: 84, weight: .bold)).foregroundStyle(ink)
                    Text(verbatim: tagline).font(.system(size: 28, weight: .medium)).foregroundStyle(ink.opacity(0.78))
                    Text(verbatim: promise).font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(dark ? PromoStory.green : Color(red: 0.1, green: 0.55, blue: 0.22))
                        .padding(.top, 6)
                }
            }
        }
        .frame(width: 1280, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .background(Color.clear)
    }

    /// Sosyal önizleme 1280×640 (bağlantı paylaşılınca görünen resim): solda ad ve cümle, sağda videodan daire menü anı (ekranın tamamı görünür)
    private static func social(_ story: PromoStory) -> some View {
        let size = PromoStory.size
        let shot = Canvas { ctx, _ in story.draw(&ctx, at: 6.75) }.frame(width: size.width, height: size.height)
        return ZStack(alignment: .leading) {
            night
            RadialGradient(colors: [PromoStory.green.opacity(0.2), .clear], center: UnitPoint(x: 0.2, y: 0.5),
                           startRadius: 0, endRadius: 560)
            shot.scaleEffect(0.53, anchor: .topLeading)
                .frame(width: size.width * 0.53, height: size.height * 0.53, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                .offset(x: 1280 - 48 - size.width * 0.53, y: 0)
            VStack(alignment: .leading, spacing: 18) {
                icon?.resizable().frame(width: 132, height: 132)
                    .shadow(color: PromoStory.green.opacity(0.35), radius: 24)
                Text(verbatim: "FingerKit").font(.system(size: 76, weight: .bold)).foregroundStyle(.white)
                Text(verbatim: "Trackpad gestures, Hyper Key\nand a radial menu for your Mac.")
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .fixedSize()
                Text(verbatim: "Free · Open source · Offline").font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(PromoStory.green)
            }
            .padding(.leading, 64)
        }
        .frame(width: 1280, height: 640)
        .clipped()
    }
}
