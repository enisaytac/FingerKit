import AppKit
import SwiftUI
import FingerKitCore
import UniformTypeIdentifiers

/// Sol sütun: "Her yerde" ve uygulamaya özel listeler
struct AppSidebar: View {
    @Environment(Engine.self) private var engine
    @Environment(UIState.self) private var ui

    var body: some View {
        SidebarScroll {
            SidebarHeader(title: String(localized: "Nerede"))
            ForEach(engine.settings.apps) { app in
                SidebarRow(selected: ui.selectedApp == app.bundleID) { ui.selectedApp = app.bundleID } label: {
                    AppIcon(profile: app)
                        .frame(width: 20, height: 20)
                    Text(app.title)
                        .lineLimit(1)
                    Spacer()
                    Text("\(app.bindings.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    if !app.isEverywhere {
                        Button(String(localized: "Listeden kaldır"), role: .destructive) {
                            if ui.selectedApp == app.bundleID { ui.selectedApp = AppProfile.everywhere }
                            engine.removeApp(app.bundleID)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AddAppMenu()
                .padding(12)
        }
    }
}

/// "Uygulama ekle": açık uygulamalardan seç ya da Uygulamalar klasöründen bul
private struct AddAppMenu: View {
    @Environment(Engine.self) private var engine
    @Environment(UIState.self) private var ui

    var body: some View {
        Menu {
            Section(String(localized: "Açık uygulamalar")) {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    Button {
                        if let url = app.bundleURL, let id = engine.addApp(at: url) { ui.selectedApp = id }
                    } label: {
                        Text(app.localizedName ?? "?")
                    }
                }
            }
            Divider()
            Button(String(localized: "Başka bir uygulama seç…")) { pickApp() }
        } label: {
            Label("Uygulama ekle", systemImage: "plus")
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runningApps: [NSRunningApplication] {
        let listed = Set(engine.settings.apps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { !listed.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Ekle"
        panel.message = String(localized: "Hareketlerini ayrı ayarlamak istediğin uygulamayı seç")
        guard panel.runModal() == .OK, let url = panel.url, let id = engine.addApp(at: url) else { return }
        ui.selectedApp = id
    }
}

/// Uygulamanın kendi simgesi; "Her yerde" için dünya simgesi
struct AppIcon: View {
    let profile: AppProfile

    var body: some View {
        if profile.isEverywhere {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.tint)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "app.dashed")
        }
    }
}
