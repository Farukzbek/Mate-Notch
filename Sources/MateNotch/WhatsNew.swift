import AppKit
import SwiftUI

// MARK: - Yenilikler: güncellemeden sonra (ve menüden) bu sürümün GitHub sürüm notları

enum WhatsNew {
    private static let seenKey = "lastSeenVersion"
    private static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Açılışta: sürüm değiştiyse notları göster. İlk kurulumda (kayıtlı sürüm yok) göstermez, yalnızca sürümü kaydeder.
    static func showIfUpdated() {
        let d = UserDefaults.standard
        let seen = d.string(forKey: seenKey)
        d.set(current, forKey: seenKey)
        guard let seen, seen != current else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { show() }
    }

    static func show() {
        let version = current
        Task {
            let notes = await fetchNotes(version)
            await MainActor.run { WhatsNewWindow.present(version: version, notes: notes) }
        }
    }

    private static func fetchNotes(_ v: String) async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(UpdateService.repo)/releases/tags/v\(v)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MateNotch-Updater", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = obj["body"] as? String, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return body
    }
}

struct WhatsNewView: View {
    let version: String
    let notes: String?
    let onClose: () -> Void

    private var rendered: AttributedString {
        guard let notes else { return AttributedString(L("Bu sürümün notlarına şu an ulaşılamadı. Notlar GitHub'daki sürüm sayfasında.")) }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: notes, options: opts)) ?? AttributedString(notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yenilikler").font(.title3.weight(.semibold))
                    Text("Mate Notch \(version)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            Divider()
            ScrollView {
                Text(rendered).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .textSelection(.enabled)
            }
            Divider()
            HStack {
                Button("GitHub'da aç") {
                    if let u = URL(string: "https://github.com/\(UpdateService.repo)/releases/tag/v\(version)") { NSWorkspace.shared.open(u) }
                }
                Spacer()
                Button("Tamam") { onClose() }.keyboardShortcut(.defaultAction)
            }.padding(14)
        }
        .frame(width: 480, height: 420)
    }
}

enum WhatsNewWindow {
    private static var window: NSWindow?
    static func present(version: String, notes: String?) {
        let w = NSWindow(contentViewController: NSHostingController(rootView: WhatsNewView(version: version, notes: notes) { window?.close() }))
        w.title = L("Yenilikler")
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        window?.close()
        window = w
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
