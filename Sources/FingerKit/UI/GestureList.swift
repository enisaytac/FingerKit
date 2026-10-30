import SwiftUI
import FingerKitCore

/// Orta sütun: seçili uygulamanın hareketleri
struct GestureList: View {
    @Environment(Engine.self) private var engine
    @Environment(UIState.self) private var ui

    private var appID: String { ui.selectedApp ?? AppProfile.everywhere }

    var body: some View {
        if let a = engine.profileIndex(appID) {
            let profile = engine.settings.apps[a]
            VStack(spacing: 0) {
                header(profile)
                CommunitySection(page: .gestures)
                list(profile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView(String(localized: "Soldan bir liste seç"), systemImage: "sidebar.left")
        }
    }

    private func header(_ profile: AppProfile) -> some View {
        HStack(spacing: 10) {
            AppIcon(profile: profile)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.title)
                    .font(.title3.weight(.semibold))
                Text(profile.isEverywhere
                     ? String(localized: "Tüm uygulamalarda geçerli")
                     : String(localized: "Yalnız \(profile.title) öndeyken; burada olmayanlar için “Her yerde” geçerli"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            SearchField(text: Bindable(ui).search)
            Button {
                ui.adding = AddFlow(appID: profile.bundleID)
            } label: {
                Label("Hareket ekle", systemImage: "plus")
            }
            .buttonStyle(.softPrimary)
            .disabled(ui.adding != nil)
        }
        .padding(.horizontal, UIStyle.pad(18))
        .padding(.vertical, UIStyle.pad(12))
    }

    @ViewBuilder
    private func list(_ profile: AppProfile) -> some View {
        let rows = filtered(profile.bindings)
        if profile.bindings.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "Henüz hareket yok"), systemImage: "hand.tap")
            } description: {
                Text(String(localized: "“Hareket ekle”ye bas, sağdaki trackpad alanı seni yönlendirecek.") + "\n" + String(localized: "Ya da yukarıdaki “Topluluğun sevdiği ayarlar”dan birini tek tıkla ekle."))
            }
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: ui.search)
        } else {
            // Her satır ayrı yumuşak kart
            ScrollView {
                LazyVStack(spacing: UIStyle.pad(6)) {
                    ForEach(rows) { binding in
                        GestureRow(binding: binding, appID: profile.bundleID)
                            .padding(.horizontal, UIStyle.pad(12))
                            .padding(.vertical, UIStyle.pad(7))
                            .surface()
                    }
                }
                .padding(UIStyle.pad(18))
            }
        }
    }

    private func filtered(_ bindings: [GestureBinding]) -> [GestureBinding] {
        let q = ui.search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return bindings }
        return bindings.filter {
            $0.gesture.name.localizedCaseInsensitiveContains(q)
                || $0.display.localizedCaseInsensitiveContains(q)
                || $0.shortcut.spoken.localizedCaseInsensitiveContains(q)
        }
    }
}

/// Tek satır: çizim, ad, uyarı, kısayol, aç/kapa, sil. Satıra tıklayınca sağda düzenleme açılır.
struct GestureRow: View {
    @Environment(Engine.self) private var engine
    @Environment(UIState.self) private var ui
    let binding: GestureBinding
    let appID: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            GestureGlyph(gesture: binding.gesture)
                .frame(width: 46, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.gesture.name)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(binding.gesture.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Dar sütunda ad harf harf kırılmasın: önce bu alan yer alır, sağdakiler sıkışmaz
            .frame(minWidth: 120, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            let conflicts = engine.conflicts(binding.gesture, binding.shortcut, in: appID, editing: binding.id)
            if !conflicts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(conflicts.map(\.message).joined(separator: "\n"))
            }
            if let task = binding.task {
                TaskChip(task: task)
                    .onTapGesture { edit() }
            } else {
                ShortcutField(shortcut: Binding(
                    get: { binding.shortcut },
                    set: { if let s = $0 { update { $0.shortcut = s; $0.task = nil } } }
                ))
            }
            Toggle("", isOn: Binding(
                get: { binding.enabled },
                set: { on in update { $0.enabled = on } }
            ))
            .toggleStyle(.softSmall)
            .labelsHidden()
            .help(binding.enabled ? String(localized: "Açık") : String(localized: "Kapalı"))
            Button {
                engine.removeBinding(binding.id, in: appID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.softQuiet)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            .help("Sil")
        }
        .padding(.vertical, 4)
        .opacity(binding.enabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .background(
            RoundedRectangle.card
                .fill(.tint.opacity(editing ? 0.14 : engine.highlighted == binding.gesture ? 0.2 : 0))
                .padding(.horizontal, -UIStyle.pad(12))
                .padding(.vertical, -UIStyle.pad(7))
                .animation(.easeOut(duration: 0.3), value: engine.highlighted)
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button(String(localized: "Düzenle")) { edit() }
            Button("Sil", role: .destructive) { engine.removeBinding(binding.id, in: appID) }
        }
    }

    private var editing: Bool { ui.adding?.editing == binding.id }

    private func edit() {
        ui.adding = AddFlow(appID: appID, gesture: binding.gesture, shortcut: binding.shortcut, task: binding.task, editing: binding.id)
    }

    private func update(_ change: (inout GestureBinding) -> Void) {
        guard let a = engine.profileIndex(appID),
              let b = engine.settings.apps[a].bindings.firstIndex(where: { $0.id == binding.id }) else { return }
        change(&engine.settings.apps[a].bindings[b])
    }
}

/// Hareket listesindeki küçük arama kutusu (üst çubukta değil; sekme değişince çubuk kaymasın diye)
private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Hareket ya da kısayol ara"), text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(SoftFieldModifier(focused: focused))
        .frame(width: 210)
    }
}
