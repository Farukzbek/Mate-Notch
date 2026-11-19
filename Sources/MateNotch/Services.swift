import AppKit
import SwiftUI
import EventKit
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Media (Apple Music + Spotify)

enum Player: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var player: Player
}

final class MediaService: ObservableObject {
    static let shared = MediaService()
    @Published var track: Track?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var accent: Color = .white

    private var basePos: Double = 0
    private var baseDate = Date()
    private var lastKey = ""
    private let queue = DispatchQueue(label: "matenotch.media")
    private var timer: Timer?

    var position: Double {
        let p = isPlaying ? basePos + Date().timeIntervalSince(baseDate) : basePos
        return min(p, track?.duration ?? p)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let players = Player.allCases.filter { running.contains($0.rawValue) }
        guard !players.isEmpty else { apply(nil, artURL: nil); return }
        queue.async {
            var best: (Track, Bool, Double, String?)?
            for p in players {
                if let r = Self.query(p) {
                    if r.1 { best = r; break }
                    if best == nil { best = r }
                }
            }
            DispatchQueue.main.async { self.apply(best, artURL: best?.3) }
        }
    }

    /// Derlenmiş betikler önbellekte: her saniye baştan derlemek CPU'yu gereksiz yoruyordu.
    /// (Yalnızca `queue` üzerinde çağrılır, bu yüzden erişim seri.)
    private static var compiled: [String: NSAppleScript] = [:]

    private static func run(_ src: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let script: NSAppleScript
        if let c = compiled[src] { script = c }
        else {
            guard let s = NSAppleScript(source: src) else { return nil }
            s.compileAndReturnError(nil)
            if compiled.count > 40 { compiled.removeAll() }     // kontrol komutları (seek vb.) şişirmesin
            compiled[src] = s
            script = s
        }
        let r = script.executeAndReturnError(&err)
        return err == nil ? r : nil
    }

    private static func query(_ p: Player) -> (Track, Bool, Double, String?)? {
        let sep = "|~|"
        let script: String
        switch p {
        case .music:
            script = """
            tell application id "com.apple.Music"
              if player state is stopped then return ""
              set t to current track
              return (player state as string) & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & ((player position) as integer as string) & "\(sep)" & ((duration of t) as integer as string) & "\(sep)"
            end tell
            """
        case .spotify:
            script = """
            tell application id "com.spotify.client"
              if player state is stopped then return ""
              set t to current track
              return (player state as string) & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & ((player position) as integer as string) & "\(sep)" & (((duration of t) / 1000) as integer as string) & "\(sep)" & (artwork url of t)
            end tell
            """
        }
        guard let s = run(script)?.stringValue, !s.isEmpty else { return nil }
        let f = s.components(separatedBy: sep)
        guard f.count >= 6 else { return nil }
        let playing = f[0].lowercased().contains("play")
        let track = Track(title: f[1], artist: f[2], album: f[3],
                          duration: Double(f[5]) ?? 0, player: p)
        return (track, playing, Double(f[4]) ?? 0, f.count > 6 && !f[6].isEmpty ? f[6] : nil)
    }

    private func apply(_ r: (Track, Bool, Double, String?)?, artURL: String?) {
        guard let (t, playing, pos, art) = r else {
            if track != nil { track = nil; isPlaying = false; artwork = nil; lastKey = "" }
            return
        }
        basePos = pos
        baseDate = Date()
        if isPlaying != playing { isPlaying = playing }
        if track != t { track = t }
        let key = "\(t.player.rawValue)|\(t.title)|\(t.artist)"
        if key != lastKey {
            lastKey = key
            artwork = nil
            loadArtwork(t, url: art, key: key)
        }
    }

    private func loadArtwork(_ t: Track, url: String?, key: String) {
        queue.async {
            var img: NSImage?
            if t.player == .spotify, let u = url, let url = URL(string: u),
               let data = try? Data(contentsOf: url) {
                img = NSImage(data: data)
            } else if t.player == .music {
                let d = Self.run("tell application id \"com.apple.Music\" to return data of artwork 1 of current track")
                if let data = d?.data { img = NSImage(data: data) }
            }
            let color = img?.averageColor()
            DispatchQueue.main.async {
                guard self.lastKey == key else { return }
                self.artwork = img
                self.accent = color ?? .white
            }
        }
    }

    // Controls
    func togglePlay() { isPlaying.toggle(); basePos = position; baseDate = Date(); send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }
    func seek(to s: Double) {
        basePos = s; baseDate = Date()
        guard let p = track?.player else { return }
        queue.async { _ = Self.run("tell application id \"\(p.rawValue)\" to set player position to \(Int(s))") }
    }

    private func send(_ cmd: String) {
        guard let p = track?.player else { return }
        queue.async {
            _ = Self.run("tell application id \"\(p.rawValue)\" to \(cmd)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.poll() }
        }
    }
}

// MARK: - Battery

final class BatteryService: ObservableObject {
    static let shared = BatteryService()
    @Published var level = 100
    @Published var pluggedIn = false
    @Published var charging = false
    @Published var flash = false
    private var flashWork: DispatchWorkItem?

    func start() {
        refresh(initial: true)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ c in
            guard let c else { return }
            let s = Unmanaged<BatteryService>.fromOpaque(c).takeUnretainedValue()
            DispatchQueue.main.async { s.refresh() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    func refresh(initial: Bool = false) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let ch = d[kIOPSIsChargingKey] as? Bool ?? false
            let wasPlugged = pluggedIn
            level = cap; charging = ch; pluggedIn = ac
            if !initial && ac && !wasPlugged { showFlash() }
        }
        PowerAlertService.shared.check()
    }

    private func showFlash() {
        flash = true
        flashWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.flash = false }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: w)
    }
}

// MARK: - Timer

extension Notification.Name { static let timerFinished = Notification.Name("matenotch.timerFinished") }

final class TimerService: ObservableObject {
    static let shared = TimerService()
    @Published var total: TimeInterval = 25 * 60
    @Published var remaining: TimeInterval = 25 * 60
    @Published var running = false
    /// Pomodoro: 25 dk odak → 5 dk mola, her 4. molada 15 dk; süre dolunca sıradaki aşama kendiliğinden başlar.
    @Published var pomodoro = UserDefaults.standard.bool(forKey: "pomodoro") {
        didSet {
            UserDefaults.standard.set(pomodoro, forKey: "pomodoro")
            if pomodoro { phaseBreak = false; round = 0; set(minutes: 25) } else { phaseBreak = false }
        }
    }
    @Published var phaseBreak = false
    @Published var round = 0
    private var end: Date?
    private var t: Timer?

    func set(minutes: Int) { pause(); total = Double(minutes * 60); remaining = total }

    private func nextPhase() {
        if phaseBreak { phaseBreak = false; total = 25 * 60 }
        else { round += 1; phaseBreak = true; total = (round % 4 == 0 ? 15 : 5) * 60 }
        remaining = total
        BannerService.shared.post(NotchBanner(icon: phaseBreak ? "cup.and.saucer.fill" : "brain.head.profile",
                                              title: phaseBreak ? L("Mola zamanı") : L("Odaklanma zamanı"),
                                              subtitle: L("\(Int(total / 60)) dk"), tint: phaseBreak ? .green : .orange))
        start()
    }

    func start() {
        guard !running else { return }
        if remaining <= 0 { remaining = total }
        end = Date().addingTimeInterval(remaining)
        running = true
        t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() { running = false; t?.invalidate(); t = nil }
    func reset() { pause(); remaining = total }

    private func tick() {
        guard let end else { return }
        let r = max(0, end.timeIntervalSinceNow)
        if Int(r.rounded(.up)) != Int(remaining.rounded(.up)) || r == 0 { remaining = r }
        if r <= 0 {
            pause()
            NSSound(named: "Glass")?.play()
            if pomodoro { nextPhase() } else { NotificationCenter.default.post(name: .timerFinished, object: nil) }
        }
    }

    var label: String { formatTime(remaining.rounded(.up)) }
}

// MARK: - Clipboard

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
    var pinned = false
}

final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    @Published var items: [ClipItem] = []
    @Published var justCopied = false
    @Published var lastPreview = ""
    @Published var lastColor: Color?
    private var hideWork: DispatchWorkItem?
    private var count = NSPasteboard.general.changeCount
    private var timer: Timer?
    private static let pinKey = "clipPins"
    private let blocked = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                           "com.agilebits.onepassword", "com.typeit4me.clipping"]

    func start() {
        items = (UserDefaults.standard.stringArray(forKey: Self.pinKey) ?? []).map { ClipItem(text: $0, date: Date(), pinned: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.check() }
    }

    /// Sabitlenenler listenin başında kalır, en eski silinirken ve "Tümünü sil"de korunur, yeniden başlatınca da durur.
    private func insertNew(_ s: String) {
        let wasPinned = items.first { $0.text == s }?.pinned ?? false
        items.removeAll { $0.text == s }
        let at = items.firstIndex { !$0.pinned } ?? items.count
        items.insert(ClipItem(text: s, date: Date(), pinned: wasPinned), at: wasPinned ? 0 : at)
        while items.count > 30, let i = items.lastIndex(where: { !$0.pinned }) { items.remove(at: i) }
        savePins()
    }
    private func savePins() { UserDefaults.standard.set(items.filter(\.pinned).map(\.text), forKey: Self.pinKey) }
    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(of: item) else { return }
        var it = items.remove(at: i)
        it.pinned.toggle()
        let at = it.pinned ? 0 : (items.firstIndex { !$0.pinned } ?? items.count)
        items.insert(it, at: at)
        savePins()
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != count else { return }
        count = pb.changeCount
        let types = (pb.types ?? []).map(\.rawValue)
        let secret = types.contains(where: { blocked.contains($0) })    // şifre yöneticileri
        if types.isEmpty { return }
        lastColor = nil
        // Geri bildirim: ne kopyalandıysa "Kopyalandı" bandı göster (gizli kopyada önizleme yok)
        if secret { flash("") }
        else if let t = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            flash(t.replacingOccurrences(of: "\n", with: " "))
        } else if types.contains("public.file-url") { flash("Dosya") }
        else if types.contains("public.png") || types.contains("public.tiff") { flash(L("Görsel")) }
        else { flash("") }
        if secret { return }
        guard let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s.count < 5000 else { return }
        insertNew(s)
    }

    private func flash(_ preview: String) {
        lastPreview = String(preview.prefix(40))
        justCopied = true
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.justCopied = false }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: w)
    }

    /// Uygulamanın kendi kopyalaması (ör. renk seçici): panoya yazar, geçmişe ekler, "Kopyalandı" bandını gösterir.
    func copyText(_ text: String, color: Color? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        count = pb.changeCount
        insertNew(text)
        lastColor = color
        flash(text)
    }

    func remove(_ item: ClipItem) { items.removeAll { $0 == item }; savePins() }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        count = pb.changeCount
        // Satır yerinde kalır (başa taşınmaz): "Kopyalandı" geri bildirimi tıklanan satırda görünsün.
    }

    func clear() { items.removeAll { !$0.pinned } }
}

// MARK: - Shelf

final class ShelfService: ObservableObject {
    static let shared = ShelfService()
    @Published var urls: [URL] = []
    private let key = "shelfPaths"
    private let datesKey = "shelfDates"
    private var dates: [String: Double] = [:]    // yol → rafa eklenme zamanı

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        dates = UserDefaults.standard.dictionary(forKey: datesKey) as? [String: Double] ?? [:]
        urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        expire()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.expire() }
    }

    func add(_ new: [URL]) {
        for u in new where !urls.contains(u) { urls.insert(u, at: 0); dates[u.path] = Date().timeIntervalSince1970 }
        save()
    }
    func remove(_ u: URL) { urls.removeAll { $0 == u }; save() }
    func clear() { urls.removeAll(); save() }
    /// "Rafı şu kadar günde bir temizle" ayarı: yalnızca raftaki kısayol kalkar, dosyaya dokunulmaz.
    func expire() {
        let days = UserDefaults.standard.integer(forKey: "shelfExpireDays")
        guard days > 0 else { return }
        let limit = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let old = urls.filter { (dates[$0.path] ?? Date().timeIntervalSince1970) < limit }
        guard !old.isEmpty else { return }
        urls.removeAll { old.contains($0) }
        save()
    }
    private func save() {
        dates = dates.filter { k, _ in urls.contains { $0.path == k } }
        for u in urls where dates[u.path] == nil { dates[u.path] = Date().timeIntervalSince1970 }
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
        UserDefaults.standard.set(dates, forKey: datesKey)
    }
}

// MARK: - Calendar

final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published var events: [EKEvent] = []
    @Published var denied = false
    private let store = EKEventStore()
    private var timer: Timer?

    /// İzin açılışta kendiliğinden İSTENMEZ (sihirbaz ister); verilmişse etkinlikler okunur.
    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess(_ done: (() -> Void)? = nil) {
        store.requestFullAccessToEvents { ok, _ in
            DispatchQueue.main.async { self.denied = !ok; self.refresh(); done?() }
        }
    }

    func start() {
        denied = !Self.authorized
        if Self.authorized { refresh() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Toplantı bağlantısı: etkinliğin URL'si, konumu ya da notlarında Zoom/Meet/Teams/Webex/Whereby adresi.
    static func meetingURL(_ e: EKEvent) -> URL? {
        let pattern = #"https?://[^\s<>"']*(zoom\.us|zoomgov\.com|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|around\.co|gather\.town)[^\s<>"']*"#
        let hay = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard let r = hay.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return URL(string: String(hay[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)")))
    }

    private var alerted = Set<String>()
    /// "Toplantı N dk sonra" bandı: bağlantılı toplantılar için başlamadan ~5 dk önce bir kez.
    private func meetingAlert() {
        guard UserDefaults.standard.bool(forKey: Pref.meetingAlert) else { return }
        for e in events {
            let mins = e.startDate.timeIntervalSinceNow / 60
            let key = (e.eventIdentifier ?? e.title ?? "") + "\(e.startDate.timeIntervalSince1970)"
            guard mins > 0, mins <= 5.5, Self.meetingURL(e) != nil, !alerted.contains(key) else { continue }
            alerted.insert(key)
            BannerService.shared.post(NotchBanner(icon: "video.fill", title: e.title ?? L("Toplantı"),
                                                  subtitle: L("\(max(1, Int(mins.rounded()))) dk sonra"), tint: .green), duration: 6)
        }
    }

    func refresh() {
        denied = !Self.authorized
        guard Self.authorized else { events = []; return }
        defer { meetingAlert() }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = Array(store.events(matching: pred).filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }.prefix(3))
    }
}

// MARK: - Stats

final class StatsService: ObservableObject {
    static let shared = StatsService()
    @Published var cpu: Double = 0
    @Published var mem: Double = 0
    @Published var disk: Double = 0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 40)
    private var prev: (Double, Double)?   // (busy, total)
    private var timer: Timer?
    private var users = 0

    func retain() {
        users += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
    }
    func release() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil; prev = nil }
    }

    private func sample() {
        // CPU
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if r == KERN_SUCCESS {
            let u = Double(info.cpu_ticks.0), s = Double(info.cpu_ticks.1)
            let i = Double(info.cpu_ticks.2), n = Double(info.cpu_ticks.3)
            let busy = u + s + n, total = busy + i
            if let p = prev, total > p.1 {
                cpu = min(1, max(0, (busy - p.0) / (total - p.1)))
                cpuHistory.append(cpu); cpuHistory.removeFirst()
            }
            prev = (busy, total)
        }
        // Memory
        var vm = vm_statistics64()
        var vc = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vc)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vc)
            }
        }
        if vr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            mem = min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
        }
        // Disk
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 {
            disk = 1 - Double(free) / Double(total)
        }
    }
}

// MARK: - Caffeinate

final class CaffeinateService: ObservableObject {
    static let shared = CaffeinateService()
    @Published var active = false
    private var id: IOPMAssertionID = 0

    func toggle() {
        if active {
            IOPMAssertionRelease(id); active = false
        } else {
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                L("Mate Notch uyanık tut") as CFString, &id)
            active = (r == kIOReturnSuccess)
        }
    }
}

// MARK: - AirDrop

enum AirDrop {
    /// Sistemin AirDrop paylaşımını açar: alıcı seçici belirir, dosyalar seçilen cihaza gider.
    private static var last = Date.distantPast
    static func send(_ urls: [URL]) {
        // Aynı bırakma birden fazla yoldan gelirse (hedef + izleyici) iki kez açılmasın
        guard Date().timeIntervalSince(last) > 1.2 else { return }
        last = Date()
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: files) else { NSSound.beep(); return }
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
    }

    /// Bırakılan sağlayıcılardan (NSItemProvider) dosya adreslerini toplayıp tek seferde gönderir.
    static func send(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { send(urls) }
    }
}
