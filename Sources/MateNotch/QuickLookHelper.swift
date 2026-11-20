import AppKit

enum QuickLook {
    /// Dosyayı Hızlı Bakış (qlmanage) ile açar; Boşluk/Esc ile kapanır.
    static func preview(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", url.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.activate(ignoringOtherApps: true) }
    }
}
