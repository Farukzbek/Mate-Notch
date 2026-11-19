import AppKit
import SwiftUI
import EventKit
import CoreBluetooth
import Intents
import ApplicationServices
import ServiceManagement

// MARK: - İzin durumları

enum PermState: Equatable { case granted, notAsked, denied, appClosed }

struct PermItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let why: String              // bu izin ne işe yarar / vermezsen ne olmaz
    let optional: Bool
    var state: PermState
}

/// Uygulamanın kullandığı izinleri tek yerde gösterir ve ister. Hiçbir izin açılışta kendiliğinden istenmez;
/// kullanıcı sihirbazdan (ilk açılışta, menüden ya da Ayarlar'dan) ister.
final class PermissionService: ObservableObject {
    static let shared = PermissionService()
    @Published var items: [PermItem] = []
    private var bt: CBCentralManager?
    private var timer: Timer?

    func startPolling() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stopPolling() { timer?.invalidate(); timer = nil }

    // MARK: Durum okuma (hiçbiri izin penceresi çıkarmaz)

    private static func automation(_ bundleID: String) -> PermState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .appClosed }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let r = AEDeterminePermissionToAutomateTarget(target.aeDesc, 0x2A2A2A2A, 0x2A2A2A2A, false)
        switch r {
        case 0: return .granted
        case -1744: return .notAsked           // errAEEventWouldRequireUserConsent
        case -1743: return .denied             // errAEEventNotPermitted
        default: return .appClosed
        }
    }

    func refresh() {
        let cal: PermState = {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }()
        let blu: PermState = {
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }()
        let foc: PermState = {
            switch INFocusStatusCenter.default.authorizationStatus {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }()
        let new: [PermItem] = [
            PermItem(id: "calendar", icon: "calendar", title: L("Takvim"),
                     why: L("Ana Sayfa'da sıradaki etkinliği ve toplantı hatırlatmasını gösterir."), optional: false, state: cal),
            PermItem(id: "bluetooth", icon: "headphones", title: L("Bluetooth"),
                     why: L("Kulaklık, fare ve klavyenin pil seviyesini okur; düşük pil uyarısı verir."), optional: false, state: blu),
            PermItem(id: "spotify", icon: "music.note", title: L("Spotify kontrolü"),
                     why: L("Çalan şarkıyı okur; oynat/duraklat, ileri/geri ve sözler için gerekir. Spotify açıkken verilebilir."), optional: false,
                     state: Self.automation("com.spotify.client")),
            PermItem(id: "music", icon: "music.quarternote.3", title: L("Apple Music kontrolü"),
                     why: L("Apple Music için aynısı. Müzik uygulaması açıkken verilebilir."), optional: false,
                     state: Self.automation("com.apple.Music")),
            PermItem(id: "accessibility", icon: "keyboard", title: L("Erişilebilirlik"),
                     why: L("Yalnızca \"tuşları Mate Notch işlesin\" seçeneği için: ses/parlaklık tuş adımını ayarlar ve sistemin kare göstergesini gizler."),
                     optional: true, state: AXIsProcessTrusted() ? .granted : .notAsked),
            PermItem(id: "focus", icon: "moon.fill", title: L("Odak durumu"),
                     why: L("Odak (Rahatsız Etmeyin) açıkken notch'ta ay simgesi gösterir."), optional: true, state: foc),
            PermItem(id: "screen", icon: "camera.viewfinder", title: L("Ekran Kaydı"),
                     why: L("Ekran görüntüsü, ekrandan metin okuma ve ekran kaydı düğmeleri için gerekebilir; macOS gerekirse kendisi sorar."),
                     optional: true, state: CGPreflightScreenCaptureAccess() ? .granted : .notAsked),
        ]
        if new.map(\.state) != items.map(\.state) || items.count != new.count { items = new }
    }

    // MARK: İstek

    private static func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    func request(_ id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let asked = item.state == .notAsked
        switch id {
        case "calendar":
            asked ? CalendarService.shared.requestAccess { self.refresh() } : Self.openSettings("Privacy_Calendars")
        case "bluetooth":
            if asked { bt = CBCentralManager() } else { Self.openSettings("Privacy_Bluetooth") }
        case "spotify", "music":
            let bundle = id == "spotify" ? "com.spotify.client" : "com.apple.Music"
            if item.state == .appClosed { return }
            if asked {
                // Bu çağrı, hedef uygulama açıkken macOS'un izin penceresini çıkarır
                DispatchQueue.global().async {
                    let t = NSAppleEventDescriptor(bundleIdentifier: bundle)
                    _ = AEDeterminePermissionToAutomateTarget(t.aeDesc, 0x2A2A2A2A, 0x2A2A2A2A, true)
                    DispatchQueue.main.async { self.refresh() }
                }
            } else { Self.openSettings("Privacy_Automation") }
        case "accessibility":
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            Self.openSettings("Privacy_Accessibility")
        case "focus":
            if asked { UserDefaults.standard.set(true, forKey: Pref.focusIndicator); FocusService.shared.enable() }
            else { Self.openSettings("Privacy_Focus") }
        case "screen":
            _ = CGRequestScreenCaptureAccess()
            Self.openSettings("Privacy_ScreenCapture")
        default: break
        }
    }
}

// MARK: - Arayüz

struct WizardView: View {
    @ObservedObject var perms = PermissionService.shared
    @State private var launchAtLogin = LaunchAtLogin.enabled
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mate Notch'a hoş geldin").font(.title2.weight(.semibold))
                        Text("İzinler").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Özelliklerin çalışması için macOS'un bazı izinleri istiyor. Hiçbiri zorunlu değil: vermediğin iznin özelliği çalışmaz, diğerleri etkilenmez. Sonra Ayarlar'dan da buraya dönebilirsin.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(perms.items) { item in
                        PermRow(item: item) { perms.request(item.id) }
                        Divider().padding(.leading, 62)
                    }
                }
            }
            Divider()
            HStack {
                Toggle("Girişte otomatik başlat", isOn: Binding(get: { launchAtLogin }, set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                Spacer()
                Button("Bitti") { onDone() }
                Button("Özellik turuna geç") { onDone(); TourWindow.show() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { perms.startPolling() }
        .onDisappear { perms.stopPolling() }
    }
}

struct PermRow: View {
    let item: PermItem
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.icon).font(.system(size: 15)).frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 13, weight: .semibold))
                    if item.optional {
                        Text("İsteğe bağlı").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
                    }
                }
                Text(item.why).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            status.frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder var status: some View {
        switch item.state {
        case .granted:
            Label("Verildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12, weight: .medium))
        case .appClosed:
            Text("Uygulama kapalı").font(.system(size: 11)).foregroundStyle(.secondary)
        case .notAsked:
            Button("İzin ver", action: action)
        case .denied:
            Button("Ayarları aç", action: action)
        }
    }
}

enum WizardWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let v = WizardView { window?.close() }
            let w = NSWindow(contentViewController: NSHostingController(rootView: v))
            w.title = L("Mate Notch — İzinler")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        let vis = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let h = min(640, vis.height - 160)
        window?.setFrame(NSRect(x: vis.midX - 290, y: vis.midY - h / 2 - 20, width: 580, height: h), display: true)
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
