import AppKit
import SwiftUI
import FingerKitCore

/// Her sayfanın üstünde, kapalı başlayan "Topluluğun sevdiği ayarlar" bölümü.
/// Satırda canlı örnek, ad, neden sevildiği ve "Ekle". Bir şeyin yerine geçecekse önce sorulur.
struct CommunitySection: View {
    let page: CommunityPage
    @Environment(Engine.self) private var engine
    /// Açık/kapalı hatırlanır. @AppStorage değil: o, Mac'in ayar deposundaki her değişiklikte
    /// (ör. açık sekmenin kaydı) bütün öneri bölümlerini yeniden çizdiriyordu.
    @State private var open: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private let tone = CommunityTone.self

    init(page: CommunityPage) {
        self.page = page
        _open = State(initialValue: UserDefaults.standard.bool(forKey: Self.openKey(page)))
    }

    /// Kurulu olmayan uygulamaların önerileri gösterilmez; uygulama adları Mac'teki adıyla
    private var picks: [CommunityPick] {
        CommunityPick.picks(for: page)
            .filter { $0.needsApp.map(Self.isInstalled) ?? true }
            .map { $0.renamingApps(Self.appName) }
    }

    var body: some View {
        let picks = picks
        let added = picks.filter { $0.isAdded(in: engine.settings) }.count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { open.toggle() }
                UserDefaults.standard.set(open, forKey: Self.openKey(page))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(tone.icon(dark))
                    Text("Topluluğun sevdiği ayarlar")
                        .fontWeight(.semibold)
                    Text(added > 0 ? String(localized: "\(added)/\(picks.count) eklendi") : String(localized: "\(picks.count) öneri"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, UIStyle.pad(16))
                .frame(minHeight: UIStyle.control + 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? String(localized: "Önerileri gizle") : String(localized: "İnsanların en çok kullandığı ayarları gör, tek tıkla ekle"))

            if open {
                VStack(alignment: .leading, spacing: 8) {
                    CommunityStrip(picks: picks)
                    Text("Öneriler Mac kullanıcılarının forumlarda ve paylaşılan ayarlarda en sık andıklarından seçildi; FingerKit internete bağlanmaz.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, UIStyle.pad(16))
                }
                .padding(.bottom, UIStyle.pad(12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Öneriler sayfadan yalnız ince bir kenarla ayrılır (CommunityTone)
        .background {
            let shape = RoundedRectangle.card
            shape.fill(tone.fill(dark))
                .overlay(shape.strokeBorder(tone.border(dark), lineWidth: 1))
        }
        .frame(maxWidth: Self.maxWidth)
        .padding(.horizontal, UIStyle.pad(18))
        .padding(.top, UIStyle.pad(2))
        .padding(.bottom, UIStyle.pad(6))
        .frame(maxWidth: .infinity)
    }

    /// Geniş pencerede üç kart yan yana sığar, daha fazla yayılmaz
    static let maxWidth: CGFloat = 1140

    private static func openKey(_ page: CommunityPage) -> String { "community.open.\(page.rawValue)" }

    static func isInstalled(_ bundleID: String) -> Bool {
        AppLookup.name(bundleID) != nil
    }

    static func appName(_ bundleID: String) -> String? {
        AppLookup.name(bundleID)
    }
}

/// Uygulama adı ve kurulu olup olmadığı bir kez sorulur: Mac'e her çizimde sormak sayfayı yavaşlatıyordu.
/// Bir dakika sonra yeniden sorulur (bu arada kurulan ya da silinen uygulama görünsün).
@MainActor
enum AppLookup {
    private static var names: [String: (name: String?, at: Date)] = [:]

    static func name(_ bundleID: String) -> String? {
        if let hit = names[bundleID], Date().timeIntervalSince(hit.at) < 60 { return hit.name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
        names[bundleID] = (name, Date())
        return name
    }
}

/// Kartlar tek sırada, sayfa sayfa yana kayar. Pencere ne genişlikte olursa olsun yarım kart görünmez:
/// sığan kart sayısı hesaplanır, kartlar alanı tam doldurur. Oklar, trackpad'de yana kaydırma ve
/// farenin tekerleği (yukarı/aşağı) bir kart kaydırır; sona gelince tekerlek sayfayı kaydırmaya devam eder.
private struct CommunityStrip: View {
    let picks: [CommunityPick]
    /// En soldaki görünen kart
    @State private var first = 0
    @State private var width: CGFloat = 0
    @State private var wheel = StripWheel()

    static let minCard: CGFloat = 250
    /// Tek kart sığan dar alanda kart bundan büyümez, ortada durur
    static let maxCard: CGFloat = 380
    static let spacing: CGFloat = 14
    private var side: CGFloat { UIStyle.pad(16) }

    /// Bu genişliğe kaç kart tam sığar
    private var perPage: Int {
        let room = width - side * 2
        return max(1, min(picks.count, Int((room + Self.spacing) / (Self.minCard + Self.spacing))))
    }
    private var cardWidth: CGFloat {
        let n = CGFloat(perPage)
        return max(1, min(Self.maxCard, (width - side * 2 - Self.spacing * (n - 1)) / n))
    }
    /// Kartlar alanı doldurmuyorsa ortalanır
    private var inset: CGFloat {
        let n = CGFloat(perPage)
        return max(0, (width - side * 2 - n * cardWidth - (n - 1) * Self.spacing) / 2)
    }
    private var lastFirst: Int { max(0, picks.count - perPage) }

    var body: some View {
        let start = min(first, lastFirst)
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(picks) { pick in
                CommunityRow(pick: pick)
                    .frame(width: cardWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .offset(x: inset - CGFloat(start) * (cardWidth + Self.spacing))
        // Genişlik pencereden gelir, kartların toplam boyundan değil
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, side)
        // Kartların gölgesi kesilmesin
        .padding(.vertical, 14)
        // Yan kartlar kenar boşluğunda görünmesin; gölge için kartın dışında 6 pt kalır
        .mask(Rectangle().padding(.horizontal, max(0, side - 6)))
        .background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { width = $1 }
        })
        .overlay(alignment: .leading) { arrow(-1) }
        .overlay(alignment: .trailing) { arrow(1) }
        .onHover { inside in
            if inside { wheel.start { step($0) } } else { wheel.stop() }
        }
        .onPageVisibility(hide: { wheel.stop() })
        // Geliştirme: ölçüm modu (TabTimer) şeridi kaydırır
        .onReceive(NotificationCenter.default.publisher(for: TabTimer.stripStep)) { _ in
            if first >= lastFirst { first = 0 } else { step(1) }
        }
        .animation(.snappy(duration: 0.3), value: start)
    }

    /// Bir kart ileri ya da geri; kayacak yer yoksa false (tekerlek o zaman sayfayı kaydırır)
    @discardableResult
    private func step(_ direction: Int) -> Bool {
        let start = min(first, lastFirst)
        let target = min(max(start + direction, 0), lastFirst)
        guard target != start else { return false }
        first = target
        return true
    }

    @ViewBuilder
    private func arrow(_ direction: Int) -> some View {
        let start = min(first, lastFirst)
        if direction < 0 ? start > 0 : start < lastFirst {
            Button {
                first = min(max(start + direction * perPage, 0), lastFirst)
            } label: {
                Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.card))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .help(direction < 0 ? String(localized: "Önceki öneriler") : String(localized: "Sonraki öneriler"))
        }
    }
}

/// Fare şeridin üstündeyken kaydırmayı dinler: tekerlek ya da trackpad hareketi biriktirilir,
/// eşik aşılınca bir kart kayar. Trackpad'de yukarı-aşağı kaydırma sayfanın kalır, yana kaydırma şeridin.
/// Farede (tekerlekli fare ya da Magic Mouse) yukarı-aşağı da şeridi kaydırır: yana kaydıramayan da gezinsin.
/// Bir parmak hareketi tek kart kaydırır: hareketin devamı ve parmak kalkınca gelen süzülme
/// (momentum) yeni kart kaydırmaz; sonraki kart için parmak yeniden değmeli.
@MainActor
private final class StripWheel {
    private var monitor: Any?
    private var total: CGFloat = 0
    /// Bu parmak hareketinde kart kaydı; yeni hareket başlayana kadar gelen olaylar yutulur
    private var used = false
    /// Tekerlekli farede bir çentik bir kart; hızlı çevirmede arka arkaya kart atlamasın
    private var quietUntil = Date.distantPast

    func start(_ step: @escaping (Int) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let precise = event.hasPreciseScrollingDeltas
            let trackpad = precise && MultitouchSource.shared.scrollIsFromTrackpad(momentum: event.momentumPhase != [])
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            // Trackpad: yalnız yana hareket şeridin. Fare: yukarı-aşağı da şeridi kaydırır.
            let delta: CGFloat
            if abs(dx) > abs(dy) { delta = -dx } else if !trackpad { delta = -dy } else { return event }
            if precise {
                if event.phase == .began || event.phase == .mayBegin { self.total = 0; self.used = false }
                // Süzülme (parmak kalktıktan sonra) hiç kart kaydırmaz
                if event.momentumPhase != [] { return self.used ? nil : event }
                if self.used { return nil }
                self.total += delta
                guard abs(self.total) >= 30 else { return nil }
                let moved = step(self.total > 0 ? 1 : -1)
                self.total = 0
                guard moved else { return event }
                self.used = true
                return nil
            }
            guard delta != 0 else { return event }
            if Date() < self.quietUntil { return nil }
            guard step(delta > 0 ? 1 : -1) else { return event }
            self.quietUntil = Date().addingTimeInterval(0.15)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        total = 0
    }
}

/// Tek öneri satırı: fare üstüne gelince örnek oynar
private struct CommunityRow: View {
    let pick: CommunityPick
    @Environment(Engine.self) private var engine
    @State private var hovering = false
    @State private var asking = false

    /// Eklenince yerinden edilecekler ve Mac'in kendi hareketleriyle çakışmalar
    private var warnings: [String] {
        var result = pick.replaces(in: engine.settings)
        for change in pick.changes {
            if case let .gesture(g, _) = change, let message = engine.systemTrackpad.conflict(with: g) {
                result.append(message)
            }
        }
        return result
    }

    var body: some View {
        let added = pick.isAdded(in: engine.settings)
        let warnings = added ? [] : warnings
        // Kart: üstte örnek, altında başlık ve açıklama, en altta uyarı ve düğme
        VStack(alignment: .leading, spacing: 12) {
            CommunityDemoView(demo: pick.demo, chip: pick.demoChip, caption: pick.title, slice: pick.demoSlice, playing: hovering)
                .clipShape(RoundedRectangle(cornerRadius: max(UIStyle.card - 8, 6), style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(pick.title)
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(pick.why)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 10) {
                if let first = warnings.first {
                    Label(first, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(warnings.joined(separator: "\n"))
                }
                Spacer(minLength: 0)
                if added {
                    Label("Eklendi", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                        .fixedSize()
                } else {
                    Button(String(localized: "Ekle")) {
                        if warnings.isEmpty { add() } else { asking = true }
                    }
                    .buttonStyle(.softPrimary)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(UIStyle.pad(10))
        .frame(maxHeight: .infinity, alignment: .top)
        .surface(hovering ? .raised : .card)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .confirmationDialog(String(localized: "“\(pick.title)” eklensin mi?"), isPresented: $asking) {
            Button(String(localized: "Yine de ekle")) { add() }
            Button(String(localized: "Vazgeç"), role: .cancel) {}
        } message: {
            Text(warnings.joined(separator: "\n"))
        }
    }

    private func add() {
        withAnimation { pick.apply(to: &engine.settings) }
        Log.write("topluluk önerisi eklendi: \(pick.id)")
    }
}

/// "Topluluğun sevdiği ayarlar" bölümünün görünümü (K6 Çizgi): zemin yok, yalnız ince kenar; ışıltı FingerKit sarısı
enum CommunityTone {
    static func fill(_ dark: Bool) -> Color { .clear }
    static func border(_ dark: Bool) -> Color { Color.primary.opacity(dark ? 0.13 : 0.12) }
    static func icon(_ dark: Bool) -> Color { .themeGold }
}
