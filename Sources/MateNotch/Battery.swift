import AppKit
import SwiftUI
import IOBluetooth
import CoreBluetooth

// MARK: - Cihaz pilleri (Mac + bağlı Bluetooth cihazlar)

struct PowerDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var percent: Int?            // nil = cihaz pil bilgisi vermiyor
    var charging = false
    var detail: String?          // "Sol %80 · Sağ %75 · Kutu %100"
    var isMac = false
}

/// Bağlı Bluetooth cihazların pili. Kaynaklar: system_profiler (AirPods/Beats, Apple fare/klavye/trackpad…) ve
/// IOBluetooth'un pil alanları (HFP pil göstergesi bildiren kulaklıklar gibi system_profiler'ın vermediği cihazlar).
/// iPhone / iPad / Apple Watch: macOS bu pilleri üçüncü taraf uygulamalara vermiyor (BatteryCenter yetki ister), burada yok.
final class DeviceBatteryService: ObservableObject {
    static let shared = DeviceBatteryService()
    @Published var devices: [PowerDevice] = []      // yalnızca Bluetooth (Mac ayrıca BatteryService'te)
    @Published var refreshing = false
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// `completion`: sonuç hazır olunca ana iş parçacığında çağrılır (bağlanma bandı için).
    func refresh(completion: (([PowerDevice]) -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: Pref.bluetoothBatteries) else {
            if !devices.isEmpty { devices = [] }
            completion?([]); return
        }
        guard !refreshing else { completion?(devices); return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            var list = Self.fromSystemProfiler()
            DispatchQueue.main.async {
                Self.mergeIOBluetooth(into: &list)             // IOBluetooth ana iş parçacığında kullanılır
                self.devices = list
                self.refreshing = false
                PowerAlertService.shared.check()
                completion?(list)
            }
        }
    }

    // MARK: system_profiler

    static func icon(forName name: String, minorType: String?) -> String {
        let n = name.lowercased(), t = (minorType ?? "").lowercased()
        if n.contains("airpods") || n.contains("beats") { return BluetoothService.icon(for: name) }
        if t.contains("mouse") || n.contains("mouse") { return "magicmouse" }
        if t.contains("keyboard") || n.contains("keyboard") { return "keyboard" }
        if t.contains("trackpad") || n.contains("trackpad") { return "trackpad" }
        if t.contains("gamepad") || t.contains("joystick") || n.contains("controller") { return "gamecontroller" }
        if t.contains("headset") || t.contains("headphone") || t.contains("handsfree") || t.contains("speaker") || n.contains("buds") { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }

    static func fromSystemProfiler() -> [PowerDevice] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(json: data)
    }

    static func parse(json: Data) -> [PowerDevice] {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let top = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = top["device_connected"] as? [[String: Any]] else { return [] }
        var out: [PowerDevice] = []
        for entry in connected {
            for (name, infoAny) in entry {
                guard let info = infoAny as? [String: Any] else { continue }
                func pct(_ k: String) -> Int? { (info[k] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
                let l = pct("device_batteryLevelLeft"), r = pct("device_batteryLevelRight"), c = pct("device_batteryLevelCase"), m = pct("device_batteryLevelMain")
                var parts: [String] = []
                if let l { parts.append("Sol %\(l)") }; if let r { parts.append(L("Sağ %\(r)")) }; if let c { parts.append("Kutu %\(c)") }
                let level = m ?? [l, r].compactMap { $0 }.min() ?? c
                out.append(PowerDevice(id: (info["device_address"] as? String) ?? name, name: name,
                                       icon: icon(forName: name, minorType: info["device_minorType"] as? String),
                                       percent: level, detail: parts.isEmpty ? nil : parts.joined(separator: " · ")))
            }
        }
        return out
    }

    // MARK: IOBluetooth (özel pil alanları)

    /// Değer geçerli mi? (0 ve 255/-1 "bilinmiyor" anlamına gelir)
    private static func valid(_ v: Int?) -> Int? { guard let v, (1...100).contains(v) else { return nil }; return v }

    static func mergeIOBluetooth(into list: inout [PowerDevice]) {
        guard CBManager.authorization == .allowedAlways else { return }      // izin yokken IOBluetooth'a dokunma: pencere çıkarır
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        func read(_ d: IOBluetoothDevice, _ key: String) -> Int? {
            guard d.responds(to: NSSelectorFromString(key)) else { return nil }
            return valid((d.value(forKey: key) as? NSNumber)?.intValue)
        }
        for d in paired where d.isConnected() {
            let name = d.name ?? L("Bluetooth cihazı")
            let single = read(d, "batteryPercentSingle") ?? read(d, "batteryPercentCombined") ?? read(d, "batteryPercent")
            let l = read(d, "batteryPercentLeft"), r = read(d, "batteryPercentRight"), c = read(d, "batteryPercentCase")
            let level = single ?? [l, r].compactMap { $0 }.min() ?? c
            var parts: [String] = []
            if let l { parts.append("Sol %\(l)") }; if let r { parts.append(L("Sağ %\(r)")) }; if let c { parts.append("Kutu %\(c)") }
            if let i = list.firstIndex(where: { $0.name == name || $0.id.caseInsensitiveCompare(d.addressString ?? "") == .orderedSame }) {
                if list[i].percent == nil { list[i].percent = level; list[i].detail = parts.isEmpty ? list[i].detail : parts.joined(separator: " · ") }
            } else {
                list.append(PowerDevice(id: d.addressString ?? name, name: name,
                                        icon: icon(forName: name, minorType: nil), percent: level,
                                        detail: parts.isEmpty ? nil : parts.joined(separator: " · ")))
            }
        }
    }
}

// MARK: - Düşük pil uyarıları (Mac + cihazlar)

final class PowerAlertService {
    static let shared = PowerAlertService()
    private var stage: [String: Int] = [:]      // cihaz → en son verilen uyarı aşaması (1 düşük, 2 çok düşük)

    func check() {
        let d = UserDefaults.standard
        let threshold = Int(max(5, min(50, d.double(forKey: Pref.lowBatteryLevel))))
        if d.bool(forKey: Pref.lowBatteryAlert) {
            let b = BatteryService.shared
            evaluate(id: "mac", name: "Mac", percent: b.level, charging: b.pluggedIn || b.charging, threshold: threshold, isMac: true)
        }
        if d.bool(forKey: Pref.lowBatteryDevices) {
            for dev in DeviceBatteryService.shared.devices {
                guard let p = dev.percent else { continue }
                evaluate(id: dev.id, name: dev.name, percent: p, charging: dev.charging, threshold: threshold, isMac: false, icon: dev.icon)
            }
        }
    }

    private func evaluate(id: String, name: String, percent: Int, charging: Bool, threshold: Int, isMac: Bool, icon: String = "battery.25") {
        let critical = max(5, min(10, threshold / 2 + 2))
        // Şarjdayken veya eşiğin biraz üstüne çıkınca sıfırla (tekrar düşünce yeniden uyarılsın)
        if charging || percent > threshold + 5 { stage[id] = nil; return }
        let s = percent <= critical ? 2 : (percent <= threshold ? 1 : 0)
        guard s > (stage[id] ?? 0) else { return }
        stage[id] = s
        if isMac { DispatchQueue.main.async { BuddyService.shared.lowBattery() } }
        BannerService.shared.post(NotchBanner(
            icon: isMac ? (s == 2 ? "battery.0percent" : "battery.25percent") : icon,
            title: s == 2 ? L("Pil çok düşük") : L("Pil azalıyor"),
            subtitle: "\(name) %\(percent)" + (isMac ? L(" · şarja tak") : ""),
            tint: s == 2 ? .red : .orange), duration: 7)
        if s == 2 { NSSound(named: "Basso")?.play() }
    }
}

// MARK: - Piller ekranı

struct BatteriesView: View {
    @ObservedObject var mac = BatteryService.shared
    @ObservedObject var svc = DeviceBatteryService.shared
    @AppStorage(Pref.lowBatteryLevel) var threshold = 20.0

    var rows: [PowerDevice] {
        [PowerDevice(id: "mac", name: "Bu Mac", icon: "laptopcomputer", percent: mac.level, charging: mac.pluggedIn || mac.charging,
                     detail: mac.pluggedIn ? (mac.charging ? L("Şarj oluyor") : L("Güç adaptörüne bağlı")) : nil, isMac: true)] + svc.devices
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    ForEach(rows) { d in row(d) }
                    if svc.devices.isEmpty {
                        Text(UserDefaults.standard.bool(forKey: Pref.bluetoothBatteries)
                             ? "Pil bilgisi veren bağlı Bluetooth cihaz yok."
                             : "Bluetooth cihaz pilleri Ayarlar'dan kapalı.")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)).padding(.top, 4)
                    }
                }
            }
            HStack {
                Spacer()
                Button { svc.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(svc.refreshing ? 360 : 0))
                        .animation(svc.refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: svc.refreshing)
                }
                .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, height: 24)            // yazı kapsülü (24 pt) sığsın
                .morph("Yenile", trailing: true)         // sağ kenarda: kapsül içeri (sola) açılsın, notch'tan taşmasın
            }
        }
        .onAppear { svc.refresh() }
    }

    func row(_ d: PowerDevice) -> some View {
        let low = (d.percent ?? 100) <= Int(threshold) && !d.charging
        let tint: Color = d.charging ? .green : (low ? .red : .white)
        return HStack(spacing: 10) {
            Image(systemName: d.icon).font(.system(size: 14)).frame(width: 22).foregroundStyle(.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let det = d.detail { Text(det).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let p = d.percent {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(tint).frame(width: max(4, g.size.width * CGFloat(p) / 100))
                    }.frame(height: 6).frame(maxHeight: .infinity)
                }.frame(width: 120, height: 14)
                HStack(spacing: 2) {
                    if d.charging { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.green) }
                    Text("%\(p)").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(low ? .red : .white)
                }.frame(width: 52, alignment: .trailing)
            } else {
                Text("pil bilgisi vermiyor").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.07)))
    }
}
