import AppKit
import SwiftUI
import CoreAudio
import CoreGraphics
import ApplicationServices

/// Ses / parlaklık / klavye aydınlatması değişikliklerini notch'ta gösterir.
/// macOS'un KENDİLİĞİNDEN yaptığı değişimleri (boşta kalınca ekranı/klavye ışığını kısma, tuşa basınca eski seviyeye döndürme)
/// tuşla elle yapılan değişimlerden ayırır; otomatik olanlar için gösterge çıkmaz.
private struct AutoChangeFilter {
    var preDim: Float?          // kısılmadan önceki seviye (otomatik kısma sürerken)

    mutating func isAutomatic(from: Float, to: Float, maxManualJump: Float) -> Bool {
        let idle = Float(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
        let delta = to - from
        if delta < 0 {
            // Boşta kalınca (tuş basışı olmadan) veya tek tuş adımından çok büyük düşüş → otomatik kısma
            if idle >= 4 || -delta > maxManualJump { if preDim == nil { preDim = from }; return true }
            return false
        }
        if let pre = preDim {                 // otomatik kısmadan sonra geri açılma
            if to >= pre - 0.03 { preDim = nil }
            return true
        }
        return delta > maxManualJump          // büyük sıçrama: geri yükleme
    }
}

final class HUDService: ObservableObject {
    static let shared = HUDService()
    enum Kind { case volume, brightness, keyboard }

    @Published var kind: Kind = .volume
    @Published var level: Double = 0          // 0...1
    @Published var muted = false
    @Published var visible = false
    @Published var keyboardAvailable = false
    @Published var hideStatus = ""            // "sistem göstergesini gizle" durumu / uyarısı

    private var hideWork: DispatchWorkItem?
    private var timer: Timer?
    private var registeredDevice: AudioObjectID = 0
    private var lastVolume: Float?
    private var lastMuted: Bool?
    // Parlaklık/klavye: yavaş (otomatik parlaklık) kaymaları saymamak için "taban" değer
    private var brightBase: Float?, brightBaseAt = Date()
    private var kbBase: Float?, kbBaseAt = Date()
    private var brightFilter = AutoChangeFilter()
    private var kbFilter = AutoChangeFilter()

    // MARK: Başlat

    func start() {
        listenDefaultOutputChange()
        registerAudio()
        audioChanged(initial: true)
        kbSetup()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
        applyHideSystem(userInitiated: false)
    }

    // MARK: Gösterme

    func show(_ k: Kind, level: Double, muted: Bool = false, force: Bool = false) {
        let d = UserDefaults.standard
        if !force {
            switch k {
            case .volume: guard d.bool(forKey: Pref.hudVolume) else { return }
            case .brightness: guard d.bool(forKey: Pref.hudBrightness) else { return }
            case .keyboard: guard d.bool(forKey: Pref.hudKeyboard) else { return }
            }
        }
        let lv = min(1, max(0, level))
        // Aynı tuş basışı birkaç yoldan (tuş yakalama, CoreAudio, yoklama) gelir: aynı değeri tekrar yayınlama, animasyonu yeniden başlatma.
        if kind != k { kind = k }
        if abs(self.level - lv) >= 0.002 { self.level = lv }
        if self.muted != muted { self.muted = muted }
        if !visible { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { visible = true } }
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.visible = false }
        }
        hideWork = w
        let dur = max(0.6, d.double(forKey: Pref.hudDuration))
        DispatchQueue.main.asyncAfter(deadline: .now() + dur, execute: w)
    }

    /// Ayarlardan önizleme (tuşa basmadan).
    func preview(_ k: Kind) { show(k, level: k == .volume ? 0.62 : 0.78, force: true) }

    // MARK: Ses (CoreAudio dinleyicisi)

    private static let vmvc: AudioObjectPropertySelector = 0x766D7663   // 'vmvc' VirtualMainVolume

    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    static func defaultOutput() -> AudioObjectID {
        var dev = AudioObjectID(); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return dev
    }

    static func readVolume(_ dev: AudioObjectID) -> Float? {
        var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
        var a = addr(vmvc, kAudioObjectPropertyScopeOutput)
        if AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == 0 { return v }
        // Bazı çıkışlarda (HDMI vb.) yalnızca kanal bazlı ses var
        var sum: Float = 0, n: Float = 0
        for el in [AudioObjectPropertyElement(1), 2] {
            var c = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, el)
            var cv = Float32(0); var s2 = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &c, 0, nil, &s2, &cv) == 0 { sum += cv; n += 1 }
        }
        return n > 0 ? sum / n : nil
    }

    static func readMute(_ dev: AudioObjectID) -> Bool {
        var m = UInt32(0); var size = UInt32(4)
        var a = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m) == 0 && m != 0
    }

    private func registerAudio() {
        let dev = Self.defaultOutput()
        guard dev != 0, dev != registeredDevice else { return }
        registeredDevice = dev
        var addrs = [Self.addr(Self.vmvc, kAudioObjectPropertyScopeOutput), Self.addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput),
                     Self.addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 1),
                     Self.addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 2)]
        for i in addrs.indices {
            AudioObjectAddPropertyListenerBlock(dev, &addrs[i], DispatchQueue.main) { [weak self] _, _ in self?.audioChanged() }
        }
    }

    private func listenDefaultOutputChange() {
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main) { [weak self] _, _ in
            self?.registeredDevice = 0
            self?.registerAudio()
            self?.audioChanged(initial: true)      // aygıt değişince taban sıfırlanır, HUD çıkmaz
            BluetoothService.shared.defaultOutputChanged()
        }
    }

    private func audioChanged(initial: Bool = false) {
        let dev = Self.defaultOutput()
        guard let v = Self.readVolume(dev) else { return }
        let m = Self.readMute(dev)
        defer { lastVolume = v; lastMuted = m }
        guard !initial, lastVolume != nil else { return }
        if abs(v - (lastVolume ?? v)) > 0.001 || m != lastMuted { show(.volume, level: Double(v), muted: m) }
    }

    // MARK: Parlaklık (özel API: DisplayServices) ve klavye aydınlatması (CoreBrightness)

    typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetB = @convention(c) (UInt32, Float) -> Int32
    private static let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let dsGet: GetB? = dsHandle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetB.self) }
    private static let dsSet: SetB? = dsHandle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetB.self) }

    static var builtinDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func readBrightness() -> Float? {
        guard let get = dsGet, let id = builtinDisplay else { return nil }
        var b: Float = -1
        return get(id, &b) == 0 && b >= 0 ? b : nil
    }

    static func setBrightness(_ v: Float) -> Bool {
        guard let set = dsSet, let id = builtinDisplay else { return false }
        return set(id, min(1, max(0, v))) == 0
    }

    private var kb: NSObject?
    private var kbID: UInt64?

    private func kbSetup() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let c = cls.init()
        let sel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard c.responds(to: sel), let arr = c.perform(sel)?.takeRetainedValue() as? [NSNumber],
              let first = arr.first else { return }
        kb = c; kbID = first.uint64Value
        keyboardAvailable = readKeyboard() != nil
    }

    func readKeyboard() -> Float? {
        guard let c = kb, let id = kbID else { return nil }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard c.responds(to: sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let v = unsafeBitCast(c.method(for: sel), to: F.self)(c, sel, id)
        return v >= 0 ? v : nil
    }

    func setKeyboard(_ v: Float) -> Bool {
        guard let c = kb, let id = kbID else { return false }
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard c.responds(to: sel) else { return false }
        typealias F = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        return unsafeBitCast(c.method(for: sel), to: F.self)(c, sel, min(1, max(0, v)), id)
    }

    /// 0,2 sn'de bir okur. Yalnızca KISA sürede ≥ %3 değişimi "tuşa basıldı" sayar (otomatik parlaklığın yavaş kayması HUD çıkarmaz).
    private func poll() {
        let d = UserDefaults.standard
        let now = Date()
        // Tuş adımı büyük ayarlandıysa (tuşları biz işliyorsak) "elle yapılmış" sayılacak en büyük sıçrama da büyür
        let stepFrac = Float(max(1, min(20, d.double(forKey: Pref.hudStep)))) / 100
        let maxManual: Float = d.bool(forKey: Pref.hudHideSystem) ? max(0.15, stepFrac * 2 + 0.03) : 0.15
        if d.bool(forKey: Pref.hudBrightness), let b = Self.readBrightness() {
            if brightBase == nil { brightBase = b; brightBaseAt = now }
            else if let base = brightBase {
                let active = visible && kind == .brightness
                if abs(b - base) >= (active ? 0.003 : 0.03) {
                    let auto = brightFilter.isAutomatic(from: base, to: b, maxManualJump: maxManual)
                    brightBase = b; brightBaseAt = now
                    if !auto { show(.brightness, level: Double(b)) }
                } else if now.timeIntervalSince(brightBaseAt) > 1.5 { brightBase = b; brightBaseAt = now }
            }
        }
        if d.bool(forKey: Pref.hudKeyboard), keyboardAvailable, let k = readKeyboard() {
            if kbBase == nil { kbBase = k; kbBaseAt = now }
            else if let base = kbBase {
                let active = visible && kind == .keyboard
                if abs(k - base) >= (active ? 0.003 : 0.03) {
                    let auto = kbFilter.isAutomatic(from: base, to: k, maxManualJump: 0.15)
                    kbBase = k; kbBaseAt = now
                    if !auto { show(.keyboard, level: Double(k)) }
                } else if now.timeIntervalSince(kbBaseAt) > 1.5 { kbBase = k; kbBaseAt = now }
            }
        }
    }

    // MARK: Sistemin kendi göstergesini gizle (deneysel)

    @Published var axWaiting = false          // Erişilebilirlik izni bekleniyor
    private var axTimer: Timer?
    private var axWaitingSince = Date()

    private static let onMessage = L("Açık: ses/parlaklık tuşlarını Mate Notch işliyor.")
    static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// `userInitiated`: kullanıcı anahtarı şimdi açtı → izin penceresi gösterilir. Uygulama açılışında sessizce denenir.
    func applyHideSystem(userInitiated: Bool = true) {
        axTimer?.invalidate(); axTimer = nil
        guard UserDefaults.standard.bool(forKey: Pref.hudHideSystem) else {
            SystemKeys.shared.stop(); axWaiting = false; hideStatus = ""
            return
        }
        if SystemKeys.shared.start(prompt: userInitiated) { axWaiting = false; hideStatus = Self.onMessage; return }

        // İzin yok: anahtarı KAPATMA. İzin verilince kendiliğinden başlasın (yeniden açıp yeniden izin istemek yok).
        axWaiting = true
        axWaitingSince = Date()
        hideStatus = L("Erişilebilirlik izni bekleniyor: Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'te Mate Notch'u aç. Açınca kendiliğinden başlar.")
        axTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard UserDefaults.standard.bool(forKey: Pref.hudHideSystem) else { t.invalidate(); self.axWaiting = false; return }
            if SystemKeys.shared.start(prompt: false) {
                t.invalidate(); self.axWaiting = false; self.hideStatus = Self.onMessage
            } else if Date().timeIntervalSince(self.axWaitingSince) > 15 {
                // Ayarlarda açık görünüp çalışmıyorsa: macOS eski bir kopyanın iznini hatırlıyordur
                self.hideStatus = L("İzin hâlâ gelmedi. Listede Mate Notch zaten açık görünüyorsa macOS eski bir kopyanın iznini tutuyor olabilir: onu seçip − ile kaldır, sonra + ile /Uygulamalar'dan Mate Notch'u yeniden ekle.")
            }
        }
        RunLoop.main.add(axTimer!, forMode: .common)
    }
}

// MARK: - Medya tuşlarını yakalama (sistem göstergesini gizlemek için)

/// Ses/parlaklık/klavye ışığı tuşlarını yakalar, işlemi kendisi yapar ve olayı yutar → macOS'un kare göstergesi çıkmaz.
/// Erişilebilirlik izni ister. Yalnızca ayar açıkken çalışır; kapatınca tuşlar normale döner.
final class SystemKeys {
    static let shared = SystemKeys()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start(prompt: Bool = true) -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else {
            if prompt { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
            return false
        }
        let mask = CGEventMask(1 << 14)      // NX_SYSDEFINED
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<SystemKeys>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return pass }
        let data = ns.data1
        let key = (data & 0xFFFF0000) >> 16
        let down = ((data & 0x0000FF00) >> 8) == 0xA
        let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)    // ⇧⌥: ince adım
        // Ses ve ekran parlaklığı: Ayarlar'daki "tuş başına değişim" (%1–%20); ⇧⌥ ile dörtte biri.
        let userStep = Float(max(1, min(20, UserDefaults.standard.double(forKey: Pref.hudStep)))) / 100
        let step: Float = fine ? max(0.005, userStep / 4) : userStep
        let keyStep: Float = fine ? 1.0 / 64 : 1.0 / 16          // klavye ışığı macOS'un kendi adımında kalır

        switch key {
        case 0, 1, 7:   // SOUND_UP, SOUND_DOWN, MUTE
            let dev = HUDService.defaultOutput()
            guard HUDService.readVolume(dev) != nil else { return pass }
            if down { changeVolume(dev, key: key, step: step) }
            return nil
        case 2, 3:      // BRIGHTNESS_UP / DOWN (yalnızca yerleşik ekran ve API çalışıyorsa)
            guard let b = HUDService.readBrightness() else { return pass }
            if down {
                let n = key == 2 ? b + step : b - step
                if HUDService.setBrightness(n) { HUDService.shared.show(.brightness, level: Double(min(1, max(0, n)))) }
            }
            return nil
        case 21, 22:    // KEYBOARD ILLUMINATION UP / DOWN
            let h = HUDService.shared
            guard h.keyboardAvailable, let k = h.readKeyboard() else { return pass }
            if down {
                let n = key == 21 ? k + keyStep : k - keyStep
                if h.setKeyboard(n) { h.show(.keyboard, level: Double(min(1, max(0, n)))) }
            }
            return nil
        default: return pass
        }
    }

    private func changeVolume(_ dev: AudioObjectID, key: Int, step: Float) {
        var mute = HUDService.readMute(dev)
        var vol = HUDService.readVolume(dev) ?? 0
        func set(_ sel: AudioObjectPropertySelector, _ value: UInt32) {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var v = value
            AudioObjectSetPropertyData(dev, &a, 0, nil, 4, &v)
        }
        func setVol(_ v: Float) {
            var a = AudioObjectPropertyAddress(mSelector: 0x766D7663, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var f = Float32(min(1, max(0, v)))
            AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &f)
        }
        if key == 7 { mute.toggle(); set(kAudioDevicePropertyMute, mute ? 1 : 0) }
        else {
            if mute { mute = false; set(kAudioDevicePropertyMute, 0) }
            vol = key == 0 ? vol + step : vol - step
            vol = min(1, max(0, vol)); setVol(vol)
        }
        HUDService.shared.show(.volume, level: Double(vol), muted: mute)
    }
}

// MARK: - Görünüm

struct HUDBanner: View {
    @ObservedObject var hud = HUDService.shared
    @AppStorage(Pref.hudStyle) var style = "bar"

    var icon: String {
        switch hud.kind {
        case .volume:
            if hud.muted || hud.level <= 0.001 { return "speaker.slash.fill" }
            return hud.level < 0.34 ? "speaker.wave.1.fill" : (hud.level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        case .brightness: return hud.level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard: return hud.level < 0.5 ? "light.min" : "light.max"
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            if style == "bar" {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white).frame(width: max(5, geo.size.width * (hud.muted ? 0 : hud.level)))
                    }
                    .frame(height: 5).frame(maxHeight: .infinity)
                }
                .frame(width: 120, height: 14)
            }
            if style != "icon" {
                Text(hud.muted ? "Sessiz" : "\(Int((hud.level * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing)
                    .contentTransition(.numericText(value: hud.muted ? 0 : (hud.level * 100).rounded()))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hud.level)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hud.muted)
    }
}
