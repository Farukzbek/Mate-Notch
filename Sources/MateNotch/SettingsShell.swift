import SwiftUI

/// Ayarlar: üstte arama, altında kategori menüsü; bir kategoriye girince yalnızca onun bölümleri görünür.
/// Aramada eşleşen bölümler (başlık + anahtar sözcük) kategori fark etmeksizin alt alta gösterilir.
struct SettingsShell: View {
    let sectionView: (String) -> AnyView
    @State private var query = ""

    struct Category: Identifiable {
        let id: String, icon: String, title: String, sections: [String]
    }

    static var categories: [Category] { [
        Category(id: "look", icon: "paintbrush.fill", title: L("Görünüm ve maskot"), sections: ["look", "closedicon", "buddy"]),
        Category(id: "behavior", icon: "hand.tap.fill", title: L("Davranış ve sekmeler"), sections: ["behavior", "tabs", "home", "shortcut"]),
        Category(id: "hud", icon: "speaker.wave.2.fill", title: L("Ses ve parlaklık"), sections: ["hud"]),
        Category(id: "music", icon: "music.note", title: L("Müzik ve sözler"), sections: ["lyrics"]),
        Category(id: "battery", icon: "battery.75percent", title: L("Pil ve bildirimler"), sections: ["battery", "alerts"]),
        Category(id: "tools", icon: "sparkles", title: L("Araçlar ve yapay zeka"), sections: ["capture", "ai"]),
        Category(id: "general", icon: "gearshape.fill", title: L("Genel"), sections: ["care", "updates"]),
    ] }

    /// Arama için: bölüm başlığı + Türkçe/İngilizce anahtar sözcükler (dilden bağımsız aranır).
    private static let keywords: [String: String] = [
        "look": "görünüm tema arka plan renk cam cam yoğunluğu ölçek boyut yazı notch genişlik yükseklik appearance theme background color glass scale size width height dil language türkçe english başlangıçta aç giriş login startup",
        "closedicon": "kapalı notch simge ekolayzer ses dalgası animasyon closed icon equalizer wave",
        "buddy": "maskot mate el sallama kulaklık yorgun uyku zıplama mascot buddy wave headphones sleep",
        "behavior": "davranış hover üzerine gelince aç gecikme titreşim haptik canlı etkinlik canlı aktivite açılış kapanış behavior delay haptics live activities raf pano zamanlayıcı toplantı hatırlatma shelf clipboard timer meeting",
        "tabs": "sekmeler raf pano zamanlayıcı istatistik sistem durumu tabs shelf clipboard timer stats",
        "home": "ana sayfa takvim etkinlik tarih albüm kapağı hızlı düğmeler uyanık tut renk seçici kısayollar home calendar artwork quick buttons caffeinate color picker shortcuts",
        "shortcut": "kısayol klavye ⌃⌥space aç kapat shortcut keyboard hotkey",
        "hud": "ses parlaklık klavye aydınlatma gösterge hud volume brightness keyboard backlight tuş adım erişilebilirlik ince adım stil çubuk yüzde süre fine step accessibility style bar percent duration sistem göstergesi gizle",
        "lyrics": "şarkı sözleri lyrics söz satırı lrclib notch satır spotify müzik music",
        "battery": "pil düşük pil uyarısı bluetooth cihaz kulaklık fare seviye battery low alert headphones mouse",
        "alerts": "göstergeler bildirimler gizlilik mikrofon kamera odak indirme hava durumu şehir indicators notifications privacy focus download weather city",
        "capture": "ekran görüntüsü kayıt alan pencere panoya screenshot capture area window clipboard",
        "ai": "yapay zeka claude openai gemini anahtar sağlayıcı ai provider api key",
        "care": "bakım izinler izinleri kontrol özellik turu önbellek temizleyici yedek dışa aktar içe aktar ayarlar permissions tour cache cleaner backup export import settings",
        "updates": "güncellemeler sürüm otomatik güncelle yenilikler updates version automatic what's new",
    ]

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr"))
    }

    private func sectionTitle(_ id: String) -> String {
        let t: [String: String] = ["look": "Görünüm", "behavior": "Davranış", "buddy": "Maskot", "ai": "Yapay Zeka", "care": "Bakım",
            "updates": "Güncellemeler", "closedicon": "Kapalı notch simgesi", "hud": "Ses ve parlaklık göstergesi",
            "battery": "Pil ve düşük pil uyarısı", "alerts": "Göstergeler ve bildirimler", "home": "Ana Sayfa",
            "capture": "Ekran görüntüsü butonu", "lyrics": "Mate Lyrics", "tabs": "Sekmeler", "shortcut": "Kısayol"]
        return t[id] ?? id
    }

    private var matches: [String] {
        let words = Self.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let order = Self.categories.flatMap(\.sections)
        return order.filter { id in
            let hay = Self.fold(sectionTitle(id) + " " + String(localized: String.LocalizationValue(sectionTitle(id))) + " " + (Self.keywords[id] ?? ""))
            return words.allSatisfy { hay.contains($0) }
        }
    }

    @State private var selection: String? = "look"
    private static let tint: [String: Color] = ["look": .purple, "behavior": .blue, "hud": .pink, "music": .red, "battery": .green, "tools": .orange, "general": .gray]

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(Self.categories) { c in
                    Label {
                        Text(c.title)
                    } icon: {
                        Image(systemName: c.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill((Self.tint[c.id] ?? .accentColor).gradient))
                    }
                    .tag(c.id)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(250)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(query.isEmpty ? (Self.categories.first { $0.id == selection }?.title ?? "") : L("Arama sonuçları"))
        }
        .searchable(text: $query, placement: .sidebar, prompt: Text("Ayarlarda ara"))
        .frame(minWidth: 860, maxWidth: 860, minHeight: 360, maxHeight: .infinity)
    }

    @ViewBuilder private var detail: some View {
        if !query.isEmpty {
            let m = matches
            if m.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form { ForEach(m, id: \.self) { sectionView($0) } }.formStyle(.grouped)
            }
        } else if let cat = Self.categories.first(where: { $0.id == selection }) {
            Form { ForEach(cat.sections, id: \.self) { sectionView($0) } }.formStyle(.grouped)
        } else {
            Color.clear
        }
    }
}
