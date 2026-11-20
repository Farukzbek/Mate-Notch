import AppKit
import SwiftUI
import Combine

// MARK: - Mate: kapalı notch'un alt kenarından sarkan küçük arkadaş (Ayarlar › Maskot'tan açılır)

enum BuddyKey {
    static let on = "buddyOn", wave = "buddyWave", grab = "buddyGrab", music = "buddyMusic"
    static let battery = "buddyBattery", phones = "buddyHeadphones", timer = "buddyTimer", sleep = "buddySleep"
    static let freq = "buddyFreq", hud = "buddyHud", events = "buddyEvents"
    static func flag(_ k: String) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? true }
}

final class BuddyService: ObservableObject {
    static let shared = BuddyService()

    // Poz durumu (BuddyView bunları çizer)
    @Published var blink = false
    @Published var glance: CGFloat = 0          // −1…1 göz kayması
    @Published var waving = false
    @Published var reach: CGFloat = 0           // 0…1 sağ elin uzanması
    @Published var paper = false                // elde/yanda kağıt
    @Published var paperHeld = false
    @Published var hop: CGFloat = 0             // yukarı sıçrama (pt)
    @Published var tired = false
    @Published var phones = false
    @Published var asleep = false
    @Published var happy = false                // ağız açık
    @Published var mood = 0                     // 0 yok, 1 sessiz, 2 sesli (coşku), 3 gözü kısık, 4 karanlık
    @Published var previewing = false           // ayar kapalıyken önizleme

    private var cancellables = Set<AnyCancellable>()
    private var busy = false
    private var tiredWork: DispatchWorkItem?
    private var phonesWork: DispatchWorkItem?
    private var moodWork: DispatchWorkItem?

    var enabled: Bool { UserDefaults.standard.bool(forKey: BuddyKey.on) }
    var bobbing: Bool { BuddyKey.flag(BuddyKey.music) && MediaService.shared.isPlaying && !asleep }

    func start() {
        // Kopyalanınca uzanıp alır
        ClipboardService.shared.$justCopied.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] v in
            if v { self?.grab() }
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: .timerFinished, object: nil, queue: .main) { [weak self] _ in self?.jump() }
        scheduleBlink()
        scheduleIdleLife()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.checkSleep() }
    }

    // MARK: Önizleme / tepki

    /// Ayarlardaki "Dene" düğmeleri: maskot kapalıysa da birkaç saniye görünür.
    func preview(_ run: @escaping () -> Void) {
        previewing = true
        NotchController.shared.previewCollapsed(editing: true)               // notch kapanır, maskot görünür
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { run() }
        NotchController.shared.previewCollapsed(editing: false, hold: 8)    // 8 sn kapalı kalır, sonra ayar önizlemesi için açılır
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { self.previewing = false }
    }

    private var active: Bool { enabled || previewing }

    func wave() {
        guard active, !busy, !asleep else { return }
        busy = true
        happy = true
        withAnimation(.easeOut(duration: 0.25)) { waving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.3)) { self.waving = false }
            self.happy = false; self.busy = false
        }
    }

    func grab() {
        guard active, BuddyKey.flag(BuddyKey.grab) || previewing, !busy, !asleep else { return }
        busy = true
        paperHeld = false
        withAnimation(.easeOut(duration: 0.2)) { paper = true }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72).delay(0.2)) { reach = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { self.paperHeld = true }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.85)) { reach = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.25)) { self.paper = false }
            self.paperHeld = false; self.happy = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { self.happy = false; self.busy = false }
    }

    func jump() {
        guard active, BuddyKey.flag(BuddyKey.timer) || previewing, !asleep else { return }
        celebrate(times: 3)
    }

    enum Event { case meeting, download, focus }

    /// Toplantı yaklaşıyor (!), indirme bitti (zıplar), Odak açıldı (sakin, gözleri kapalı).
    func event(_ e: Event) {
        guard active, BuddyKey.flag(BuddyKey.events) || previewing, !asleep else { return }
        switch e {
        case .download: celebrate(times: 2)
        case .meeting: setMood(5, for: 4.5)
        case .focus: setMood(7, for: 3.5)
        }
    }

    private func setMood(_ m: Int, for secs: Double) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { mood = m }
        moodWork?.cancel()
        let w = DispatchWorkItem { withAnimation(.easeOut(duration: 0.3)) { self.mood = 0 } }
        moodWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: w)
    }

    private func celebrate(times: Int) {
        happy = true
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                withAnimation(.easeOut(duration: 0.2)) { self.hop = 7 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.easeIn(duration: 0.2)) { self.hop = 0 } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(times) + 0.2) { self.happy = false }
    }

    func headphones() {
        guard active, BuddyKey.flag(BuddyKey.phones) || previewing else { return }
        wake()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { phones = true }
        phonesWork?.cancel()
        let w = DispatchWorkItem { withAnimation(.easeOut(duration: 0.3)) { self.phones = false } }
        phonesWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 9, execute: w)
    }

    /// Ses/parlaklık uç noktalarında (sessiz, tam ses, tam/sıfır parlaklık) kısa tepki.
    func hudReact(_ k: HUDService.Kind, level: Double, muted: Bool) {
        guard active, BuddyKey.flag(BuddyKey.hud) || previewing, !asleep else { return }
        var m = 0
        switch k {
        case .volume: if muted || level <= 0.001 { m = 1 } else if level >= 0.99 { m = 2 }
        case .brightness: if level >= 0.99 { m = 3 } else if level <= 0.001 { m = 4 }
        case .keyboard: break
        }
        guard m != 0 else { return }
        setMood(m, for: 2.2)
    }

    func lowBattery() {
        guard active, BuddyKey.flag(BuddyKey.battery) || previewing else { return }
        wake()
        withAnimation(.easeInOut(duration: 0.4)) { tired = true }
        tiredWork?.cancel()
        let w = DispatchWorkItem { withAnimation(.easeInOut(duration: 0.4)) { self.tired = false } }
        tiredWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: w)
    }

    // MARK: Yaşam belirtileri

    private func scheduleBlink() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2.5...6)) { [weak self] in
            guard let self else { return }
            if self.active {
                self.blink = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.blink = false }
            }
            self.scheduleBlink()
        }
    }

    private func scheduleIdleLife() {
        let range: ClosedRange<Double>
        switch UserDefaults.standard.string(forKey: BuddyKey.freq) ?? "normal" {
        case "rare": range = 150...300
        case "often": range = 25...70
        default: range = 60...150
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: range)) { [weak self] in
            guard let self else { return }
            if self.active, !self.busy, !self.asleep {
                if BuddyKey.flag(BuddyKey.wave), Bool.random() { self.wave() } else { self.lookAround() }
            }
            self.scheduleIdleLife()
        }
    }

    private func lookAround() {
        withAnimation(.easeInOut(duration: 0.3)) { glance = Bool.random() ? 1 : -1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.easeInOut(duration: 0.3)) { self.glance = 0 } }
    }

    private func checkSleep() {
        guard active, BuddyKey.flag(BuddyKey.sleep) else { if asleep { wake() }; return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle > 300, !asleep, !busy { withAnimation(.easeInOut(duration: 0.6)) { asleep = true } }
        else if idle < 5, asleep { wake() }
    }

    func wake() { if asleep { withAnimation(.easeInOut(duration: 0.3)) { asleep = false } } }
}

// MARK: - Çizim (notch'un sağ kanadında: yuvarlak yüz yok, yalnızca göz ve ağız)

struct BuddyView: View {
    @ObservedObject var b = BuddyService.shared
    private let ink = Color(red: 0.96, green: 0.94, blue: 0.89)     // siyah notch üzerinde açık renk çizgiler

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bob: CGFloat = b.bobbing ? CGFloat(sin(t * 5.4)) * 1.3 : b.asleep ? CGFloat(sin(t * 1.1)) * 0.6 : CGFloat(sin(t * 1.5)) * 0.4
            let cy = 16 + bob - b.hop
            ZStack(alignment: .topLeading) {
                if b.paper {
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 7, height: 9)
                        .overlay(VStack(spacing: 1.5) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(.gray.opacity(0.6)).frame(width: 4, height: 0.8) } })
                        .rotationEffect(.degrees(b.paperHeld ? -12 : 8))
                        .position(x: b.paperHeld ? 36 - 10 * (1 - b.reach) : 42, y: b.paperHeld ? 22 - 5 * (1 - b.reach) : 24)
                }
                ZStack {
                    eyes(t)
                    mouth
                    if b.phones { headphones }
                    if b.tired { sweat }
                }
                .frame(width: 26, height: 22)
                .position(x: 21 + (b.mood == 2 ? CGFloat(sin(t * 38)) * 0.9 : 0), y: cy)
                if b.mood == 5 {
                    Text("!").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.3))
                        .position(x: 37, y: 5 + CGFloat(sin(t * 9)) * 1.2)
                }
                hand(t: t)
                if b.asleep { zzz(t) }
            }
            .frame(width: 46, height: 32)
        }
        .frame(width: 46, height: 32)
        .allowsHitTesting(false)
    }

    private func eyes(_ t: Double) -> some View {
        let shut = b.blink || b.asleep
        let open: CGFloat = shut || b.mood == 4 || b.mood == 7 ? 0.12 : (b.tired ? 0.45 : b.mood == 3 ? 0.3 : b.mood == 2 || b.mood == 5 ? 1.25 : 1)
        return HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { _ in Capsule().fill(ink).frame(width: 3, height: 5).scaleEffect(y: open) }
        }
        .offset(x: (b.mood == 5 ? CGFloat(sin(t * 6)) : b.glance) * 2, y: -3)
    }

    @ViewBuilder private var mouth: some View {
        if b.asleep { Circle().fill(ink).frame(width: 2.6, height: 2.6).offset(y: 5) }
        else if b.mood == 5 { Circle().fill(ink).frame(width: 3.6, height: 3.6).offset(y: 5) }
        else if b.mood == 1 { Capsule().fill(ink).frame(width: 7, height: 1.6).offset(y: 5) }
        else if b.mood == 2 { Capsule().fill(ink).frame(width: 9, height: 6).offset(y: 4.5) }
        else if b.mood == 3 { Capsule().fill(ink).frame(width: 7, height: 1.6).offset(y: 5).rotationEffect(.degrees(-6)) }
        else if b.happy { Capsule().fill(ink).frame(width: 8, height: 5).offset(y: 4.5) }
        else if b.tired { Capsule().fill(ink).frame(width: 6, height: 1.6).offset(y: 5) }
        else { SmileShape().stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 9, height: 3.4).offset(y: 4.4) }
    }

    private var headphones: some View {
        let c = Color.white.opacity(0.55)
        return ZStack {
            Circle().trim(from: 0.5, to: 1).stroke(c, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 21, height: 21).offset(y: -1)
            RoundedRectangle(cornerRadius: 1.6).fill(c).frame(width: 3.6, height: 7.5).offset(x: -10.5, y: 0.5)
            RoundedRectangle(cornerRadius: 1.6).fill(c).frame(width: 3.6, height: 7.5).offset(x: 10.5, y: 0.5)
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private var sweat: some View {
        Circle().fill(Color(red: 0.55, green: 0.78, blue: 0.95)).frame(width: 3.4, height: 4.2).offset(x: 11, y: -7)
    }

    private func zzz(_ t: Double) -> some View {
        let p = CGFloat((t.truncatingRemainder(dividingBy: 3)) / 3)
        return Text("z").font(.system(size: 6 + p * 3, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.75 - Double(p) * 0.6))
            .position(x: 33 + p * 5, y: 8 - p * 6)
    }

    /// El: sistemin kendi el simgesi (temiz çizgiler). Sallarken bilekten sağa-sola döner, uzanırken kağıda gider.
    @ViewBuilder private func hand(t: Double) -> some View {
        if b.waving {
            Image(systemName: "hand.wave.fill").font(.system(size: 12, weight: .regular)).foregroundStyle(ink)
                .scaleEffect(x: -1, y: 1)                                  // simge sol eldir; sağ el olması için aynalanır
                .rotationEffect(.degrees(sin(t * 11) * 16), anchor: .bottom)
                .position(x: 38, y: 12)
        } else if b.reach > 0.001 {
            Image(systemName: "hand.raised.fill").font(.system(size: 11, weight: .regular)).foregroundStyle(ink)
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(-20))
                .position(x: 33 + 7 * b.reach, y: 16 + 5 * b.reach)
        }
    }
}

struct SmileShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        return p
    }
}

// MARK: - Ayarlar bölümü

struct BuddySettingsSection: View {
    @AppStorage(BuddyKey.on) var on = false
    @AppStorage(BuddyKey.wave) var wave = true
    @AppStorage(BuddyKey.grab) var grab = true
    @AppStorage(BuddyKey.music) var music = true
    @AppStorage(BuddyKey.battery) var battery = true
    @AppStorage(BuddyKey.phones) var phones = true
    @AppStorage(BuddyKey.timer) var timer = true
    @AppStorage(BuddyKey.sleep) var sleep = true
    @AppStorage(BuddyKey.freq) var freq = "normal"
    @AppStorage(BuddyKey.hud) var hudReact = true
    @AppStorage(BuddyKey.events) var events = true
    private let buddy = BuddyService.shared

    var body: some View {
        Group { content }.collapsesNotch()
    }

    @ViewBuilder private var content: some View {
        Toggle("Maskotu göster (kapalı notch'tan sarkan küçük arkadaş)", isOn: $on)
        Group {
            row("Ara sıra el sallasın", $wave) { buddy.wave() }
            row("Bir şey kopyalanınca uzanıp alsın", $grab) { buddy.grab() }
            row("Müzik çalarken ritim tutsun", $music, nil)
            row("Pil azalınca yorgun görünsün", $battery) { buddy.lowBattery() }
            row("Kulaklık bağlanınca kulaklık taksın", $phones) { buddy.headphones() }
            row("Zamanlayıcı bitince zıplasın", $timer) { buddy.jump() }
            row("Bir süre işlem yapılmayınca uyusun", $sleep, nil)
            row("Ses ve parlaklık uç noktalarında tepki versin", $hudReact) { buddy.hudReact(.volume, level: 1, muted: false) }
            row("Toplantı, indirme ve Odak olaylarına tepki versin", $events) { buddy.event(.meeting) }
            Picker("Canlılık", selection: $freq) {
                Text("Az").tag("rare"); Text("Normal").tag("normal"); Text("Sık").tag("often")
            }
        }
        .disabled(!on)
        Text("Maskot yalnızca notch kapalıyken görünür. Her davranışı ayrı ayrı kapatabilirsin; \"Dene\" maskot kapalıyken de birkaç saniye gösterir.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func row(_ title: LocalizedStringKey, _ bind: Binding<Bool>, _ demo: (() -> Void)?) -> some View {
        HStack {
            Toggle(title, isOn: bind)
            if let demo { Button("Dene") { buddy.preview(demo) }.buttonStyle(.link).disabled(!bind.wrappedValue) }
        }
    }
}
