import SwiftUI
import FingerKitCore

/// "Pano" sekmesi: aç/kapa, listeyi açan tuş, son kopyalananlar (tek tek silme, hepsini temizle)
struct ClipboardView: View {
    @Environment(Engine.self) private var engine
    @State private var listening = false
    @State private var stopRecording: (() -> Void)?
    @State private var confirmClear = false

    var body: some View {
        @Bindable var engine = engine
        let clip = engine.settings.clipboard
        VStack(spacing: 0) {
            header
            ScrollView {
                // Öneriler sayfayla birlikte kayar: açılınca sayfayı pencereden taşırmaz
                CommunitySection(page: .clipboard)
                VStack(alignment: .leading, spacing: UIStyle.pad(16)) {
                    if !engine.settings.enabled, clip.enabled {
                        notice(String(localized: "FingerKit kapalı; pano dinlenmiyor. Sol üstteki düğmeden aç."))
                    } else if clip.enabled, !engine.settings.hyper.enabled {
                        notice(String(localized: "Hiper Tuş kapalı; kopyalar kaydediliyor ama ⇪ + \(clip.key) listeyi açmaz. “Hiper Tuş” sekmesinden aç."))
                    }
                    FeatureExplainer(
                        title: String(localized: "Kopyaladığın her şey bir tuş uzakta"),
                        lines: [String(localized: "⇪ + \(clip.key) ekranın ortasında panoyu açar: üstte görseller ve ekran görüntüleri, ortada yazılar, altta bağlantılar."),
                                String(localized: "Birine tıkla ya da oklarla seçip ↩'a bas: öndeki uygulamaya yapıştırılır. Boşluk büyük önizler, P sabitler."),
                                String(localized: "Görseldeki yazıyı T ile kopyalarsın (Mac'in kendi yazı tanıması, internete gitmez).")],
                        demo: CommunityDemo(.keys(["⇪", clip.key]), .clipboardList),
                        chip: "⇪ + \(clip.key)", caption: String(localized: "Pano açılır"))
                    SectionTitle(title: String(localized: "Kısayol"))
                    shortcutRow
                    SectionTitle(title: String(localized: "Saklama"))
                    keepRows
                    HStack(alignment: .lastTextBaseline) {
                        SectionTitle(title: String(localized: "Son kopyalananlar"))
                        Text("\(engine.clipHistory.items.count)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Hepsini temizle", role: .destructive) { confirmClear = true }
                            .disabled(engine.clipHistory.items.allSatisfy(\.pinned))
                            .help(String(localized: "Sabitlenenler kalır"))
                    }
                    list
                    Text(String(localized: "Kopyalar yalnız bu Mac'te bir dosyada durur, dışarı gitmez. Şifre yöneticilerinin gizli diye işaretlediği kopyalar kaydedilmez. Aynı şey ikinci kez eklenmez, en üste çıkar. Görseldeki yazıyı Mac'in kendi yazı tanıma özelliği okur; internete gitmez."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(UIStyle.pad(20))
                .frame(maxWidth: .infinity)
            }
            .opacity(clip.enabled ? 1 : 0.5)
        }
        .confirmationDialog(String(localized: "Bütün kopyalar silinsin mi?"), isPresented: $confirmClear) {
            Button("Hepsini sil", role: .destructive) { engine.clipHistory.clear() }
            Button(String(localized: "Vazgeç"), role: .cancel) {}
        }
        .onPageVisibility(hide: { stopListening() })
    }

    private var header: some View {
        @Bindable var engine = engine
        return PageHeader(icon: "doc.on.clipboard.fill",
                          title: String(localized: "Pano geçmişi"),
                          detail: String(localized: "Kopyaladığın yazılar, görseller, bağlantılar ve ekran görüntüleri saklanır. ⇪ + \(engine.settings.clipboard.key) ekranda panoyu açar; seçtiğin şey yapıştırılır.")) {
            Toggle("", isOn: $engine.settings.clipboard.enabled)
                .toggleStyle(.soft)
                .labelsHidden()
                .help(engine.settings.clipboard.enabled ? String(localized: "Pano geçmişi açık") : String(localized: "Pano geçmişi kapalı; kopyalar kaydedilmez"))
        }
    }

    private var shortcutRow: some View {
        let clip = engine.settings.clipboard
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(String(localized: "Listeyi aç"))
                    .fontWeight(.medium)
                Spacer()
                Button {
                    listening ? stopListening() : startListening()
                } label: {
                    HyperKeyCap(key: listening ? nil : clip.key, listening: listening)
                }
                .buttonStyle(.plain)
                .help(listening ? String(localized: "Yeni tuşa bas; Esc vazgeçer") : String(localized: "Tıkla, yeni tuşa bas"))
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(8))
        .surface()
    }

    /// Aynı tuş Hyper Key sekmesinde de kullanılıyorsa: pano önce gelir
    private var warning: String? {
        let clip = engine.settings.clipboard
        let hyper = engine.settings.hyper
        if let snap = hyper.snap(for: clip.keyCode) {
            return String(localized: "⇪ + \(clip.key) “\(snap.layout.title)” için de kayıtlı; pano listesi önce gelir.")
        }
        if let app = hyper.binding(for: clip.keyCode) {
            return String(localized: "⇪ + \(clip.key) \(app.appName)'yi de açıyor; pano listesi önce gelir.")
        }
        return nil
    }

    /// Kaç gün tutulsun, ekran görüntüleri gelsin mi
    private var keepRows: some View {
        @Bindable var engine = engine
        return CardStack {
            HStack {
                Text(String(localized: "Kopyalar kaç gün kalsın"))
                    .fontWeight(.medium)
                Spacer()
                Menu {
                    Picker("", selection: $engine.settings.clipboard.keepDays) {
                        ForEach([1, 3, 7, 14, 30], id: \.self) { d in
                            Text(dayTitle(d)).tag(d)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        Text(dayTitle(engine.settings.clipboard.keepDays))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, UIStyle.pad(12))
            .padding(.vertical, UIStyle.pad(8))
            Toggle(isOn: $engine.settings.clipboard.screenshots) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Ekran görüntüleri ve kayıtları da gelsin"))
                        .fontWeight(.medium)
                    Text(String(localized: "Kaydedildiği klasörden (\(ScreenshotWatcher.folder.lastPathComponent)) kendiliğinden listeye düşer; dosya yerinde kalır."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(SoftToggleStyle(spread: true))
            .padding(.horizontal, UIStyle.pad(12))
            .padding(.vertical, UIStyle.pad(8))
            Label(String(localized: "Sabitlediğin kopya süre dolsa da silinmez."), systemImage: "pin")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, UIStyle.pad(12))
                .padding(.vertical, UIStyle.pad(8))
        }
    }

    private func dayTitle(_ d: Int) -> String {
        d == 1 ? String(localized: "1 gün") : String(localized: "\(d) gün")
    }

    @ViewBuilder
    private var list: some View {
        let all = engine.clipHistory.items
        let items = all.filter(\.pinned) + all.filter { !$0.pinned }.prefix(100)
        if items.isEmpty {
            Text(String(localized: "Henüz kopya yok. Bir yazıyı ⌘C ile kopyala, burada görünür."))
                .foregroundStyle(.secondary)
        } else {
            CardStack(spacing: 5, lazy: true) {
                ForEach(items) { item in
                    ClipRow(item: item, pin: { engine.clipHistory.togglePin(item.id) }) { engine.clipHistory.remove(item.id) }
                }
            }
        }
    }

    private func notice(_ text: String) -> some View {
        SoftNotice(icon: "pause.circle.fill", text: text)
    }

    private func startListening() {
        stopListening()
        listening = true
        stopRecording = listenForKey(engine) { key in
            stopListening()
            guard let key else { return }
            engine.settings.clipboard.keyCode = key.0
            engine.settings.clipboard.key = key.1
        }
    }

    private func stopListening() {
        stopRecording?()
        stopRecording = nil
        listening = false
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let pin: () -> Void
    let remove: () -> Void
    @State private var hovering = false
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            switch item.kind {
            case .image, .video:
                Group {
                    if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) } else { Color.secondary.opacity(0.15) }
                }
                .frame(width: 36, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: max(UIStyle.small - 4, 4), style: .continuous))
                .task(id: item.file) { thumb = await ThumbnailCache.image(for: item.file) }
            case .link:
                Image(systemName: "link").foregroundStyle(.secondary).frame(width: 36)
            case .text:
                Image(systemName: "text.alignleft").foregroundStyle(.secondary).frame(width: 36)
            }
            Text(item.kind == .image || item.kind == .video ? (item.file.map { URL(fileURLWithPath: $0).lastPathComponent } ?? item.title()) : item.title())
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(item.age())
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: pin) {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.softQuiet)
            .opacity(hovering || item.pinned ? 1 : 0.35)
            .help(item.pinned ? String(localized: "Sabitliği kaldır") : String(localized: "Sabitle: süre dolsa da silinmesin"))
            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.softQuiet)
            .opacity(hovering ? 1 : 0.35)
            .help(String(localized: "Bu kopyayı sil"))
        }
        .padding(.horizontal, UIStyle.pad(12))
        .padding(.vertical, UIStyle.pad(5))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(item.text.count > 400 ? String(item.text.prefix(400)) + "…" : item.text)
        .contextMenu {
            Button("Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.text, forType: .string)
            }
            Button("Sil", role: .destructive, action: remove)
        }
    }
}
