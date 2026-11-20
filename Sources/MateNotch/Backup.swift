import AppKit

/// Ayarları dosyaya kaydet / dosyadan geri yükle (Ayarlar › Bakım).
enum SettingsBackup {
    private static var domain: String { Bundle.main.bundleIdentifier ?? "online.matestudios.matenotch" }
    private static let skip: Set<String> = ["lastSeenVersion"]

    static func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "MateNotch-ayarlar.plist"
        p.allowedContentTypes = [.propertyList]
        guard p.runModal() == .OK, let url = p.url else { return }
        let all = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let dict = all.filter { !skip.contains($0.key) }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: url)
        } catch { alert(L("Ayarlar kaydedilemedi"), error.localizedDescription) }
    }

    static func `import`() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.propertyList]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return }
        guard let data = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any], !dict.isEmpty else {
            alert(L("Dosya okunamadı"), L("Geçerli bir Mate Notch ayar dosyası seç.")); return
        }
        let d = UserDefaults.standard
        for (k, v) in dict where !skip.contains(k) { d.set(v, forKey: k) }
        d.synchronize()
        AppLanguage.relaunch()
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
