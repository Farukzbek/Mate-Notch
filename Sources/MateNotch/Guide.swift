import SwiftUI
import AppKit

// MARK: - Etkileşimli rehber: notch'un içinde, anlatılan öğeye küçük bir ışık karesi tutar, geri kalanını gölgeler, adım adım ilerler.

struct GuideStep: Identifiable {
    let id: String
    let target: String?          // guideTarget kimliği (nil: ortada kart)
    let tab: Tab?                // adım başlarken açılacak sekme (nil: değiştirme)
    let title: String
    let text: String
}

struct GuideFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension View {
    /// Rehberin bu öğeyi bulabilmesi için çerçevesini yayınlar (koordinat alanı: "notchSpace").
    func guideTarget(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: GuideFramesKey.self, value: [id: g.frame(in: .named("notchSpace"))])
        })
    }
}

final class GuideService: ObservableObject {
    static let shared = GuideService()
    @Published var active = false
    @Published var index = 0
    @Published var frames: [String: CGRect] = [:]
    private(set) var steps: [GuideStep] = []
    private var monitor: Any?

    var step: GuideStep? { steps.indices.contains(index) ? steps[index] : nil }

    static func catalog() -> [GuideStep] {
        let visible = Set(Tab.visible())
        var s: [GuideStep] = [
            GuideStep(id: "welcome", target: nil, tab: .home, title: L("Mate Notch'a hoş geldin"),
                      text: L("Özellikleri kısa bir rehberle tek tek göstereceğim. İstediğin an Atla'ya basabilirsin.")),
            GuideStep(id: "tabs", target: "tabs", tab: .home, title: L("Sekmeler"),
                      text: L("Üstteki sekmelerle Ana Sayfa, Raf, Pano, Zamanlayıcı ve Sistem arasında geçersin.")),
            GuideStep(id: "media", target: "media", tab: .home, title: L("Müzik ve sözler"),
                      text: L("Apple Music ve Spotify çalarken şarkı, kontroller ve senkron sözler burada. Sözler kayarsa − / + ile eşzamanla.")),
            GuideStep(id: "side", target: "side", tab: .home, title: L("Takvim ve hızlı düğmeler"),
                      text: L("Sıradaki etkinlik, hava durumu ve tek tıkla uyanık tut, odak zamanlayıcısı, ekran görüntüsü, renk seçici.")),
        ]
        func add(_ t: Tab, _ target: String, _ title: String, _ text: String, open: Bool = true) {
            if visible.contains(t) || t == .batteries { s.append(GuideStep(id: t.rawValue, target: target, tab: open ? t : nil, title: title, text: text)) }
        }
        add(.shelf, "tab.shelf", L("Raf"), L("Dosyaları notch'a bırak, sonra istediğin yere sürükle. Boşluk ile önizle, AirDrop ile gönder."))
        add(.clipboard, "tab.clipboard", L("Pano geçmişi"), L("Kopyaladıkların burada. Ara, sabitle, tek tıkla geri kopyala. Şifre yöneticisi kopyaları kaydedilmez."))
        add(.timer, "tab.timer", L("Zamanlayıcı"), L("Pomodoro ve geri sayım. Süre bitince notch açılır ve maskot zıplar."))
        add(.stats, "tab.stats", L("Sistem"), L("İşlemci, bellek, disk, ağ hızı ve seçtiğin şehirlerin saati."))
        add(.ai, "ai", L("Yapay zeka"), L("Metni özetle, düzelt, çevir ya da soru sor. Varsayılan olarak veriler Mac'inden çıkmaz."))
        s.append(GuideStep(id: "battery", target: "battery", tab: .home, title: L("Pil"),
                           text: L("Mac'in pili. Üzerine gelince bağlı kulaklık, fare ve klavyenin pilleri görünür.")))
        s.append(GuideStep(id: "settings", target: "settings", tab: .home, title: L("Ayarlar"),
                           text: L("Her şey burada: arama çubuğu ve 🌐 dil menüsüyle istediğin ayarı hemen bulursun.")))
        add(.notes, "bottom.notes", L("Notlar"), L("Hızlı not al; tıklayınca panoya kopyalanır, istersen Notlar uygulamasına aktar."))
        add(.mixer, "bottom.mixer", L("Ses mikseri"), L("Ses çalan her uygulamanın seviyesini ayrı ayarla; simgeye tıklayınca susturur."))
        add(.mirror, "bottom.mirror", L("Ayna"), L("Kameranı ayna gibi kullan, fotoğraf çek, halka ışığı aç. Kamera yalnızca bu sekme açıkken çalışır."), open: false)
        add(.shortcuts, "bottom.shortcuts", L("Kestirmeler"), L("Apple Kestirmeler'den seçtiğin kestirmeleri kendi simge ve renklerinle tek tıkla çalıştır."))
        s.append(GuideStep(id: "done", target: nil, tab: .home, title: L("Hazırsın!"),
                           text: L("Rehberi menü çubuğundaki simgeden ya da Ayarlar › Genel'den istediğin zaman yeniden başlatabilirsin.")))
        return s
    }

    /// İlk kurulumdan sonra bir kez.
    func startFirstTime() {
        guard !UserDefaults.standard.bool(forKey: "guideShown") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.start() }
    }

    func start() {
        steps = Self.catalog(); index = 0
        NotchState.shared.previewHold = true            // rehber sürerken notch açık kalır
        NotchController.shared.open()
        enter()
        withAnimation(.easeOut(duration: 0.25)) { active = true }
        installKeys()
    }

    private func enter() {
        if let t = step?.tab { withAnimation(.snappy(duration: 0.25)) { NotchState.shared.tab = t } }
    }

    func next() { if index >= steps.count - 1 { finish() } else { index += 1; enter() } }
    func back() { if index > 0 { index -= 1; enter() } }

    func finish() {
        UserDefaults.standard.set(true, forKey: "guideShown")
        withAnimation(.easeOut(duration: 0.25)) { active = false }
        NotchState.shared.previewHold = false
        NotchState.shared.tab = .home
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func installKeys() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.active else { return e }
            switch e.keyCode {
            case 53: self.finish(); return nil          // Esc
            case 124, 36: self.next(); return nil       // → / Enter
            case 123: self.back(); return nil           // ←
            default: return e
            }
        }
    }
}

/// Gölge + ışık karesi: dış dikdörtgen ile içindeki "delik" tek şekil; delik konumdan konuma yumuşakça kayar.
struct SpotShape: Shape {
    var rect: CGRect
    var includeOuter: Bool
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(rect.origin.x, rect.origin.y), .init(rect.size.width, rect.size.height)) }
        set { rect = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        if includeOuter { p.addRect(r) }
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 12, height: 12))
        return p
    }
}

struct GuideOverlay: View {
    @ObservedObject var guide = GuideService.shared
    private let cardW: CGFloat = 262
    private let cardH: CGFloat = 118
    private let cameraZone: CGFloat = 50          // üstteki kamera çentiği / sekme satırı: kart buraya girmez

    var body: some View {
        if guide.active, let step = guide.step {
            GeometryReader { geo in
                let size = geo.size
                let target = step.target.flatMap { guide.frames[$0] }.map { $0.insetBy(dx: -6, dy: -5) }
                let hole = target ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
                ZStack(alignment: .topLeading) {
                    SpotShape(rect: hole, includeOuter: true)
                        .fill(Color.black.opacity(0.66), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture { }                           // gölgeli alandaki tıklamalar altındaki öğelere ulaşmaz
                    SpotShape(rect: hole, includeOuter: false)
                        .stroke(.white.opacity(0.92), lineWidth: 1.6)
                        .shadow(color: .white.opacity(0.5), radius: 8)
                        .opacity(target == nil ? 0 : 1)
                        .allowsHitTesting(false)
                    card(step)
                        .position(cardCenter(size, target))
                }
                .animation(.spring(response: 0.55, dampingFraction: 0.88), value: hole)
                .animation(.spring(response: 0.55, dampingFraction: 0.88), value: guide.index)
            }
            .transition(.opacity)
        }
    }

    /// Kart notch'un yatay ortasında durur (kamera çentiğinin altında); hedefle çakışırsa aşağı/yukarı, o da olmazsa yana kayar.
    private func cardCenter(_ size: CGSize, _ hole: CGRect?) -> CGPoint {
        let cx = size.width / 2
        let top = cameraZone + cardH / 2
        let bottom = size.height - cardH / 2 - 30                // alt köşeler yuvarlak: kart köşeye taşmaz
        let mid = min(max((top + bottom) / 2, top), bottom)
        func rect(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - cardW / 2, y: y - cardH / 2, width: cardW, height: cardH) }
        guard let h = hole else { return CGPoint(x: cx, y: mid) }
        let minX = cardW / 2 + 28, maxX = size.width - cardW / 2 - 28
        let cands: [CGPoint] = [
            CGPoint(x: cx, y: mid), CGPoint(x: cx, y: bottom), CGPoint(x: cx, y: top),                    // ortada: orta, alt, üst
            CGPoint(x: maxX, y: mid), CGPoint(x: minX, y: mid),                                            // yana kayarak
            CGPoint(x: maxX, y: bottom), CGPoint(x: minX, y: bottom), CGPoint(x: maxX, y: top), CGPoint(x: minX, y: top),
        ]
        if let free = cands.first(where: { overlap(rect($0.x, $0.y), h) < 1 }) { return free }
        return cands.min { overlap(rect($0.x, $0.y), h) < overlap(rect($1.x, $1.y), h) } ?? cands[0]
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat { let i = a.intersection(b); return i.isNull ? 0 : i.width * i.height }

    private func card(_ step: GuideStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 13, weight: .bold))
                Text(step.text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true).lineLimit(4)
            }
            .id(step.id)
            .transition(.opacity)                       // içerik yumuşakça değişir; kart yerinde süzülür
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text("\(guide.index + 1) / \(guide.steps.count)").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
                Spacer()
                if guide.index < guide.steps.count - 1 {
                    Button { guide.finish() } label: { Text("Atla").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6)) }.buttonStyle(.plain)
                }
                if guide.index > 0 {
                    Button { guide.back() } label: { Text("Geri").font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(.white.opacity(0.14))) }.buttonStyle(.plain)
                }
                Button { guide.next() } label: {
                    Text(guide.index == guide.steps.count - 1 ? "Bitti" : "İleri").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).frame(height: 22).background(Capsule().fill(.white))
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: cardW, height: cardH, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .foregroundStyle(.white)
    }
}
