import AppKit
import SwiftUI

// Yumuşak tasarım parçaları: bütün ekranlar köşe, boşluk, yüzey, düğme ve anahtarı buradan alır.
// Ölçüler o anki tasarım yönünden (UIStyle) okunur; kenar çizgisi yerine gölge ve ton farkı.

// MARK: - Yüzeyler

/// Bir yüzeyin katmandaki yeri
enum SurfaceKind {
    /// Sayfanın üstündeki kart
    case card
    /// Öne çıkan kart (düzenleme kartı, açılan pencere): biraz daha belirgin
    case raised
    /// Kartın içindeki çukur alan
    case well
    /// Renkli uyarı kutusu
    case tinted(Color)
}

private struct SurfaceModifier: ViewModifier {
    let kind: SurfaceKind
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background { background }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        switch kind {
        case .well:
            shape.fill(Color.primary.opacity(dark ? 0.06 : 0.05))
        case .tinted(let tint):
            shape.fill(tint.opacity(dark ? 0.13 : 0.11))
        case .card, .raised:
            // Katmanlar ton farkıyla ayrılır; gölge yalnız ipucu kadar
            let lift = UIStyle.shadow * (kind.isRaised ? 1.4 : 1)
            shape.fill(Color.card)
                .shadow(color: .black.opacity((dark ? 0.4 : 0.08) * lift), radius: 8, y: 2)
        }
    }
}

private extension SurfaceKind {
    var isRaised: Bool { if case .raised = self { true } else { false } }
}

extension View {
    /// Kart, öne çıkan kart, çukur alan ya da renkli uyarı zemini
    func surface(_ kind: SurfaceKind = .card, radius: CGFloat = UIStyle.card) -> some View {
        modifier(SurfaceModifier(kind: kind, radius: radius))
    }

    /// Seçili ya da düzenlenen satırın zemini (kartın biçiminde)
    func rowHighlight(_ on: Bool, strength: Double = 0.14) -> some View {
        background(RoundedRectangle.card.fill(.tint.opacity(on ? strength : 0)))
    }
}

extension Color {
    /// Yazı kutusu, sekme ve seçici zemini: her katmanın üstünde okunan hafif ton
    static let fieldFill = Color.primary.opacity(0.07)
}

// MARK: - Hap düğme

/// Bütün düğmeler: hap biçimi, büyük, çizgisiz. Ana düğme vurgu renginde, sessiz düğme yalnız simge.
struct SoftButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, quiet, link }
    var kind: Kind = .normal
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(configuration: configuration, kind: kind, small: small)
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
    static var softPrimary: SoftButtonStyle { SoftButtonStyle(kind: .primary) }
    static var softQuiet: SoftButtonStyle { SoftButtonStyle(kind: .quiet) }
    static var softLink: SoftButtonStyle { SoftButtonStyle(kind: .link) }
}

private struct SoftButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SoftButtonStyle.Kind
    let small: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let isSmall = small || controlSize == .small || controlSize == .mini
        let height = isSmall ? UIStyle.control - 6 : UIStyle.control
        let pressed = configuration.isPressed
        Group {
            switch kind {
            case .primary:
                configuration.label
                    .font(.system(size: isSmall ? 12 : 13, weight: .semibold))
                    .foregroundStyle(onPrimary)
                    .padding(.horizontal, height * 0.55)
                    .frame(minHeight: height)
                    .background(Capsule().fill(Color.primary.opacity(hovering ? 0.95 : 0.88)))
            case .normal:
                configuration.label
                    .font(.system(size: isSmall ? 12 : 13, weight: .medium))
                    .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                    .padding(.horizontal, height * 0.5)
                    .frame(minHeight: height)
                    .background(Capsule().fill(Color.primary.opacity(hovering ? 0.12 : 0.075)))
            case .quiet:
                configuration.label
                    .frame(minWidth: height - 4, minHeight: height - 4)
                    .background(Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0)))
            case .link:
                configuration.label
                    .foregroundStyle(.tint)
                    .opacity(hovering ? 0.8 : 1)
            }
        }
        .contentShape(Capsule())
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(enabled ? (pressed ? 0.85 : 1) : 0.42)
        .onHover { hovering = $0 && enabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    /// Ana düğme nötr (sarı yalnız seçili şeyde): koyu temada beyaz, açıkta siyah
    private var onPrimary: Color { scheme == .dark ? .black : .white }
}

// MARK: - Aç/kapa anahtarı

/// Yumuşak anahtar: hap biçimli yol, gölgeli beyaz düğme; açıkken vurgu renginde
struct SoftToggleStyle: ToggleStyle {
    var small = false
    /// Yazı solda, anahtar en sağda
    var spread = false

    func makeBody(configuration: Configuration) -> some View {
        SoftSwitch(configuration: configuration, small: small, spread: spread)
    }
}

extension ToggleStyle where Self == SoftToggleStyle {
    static var soft: SoftToggleStyle { SoftToggleStyle() }
    static var softSmall: SoftToggleStyle { SoftToggleStyle(small: true) }
}

private struct SoftSwitch: View {
    let configuration: ToggleStyleConfiguration
    let small: Bool
    let spread: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        let isSmall = small || controlSize == .small || controlSize == .mini
        let height: CGFloat = isSmall ? 18 : 22
        HStack(spacing: 8) {
            configuration.label
            if spread { Spacer(minLength: 8) }
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.18)))
                .frame(width: height * 1.72, height: height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled else { return }
            withAnimation(.snappy(duration: 0.18)) { configuration.isOn.toggle() }
        }
        .opacity(enabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Seçiciler

/// Bölmeli seçici: hap içinde haplar; seçili olan kart tonunda, hafif gölgeli
struct SoftSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var fontSize: CGFloat = 12.5
    @Namespace private var space

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(LocalizedStringKey(option.title))
                        .font(.system(size: fontSize, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: UIStyle.control - 8)
                        .background {
                            if on {
                                Capsule().fill(Color.card)
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "secili", in: space)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.fieldFill))
        .fixedSize()
    }
}

/// Yazı ve arama kutusu zemini: hap, çizgisiz, odaktayken vurgu tonu
struct SoftFieldModifier: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: UIStyle.control - 2)
            .background(Capsule().fill(focused ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(Color.fieldFill)))
    }
}

// MARK: - Kenar sütunu

/// Sol sütunda bölüm başlığı
struct SidebarHeader: View {
    let title: String

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
            .padding(.top, UIStyle.pad(8))
            .padding(.bottom, 2)
    }
}

/// Sol sütun satırı: hap biçimli seçim zemini, üstüne gelince hafif ton
struct SidebarRow<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        let height: CGFloat = 32
        Button(action: action) {
            HStack(spacing: 9) { label() }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: min(UIStyle.small + 3, height / 2), style: .continuous)
                        .fill(selected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.05 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Sol sütunun kaydırılan içi: başlık ve satırlar, kenarlarda pay
struct SidebarScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }
}

// MARK: - Sayfa parçaları

/// Sekme başlığındaki simge: nötr renkte (sarı yalnız seçili şeyde)
struct SectionIcon: View {
    let symbol: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.78))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }
}

/// Sekmelerin üst başlığı: simge, ad, kısa açıklama, sağda anahtar ya da düğmeler
struct PageHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: UIStyle.pad(12)) {
            SectionIcon(symbol: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, UIStyle.pad(18))
        .padding(.vertical, UIStyle.pad(12))
    }
}

/// Renkli uyarı kutusu (izin, kapalı, çakışma)
struct SoftNotice: View {
    var icon = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var title: String?
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title).font(.headline).foregroundStyle(tint)
                }
                Text(text)
                    .font(title == nil ? .body : .callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(UIStyle.pad(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.tinted(tint))
    }
}

/// Liste: her satır ayrı yumuşak kart
struct CardStack<Content: View>: View {
    var spacing: CGFloat = 6
    /// Uzun listelerde satırlar ekrana yaklaştıkça kurulur (ör. 100 kopyalık pano)
    var lazy = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        if lazy {
            LazyVStack(spacing: UIStyle.pad(spacing)) { rows }
        } else {
            VStack(spacing: UIStyle.pad(spacing)) { rows }
        }
    }

    private var rows: some View {
        ForEach(subviews: content()) { row in
            row
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
        }
    }
}

/// Tuş çizimi ("⌘Q", "⇪"): çukur zeminde, çizgisiz; dinlerken vurgu tonunda
struct KeyCap: View {
    let text: String
    var listening = false

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, 6)
            .background(RoundedRectangle.small.fill(listening ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color.fieldFill)))
    }
}

/// Sayfadaki bölüm başlığı
struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title)).font(.headline)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, UIStyle.pad(6))
    }
}

/// Ekleme kartındaki adım numarası: yumuşak yuvarlak
struct StepNumber: View {
    let n: Int

    var body: some View {
        Text("\(n)")
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .frame(width: 22, height: 22)
            .background(Circle().fill(.tint.opacity(0.22)))
    }
}

/// Anlatım satırları: simge sabit genişlikte, yazılar aynı hizada
struct SoftListLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .foregroundStyle(.secondary)
                .frame(width: 20)
            configuration.title
        }
    }
}

private struct PageVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Sayfa şu an ekranda mı (sekmeler bellekte kaldığı için gizli sayfa da kurulu durur)
    var pageVisible: Bool {
        get { self[PageVisibleKey.self] }
        set { self[PageVisibleKey.self] = newValue }
    }
}

extension View {
    /// Sayfa ekrana gelince ve ekrandan gidince: gizli sekmede kalan sayfa için onAppear/onDisappear yetmez
    func onPageVisibility(show: @escaping () -> Void = {}, hide: @escaping () -> Void = {}) -> some View {
        modifier(PageVisibility(show: show, hide: hide))
    }
}

extension View {
    /// ↩ / Esc kısayolu yalnız sayfa ekrandayken çalışır (gizli sekmedeki düğmeye basılmasın)
    func pageShortcut(_ shortcut: KeyboardShortcut) -> some View {
        modifier(PageShortcut(shortcut: shortcut))
    }
}

private struct PageShortcut: ViewModifier {
    let shortcut: KeyboardShortcut
    @Environment(\.pageVisible) private var visible

    func body(content: Content) -> some View {
        content.keyboardShortcut(visible ? shortcut : nil)
    }
}

private struct PageVisibility: ViewModifier {
    let show: () -> Void
    let hide: () -> Void
    @Environment(\.pageVisible) private var visible

    func body(content: Content) -> some View {
        content
            .onAppear { if visible { show() } }
            .onDisappear { if visible { hide() } }
            .onChange(of: visible) { $1 ? show() : hide() }
    }
}
