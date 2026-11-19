import AppKit
import SwiftUI
import Combine

// MARK: - Mate: kapalı notch'un alt kenarından sarkan küçük arkadaş (Ayarlar › Maskot'tan açılır)

enum BuddyKey {
    static let on = "buddyOn", wave = "buddyWave", grab = "buddyGrab", music = "buddyMusic"
    static let battery = "buddyBattery", phones = "buddyHeadphones", timer = "buddyTimer", sleep = "buddySleep"
    static let freq = "buddyFreq"
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
    @Published var previewing = false           // ayar kapalıyken önizleme

    private var cancellables = Set<AnyCancellable>()
    private var busy = false
    private var tiredWork: DispatchWorkItem?
    private var phonesWork: DispatchWorkItem?

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
        happy = true
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                withAnimation(.easeOut(duration: 0.2)) { self.hop = 7 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.easeIn(duration: 0.2)) { self.hop = 0 } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { self.happy = false }
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

// MARK: - Çizim (notch'un sağ kanadında küçük yüz)

struct BuddyView: View {
    @ObservedObject var b = BuddyService.shared
    private let face = Color(red: 0.96, green: 0.94, blue: 0.89)
    private let ink = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bob: CGFloat = b.bobbing ? CGFloat(sin(t * 5.4)) * 1.3 : b.asleep ? CGFloat(sin(t * 1.1)) * 0.6 : CGFloat(sin(t * 1.5)) * 0.4
            let hy = 16 + bob - b.hop
            ZStack(alignment: .topLeading) {
                if b.paper {
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 7, height: 9)
                        .overlay(VStack(spacing: 1.5) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(.gray.opacity(0.6)).frame(width: 4, height: 0.8) } })
                        .rotationEffect(.degrees(b.paperHeld ? -12 : 8))
                        .scaleEffect(b.paperHeld ? 1 - b.reach * 0.0 : 1)
                        .position(x: b.paperHeld ? 31 + 9 * b.reach : 41, y: b.paperHeld ? 18 + 7 * b.reach : 25)
                }
                arm(t: t, hy: hy)
                ZStack {
                    Circle().fill(face)
                    eyes
                    mouth
                    if b.phones { headphones }
                    if b.tired { sweat }
                }
                .frame(width: 20, height: 20)
                .position(x: 23, y: hy)
                if b.asleep { zzz(t) }
            }
            .frame(width: 46, height: 32)
        }
        .frame(width: 46, height: 32)
        .allowsHitTesting(false)
    }

    private var eyes: some View {
        let shut = b.blink || b.asleep
        let open: CGFloat = shut ? 0.12 : (b.tired ? 0.45 : 1)
        return HStack(spacing: 5.5) {
            ForEach(0..<2, id: \.self) { _ in Capsule().fill(ink).frame(width: 2.5, height: 4).scaleEffect(y: open) }
        }
        .offset(x: b.glance * 1.6, y: -1.5)
    }

    @ViewBuilder private var mouth: some View {
        if b.asleep { Circle().fill(ink).frame(width: 2.4, height: 2.4).offset(y: 5) }
        else if b.happy { Capsule().fill(ink).frame(width: 7, height: 4.4).offset(y: 4.6) }
        else if b.tired { Capsule().fill(ink).frame(width: 5.5, height: 1.4).offset(y: 5) }
        else { SmileShape().stroke(ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round)).frame(width: 8, height: 3.2).offset(y: 4.4) }
    }

    private var headphones: some View {
        ZStack {
            Circle().trim(from: 0.5, to: 1).stroke(Color(white: 0.22), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 19.5, height: 19.5).offset(y: -0.5)
            RoundedRectangle(cornerRadius: 1.6).fill(Color(white: 0.22)).frame(width: 3.6, height: 7.5).offset(x: -10, y: 1)
            RoundedRectangle(cornerRadius: 1.6).fill(Color(white: 0.22)).frame(width: 3.6, height: 7.5).offset(x: 10, y: 1)
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private var sweat: some View {
        Circle().fill(Color(red: 0.55, green: 0.78, blue: 0.95)).frame(width: 3.4, height: 4.2).offset(x: 8, y: -5.5)
    }

    private func zzz(_ t: Double) -> some View {
        let p = CGFloat((t.truncatingRemainder(dividingBy: 3)) / 3)
        return Text("z").font(.system(size: 6 + p * 3, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.75 - Double(p) * 0.6))
            .position(x: 34 + p * 5, y: 8 - p * 6)
    }

    @ViewBuilder private func arm(t: Double, hy: CGFloat) -> some View {
        if b.waving || b.reach > 0.001 {
            let shoulder = CGPoint(x: 31, y: hy + 2)
            let hand: CGPoint = b.reach > 0.001
                ? CGPoint(x: 31 + 10 * b.reach, y: hy + 2 + 8 * b.reach)
                : CGPoint(x: 36 + CGFloat(sin(t * 13)) * 3, y: 8 + CGFloat(cos(t * 13)) * 1.2)
            Path { p in p.move(to: shoulder); p.addLine(to: hand) }
                .stroke(face, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            Circle().fill(face).frame(width: 5.5, height: 5.5).position(hand)
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
