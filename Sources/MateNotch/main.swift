import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var updateItem: NSMenuItem!
    var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        Self.installMainMenu()
        NotchController.shared.setup()
        MediaService.shared.start()
        BatteryService.shared.start()
        ClipboardService.shared.start()
        CalendarService.shared.start()
        LyricsService.shared.start()
        UpdateService.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuIcon()
        let menu = NSMenu()
        menu.addItem(withTitle: "Aç / Kapat", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Önbellek Temizleyici…", action: #selector(cleaner), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ayarlar…", action: #selector(settings), keyEquivalent: ",").target = self
        updateItem = menu.addItem(withTitle: "Güncelle", action: #selector(installUpdate), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        UpdateService.shared.$available.receive(on: DispatchQueue.main).sink { [weak self] v in
            self?.updateItem.isHidden = (v == nil)
            if let v { self?.updateItem.title = "Güncelle: \(v) · yeniden başlat" }
        }.store(in: &bag)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Mate Notch'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// Menü çubuğunda görünmeyen ama klavye kısayollarını (⌘C/⌘V/⌘X/⌘A/⌘Z) yazı alanlarına ileten ana menü.
    static func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Mate Notch'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    /// Gülen yüzlü kapsül: Mate yazılımı olduğu belli olsun. Template olduğu için açık/koyu menü çubuğuna uyar.
    static func menuIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 0.5, width: 12, height: 17), xRadius: 6, yRadius: 6).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 5.9, y: 10.2, width: 2, height: 2.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.1, y: 10.2, width: 2, height: 2.6)).fill()
            let smile = NSBezierPath()
            smile.lineWidth = 1.4
            smile.lineCapStyle = .round
            smile.move(to: NSPoint(x: 5.8, y: 7.4))
            smile.curve(to: NSPoint(x: 12.2, y: 7.4), controlPoint1: NSPoint(x: 7.0, y: 3.8), controlPoint2: NSPoint(x: 11.0, y: 3.8))
            smile.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc func toggle() { NotchController.shared.toggle() }
    @objc func installUpdate() { UpdateService.shared.install() }
    @objc func cleaner() { CleanerWindow.show() }
    @objc func settings() { SettingsWindow.show() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
