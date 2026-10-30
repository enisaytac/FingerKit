import AppKit
import SwiftUI
import FingerKitCore

/// "Hazır iş" düğmesi: hareket, Hyper Key, daire menü ve uygulama kısayolları aynı listeyi gösterir.
/// Her işin yanında karşılığı olan kısayol yazar ("Pencereyi küçült · ⌘M").
struct TaskPicker: View {
    var title = String(localized: "Hazır iş")
    let pick: (ReadyTask) -> Void
    @State private var shortcuts: [String]?

    var body: some View {
        Menu {
            TaskMenuItems(shortcuts: shortcuts, pick: pick)
        } label: {
            Label(title, systemImage: "wand.and.stars")
        }
        .fixedSize()
        .help(String(localized: "Kısayol yerine hazır bir iş seç: uygulama aç, site aç, Kestirme, ses…"))
        .onAppear { if shortcuts == nil { Shortcuts.list { shortcuts = $0 } } }
    }
}

/// Menünün içi: gruplar, uygulama aç, site aç, Kestirmeler. Başka menülerin (daire yuvası) içine de konur.
struct TaskMenuItems: View {
    /// Mac'teki kestirmeler (nil: okunuyor)
    let shortcuts: [String]?
    let pick: (ReadyTask) -> Void

    var body: some View {
        ForEach(ReadyTask.Group.allCases, id: \.self) { group in
            Menu(group.title) {
                ForEach(group.tasks, id: \.self) { task in
                    Button { pick(task) } label: { Label(task.label, systemImage: task.symbol) }
                }
            }
        }
        Divider()
        Button { if let task = TaskPrompts.app() { pick(task) } } label: {
            Label(String(localized: "Uygulama aç…"), systemImage: "app.badge")
        }
        Button { if let task = TaskPrompts.site() { pick(task) } } label: {
            Label(String(localized: "Site aç…"), systemImage: "safari")
        }
        Menu(String(localized: "Kestirme çalıştır")) {
            if let shortcuts, !shortcuts.isEmpty {
                ForEach(shortcuts, id: \.self) { name in
                    Button(name) { pick(.runShortcut(name)) }
                }
            } else {
                Text(shortcuts == nil ? String(localized: "Kestirmeler okunuyor…") : String(localized: "Mac'te kestirme yok; Kestirmeler uygulamasında oluştur"))
            }
        }
    }
}

/// Ek bilgi isteyen işler: uygulama seçme ve adres yazma pencereleri
enum TaskPrompts {
    static func app() -> ReadyTask? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.message = String(localized: "Açılacak uygulamayı seç")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return .openApp(bundleID: id, name: name)
    }

    static func site() -> ReadyTask? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Hangi site açılsın?")
        alert.informativeText = String(localized: "Adresi yaz (ör. youtube.com). Varsayılan tarayıcında açılır.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "example.com"
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Tamam"))
        alert.addButton(withTitle: String(localized: "Vazgeç"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let url = ReadyTask.normalizedURL(field.stringValue) else { return nil }
        return .openURL(url)
    }
}

/// Satırda seçili hazır iş: simge ve ad (kısayolu varsa yanında)
struct TaskChip: View {
    let task: ReadyTask

    var body: some View {
        Label(task.label, systemImage: task.symbol)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .frame(minHeight: UIStyle.control - 4)
            .background(Capsule().fill(.tint.opacity(0.16)))
    }
}
