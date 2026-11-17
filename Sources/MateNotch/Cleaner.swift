import AppKit
import SwiftUI

/// Önbellek temizleyici: yalnızca kullanıcının kendi klasörlerindeki yeniden oluşturulabilir dosyaları listeler.
/// Her öğe için neye ait olduğu, silinirse ne olacağı ve boyutu gösterilir; silmeden önce onay istenir.

enum CacheRisk { case safe, caution }

struct CacheItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String          // neye ait + silinirse ne olur
    let location: String        // kullanıcıya gösterilen yol
    let paths: [URL]            // İÇERİĞİ silinecek klasörler (klasörün kendisi kalır)
    var size: Int64
    let risk: CacheRisk
    let appPath: String?        // ikon için
    let symbol: String
    var selected: Bool
}

final class CacheCleaner: ObservableObject {
    static let shared = CacheCleaner()
    @Published var items: [CacheItem] = []
    @Published var scanning = false
    @Published var message = ""

    private let home = FileManager.default.homeDirectoryForCurrentUser

    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    // Güvenlik: yalnızca bu köklerin altı silinebilir
    private var allowedRoots: [String] {
        ["Library/Caches", "Library/Logs", "Library/Developer/Xcode/DerivedData",
         "Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/CoreSimulator/Caches", ".Trash"]
            .map { home.appendingPathComponent($0).standardizedFileURL.path }
    }

    func isAllowed(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return allowedRoots.contains { p == $0 || p.hasPrefix($0 + "/") }
    }

    // MARK: Tarama

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.buildItems()
            DispatchQueue.main.async { self.items = result; self.scanning = false }
        }
    }

    static func dirSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0) }
        }
        return total
    }

    private func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Bilinen önbellekler için açıklamalar; bilinmeyenler uygulama adıyla genel açıklama alır.
    private static let known: [String: (String, String, CacheRisk)] = [
        "com.apple.Safari": ("Safari web önbelleği", "Safari'nin sitelerden sakladığı görseller, betikler ve veriler. Silinirse siteler ilk açılışta biraz yavaş yüklenir. Oturumların, şifrelerin ve geçmişin silinmez.", .safe),
        "com.apple.dt.Xcode": ("Xcode önbelleği", "Xcode'un kod tamamlama ve dizin önbellekleri. Silinirse Xcode bir sonraki açılışta yeniden oluşturur.", .safe),
        "Homebrew": ("Homebrew indirme önbelleği", "Homebrew'un indirdiği paket dosyaları. Silinirse paketler gerektiğinde yeniden indirilir.", .safe),
        "org.swift.swiftpm": ("Swift Package Manager önbelleği", "Swift paketlerinin indirilen kaynakları. Silinirse projeler derlenirken yeniden indirilir.", .safe),
        "pip": ("Python (pip) paket önbelleği", "pip'in indirdiği Python paketleri. Silinirse yeniden indirilir.", .safe),
        "Google": ("Google Chrome ve Google uygulamaları önbelleği", "Chrome'un sitelerden sakladığı geçici dosyalar. Silinirse siteler ilk açılışta yavaş yüklenebilir; oturumların silinmez.", .safe),
        "com.spotify.client": ("Spotify önbelleği", "Spotify'ın şarkı ve görsel önbelleği. DİKKAT: İndirdiğin çevrimdışı şarkılar da burada duruyor olabilir, silinirse yeniden indirmen gerekir.", .caution),
        "CloudKit": ("iCloud (CloudKit) geçici verileri", "iCloud senkronizasyonunun geçici dosyaları. Silinirse gerektiğinde yeniden indirilir.", .safe),
        "com.microsoft.VSCode": ("Visual Studio Code önbelleği", "VS Code'un geçici önbellek dosyaları. Silinirse yeniden oluşturulur.", .safe),
        "com.google.Chrome": ("Google Chrome önbelleği", "Chrome'un sitelerden sakladığı geçici dosyalar. Silinirse siteler ilk açılışta yavaş yüklenebilir; oturumların silinmez.", .safe),
    ]
    private static let appleAllowed: Set<String> = ["com.apple.Safari", "com.apple.dt.Xcode"]

    private func buildItems() -> [CacheItem] {
        var out: [CacheItem] = []
        let ws = NSWorkspace.shared

        // 1) ~/Library/Caches altındaki uygulama önbellekleri
        let caches = home.appendingPathComponent("Library/Caches")
        var small: [(URL, Int64)] = []
        for url in children(caches) {
            let name = url.lastPathComponent
            if name.hasPrefix("com.apple.") && !Self.appleAllowed.contains(name) { continue }   // sistem servisleri: dokunma
            if name.hasPrefix(".") { continue }
            let size = Self.dirSize(url)
            guard size > 0 else { continue }
            if size < 20_000_000 { small.append((url, size)); continue }

            var title = name, detail = "", risk = CacheRisk.safe, appPath: String?
            if let k = Self.known[name] { (title, detail, risk) = k }
            if appPath == nil, name.contains("."), let app = ws.urlForApplication(withBundleIdentifier: name) {
                appPath = app.path
                let appName = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
                if detail.isEmpty {
                    title = "\(appName) önbelleği"
                    detail = "\(appName) uygulamasının geçici dosyaları (görseller, indirilen veriler). Silinirse uygulama gerektiğinde yeniden oluşturur; ilk açılış biraz yavaş olabilir."
                }
            }
            if detail.isEmpty {
                detail = "\"\(name)\" klasörü: bu ada ait uygulama/araç önbelleği (uygulama bulunamadı). Genellikle silinirse yeniden oluşturulur."
            }
            out.append(CacheItem(title: title, detail: detail, location: "~/Library/Caches/\(name)", paths: [url], size: size,
                                 risk: risk, appPath: appPath, symbol: "internaldrive", selected: risk == .safe))
        }
        if !small.isEmpty {
            out.append(CacheItem(title: "Diğer küçük önbellekler (\(small.count) klasör)",
                                 detail: "Her biri 20 MB'dan küçük, çeşitli uygulamaların geçici dosyaları. Uygulamalar gerektiğinde yeniden oluşturur.",
                                 location: "~/Library/Caches", paths: small.map { $0.0 }, size: small.reduce(0) { $0 + $1.1 },
                                 risk: .safe, appPath: nil, symbol: "tray.2", selected: true))
        }

        // 2) Diğer bilinen konumlar
        func add(_ title: String, _ detail: String, _ rel: String, risk: CacheRisk, selected: Bool, symbol: String) {
            let url = home.appendingPathComponent(rel)
            let size = Self.dirSize(url)
            guard size > 0 else { return }
            out.append(CacheItem(title: title, detail: detail, location: "~/" + rel, paths: [url], size: size,
                                 risk: risk, appPath: nil, symbol: symbol, selected: selected))
        }
        add("Uygulama günlükleri", "Uygulamaların ve sistemin tuttuğu günlük (log) dosyaları. Hata ayıklamaya yarar, silinmesi hiçbir şeyi bozmaz.",
            "Library/Logs", risk: .safe, selected: true, symbol: "doc.text")
        add("Xcode derleme çıktıları (DerivedData)", "Xcode projelerinin derleme ara dosyaları. Silinirse projeler bir sonraki derlemede baştan derlenir (ilk derleme uzun sürer).",
            "Library/Developer/Xcode/DerivedData", risk: .safe, selected: true, symbol: "hammer")
        add("Xcode simülatör önbelleği", "iOS simülatörlerinin geçici önbelleği. Silinirse simülatör gerektiğinde yeniden oluşturur.",
            "Library/Developer/CoreSimulator/Caches", risk: .safe, selected: true, symbol: "iphone")
        add("Xcode cihaz desteği (iOS DeviceSupport)", "Bağladığın iPhone/iPad için indirilen hata ayıklama dosyaları. Silinirse cihaz bağlandığında yeniden indirilir ve bu uzun sürebilir.",
            "Library/Developer/Xcode/iOS DeviceSupport", risk: .caution, selected: false, symbol: "cable.connector")
        add("Çöp Kutusu", "Çöpe attığın dosyalar. DİKKAT: Burası boşaltılırsa dosyalar kalıcı olarak silinir ve geri getirilemez.",
            ".Trash", risk: .caution, selected: false, symbol: "trash")

        out.sort { $0.size > $1.size }
        return out
    }

    // MARK: Silme

    func clean(onDone: @escaping (Int64, Int) -> Void) {
        let selected = items.filter(\.selected)
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0, failed = 0
            for item in selected {
                for root in item.paths where self.isAllowed(root) {
                    let r = self.wipe(root)
                    freed += r.0; failed += r.1
                }
            }
            DispatchQueue.main.async {
                onDone(freed, failed)
                self.scanning = false
                self.scan()
            }
        }
    }

    /// Klasörün İÇİNDEKİLERİ siler (klasörün kendisi kalır).
    private func wipe(_ root: URL) -> (Int64, Int) {
        let fm = FileManager.default
        var freed: Int64 = 0, failed = 0
        for child in children(root) {
            let size = Self.dirSize(child)
            do { try fm.removeItem(at: child); freed += size } catch { failed += 1 }
        }
        return (freed, failed)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Arayüz

struct CleanerView: View {
    @ObservedObject var cleaner = CacheCleaner.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Önbellek Temizleyici").font(.title2.bold())
                Text("Yalnızca kendi kullanıcı klasörlerindeki, silinirse yeniden oluşturulabilen dosyalar listelenir. Sistem dosyalarına ve belgelerine dokunulmaz. Hiçbir şey sen onaylamadan silinmez.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Divider()

            if cleaner.scanning && cleaner.items.isEmpty {
                VStack(spacing: 10) { ProgressView(); Text("Önbellekler taranıyor…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cleaner.items.isEmpty {
                Text("Temizlenecek önbellek bulunamadı 🎉").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($cleaner.items) { $item in
                            CacheRow(item: $item)
                            Divider()
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 10) {
                Button("Yeniden tara") { cleaner.scan() }.disabled(cleaner.scanning)
                Button(cleaner.items.allSatisfy(\.selected) ? "Hiçbirini seçme" : "Hepsini seç") {
                    let all = !cleaner.items.allSatisfy(\.selected)
                    for i in cleaner.items.indices { cleaner.items[i].selected = all }
                }.disabled(cleaner.items.isEmpty)
                if !cleaner.message.isEmpty { Text(cleaner.message).font(.caption).foregroundStyle(.green).lineLimit(2) }
                Spacer()
                Text("Toplam \(CacheCleaner.format(cleaner.totalSize)) · Seçili \(CacheCleaner.format(cleaner.selectedSize))")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                Button("Seçilenleri sil…") { confirmAndClean() }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(cleaner.selectedSize == 0 || cleaner.scanning)
            }
            .padding(12)
        }
        .frame(minWidth: 700, minHeight: 360)
        .onAppear { if cleaner.items.isEmpty { cleaner.scan() } }
    }

    func confirmAndClean() {
        let chosen = cleaner.items.filter(\.selected)
        guard !chosen.isEmpty else { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "\(chosen.count) öğe silinecek (\(CacheCleaner.format(cleaner.selectedSize)))"
        var lines = chosen.prefix(12).map { "• \($0.title) — \(CacheCleaner.format($0.size))" }
        if chosen.count > 12 { lines.append("… ve \(chosen.count - 12) öğe daha") }
        var info = lines.joined(separator: "\n") + "\n\nBu işlem geri alınamaz. Uygulamalar gerekli önbellek dosyalarını gerektiğinde yeniden oluşturur."
        if chosen.contains(where: { $0.risk == .caution }) {
            info += "\n\nDikkat: Seçtiklerin arasında silinmesi daha etkili olan öğeler var (çevrimdışı şarkılar, Çöp Kutusu vb.)."
        }
        a.informativeText = info
        a.addButton(withTitle: "Sil")
        a.addButton(withTitle: "Vazgeç")
        a.buttons[0].hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        cleaner.message = "Temizleniyor…"
        cleaner.clean { freed, failed in
            cleaner.message = "\(CacheCleaner.format(freed)) temizlendi" + (failed > 0 ? " · \(failed) dosya silinemedi (kullanımda veya izin yok)" : "")
        }
    }
}

struct CacheRow: View {
    @Binding var item: CacheItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $item.selected).labelsHidden().padding(.top, 2)
            icon.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 13, weight: .semibold))
                    if item.risk == .caution {
                        Text("Dikkat").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.orange.opacity(0.18)))
                    }
                }
                Text(item.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(item.location).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(CacheCleaner.format(item.size)).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { item.selected.toggle() }
    }

    @ViewBuilder var icon: some View {
        if let p = item.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable()
        } else {
            Image(systemName: item.symbol).font(.system(size: 18)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
        }
    }
}

enum CleanerWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: CleanerView()))
            w.title = "Önbellek Temizleyici"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w
        }
        let vis = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let h = max(380, min(640, vis.height - 120))
        window?.setFrame(NSRect(x: vis.midX - 370, y: vis.minY + (vis.height - h) / 2 - 20, width: 740, height: h), display: true)
        CacheCleaner.shared.scan()
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
