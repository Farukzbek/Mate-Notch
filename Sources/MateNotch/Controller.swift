import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import ServiceManagement
import EventKit

typealias EKEventAlias = EKEvent

extension Notification.Name { static let mouseTick = Notification.Name("matenotch.mouseTick") }

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchController {
    static let shared = NotchController()
    let state = NotchState.shared
    private var panel: NotchPanel!
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    func setup() {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: RootView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        host.sizingOptions = []
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()

        state.$isOpen.removeDuplicates().sink { [weak self] open in
            self?.panel.ignoresMouseEvents = !open
        }.store(in: &bag)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.state.geometry = NotchGeometry.current()
            self?.reposition()
        }
        NotificationCenter.default.addObserver(forName: .timerFinished, object: nil, queue: .main) { [weak self] _ in
            self?.state.tab = .timer
            self?.open()
        }

        if let t = ProcessInfo.processInfo.environment["MATENOTCH_AI_TEST"] {
            Task {
                var out = "provider: \(AIService.shared.active().rawValue)\n"
                for action in [AIAction.summarize, .toEN, .fix] {
                    do { let r = try await AIService.shared.complete(system: action.system, prompt: t); out += "[\(action.rawValue)] \(r.text)\n" }
                    catch { out += "[\(action.rawValue)] HATA: \(error.localizedDescription)\n" }
                }
                try? out.write(toFile: "/tmp/matenotch_ai.txt", atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.environment["MATENOTCH_CLEANER"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { CleanerWindow.show() }
        }
        if let f = ProcessInfo.processInfo.environment["MATENOTCH_AIRDROP_TEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                AirDrop.send(providers: [NSItemProvider(contentsOf: URL(fileURLWithPath: f))!])
            }
        }
        if ProcessInfo.processInfo.environment["MATENOTCH_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let t = ProcessInfo.processInfo.environment["MATENOTCH_TAB"], let tab = Tab(rawValue: t) { NotchController.shared.state.tab = tab }
                NotchController.shared.state.pinned = true; NotchController.shared.open()
            }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
        installMonitors()
        startDragWatcher()
        HotKey.register(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
    }

    /// Panel, açık notch'a sığacak kadar büyük (gölge payıyla). Şeffaf alan başka pencerelerin tıklamasını engellemesin.
    var panelSize: NSSize {
        let sc = max(0.8, min(1.3, CGFloat(UserDefaults.standard.double(forKey: Pref.uiScale))))
        let g = state.geometry
        return NSSize(width: Layout.openW * sc + 90, height: g.notchHeight + Layout.bodyH * sc + 70)
    }

    private func reposition() {
        let g = state.geometry
        let size = panelSize
        let frame = NSRect(x: g.screenFrame.midX - size.width / 2, y: g.screenFrame.maxY - size.height,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    // MARK: Rects (screen coordinates, origin bottom-left)

    private var hotRect: NSRect {
        let g = state.geometry
        let extra: CGFloat = state.pillVisible ? Layout.pillExtra : 0   // satır sayısına göre
        let w = max(g.notchWidth + Layout.sideW * 2, state.pillVisible ? Layout.pillMinW : 0)
        let pad = CGFloat(UserDefaults.standard.double(forKey: Pref.hotPadding))   // açılma alanı genişletme
        let exW = CGFloat(UserDefaults.standard.double(forKey: Pref.collapsedExtraW))
        let exH = CGFloat(UserDefaults.standard.double(forKey: Pref.collapsedExtraH))
        let ew = max(exW, g.notchWidth - w)      // açılma alanı fiziksel notch'tan küçülmesin
        let eh = max(exH, 0)
        return NSRect(x: g.screenFrame.midX - (w + ew) / 2 - pad, y: g.screenFrame.maxY - g.notchHeight - eh - 2 - extra - pad,
                      width: w + ew + 2 * pad, height: g.notchHeight + eh + 12 + extra + pad)
    }
    private var openRect: NSRect {
        let g = state.geometry
        let sc = CGFloat(UserDefaults.standard.double(forKey: Pref.uiScale))
        let h = g.notchHeight + Layout.bodyH * sc + 24
        let w = Layout.openW * sc
        return NSRect(x: g.screenFrame.midX - w / 2 - 16, y: g.screenFrame.maxY - h,
                      width: w + 32, height: h + 12)
    }

    // MARK: Açılma alanı önizlemesi (Ayarlar'da kaydırıcıyı oynatırken)

    private var hotPanel: NSPanel?
    private var hotHideWork: DispatchWorkItem?
    private var hotEditing = false

    /// `editing`: kaydırıcı sürükleniyor. Değer değişince alanı göster/güncelle; bırakınca solarak kapat.
    func hotPreview(editing: Bool?) {
        if let e = editing { hotEditing = e }
        hotHideWork?.cancel()
        let rect = hotRect.intersection(state.geometry.screenFrame)
        if hotPanel == nil {
            let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let v = NSView(); v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.38).cgColor
            v.layer?.cornerRadius = 12
            v.layer?.borderWidth = 1
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
            p.contentView = v
            p.alphaValue = 0
            hotPanel = p
        }
        hotPanel?.setFrame(rect, display: true)
        hotPanel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; hotPanel?.animator().alphaValue = 1 }
        if !hotEditing {
            let w = DispatchWorkItem { [weak self] in self?.hideHotPreview() }
            hotHideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + (editing == false ? 0.35 : 1.0), execute: w)
        }
    }

    private func hideHotPreview() {
        guard let p = hotPanel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) {
            if p.alphaValue == 0 { p.orderOut(nil) }
        }
    }

    /// Kapalı notch boyutu ayarlanırken: kaydırırken notch kapalı hâlde gösterilir, bırakınca ayar önizlemesi için yeniden açılır.
    func previewCollapsed(editing: Bool) {
        if editing { close() }
        else if state.previewHold { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.open() } }
    }

    // MARK: Open / close

    func toggle() { state.isOpen ? close() : open() }

    func open() {
        openWork?.cancel(); closeWork?.cancel()
        guard !state.isOpen else { return }
        if UserDefaults.standard.bool(forKey: Pref.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if state.tab == .stats || state.tab == .timer { /* keep */ }
        state.isOpen = true
    }

    func close() {
        openWork?.cancel(); closeWork?.cancel()
        guard state.isOpen else { return }
        state.isOpen = false
    }

    // MARK: Dosya sürükleme algılama
    // Başka bir uygulamadan (Finder) dosya sürüklenirken macOS fare olaylarını global izleyicilere göndermez.
    // Bu yüzden fare düğmesi basılıyken sürükleme panosunu yoklarız.

    private var dragTimer: Timer?
    private var dragCount = NSPasteboard(name: .drag).changeCount
    private var dragActive = false

    private func startDragWatcher() {
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.pollDrag() }
        RunLoop.main.add(t, forMode: .common)
        dragTimer = t
    }

    private func pollDrag() {
        let pb = NSPasteboard(name: .drag)
        guard NSEvent.pressedMouseButtons & 1 != 0 else {          // sol tuş bırakıldı: sürükleme bitti
            if dragActive {
                // Fare AirDrop kutusunun üstündeyken bırakıldı: dosyaları doğrudan sürükleme panosundan okuyup gönder.
                // (macOS'un bırakma bildirimi bu kutuda güvenilir gelmiyor; bu yol ona bağlı değil.)
                if state.airdropHover {
                    let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                    state.airdropHover = false
                    if !urls.isEmpty { AirDrop.send(urls) }
                }
                dragActive = false; state.dragging = false; state.airdropHover = false
            }
            dragCount = pb.changeCount
            return
        }
        if !dragActive {
            guard pb.changeCount != dragCount,
                  pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
            dragActive = true
            state.dragging = true
            if state.isOpen { state.tab = .shelf }                   // açıksa Raf'a (AirDrop alanı) geç
        }
        // İmleç AirDrop kutusunun üstünde mi? (kutu renk değiştirir, bırakınca gönderilir)
        if state.isOpen, let r = DropView.airdrop?.screenRect {
            let inside = r.contains(NSEvent.mouseLocation)
            if inside != state.airdropHover { state.airdropHover = inside }
        } else if state.airdropHover { state.airdropHover = false }
        // Dosya notch'a yaklaşınca Raf'ı aç (alan, normal açılma alanından biraz geniş)
        let p = NSEvent.mouseLocation
        if !state.isOpen, hotRect.insetBy(dx: -30, dy: -24).contains(p) {
            state.tab = .shelf
            open()
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e) }
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e); return e }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == UInt16(kVK_Escape), self?.state.isOpen == true, self?.state.previewHold == false { self?.close(); return nil }
            return e
        }
    }

    private func handle(_ e: NSEvent) {
        if state.isOpen { NotificationCenter.default.post(name: .mouseTick, object: nil) }
        let p = NSEvent.mouseLocation
        let inHot = hotRect.contains(p)
        let inOpen = openRect.contains(p)
        let onHover = UserDefaults.standard.bool(forKey: Pref.openOnHover)

        switch e.type {
        case .leftMouseDown:
            if !state.isOpen, inHot, !onHover { open() }
            else if state.isOpen, !inOpen, !state.pinned, !state.previewHold, !state.inputFocused { close() }
        case .leftMouseDragged:
            // Dosya sürüklerken Raf'ı aç
            let pb = NSPasteboard(name: .drag)
            let hasFiles = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            if hasFiles {
                state.dragging = true
                if !state.isOpen, inHot || inOpen { state.tab = .shelf; open() }
            }
        case .leftMouseUp:
            state.dragging = false
        default: break
        }

        if e.type == .mouseMoved || e.type == .leftMouseDragged { hover(inHot: inHot, inOpen: inOpen, onHover: onHover) }
    }

    private func hover(inHot: Bool, inOpen: Bool, onHover: Bool) {
        if !state.isOpen {
            closeWork?.cancel()
            if inHot, onHover {
                if openWork == nil || openWork?.isCancelled == true {
                    let delay = UserDefaults.standard.double(forKey: Pref.hoverDelay)
                    let w = DispatchWorkItem { [weak self] in self?.open(); self?.openWork = nil }
                    openWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
                }
            } else {
                openWork?.cancel(); openWork = nil
            }
        } else {
            if inOpen || state.pinned || state.dragging || state.previewHold || state.inputFocused || AIState.shared.busy {
                closeWork?.cancel(); closeWork = nil
            } else if closeWork == nil || closeWork?.isCancelled == true {
                let w = DispatchWorkItem { [weak self] in self?.close(); self?.closeWork = nil }
                closeWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + UserDefaults.standard.double(forKey: Pref.closeDelay), execute: w)
            }
        }
    }
}

// MARK: - Global hotkey

enum HotKey {
    static var handler: (() -> Void)?
    static func register(keyCode: UInt32, modifiers: UInt32, _ h: @escaping () -> Void) {
        handler = h
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4144_4143), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {}
    }
}

// MARK: - Settings window

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Mate Notch Ayarları"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            window = w
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                NotchState.shared.previewHold = false     // pencere kapanınca notch normal davranışına döner
            }
        }
        // Pencere notch'un ve açık notch önizlemesinin ALTINA yerleşir; ikisi aynı anda görünür.
        let vis = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top: CGFloat = NotchController.shared.panelSize.height + 8
        let h = max(320, min(900, vis.height - top - 10))
        window?.setFrame(NSRect(x: vis.midX - 260, y: vis.maxY - top - h, width: 520, height: h), display: true)

        NotchState.shared.previewHold = true            // ayar yaparken notch açık kalır
        NotchController.shared.open()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
