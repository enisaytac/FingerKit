import SwiftUI
import FingerKitCore

/// Sağ sütun: canlı trackpad, tanınan hareket, hareket ekleme adımları
struct LivePanel: View {
    @Environment(Engine.self) private var engine
    @Environment(UIState.self) private var ui

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !engine.isTrusted { PermissionCard() }
                if !engine.trackpadFound {
                    SoftNotice(title: String(localized: "Trackpad bulunamadı"),
                           text: String(localized: "Dokunma verisi alınamıyor. FingerKit'i kapatıp yeniden aç."))
                }

                Text("Canlı trackpad")
                    .font(.headline)
                TrackpadCanvas(touches: engine.liveTouches, aspect: engine.liveAspect)
                RecognizedBadge()

                if let flow = ui.adding {
                    AddCard(flow: flow)
                } else {
                    Text("Trackpad'de bir hareket yap; FingerKit tanıdığını burada gösterir. Bu pencere öndeyken kısayol gönderilmez, yalnız gösterilir.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(UIStyle.pad(20))
        }
        .onPageVisibility(show: { engine.liveViewVisible = true }, hide: { engine.liveViewVisible = false })
    }
}

/// Trackpad'in büyük çizimi; değen parmaklar nokta olarak görünür
struct TrackpadCanvas: View {
    let touches: [Touch]
    let aspect: Double

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let pad = RoundedRectangle(cornerRadius: UIStyle.card, style: .continuous).path(in: rect.insetBy(dx: 1, dy: 1))
            ctx.fill(pad, with: .color(Color.card))
            ctx.fill(pad, with: .color(.primary.opacity(0.03)))
            for t in touches where (1...5).contains(t.state) {
                let center = CGPoint(x: t.x * size.width, y: (1 - t.y) * size.height)
                let r = max(10, min(24, 10 + t.size * 6))
                let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                // Önizlemelerdeki parmaklarla aynı altın sarısı
                if t.isDown {
                    ctx.fill(dot, with: .linearGradient(Gradient(colors: [.fingerGoldLight, .fingerGold, .fingerGoldDeep]),
                                                        startPoint: CGPoint(x: center.x, y: center.y - r),
                                                        endPoint: CGPoint(x: center.x, y: center.y + r)))
                    ctx.stroke(dot, with: .color(.fingerGoldDeep.opacity(0.6)), lineWidth: 1)
                } else {
                    ctx.fill(dot, with: .color(.fingerGold.opacity(0.3)))
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .surface()
        .overlay(alignment: .bottomTrailing) {
            let count = touches.filter(\.isDown).count
            if count > 0 {
                Text("\(count) parmak")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(UIStyle.pad(10))
            }
        }
    }
}

/// Son tanınan hareketin adı; kısa süre parlar
private struct RecognizedBadge: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 10) {
            if let g = engine.highlighted {
                GestureGlyph(gesture: g)
                    .frame(width: 40, height: 28)
                Text(g.name)
                    .font(.title3.weight(.semibold))
            } else {
                Text("Hareket bekleniyor…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Capsule().fill(engine.highlighted == nil ? AnyShapeStyle(Color.fieldFill) : AnyShapeStyle(.tint.opacity(0.18))))
        .animation(.easeOut(duration: 0.25), value: engine.highlightCount)
    }
}

/// Yeni hareket ekleme ya da düzenleme: 1) hareketi yap ya da listeden seç  2) kısayolu bas  3) kaydet.
/// Çakışma varsa kartta sarı uyarı görünür, kaydederken bir kez daha sorulur.
private struct AddCard: View {
    @Environment(Engine.self) private var engine
    @Environment(UIState.self) private var ui
    let flow: AddFlow
    @State private var confirming = false

    private var appName: String {
        engine.settings.apps.first { $0.bundleID == flow.appID }?.name ?? ""
    }

    private var conflicts: [Conflict] {
        guard let g = flow.gesture else { return [] }
        return engine.conflicts(g, flow.shortcut, in: flow.appID, editing: flow.editing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(flow.editing == nil ? "Yeni hareket" : "Düzenle") · \(appName)")
                .font(.headline)

            step(1, done: flow.gesture != nil) {
                if let g = flow.gesture {
                    HStack(spacing: 8) {
                        GestureGlyph(gesture: g).frame(width: 40, height: 28)
                        Text(g.name).fontWeight(.medium)
                        Spacer()
                        Button("Yeniden yap") { setGesture(nil) }
                            .buttonStyle(.softLink)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Hareketi trackpad'de yap")
                        }
                        GesturePicker { setGesture($0) }
                    }
                }
            }

            step(2, done: flow.shortcut != nil) {
                if flow.gesture == nil {
                    Text("Kısayolu bas").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if let task = flow.task {
                            HStack {
                                TaskChip(task: task)
                                Spacer()
                                Button(String(localized: "Kısayol bas")) { ui.adding?.task = nil; ui.adding?.shortcut = nil }
                                    .buttonStyle(.softLink)
                            }
                        } else {
                            HStack {
                                Text("Kısayolu bas")
                                Spacer()
                                ShortcutField(shortcut: Binding(
                                    get: { ui.adding?.shortcut },
                                    set: { ui.adding?.shortcut = $0; ui.adding?.task = nil }
                                ), autoStart: flow.shortcut == nil)
                            }
                            MousePicker { ui.adding?.shortcut = $0; ui.adding?.task = nil }
                        }
                        HStack(spacing: 6) {
                            Text(String(localized: "ya da"))
                                .foregroundStyle(.secondary)
                            TaskPicker { task in
                                ui.adding?.task = task
                                ui.adding?.shortcut = task.keys ?? .none
                            }
                        }
                    }
                }
            }

            ForEach(conflicts, id: \.self) { c in
                Label(c.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Vazgeç") { finish() }
                    .pageShortcut(.cancelAction)
                Spacer()
                Button(flow.editing == nil ? "Ekle" : "Kaydet") {
                    if conflicts.isEmpty { save() } else { confirming = true }
                }
                .buttonStyle(.softPrimary)
                .pageShortcut(.defaultAction)
                .disabled(flow.gesture == nil || flow.shortcut == nil)
            }
        }
        .padding(UIStyle.pad(16))
        .surface(.raised)
        .alert("Bu hareket başka bir şeyle çakışıyor", isPresented: $confirming) {
            Button("Yine de kaydet") { save() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(conflicts.map(\.message).joined(separator: "\n\n"))
        }
        .onPageVisibility(show: { listenIfNeeded() }, hide: { engine.recording = nil })
        .onChange(of: flow.gesture) { listenIfNeeded() }
    }

    private func step<Content: View>(_ n: Int, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .foregroundStyle(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                .font(.title3)
            content()
        }
    }

    private func setGesture(_ g: Gesture?) {
        ui.adding?.gesture = g
    }

    /// Hareket henüz seçilmediyse trackpad'deki bir sonraki hareket kaydedilir
    private func listenIfNeeded() {
        if flow.gesture == nil {
            engine.recording = { g in ui.adding?.gesture = g }
        } else {
            engine.recording = nil
        }
    }

    private func save() {
        guard let g = flow.gesture, let s = flow.shortcut else { return }
        if let id = flow.editing {
            engine.updateBinding(id, g, s, task: flow.task, in: flow.appID)
        } else {
            engine.setBinding(g, s, task: flow.task, in: flow.appID)
        }
        finish()
    }

    private func finish() {
        engine.recording = nil
        ui.adding = nil
    }
}

/// Hareketi trackpad'de yapmak yerine listeden seçmek için
private struct GesturePicker: View {
    let onPick: (Gesture) -> Void

    var body: some View {
        Menu("ya da listeden seç") {
            ForEach(Gesture.Group.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(Gesture.allCases.filter { $0.group == group }) { g in
                        Button(g.name) { onPick(g) }
                    }
                }
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}

/// Tuş yerine fare tıklaması seçmek için (trackpad'de orta tık olmadığından)
private struct MousePicker: View {
    let onPick: (Shortcut) -> Void

    private let choices: [Shortcut] = [
        Shortcut(mouse: .middle),
        Shortcut(mouse: .left, modifiers: [.command]),
        Shortcut(mouse: .left, modifiers: [.shift, .command]),
        Shortcut(mouse: .left, modifiers: [.option]),
        Shortcut(mouse: .right),
    ]

    var body: some View {
        Menu("ya da fare tıklaması seç") {
            ForEach(choices, id: \.self) { s in
                Button("\(s.display)  (\(s.spoken))") { onPick(s) }
            }
        }
        .controlSize(.small)
        .fixedSize()
        .help("Tıklama, imlecin o an olduğu yere yapılır")
    }
}

/// Erişilebilirlik izni yokken görünen uyarı
private struct PermissionCard: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("İzin gerekli", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Kısayol gönderebilmek için FingerKit'e Erişilebilirlik izni ver: açılan ayar penceresinde listede “FingerKit”in yanındaki düğmeyi aç. İzin gelince bu kutu kendiliğinden kaybolur.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("İzin ayarlarını aç") { engine.openAccessibilitySettings() }
                .buttonStyle(.softPrimary)
        }
        .padding(UIStyle.pad(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.tinted(.orange))
    }
}
