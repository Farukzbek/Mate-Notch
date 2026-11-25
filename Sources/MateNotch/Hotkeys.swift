import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Genel (global) kısayollar: notch'u aç/kapat + her sekme için ayrı kısayol. Ayarlar › Davranış › Kısayollar'dan atanır.
struct HotKeySpec: Equatable {
    var keyCode: UInt32
    var mods: UInt32          // Carbon: cmdKey | shiftKey | optionKey | controlKey
    var label: String         // "⌃⌥Space"

    var encoded: String { "\(keyCode):\(mods):\(label)" }
    init(keyCode: UInt32, mods: UInt32, label: String) { self.keyCode = keyCode; self.mods = mods; self.label = label }
    init?(encoded: String) {
        let p = encoded.split(separator: ":", maxSplits: 2).map(String.init)
        guard p.count == 3, let k = UInt32(p[0]), let m = UInt32(p[1]) else { return nil }
        self.init(keyCode: k, mods: m, label: p[2])
    }
}

enum HotKeyAction: String, CaseIterable, Identifiable {
    case toggle, home, shelf, clipboard, timer, stats, ai, batteries, notes, mixer, mirror, shortcuts
    var id: String { rawValue }
    var tab: Tab? { Tab(rawValue: rawValue) }
    var title: String { tab.map { L("Sekmeyi aç: \($0.title)") } ?? L("Notch'u aç / kapat") }
    var defaultsKey: String { "hk." + rawValue }
    /// Boş bırakılan (kullanıcının temizlediği) kısayol "none" olarak saklanır; hiç ayarlanmamışsa varsayılan geçerli.
    var defaultSpec: HotKeySpec? {
        self == .toggle ? HotKeySpec(keyCode: UInt32(kVK_Space), mods: UInt32(controlKey | optionKey), label: "⌃⌥Space") : nil
    }
    var spec: HotKeySpec? {
        guard let s = UserDefaults.standard.string(forKey: defaultsKey) else { return defaultSpec }
        return s == "none" ? nil : HotKeySpec(encoded: s)
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    var perform: ((HotKeyAction) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    func start() {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let all = HotKeyAction.allCases
                if hk.signature == 0x4D4E_484B, Int(hk.id) < all.count {
                    let a = all[Int(hk.id)]
                    DispatchQueue.main.async { HotKeyManager.shared.perform?(a) }
                }
                return noErr
            }, 1, &spec, nil, nil)
        }
        reload()
    }

    func reload() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs = [:]
        for (i, a) in HotKeyAction.allCases.enumerated() {
            guard let s = a.spec else { continue }
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(s.keyCode, s.mods, EventHotKeyID(signature: 0x4D4E_484B, id: UInt32(i)),
                                         GetApplicationEventTarget(), 0, &ref)
            if st == noErr, let ref { refs[UInt32(i)] = ref }
        }
    }

    static func set(_ a: HotKeyAction, _ s: HotKeySpec?) {
        UserDefaults.standard.set(s?.encoded ?? "none", forKey: a.defaultsKey)
        shared.reload()
    }
}

// MARK: - Kısayol kaydedici (ayarlarda)

struct ShortcutRecorder: View {
    let action: HotKeyAction
    @State private var current: HotKeySpec?
    @State private var recording = false
    @State private var warning = ""
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if !warning.isEmpty { Text(warning).font(.caption).foregroundStyle(.orange) }
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? L("Tuşlara bas…") : (current?.label ?? L("Kısayol kaydet")))
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
                    .foregroundStyle(recording ? Color.accentColor : (current == nil ? .secondary : .primary))
            }
            .buttonStyle(.bordered)
            if current != nil && !recording {
                Button { HotKeyManager.set(action, nil); current = nil; warning = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help(L("Temizle"))
            }
        }
        .onAppear { current = action.spec }
        .onDisappear { stop() }
    }

    private func start() {
        warning = ""; recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            if e.keyCode == UInt16(kVK_Delete) || e.keyCode == UInt16(kVK_ForwardDelete) {
                HotKeyManager.set(action, nil); current = nil; stop(); return nil
            }
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: UInt32 = 0
            var glyph = ""
            if f.contains(.control) { mods |= UInt32(controlKey); glyph += "⌃" }
            if f.contains(.option) { mods |= UInt32(optionKey); glyph += "⌥" }
            if f.contains(.shift) { mods |= UInt32(shiftKey); glyph += "⇧" }
            if f.contains(.command) { mods |= UInt32(cmdKey); glyph += "⌘" }
            guard f.contains(.control) || f.contains(.option) || f.contains(.command) else {
                warning = L("⌃, ⌥ ya da ⌘ ile birlikte bas"); return nil
            }
            let spec = HotKeySpec(keyCode: UInt32(e.keyCode), mods: mods, label: glyph + Self.keyName(e))
            if let other = HotKeyAction.allCases.first(where: { $0 != action && $0.spec == spec }) {
                warning = L("Zaten kullanılıyor: \(other.title)"); return nil
            }
            HotKeyManager.set(action, spec); current = spec; stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private static func keyName(_ e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"; case kVK_F4: return "F4"
        case kVK_F5: return "F5"; case kVK_F6: return "F6"; case kVK_F7: return "F7"; case kVK_F8: return "F8"
        case kVK_F9: return "F9"; case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        default: return (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
