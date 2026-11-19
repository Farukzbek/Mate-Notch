import AppKit
import CoreAudio
import SwiftUI

// MARK: - Küçük açılır menü yardımcısı (notch açıkken kapanmasın diye menü boyunca kilitlenir)

final class ClosureMenuItem: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, checked: Bool = false, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { block() }
}

enum PopMenu {
    static func show(_ items: [NSMenuItem]) {
        let menu = NSMenu()
        items.forEach { menu.addItem($0) }
        NotchState.shared.inputFocused = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        NotchState.shared.inputFocused = false
    }
}

// MARK: - Ses çıkışı seçici

enum AudioOutputs {
    struct Device { let id: AudioObjectID; let name: String }

    static func list() -> [Device] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == 0 else { return [] }
        return ids.compactMap { id in
            var oa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var s: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &oa, 0, nil, &s) == 0, s > 0 else { return nil }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(s), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &oa, 0, nil, &s, raw) == 0 else { return nil }
            let bufs = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            guard bufs.reduce(0, { $0 + Int($1.mNumberChannels) }) > 0 else { return nil }
            var nameRef: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &nameRef) == 0, let n = nameRef?.takeRetainedValue() else { return nil }
            return Device(id: id, name: n as String)
        }
    }

    static func setDefault(_ id: AudioObjectID) {
        var dev = id
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &dev)
    }

    static func showMenu() {
        let cur = HUDService.defaultOutput()
        PopMenu.show(list().map { d in ClosureMenuItem(d.name, checked: d.id == cur) { setDefault(d.id) } })
    }
}

struct OutputPickerButton: View {
    var body: some View {
        Button { AudioOutputs.showMenu() } label: { Image(systemName: "airplayaudio").font(.system(size: 13)) }
            .buttonStyle(PressStyle()).tip(L("Ses çıkışı"), .top)
    }
}

// MARK: - Apple Kısayolları

enum ShortcutsService {
    static var available: Bool { FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts") }

    static func list(_ done: @escaping ([String]) -> Void) {
        DispatchQueue.global().async {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["list"]
            p.standardOutput = pipe; p.standardError = Pipe()
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let names = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            DispatchQueue.main.async { done(names) }
        }
    }

    static func run(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["run", name]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run()
        BannerService.shared.post(NotchBanner(icon: "bolt.fill", title: name, subtitle: L("Kısayol çalıştı"), tint: .yellow))
    }

    static func showMenu() {
        list { names in
            if names.isEmpty {
                PopMenu.show([ClosureMenuItem(L("Kısayol bulunamadı")) {}])
            } else {
                PopMenu.show(names.map { n in ClosureMenuItem(n) { run(n) } })
            }
        }
    }
}
