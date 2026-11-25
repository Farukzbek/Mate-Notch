import AppKit
import CoreAudio
import SwiftUI
import Darwin

// MARK: - Ses mikseri: uygulama başına ses seviyesi (macOS 14.2+ Core Audio "process tap")
//
// Çalışma biçimi: seviyesi %100'ün altına çekilen uygulamanın sesi bir tap ile yakalanır (özgün çıkışı susturulur),
// ölçeklenip aynı çıkış aygıtından çalınır. %100'e dönünce tap kaldırılır → ses normal yoluna döner.

struct MixerApp: Identifiable, Equatable {
    let id: String                 // paket kimliği (yoksa "pid:<n>")
    let name: String
    let icon: NSImage?
    let pid: pid_t                 // ana uygulamanın pid'i
    var objectIDs: [AudioObjectID] // bu uygulamanın ses üreten süreç nesneleri (yardımcı süreçler dahil)
    static func == (a: MixerApp, b: MixerApp) -> Bool { a.id == b.id && a.objectIDs == b.objectIDs }
}

/// Tek uygulama için tap + toplu aygıt + IO işlemi.
final class AppTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let heard = UnsafeMutablePointer<Int32>.allocate(capacity: 1)      // tap'ten gerçek (sıfır olmayan) ses geldi mi → izin çalışıyor
    var seenAudio: Bool { heard.pointee != 0 }
    let objectIDs: [AudioObjectID]
    let outputDevice: AudioObjectID
    private(set) var failed = false

    init(objectIDs: [AudioObjectID], outputDevice: AudioObjectID, gain g: Float) {
        self.objectIDs = objectIDs; self.outputDevice = outputDevice
        gain.initialize(to: g); heard.initialize(to: 0)
        create()
    }

    var level: Float { get { gain.pointee } set { gain.pointee = max(0, min(1.5, newValue)) } }

    private static func deviceUID(_ dev: AudioObjectID) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var s: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &s) == 0, let u = s?.takeRetainedValue() else { return nil }
        return u as String
    }

    private func create() {
        guard #available(macOS 14.2, *), let outUID = Self.deviceUID(outputDevice) else { failed = true; return }
        let desc = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        desc.name = "Mate Notch Mixer"
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { failed = true; return }
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mate Notch Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { destroy(); failed = true; return }
        let g = gain, hd = heard
        let st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, outData, _ in
            AppTap.process(inData, outData, g.pointee)
            if hd.pointee == 0 {
                for b in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)) {
                    guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for k in 0..<Int(b.mDataByteSize) / 4 where p[k] != 0 { hd.pointee = 1; return }
                }
            }
        }
        guard st == noErr, let procID, AudioDeviceStart(aggID, procID) == noErr else { destroy(); failed = true; return }
    }

    /// Ses iş parçacığında: tap'tan gelen örnekleri ölçekleyip çıkışa yazar (ayırma/yeniden düzenleme dahil).
    private static func process(_ inData: UnsafePointer<AudioBufferList>, _ outData: UnsafeMutablePointer<AudioBufferList>, _ g: Float) {
        let inB = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outB = UnsafeMutableAudioBufferListPointer(outData)
        for b in outB { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
        guard inB.count > 0, outB.count > 0 else { return }
        let fsz = MemoryLayout<Float>.size
        if inB.count == outB.count {
            for i in 0..<inB.count {
                guard let s = inB[i].mData, let d = outB[i].mData else { continue }
                let n = Int(min(inB[i].mDataByteSize, outB[i].mDataByteSize)) / fsz
                if inB[i].mNumberChannels == outB[i].mNumberChannels {
                    let sp = s.assumingMemoryBound(to: Float.self), dp = d.assumingMemoryBound(to: Float.self)
                    for k in 0..<n { dp[k] = sp[k] * g }
                }
            }
        } else if inB.count == 1, outB.count == Int(inB[0].mNumberChannels), let s = inB[0].mData {
            // girdi: tek ara kanallı (interleaved) buffer → çıktı: kanal başına ayrı buffer
            let ch = Int(inB[0].mNumberChannels), sp = s.assumingMemoryBound(to: Float.self)
            let frames = Int(inB[0].mDataByteSize) / fsz / ch
            for c in 0..<ch {
                guard let d = outB[c].mData else { continue }
                let dp = d.assumingMemoryBound(to: Float.self)
                let m = min(frames, Int(outB[c].mDataByteSize) / fsz)
                for f in 0..<m { dp[f] = sp[f * ch + c] * g }
            }
        } else if outB.count == 1, inB.count == Int(outB[0].mNumberChannels), let d = outB[0].mData {
            // girdi: kanal başına ayrı buffer → çıktı: tek ara kanallı buffer
            let ch = Int(outB[0].mNumberChannels), dp = d.assumingMemoryBound(to: Float.self)
            let frames = Int(outB[0].mDataByteSize) / fsz / ch
            for c in 0..<ch {
                guard let s = inB[c].mData else { continue }
                let sp = s.assumingMemoryBound(to: Float.self)
                let m = min(frames, Int(inB[c].mDataByteSize) / fsz)
                for f in 0..<m { dp[f * ch + c] = sp[f] * g }
            }
        }
    }

    private func destroy() {
        if aggID != kAudioObjectUnknown {
            if let procID { AudioDeviceStop(aggID, procID); AudioDeviceDestroyIOProcID(aggID, procID) }
            procID = nil
            AudioHardwareDestroyAggregateDevice(aggID); aggID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }

    func stop() { destroy() }
    deinit { destroy(); gain.deallocate(); heard.deallocate() }
}

final class MixerService: ObservableObject {
    static let shared = MixerService()
    @Published var apps: [MixerApp] = []
    @Published var levels: [String: Float] = [:]       // 0…1 (yoksa 1)
    @Published var muted: Set<String> = []
    @Published var problem = false                     // tap kurulamadı (izin / sistem sürümü)
    private var taps: [String: AppTap] = [:]
    private var creating = Set<String>()
    private let tapQueue = DispatchQueue(label: "matenotch.mixer.taps")      // tap kurma/kaldırma yavaş (≈0,3–0,5 sn): arayüzü dondurmasın
    private var timer: Timer?
    private var users = 0
    private let saveKey = "mixerLevels"

    var supported: Bool { if #available(macOS 14.2, *) { return true } else { return false } }

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: saveKey) as? [String: Double] ?? [:]
        levels = saved.mapValues { Float($0) }
    }

    func level(_ id: String) -> Float { muted.contains(id) ? 0 : (levels[id] ?? 1) }

    // MARK: Tarama

    func retain() {
        users += 1
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func release() {
        users = max(0, users - 1)
        if users == 0 { scan() }          // sekmeden çıkınca hazır bekleyen (%100) tap'ler kaldırılır: ses normal yoluna döner
        if users == 0 && taps.isEmpty { timer?.invalidate(); timer = nil }
    }

    /// Kayıtlı seviyeleri otomatik uygulamak için arka planda da (tap varken ya da kayıtlı seviye varken) tarar.
    func startBackground() {
        guard supported, !levels.filter({ $0.value < 1 }).isEmpty, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private static func prop<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ def: T) -> T? {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = def; var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == 0 ? v : nil
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let pp = info.kp_eproc.e_ppid
        return pp > 1 ? pp : nil
    }

    /// "Sorumlu süreç" (macOS'un bir yardımcı/XPC sürecini hangi uygulamaya bağladığı): Safari'nin ses veren WebKit.GPU sürecinin
    /// üst süreci launchd olduğundan ana uygulama ancak bununla bulunur. Özel ama yaygın kullanılan bir sistem işlevi.
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsible: ResponsibleFn? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsibleFn.self) }

    /// Yardımcı süreçleri (ör. Safari/Chrome'un ses sürecini) görünür ana uygulamaya bağlar.
    private static func owner(of pid: pid_t) -> NSRunningApplication? {
        if let a = NSRunningApplication(processIdentifier: pid), a.activationPolicy == .regular { return a }
        if let r = responsible?(pid), r > 1, r != pid, let a = NSRunningApplication(processIdentifier: r), a.activationPolicy == .regular { return a }
        var p: pid_t? = pid
        for _ in 0..<8 {
            guard let cur = p else { return nil }
            if let a = NSRunningApplication(processIdentifier: cur), a.activationPolicy == .regular { return a }
            p = parent(of: cur)
        }
        return nil
    }

    func scan() {
        guard supported else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var list: [AudioObjectID] = []
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 {
            list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &list)
        }
        var byApp: [String: MixerApp] = [:]
        let me = getpid()
        for o in list {
            guard let pid: Int32 = Self.prop(o, kAudioProcessPropertyPID, Int32(0)), pid != me else { continue }
            let running: UInt32 = Self.prop(o, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0
            guard running != 0, let app = Self.owner(of: pid) else { continue }
            let id = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            if var cur = byApp[id] { cur.objectIDs.append(o); byApp[id] = cur }
            else { byApp[id] = MixerApp(id: id, name: app.localizedName ?? id, icon: app.icon, pid: app.processIdentifier, objectIDs: [o]) }
        }
        // Tap'i olan ama şu an ses üretmeyen uygulamalar listede kalsın (seviyesi sıfırlanabilsin)
        for (id, _) in taps where byApp[id] == nil {
            if let prev = apps.first(where: { $0.id == id }) { byApp[id] = MixerApp(id: id, name: prev.name, icon: prev.icon, pid: prev.pid, objectIDs: []) }
        }
        let sorted = byApp.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if sorted != apps { apps = sorted }

        // Tap'leri güncel tut: yeni ses süreçleri, çıkış aygıtı değişimi, kayıtlı seviyeler.
        // Mikser sekmesi açıkken (ve izin daha önce çalıştıysa) tüm uygulamalara %100'lük hazır tap kurulur: kaydırınca/susturunca
        // yeni tap kurmak gerekmediğinden tepki anlıktır. Sekmeden çıkınca %100'dekiler kaldırılır.
        let out = HUDService.defaultOutput()
        let warm = users > 0 && UserDefaults.standard.bool(forKey: "mixerTapOK")
        if !UserDefaults.standard.bool(forKey: "mixerTapOK"), taps.values.contains(where: { $0.seenAudio }) {
            UserDefaults.standard.set(true, forKey: "mixerTapOK")
        }
        for a in sorted {
            let want = level(a.id)
            let needTap = want < 0.999 || (warm && !a.objectIDs.isEmpty)
            if !needTap { if let t = taps.removeValue(forKey: a.id) { tapQueue.async { t.stop() } }; continue }
            if a.objectIDs.isEmpty { taps[a.id]?.level = want; continue }
            if let t = taps[a.id], t.objectIDs == a.objectIDs, t.outputDevice == out, !t.failed { t.level = want; continue }
            if creating.contains(a.id) { continue }
            let old = taps.removeValue(forKey: a.id)
            creating.insert(a.id)
            let id = a.id, ids = a.objectIDs
            tapQueue.async { [weak self] in
                old?.stop()
                let t = AppTap(objectIDs: ids, outputDevice: out, gain: 1)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.creating.remove(id)
                    if t.failed { t.stop(); self.problem = true; return }
                    self.problem = false
                    t.level = self.level(id)          // kurulurken değişmiş olabilir
                    self.taps[id] = t
                }
            }
        }
        if users == 0 && taps.isEmpty && creating.isEmpty && levels.filter({ $0.value < 1 }).isEmpty { timer?.invalidate(); timer = nil }
    }

    // MARK: Kontrol

    func set(_ id: String, _ v: Float) {
        let c = max(0, min(1, v))
        levels[id] = c
        if c > 0 { muted.remove(id) }
        persistSoon(); apply(id)
    }
    func toggleMute(_ id: String) {
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        apply(id)
    }
    /// Ses kaydı iznini sorar: şu an ses çalan bir uygulamaya SESİNİ DEĞİŞTİRMEYEN (susturmayan) kısa bir tap kurup bırakır.
    /// Çalan uygulama yoksa `done(false)`: önce bir şey çalıp tekrar denemek gerekir.
    func requestPermission(_ done: @escaping (Bool) -> Void) {
        guard #available(macOS 14.2, *) else { done(false); return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var list: [AudioObjectID] = []
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 {
            list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &list)
        }
        let running = list.filter { (Self.prop($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0 && (Self.prop($0, kAudioProcessPropertyPID, Int32(0)) ?? 0) != getpid() }
        guard let o = running.first else {
            BannerService.shared.post(NotchBanner(icon: "speaker.wave.2.fill", title: L("Önce bir uygulamada ses çal"), subtitle: L("Sonra bu izni tekrar iste"), tint: .orange))
            done(false); return
        }
        tapQueue.async {
            let desc = CATapDescription(stereoMixdownOfProcesses: [o])
            desc.muteBehavior = .unmuted
            desc.isPrivate = true
            var id = AudioObjectID(kAudioObjectUnknown)
            let ok = AudioHardwareCreateProcessTap(desc, &id) == noErr
            if ok { AudioHardwareDestroyProcessTap(id) }
            DispatchQueue.main.async {
                if ok { UserDefaults.standard.set(true, forKey: "mixerTapOK") }
                done(ok)
            }
        }
    }

    func resetAll() {
        levels = [:]; muted = []; persistSoon()
        for id in Array(taps.keys) { apply(id) }
        requestScan()
    }
    func reset(_ id: String) { levels[id] = nil; muted.remove(id); persistSoon(); apply(id) }

    /// Kaydırırken anlık tepki: tap zaten varsa yalnızca kazancı yazar (ses iş parçacığı hemen okur), ağır tarama yapılmaz.
    private func apply(_ id: String) {
        let want = level(id)
        if let t = taps[id], want < 0.999 { t.level = want; return }
        requestScan()           // tap kurulacak ya da kaldırılacak
    }

    private var scanQueued = false
    private func requestScan() {
        guard !scanQueued else { return }
        scanQueued = true
        DispatchQueue.main.async { [weak self] in self?.scanQueued = false; self?.scan() }
    }

    private var persistWork: DispatchWorkItem?
    private func persistSoon() {
        persistWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.levels.filter { $0.value < 0.999 }.mapValues { Double($0) }, forKey: self.saveKey)
        }
        persistWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func stopAll() { taps.values.forEach { $0.stop() }; taps = [:] }
}

// MARK: - Arayüz

/// Mikser: çerçevesiz, dikey kanallar. Her uygulama için dikey kaydırıcı; altında yalnızca uygulama simgesi (çerçeveli kare).
/// Simgeye tıkla: sustur / sesi aç. Çift tıkla ya da sağ tık: sıfırla. Üzerine gelince uygulamanın adı çıkar.
struct MixerView: View {
    @ObservedObject var mixer = MixerService.shared

    var body: some View {
        Group {
            if !mixer.supported {
                note("exclamationmark.triangle", L("Ses mikseri macOS 14.2 veya üstünü gerektirir."))
            } else if mixer.apps.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "slider.vertical.3").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3))
                    Text("Şu an ses çalan uygulama yok").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    Text("Bir uygulama ses çalmaya başlayınca burada görünür.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .bottom, spacing: 12) {
                                ForEach(mixer.apps) { a in MixerChannel(app: a) }
                            }
                            .padding(.horizontal, 6)
                            .frame(minWidth: geo.size.width)        // az uygulamada ortada dursun
                        }
                    }
                    if mixer.problem {
                        Text("Ses kaydı izni gerekli: Sistem Ayarları › Gizlilik ve Güvenlik › Ekran ve Sistem Ses Kaydı'nda Mate Notch'u aç.")
                            .font(.system(size: 9.5)).foregroundStyle(.orange).lineLimit(2)
                    }
                }
            }
        }
        .onAppear { mixer.retain() }
        .onDisappear { mixer.release() }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white.opacity(0.35))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MixerChannel: View {
    let app: MixerApp
    @ObservedObject var mixer = MixerService.shared

    var body: some View {
        let muted = mixer.muted.contains(app.id)
        let v = Double(mixer.levels[app.id] ?? 1)
        let changed = muted || v < 0.999
        VStack(spacing: 7) {
            Text("\(Int(((muted ? 0 : v) * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText(value: (muted ? 0 : v) * 100))
                .foregroundStyle(changed ? Color(red: 1, green: 0.72, blue: 0.42) : .white.opacity(0.5))
            VSlider(value: Binding(get: { muted ? 0 : v }, set: { mixer.set(app.id, Float($0)) }), tint: changed ? Color(red: 1, green: 0.72, blue: 0.42) : .white.opacity(0.9))
                .frame(width: 30, height: 66)
            // Yalnızca simge çerçeveli; ad üzerine gelince çıkar
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.8)
                if let i = app.icon { Image(nsImage: i).resizable().frame(width: 26, height: 26).opacity(muted ? 0.35 : 1) }
                if muted { Image(systemName: "speaker.slash.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.22)) { mixer.reset(app.id) } }
            .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { mixer.toggleMute(app.id) } }     // sustur / aç: kaydırıcı hızlıca iner-çıkar
            .contextMenu {
                Button(muted ? "Sesi aç" : "Sustur") { withAnimation(.easeOut(duration: 0.22)) { mixer.toggleMute(app.id) } }
                Button("Sıfırla") { withAnimation(.easeOut(duration: 0.22)) { mixer.reset(app.id) } }
            }
            .tip(app.name, .top)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .frame(width: 60)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 0.8))
    }
}

/// Dikey kaydırıcı: ince kanal, altından dolar; tıklayınca ya da sürükleyince değer ayarlanır.
struct VSlider: View {
    @Binding var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.14)).frame(width: 6)
                Capsule().fill(tint).frame(width: 6, height: max(6, h * value))
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(y: -(h - 14) * value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(1, max(0, 1 - Double(g.location.y - 7) / Double(h - 14)))
            })
        }
    }
}
