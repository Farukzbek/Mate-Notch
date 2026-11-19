import AppKit

/// Ekran görüntüsü / video kaydı. Sistemin `screencapture` aracını kullanır.
final class CaptureService: ObservableObject {
    static let shared = CaptureService()
    @Published var recording = false
    private var proc: Process?

    static func icon(_ mode: String, recording: Bool) -> String {
        if recording { return "stop.circle.fill" }
        switch mode {
        case "full": return "macwindow"
        case "video": return "record.circle"
        case "tool": return "camera.aperture"
        default: return "viewfinder.rectangular"
        }
    }

    static func label(_ mode: String, recording: Bool) -> String {
        if recording { return L("Kaydı durdur") }
        switch mode {
        case "full": return L("Tam ekran görüntüsü")
        case "video": return L("Video kaydı")
        case "tool": return L("Çekim aracı")
        default: return L("Alan seç")
        }
    }

    func run() {
        if recording { proc?.interrupt(); return }   // SIGINT: kaydı düzgünce bitirir
        let mode = UserDefaults.standard.string(forKey: Pref.captureMode) ?? "area"
        NotchController.shared.close()               // notch görüntüye girmesin
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.exec(mode) }
    }

    private func path(_ ext: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return NSHomeDirectory() + "/Desktop/Mate Notch \(f.string(from: Date())).\(ext)"
    }

    private func exec(_ mode: String) {
        let clip = UserDefaults.standard.bool(forKey: Pref.captureClipboard)
        let dest = clip ? ["-c"] : [path("png")]
        let args: [String]
        switch mode {
        case "full": args = ["-x"] + dest
        case "video": args = ["-v", path("mov")]
        case "tool": args = ["-U"]
        default: args = ["-i"] + dest
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args
        if mode == "video" {
            p.terminationHandler = { _ in DispatchQueue.main.async { self.recording = false; self.proc = nil } }
        }
        do {
            try p.run()
            if mode == "video" { proc = p; recording = true }
        } catch { NSSound.beep() }
    }
}
