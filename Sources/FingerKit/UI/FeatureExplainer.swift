import SwiftUI
import FingerKitCore

/// Bir özelliği anlatan kart: solda canlı önizleme (fare üstündeyken oynar), sağda 2-3 kısa cümle.
/// İlk kez açan biri ne olduğunu bu karttan anlasın.
struct FeatureExplainer: View {
    let title: String
    let lines: [String]
    let demo: CommunityDemo
    var chip: String?
    var caption: String?
    var slice: String?
    /// Öne çıkan kart: başlığın yanında sarı etiket (ör. "Yeni"), çerçeve vurgu renginde
    var badge: String?
    /// Kartın altında ilgili sekmeye götüren bağlantı
    var link: (title: String, action: () -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: UIStyle.pad(14)) {
            CommunityDemoView(demo: demo, chip: chip, caption: caption, slice: slice, playing: hovering)
                .frame(width: 200)
                .clipShape(RoundedRectangle(cornerRadius: max(UIStyle.card - 6, 6), style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.black.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(.tint))
                    }
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                }
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let link {
                    Button(action: link.action) {
                        Label(link.title, systemImage: "arrow.right.circle.fill")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.softLink)
                    .padding(.top, 3)
                }
                if !hovering {
                    Label(String(localized: "Oynatmak için fareyi önizlemenin üstüne getir"), systemImage: "play.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(UIStyle.pad(10))
        .surface()
        .overlay(RoundedRectangle.card.fill(.tint.opacity(badge == nil ? 0 : 0.07)).allowsHitTesting(false))
        .onHover { hovering = $0 }
    }
}
