import AppKit
import SwiftUI
import CoreAudio
import CoreMediaIO
import Intents
import Vision

// MARK: - Genel bildirim (geçici bant)

struct NotchBanner: Equatable {
    var icon: String
    var title: String
    var subtitle: String?
    var tint: Color = .white
}

/// Kapalı notch'un altında kısa süre görünen bildirim bandı (Bluetooth bağlandı, indirme bitti…).
final class BannerService: ObservableObject {
    static let shared = BannerService()
    @Published var current: NotchBanner?
    private var work: DispatchWorkItem?

    func post(_ b: NotchBanner, duration: TimeInterval = 3.6) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { self.current = b }
            self.work?.cancel()
            let w = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.25)) { self?.current = nil } }
            self.work = w
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
        }
    }
}

struct BannerView: View {
    @ObservedObject var bn = BannerService.shared
    var body: some View {
        if let b = bn.current {
            HStack(spacing: 8) {
                Image(systemName: b.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(b.tint)
                Text(b.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let s = b.subtitle { Text(s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Bluetooth (AirPods vb.) bağlanınca pil bandı

final class BluetoothService {
    static let shared = BluetoothService()

    /// Varsayılan çıkış değişince çağrılır; Bluetooth bir aygıta geçildiyse isim + pil bandı gösterir.
    func defaultOutputChanged() {
        guard UserDefaults.standard.bool(forKey: Pref.bannerBluetooth) else { return }
        let dev = HUDService.defaultOutput()
        guard let (name, isBT) = Self.nameAndTransport(dev), isBT else { return }
        DispatchQueue.global(qos: .utility).async {
            let battery = Self.batteryText(forDeviceNamed: name)
            BannerService.shared.post(NotchBanner(icon: Self.icon(for: name), title: name,
                                                  subtitle: battery.map { "Bağlandı · \($0)" } ?? "Bağlandı", tint: .green))
        }
    }

    static func nameAndTransport(_ dev: AudioObjectID) -> (String, Bool)? {
        guard dev != 0 else { return nil }
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &nameRef) == 0, let name = nameRef?.takeRetainedValue() as String? else { return nil }
        var t = UInt32(0); var tsize = UInt32(4)
        var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(dev, &ta, 0, nil, &tsize, &t)
        return (name, t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE)
    }

    static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpods.pro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// system_profiler çıktısından (izin gerektirmez) bağlı aygıtın pil yüzdesi.
    static func batteryText(forDeviceNamed name: String) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parseBattery(json: data, deviceNamed: name)
    }

    static func parseBattery(json: Data, deviceNamed name: String) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let top = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = top["device_connected"] as? [[String: Any]] else { return nil }
        for entry in connected {
            for (devName, infoAny) in entry {
                guard devName == name || devName.contains(name) || name.contains(devName), let info = infoAny as? [String: Any] else { continue }
                func v(_ k: String) -> String? { (info[k] as? String).map { $0.hasSuffix("%") ? $0 : $0 + "%" } }
                var parts: [String] = []
                if let l = v("device_batteryLevelLeft") { parts.append("Sol \(l)") }
                if let r = v("device_batteryLevelRight") { parts.append("Sağ \(r)") }
                if let c = v("device_batteryLevelCase") { parts.append("Kutu \(c)") }
                if parts.isEmpty, let m = v("device_batteryLevelMain") { parts.append(m) }
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }
        }
        return nil
    }
}

// MARK: - Gizlilik göstergeleri (kamera / mikrofon kullanımda)

final class PrivacyService: ObservableObject {
    static let shared = PrivacyService()
    @Published var camera = false
    @Published var mic = false
    private var timer: Timer?

    var active: Bool { UserDefaults.standard.bool(forKey: Pref.privacyIndicator) && (camera || mic) }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func poll() {
        guard UserDefaults.standard.bool(forKey: Pref.privacyIndicator) else {
            if camera || mic { camera = false; mic = false }
            return
        }
        let c = Self.cameraRunning(), m = Self.micRunning()
        if c != camera { camera = c }
        if m != mic { mic = m }
    }

    static func micRunning() -> Bool {
        var size: UInt32 = 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
        var devs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &devs)
        for d in devs {
            var ia = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var sz: UInt32 = 0
            AudioObjectGetPropertyDataSize(d, &ia, 0, nil, &sz)
            guard sz > 0 else { continue }          // giriş akışı yok → mikrofon değil
            var run = UInt32(0); var rsz = UInt32(4)
            var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(d, &ra, 0, nil, &rsz, &run) == 0, run != 0 { return true }
        }
        return false
    }

    static func cameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var ra = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                               mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                               mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var run = UInt32(0); var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &ra, 0, nil, 4, &u, &run) == 0, run != 0 { return true }
        }
        return false
    }
}

// MARK: - Odak (Rahatsız Etmeyin) göstergesi — resmi INFocusStatusCenter

final class FocusService: ObservableObject {
    static let shared = FocusService()
    @Published var active = false
    @Published var status = ""
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
    }

    /// Ayardan açılınca izin ister.
    func enable() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
    }

    func refresh() {
        guard UserDefaults.standard.bool(forKey: Pref.focusIndicator) else { if active { active = false }; status = ""; return }
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized:
            let f = INFocusStatusCenter.default.focusStatus.isFocused ?? false
            if f != active { active = f }
            status = "İzin verildi ✓"
        case .denied: active = false; status = "İzin reddedildi: Sistem Ayarları › Gizlilik ve Güvenlik › Odak'tan aç."
        case .restricted: active = false; status = "Bu Mac'te kısıtlı."
        default: active = false; status = "İzin bekleniyor…"
        }
    }
}

// MARK: - İndirme göstergesi (~/Downloads)

final class DownloadService: ObservableObject {
    static let shared = DownloadService()
    @Published var count = 0
    @Published var bytes: Int64 = 0
    private var timer: Timer?
    private var previous: [String: Int64] = [:]
    private let exts: Set<String> = ["crdownload", "download", "part", "opdownload", "partial"]
    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    var active: Bool { UserDefaults.standard.bool(forKey: Pref.downloadIndicator) && count > 0 }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func poll() {
        guard UserDefaults.standard.bool(forKey: Pref.downloadIndicator) else {
            if count != 0 { count = 0; bytes = 0 }
            previous = [:]
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let items = (try? FileManager.default.contentsOfDirectory(at: self.dir, includingPropertiesForKeys: nil)) ?? []
            var current: [String: Int64] = [:]
            for u in items where self.exts.contains(u.pathExtension.lowercased()) {
                current[u.lastPathComponent] = CacheCleaner.dirSize(u)
            }
            let finished = self.previous.keys.filter { current[$0] == nil }
            DispatchQueue.main.async {
                self.previous = current
                let total = current.values.reduce(0, +)
                if self.count != current.count { self.count = current.count }
                self.bytes = total
                for tmp in finished {
                    let base = (tmp as NSString).deletingPathExtension
                    if FileManager.default.fileExists(atPath: self.dir.appendingPathComponent(base).path) {
                        BannerService.shared.post(NotchBanner(icon: "checkmark.circle.fill", title: "İndirme tamamlandı",
                                                              subtitle: base, tint: .green))
                    }
                }
            }
        }
    }
}

// MARK: - Hava durumu (Open-Meteo, anahtar gerekmez; şehir elle seçilir, konum izni yok)

final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published var temp: Int?
    @Published var symbol = "cloud.fill"
    @Published var text = ""
    @Published var searchStatus = ""
    private var timer: Timer?

    var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.weatherEnabled) }
    var city: String { UserDefaults.standard.string(forKey: Pref.weatherCity) ?? "" }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
    }

    /// Ayarlardan şehir ara → enlem/boylam kaydedilir.
    func search(_ name: String) {
        let q = name.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=1&language=tr") else { return }
        searchStatus = "Aranıyor…"
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let r = (json?["results"] as? [[String: Any]])?.first
            DispatchQueue.main.async {
                guard let r, let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { self.searchStatus = "Şehir bulunamadı"; return }
                let d = UserDefaults.standard
                d.set(lat, forKey: Pref.weatherLat); d.set(lon, forKey: Pref.weatherLon)
                let label = [r["name"] as? String, r["country"] as? String].compactMap { $0 }.joined(separator: ", ")
                d.set(label, forKey: Pref.weatherCity)
                self.searchStatus = "Seçildi: \(label)"
                self.refresh()
            }
        }.resume()
    }

    func refresh() {
        let d = UserDefaults.standard
        guard enabled, d.object(forKey: Pref.weatherLat) != nil else { return }
        let lat = d.double(forKey: Pref.weatherLat), lon = d.double(forKey: Pref.weatherLon)
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,is_day&timezone=auto") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let json = data.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
                  let cur = json["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double,
                  let code = cur["weather_code"] as? Int else { return }
            let day = (cur["is_day"] as? Int ?? 1) == 1
            let (sym, txt) = Self.describe(code, day: day)
            DispatchQueue.main.async { self.temp = Int(t.rounded()); self.symbol = sym; self.text = txt }
        }.resume()
    }

    /// WMO hava durumu kodu → SF Symbol + Türkçe açıklama
    static func describe(_ code: Int, day: Bool) -> (String, String) {
        switch code {
        case 0: return (day ? "sun.max.fill" : "moon.stars.fill", "Açık")
        case 1, 2: return (day ? "cloud.sun.fill" : "cloud.moon.fill", "Parçalı bulutlu")
        case 3: return ("cloud.fill", "Bulutlu")
        case 45, 48: return ("cloud.fog.fill", "Sisli")
        case 51...57: return ("cloud.drizzle.fill", "Çise")
        case 61...67, 80...82: return ("cloud.rain.fill", "Yağmurlu")
        case 71...77, 85, 86: return ("cloud.snow.fill", "Karlı")
        case 95...99: return ("cloud.bolt.rain.fill", "Fırtınalı")
        default: return ("cloud.fill", "")
        }
    }
}

// MARK: - Ekrandan metin okuma (OCR, Vision — cihaz içi)

enum OCR {
    /// Ekranda bir alan seçtirir, içindeki metni okur. Tamamlanınca ana iş parçacığında çağrılır.
    static func captureAndRecognize(_ done: @escaping (Result<String, AIError>) -> Void) {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-c"]                       // alan seç → panoya görüntü
            try? p.run(); p.waitUntilExit()
            DispatchQueue.main.async {
                guard pb.changeCount != before, let img = NSImage(pasteboard: pb),
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { done(.failure(AIError("Seçim iptal edildi"))); return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let req = VNRecognizeTextRequest()
                    req.recognitionLevel = .accurate
                    req.recognitionLanguages = ["tr-TR", "en-US"]
                    req.usesLanguageCorrection = true
                    do { try VNImageRequestHandler(cgImage: cg).perform([req]) }
                    catch { DispatchQueue.main.async { done(.failure(AIError("Metin okunamadı"))) }; return }
                    let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    DispatchQueue.main.async {
                        text.isEmpty ? done(.failure(AIError("Seçilen alanda metin bulunamadı"))) : done(.success(text))
                    }
                }
            }
        }
    }
}
