import AppKit
import SwiftUI

// MARK: - Özellik turu: ilk açılışta (ve sonradan menüden) özellikleri tek tek açıp deneme, atlama

struct TourStep: Identifiable {
    let id: String
    let icon: String
    let title: String
    let text: String
    let keys: [String]                  // açılıp kapanan ayarlar (hepsi birlikte)
    var demo: (() -> Void)? = nil       // "Dene" düğmesi: notch'ta örnek gösterir
}

enum TourCatalog {
    static func demoBanner(_ icon: String, _ title: String, _ sub: String?, _ tint: Color) {
        NotchController.shared.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            BannerService.shared.post(NotchBanner(icon: icon, title: title, subtitle: sub, tint: tint), duration: 4)
        }
    }

    static var steps: [TourStep] { [
        TourStep(id: "lyrics", icon: "quote.bubble", title: L("Şarkı sözleri"),
                 text: L("Çalan şarkının senkron sözleri kapalı notch'ta ve açık notch'taki müzik kartında görünür. Sözler lrclib.net'ten gelir."),
                 keys: [Pref.lyricsEnabled, Pref.lyricsInNotch]),
        TourStep(id: "hud", icon: "speaker.wave.2.fill", title: L("Ses ve parlaklık göstergesi"),
                 text: L("Ses, parlaklık ve klavye ışığı değişince macOS'un ortadaki karesi yerine notch'ta şık bir gösterge çıkar. Erişilebilirlik izni verirsen macOS'un kendi göstergesi de gizlenir."),
                 keys: [Pref.hudVolume, Pref.hudBrightness, Pref.hudKeyboard, Pref.hudHideSystem],
                 demo: { NotchController.shared.close(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { HUDService.shared.show(.volume, level: 0.6, force: true) } }),
        TourStep(id: "lowbattery", icon: "battery.25", title: L("Düşük pil uyarısı"),
                 text: L("Mac'in ya da Bluetooth cihazların (kulaklık, fare…) pili azalınca notch'ta uyarı çıkar."),
                 keys: [Pref.lowBatteryAlert, Pref.lowBatteryDevices],
                 demo: { demoBanner("battery.25", L("Pil azalıyor"), "%20", .orange) }),
        TourStep(id: "bluetooth", icon: "headphones", title: L("Kulaklık bağlanınca bildir"),
                 text: L("Bluetooth kulaklık bağlanınca adı ve pil durumu (AirPods dahil) kısa süre görünür."),
                 keys: [Pref.bannerBluetooth],
                 demo: { demoBanner("headphones", "AirPods Pro", L("Bağlandı · %85"), .green) }),
        TourStep(id: "calendar", icon: "calendar", title: L("Takvim ve toplantılar"),
                 text: L("Ana Sayfa'da sıradaki etkinlik görünür; toplantıda Katıl düğmesi çıkar ve başlamadan 5 dk önce uyarır."),
                 keys: [Pref.showCalendar, Pref.calEvent, Pref.meetingAlert],
                 demo: { demoBanner("video.fill", L("Toplantı"), L("5 dk sonra"), .green) }),
        TourStep(id: "privacy", icon: "camera.fill", title: L("Kamera / mikrofon göstergesi"),
                 text: L("Kamera ya da mikrofon kullanılırken notch'ta küçük bir gösterge çıkar; kimin dinlediğini hep bilirsin."),
                 keys: [Pref.privacyIndicator]),
        TourStep(id: "focus", icon: "moon.fill", title: L("Odak durumu"),
                 text: L("Odak (Rahatsız Etmeyin) açıkken notch'ta ay simgesi gösterir. macOS bir kez izin sorar."),
                 keys: [Pref.focusIndicator]),
        TourStep(id: "downloads", icon: "arrow.down.circle.fill", title: L("İndirme ilerlemesi"),
                 text: L("İndirilenler klasörüne inen dosyaların ilerlemesi notch'ta görünür. macOS bir kez izin sorar."),
                 keys: [Pref.downloadIndicator],
                 demo: { demoBanner("arrow.down.circle.fill", L("İndirme tamamlandı"), "Rapor.pdf", .blue) }),
        TourStep(id: "weather", icon: "cloud.sun.fill", title: L("Hava durumu"),
                 text: L("Ana Sayfa'da seçtiğin şehrin hava durumu görünür. Konumun kullanılmaz, yalnızca şehir adı gönderilir."),
                 keys: [Pref.weatherEnabled]),
        TourStep(id: "ai", icon: "sparkles", title: L("Yapay zeka"),
                 text: L("Metni özetle, düzelt, çevir ya da bir şey sor. Varsayılan olarak cihaz içi Apple modeli çalışır; istersen bulut model bağlarsın."),
                 keys: [Pref.showAI]),
        TourStep(id: "updates", icon: "arrow.triangle.2.circlepath", title: L("Otomatik güncelleme"),
                 text: L("Yeni sürüm çıkınca doğrulanıp kendiliğinden kurulur ve uygulama yeniden başlar."),
                 keys: [Pref.autoUpdateInstall]),
    ] }
}

struct TourView: View {
    let onDone: () -> Void
    private let steps = TourCatalog.steps
    @State private var index = 0
    @State private var refresh = 0
    @State private var skipped = Set<String>()

    private var step: TourStep { steps[index] }
    private func isOn(_ s: TourStep) -> Bool { _ = refresh; return UserDefaults.standard.bool(forKey: s.keys[0]) }
    private func set(_ s: TourStep, _ on: Bool) {
        for k in s.keys { UserDefaults.standard.set(on, forKey: k) }
        refresh += 1
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Özellik turu").font(.title2.weight(.semibold))
                Text("Her özelliği açıp kapatabilir, deneyebilir ya da atlayabilirsin. Hepsine Ayarlar'dan da ulaşırsın.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Divider()
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                Image(systemName: step.icon).font(.system(size: 34, weight: .medium))
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.quaternary))
                Text(step.title).font(.title3.weight(.semibold))
                Text(step.text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 400)
                HStack(spacing: 14) {
                    Toggle("Açık", isOn: Binding(get: { isOn(step) }, set: { set(step, $0) })).toggleStyle(.switch)
                    if let demo = step.demo { Button("Dene") { demo() } }
                }
                Spacer(minLength: 0)
            }
            .id(step.id)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 24)
            Divider()
            HStack {
                Button("Geri") { withAnimation(.smooth(duration: 0.25)) { index -= 1 } }.disabled(index == 0)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(steps.indices, id: \.self) { i in
                        Circle().fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button("Atla") { advance() }
                Button(index == steps.count - 1 ? "Bitti" : "İleri") { advance() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    private func advance() {
        if index == steps.count - 1 { onDone() } else { withAnimation(.smooth(duration: 0.25)) { index += 1 } }
    }
}

enum TourWindow {
    private static var window: NSWindow?
    static func show() {
        let v = TourView { window?.close() }
        let w = window ?? NSWindow(contentViewController: NSHostingController(rootView: v))
        w.contentViewController = NSHostingController(rootView: v)    // her açılışta baştan başlar
        w.title = L("Mate Notch — Özellik turu")
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        window = w
        let vis = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        w.setFrame(NSRect(x: vis.midX - 270, y: vis.midY - 250, width: 540, height: 500), display: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - İlk açılışta dil seçimi (sihirbazdan önce; metinler bilerek iki dilli ve yerelleştirilmez)

struct LanguageChooser: View {
    let pick: (String) -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "globe").font(.system(size: 34, weight: .medium)).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(verbatim: "Dil seçin · Choose your language").font(.title3.weight(.semibold))
                Text(verbatim: "Sonra Ayarlar'dan değiştirebilirsin · You can change it later in Settings")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                langButton("Türkçe", "tr")
                langButton("English", "en")
            }
            Button { pick("auto") } label: { Text(verbatim: "Sistem diliyle devam et · Use system language") }
                .buttonStyle(.link)
        }
        .padding(28).frame(width: 460)
    }
    private func langButton(_ title: String, _ code: String) -> some View {
        Button { pick(code) } label: { Text(verbatim: title).font(.system(size: 15, weight: .semibold)).frame(width: 150, height: 40) }
            .buttonStyle(.borderedProminent).controlSize(.large)
    }
}

enum LanguageWindow {
    private static var window: NSWindow?
    static func show(then next: @escaping () -> Void) {
        let v = LanguageChooser { code in
            UserDefaults.standard.set(true, forKey: "langChosen")
            window?.close()
            if code == "auto" { AppLanguage.clearOverride(); next() }
            else if code == AppLanguage.effective { AppLanguage.setOverride(code); next() }   // zaten bu dilde: yeniden başlatmaya gerek yok
            else { AppLanguage.apply(code) }                                                    // yeniden başlar, sihirbaz seçilen dilde açılır
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: v))
        w.title = "Mate Notch"
        w.styleMask = [.titled]
        w.isReleasedWhenClosed = false
        window = w
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
