import AppKit
import EventKit
import Intents

/// `Mate Notch --selftest <dosya>`: alt sistemleri bir kez dener, sonucu dosyaya yazıp çıkar.
/// Sertleştirilmiş çalışma zamanı / imza değişikliğinin hiçbir özelliği bozmadığını doğrulamak ve destek için.
enum Diagnostics {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return }
        let path = args[i + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            var lines: [String] = []
            func rep(_ name: String, _ ok: Bool, _ detail: String) { lines.append("\(ok ? "OK  " : "YOK ") \(name): \(detail)") }

            rep("Ses (CoreAudio)", HUDService.readVolume(HUDService.defaultOutput()) != nil,
                HUDService.readVolume(HUDService.defaultOutput()).map { String(format: "%.0f%%", $0 * 100) } ?? "okunamadı")
            let b = HUDService.readBrightness()
            rep("Ekran parlaklığı (DisplayServices)", b != nil, b.map { String(format: "%.0f%%", $0 * 100) } ?? "okunamadı")
            let k = HUDService.shared.readKeyboard()
            rep("Klavye ışığı (CoreBrightness)", k != nil, k.map { String(format: "%.0f%%", $0 * 100) } ?? "okunamadı / yok")
            rep("Mac pili (IOKit)", true, "%\(BatteryService.shared.level)")
            rep("Kamera / mikrofon durumu", true, "kamera=\(PrivacyService.cameraRunning()) mikrofon=\(PrivacyService.micRunning())")
            rep("Takvim", CalendarService.authorized, CalendarService.authorized ? "izin var, \(CalendarService.shared.events.count) etkinlik" : "izin yok")
            rep("Odak durumu API'si", true, "izin durumu=\(INFocusStatusCenter.default.authorizationStatus.rawValue)")
            let m = MediaService.shared
            rep("Müzik (AppleScript)", m.track != nil, m.track.map { "\($0.title) — \($0.artist) [\($0.player)]" } ?? "çalan şarkı okunamadı (Spotify/Müzik kapalı ya da izin yok)")

            let group = DispatchGroup()
            group.enter()
            DeviceBatteryService.shared.refresh { list in
                rep("Bluetooth pilleri", true, list.isEmpty ? "bağlı cihaz yok" : list.map { "\($0.name)=\($0.percent.map { "%\($0)" } ?? "?")" }.joined(separator: ", "))
                group.leave()
            }
            group.enter()
            URLSession.shared.dataTask(with: URL(string: "https://api.github.com/repos/Farukzbek/Mate-Notch/releases/latest")!) { data, resp, _ in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                rep("Ağ (GitHub API)", code == 200, "HTTP \(code)")
                group.leave()
            }.resume()
            group.notify(queue: .main) {
                let sign = Bundle.main.bundleURL.path
                lines.insert("Mate Notch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") — \(sign)", at: 0)
                try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
    }
}
