import AppKit
import CryptoKit

/// GitHub Releases üzerinden otomatik güncelleme (Sparkle'sız, hafif).
/// Son sürümü denetler → DMG'yi indirir → SHA-256 + imza + paket kimliği doğrular → uygulama kapanınca yerini değiştirir ve yeniden açar.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    static let repo = "Farukzbek/Mate-Notch"

    @Published var status = "Henüz denetlenmedi"
    @Published var available: String?          // yeni sürüm etiketi (ör. "v1.1.0")
    @Published var busy = false

    private var dmgURL: URL?
    private var shaURL: URL?
    private var pageURL: URL?
    private var timer: Timer?
    private var installing = false

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    struct UpdateError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.autoCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in self?.autoCheck() }
        // Kurulum için uygun an (kayıt yok, notch kapalı) beklenirken her dakika yeniden dene
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tryAutoInstall() }
    }

    private func autoCheck() {
        if UserDefaults.standard.bool(forKey: Pref.autoUpdateCheck) { check(silent: true) }
    }

    // MARK: Denetim

    func check(silent: Bool = false) {
        guard !busy else { return }
        busy = true
        if !silent { status = "Denetleniyor…" }
        Task {
            let outcome = await Self.fetchLatest()
            await MainActor.run { self.finish(outcome, silent: silent) }
        }
    }

    private enum Outcome { case release(Release), none, failed(String) }

    private static func fetchLatest() async -> Outcome {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return .failed("Adres hatalı") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MateNotch-Updater", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { return .none }
            guard code == 200 else { return .failed("GitHub yanıtı: \(code)") }
            return .release(try JSONDecoder().decode(Release.self, from: data))
        } catch { return .failed("Denetlenemedi (internet?)") }
    }

    private func finish(_ outcome: Outcome, silent: Bool) {
        busy = false
        switch outcome {
        case .none:
            if !silent { status = "Henüz yayınlanmış sürüm yok" }
        case .failed(let m):
            if !silent { status = m }
        case .release(let r):
            guard Self.isNewer(r.tag_name, than: current),
                  let dmg = r.assets.first(where: { $0.name == "Mate-Notch.dmg" }),
                  let dmgURL = URL(string: dmg.browser_download_url) else {
                available = nil
                status = "Güncel (sürüm \(current))"
                return
            }
            self.dmgURL = dmgURL
            self.shaURL = r.assets.first(where: { $0.name == "Mate-Notch.dmg.sha256" }).flatMap { URL(string: $0.browser_download_url) }
            self.pageURL = URL(string: r.html_url)
            available = r.tag_name
            status = "Yeni sürüm \(r.tag_name) hazır"
            tryAutoInstall()
        }
    }

    static func isNewer(_ tag: String, than cur: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(tag), b = parts(cur)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Kurulum

    /// Kayıt yokken ve notch kapalıyken kendiliğinden kur (ayar açıksa).
    private func tryAutoInstall() {
        guard available != nil, !installing, UserDefaults.standard.bool(forKey: Pref.autoUpdateInstall),
              !CaptureService.shared.recording, !NotchState.shared.isOpen, !TimerService.shared.running else { return }
        install()
    }

    func install() {
        guard let dmg = dmgURL, !installing else { return }
        installing = true
        status = "İndiriliyor…"
        Task {
            do {
                try await Self.download(dmg, sha: shaURL, setStatus: { s in DispatchQueue.main.async { self.status = s } })
            } catch {
                await MainActor.run {
                    self.installing = false
                    self.status = "Güncelleme başarısız: \(error.localizedDescription)"
                    if let p = self.pageURL { NSWorkspace.shared.open(p) }   // elle indirme sayfası
                }
            }
        }
    }

    private static func download(_ dmgURL: URL, sha: URL?, setStatus: @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        let dest = Bundle.main.bundleURL
        guard dest.pathExtension == "app", fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            throw UpdateError(message: "Uygulama klasörüne yazılamıyor; indirme sayfası açılıyor")
        }
        let work = fm.temporaryDirectory.appendingPathComponent("MateNotchUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let (tmp, resp) = try await URLSession.shared.download(from: dmgURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message: "İndirme başarısız") }
        let dmg = work.appendingPathComponent("Mate-Notch.dmg")
        try fm.moveItem(at: tmp, to: dmg)

        setStatus("Doğrulanıyor…")
        if let sha {
            let (data, _) = try await URLSession.shared.data(from: sha)
            let expected = String(data: data, encoding: .utf8)?.split(whereSeparator: { $0.isWhitespace }).first.map { String($0).lowercased() }
            let actual = SHA256.hash(data: try Data(contentsOf: dmg, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { throw UpdateError(message: "Sağlama toplamı uyuşmuyor") }
        }

        let mnt = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mnt, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mnt.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mnt.path, "-force"]) }

        let newApp = work.appendingPathComponent("Mate Notch.app")
        try run("/usr/bin/ditto", [mnt.appendingPathComponent("Mate Notch.app").path, newApp.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError(message: "Paket kimliği uyuşmuyor")
        }

        // Uygulama kapanınca yerini değiştirip yeniden açan betik
        let script = work.appendingPathComponent("swap.sh")
        try """
        #!/bin/bash
        PID="$1"; NEW="$2"; DEST="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$DEST.old"
        if mv "$DEST" "$DEST.old" && ditto "$NEW" "$DEST"; then rm -rf "$DEST.old"; else rm -rf "$DEST"; mv "$DEST.old" "$DEST"; fi
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        rm -rf "\\(work.path)"
        """.write(to: script, atomically: true, encoding: .utf8)

        setStatus("Yeniden başlatılıyor…")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, dest.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw UpdateError(message: "\((path as NSString).lastPathComponent) hata verdi") }
        return text
    }
}
