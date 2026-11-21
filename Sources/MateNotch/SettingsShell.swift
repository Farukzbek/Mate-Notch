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
        Category(id: "battery", icon: "battery.75percent", title: L("Pil ve bildirimler"), sections: ["battery", "alerts", "focus", "weather"]),
        Category(id: "tools", icon: "sparkles", title: L("Araçlar ve yapay zeka"), sections: ["capture", "ai"]),
        Category(id: "general", icon: "gearshape.fill", title: L("Genel"), sections: ["care", "updates"]),
    ] }

    /// Arama için: bölüm başlığı + Türkçe/İngilizce anahtar sözcükler (dilden bağımsız aranır).
    private static let keywords: [String: String] = [
        "look": "görünüm tema arka plan renk cam cam yoğunluğu ölçek boyut yazı notch genişlik yükseklik appearance theme background color glass scale size width height",
        "closedicon": "kapalı notch simge ekolayzer ses dalgası animasyon closed icon equalizer wave",
        "buddy": "maskot mate el sallama kulaklık yorgun uyku zıplama mascot buddy wave headphones sleep",
        "behavior": "dil language sprache idioma langue lingua língua taal türkçe english deutsch español français português globe başlangıçta aç giriş login startup davranış pano geçmişi limit otomatik sil clipboard history limit  hover üzerine gelince aç gecikme titreşim haptik canlı etkinlik canlı aktivite açılış kapanış behavior delay haptics live activities raf pano zamanlayıcı toplantı hatırlatma shelf clipboard timer meeting",
        "tabs": "sekmeler raf pano zamanlayıcı istatistik sistem durumu tabs shelf clipboard timer stats",
        "home": "ana sayfa takvim etkinlik tarih albüm kapağı hızlı düğmeler uyanık tut renk seçici kısayollar home calendar artwork quick buttons caffeinate color picker shortcuts",
        "shortcut": "kısayol klavye ⌃⌥space aç kapat shortcut keyboard hotkey",
        "hud": "ses parlaklık boyut renk  klavye aydınlatma gösterge hud volume brightness keyboard backlight tuş adım erişilebilirlik ince adım stil çubuk yüzde süre fine step accessibility style bar percent duration sistem göstergesi gizle",
        "lyrics": "şarkı sözleri lyrics söz satırı lrclib notch satır spotify müzik music",
        "battery": "pil düşük pil uyarısı bluetooth cihaz kulaklık fare seviye battery low alert headphones mouse",
        "focus": "odak rahatsız etmeyin ay simgesi çalışma uyku focus do not disturb moon",
        "weather": "hava durumu sıcaklık şehir derece fahrenheit celsius weather temperature city unit",
        "alerts": "göstergeler bildirimler gizlilik mikrofon kamera indirme indicators notifications privacy focus download weather city",
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
            "battery": "Pil ve düşük pil uyarısı", "alerts": "Göstergeler ve bildirimler", "focus": "Odak (Rahatsız Etmeyin)", "weather": "Hava durumu", "home": "Ana Sayfa",
            "capture": "Ekran görüntüsü butonu", "lyrics": "Mate Lyrics", "tabs": "Sekmeler", "shortcut": "Kısayol"]
        return t[id] ?? id
    }

    /// Aranan sözcüklerin hepsini içeren ayar satırları (başlık + tüm dillerdeki karşılıkları + eş anlamlılar).
    private var rowMatches: [SettingRowItem] {
        let words = Self.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let order = Self.categories.flatMap(\.sections)
        return SettingsIndex.rows.filter { r in
            let hay = Self.fold(r.title + " " + String(localized: String.LocalizationValue(r.title)) + " " + r.search )
            return words.allSatisfy { hay.contains($0) }
        }.sorted { (order.firstIndex(of: $0.section) ?? 99) < (order.firstIndex(of: $1.section) ?? 99) }
    }

    /// Satır bulunamazsa bölüm anahtar sözcüklerine bakılır (ör. "hud").
    private var sectionMatches: [String] {
        let words = Self.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return Self.categories.flatMap(\.sections).filter { id in
            let hay = Self.fold(sectionTitle(id) + " " + String(localized: String.LocalizationValue(sectionTitle(id))) + " " + (Self.keywords[id] ?? ""))
            return words.allSatisfy { hay.contains($0) }
        }
    }

    @State private var selection: String? = "look"
    @ObservedObject private var nav = SettingsNav.shared
    private static let tint: [String: Color] = ["look": .purple, "behavior": .blue, "hud": .pink, "music": .red, "battery": .green, "tools": .orange, "general": .gray]

    private func category(of section: String) -> Category? { Self.categories.first { $0.sections.contains(section) } }

    private func open(section: String, row: String?) {
        guard let c = category(of: section) else { return }
        query = ""
        selection = c.id
        nav.pending = row ?? "sec:" + section
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Ayarlarda ara", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.08)))
                .padding(.horizontal, 12).padding(.top, 44).padding(.bottom, 8)
                List(selection: Binding(get: { query.isEmpty ? selection : nil }, set: { if let v = $0 { query = ""; selection = v } })) {
                    ForEach(Self.categories) { c in
                        Label {
                            Text(c.title).lineLimit(1).minimumScaleFactor(0.8)
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
                .scrollContentBackground(.hidden)
                languageMenu
            }
            .frame(width: 280)
            .background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                Text(query.isEmpty ? (Self.categories.first { $0.id == selection }?.title ?? "") : L("Arama sonuçları"))
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 4)
                detail
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 890, maxWidth: 890, minHeight: 360, maxHeight: .infinity)
    }

    /// Dil ne olursa olsun bulunabilsin diye: dünya simgeli düğme, dil adları kendi dillerinde.
    private var languageMenu: some View {
        let names: [(String, String)] = [("auto", "Auto"), ("tr", "Türkçe"), ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("fr", "Français"), ("pt-BR", "Português (Brasil)")]
        let cur = AppLanguage.current
        return Menu {
            ForEach(names, id: \.0) { code, name in
                Button { if code != cur { AppLanguage.apply(code) } } label: {
                    if code == cur { Label(name, systemImage: "checkmark") } else { Text(verbatim: name) }
                }
            }
        } label: {
            Label { Text(verbatim: names.first { $0.0 == cur }?.1 ?? "Auto") } icon: { Image(systemName: "globe") }
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var detail: some View {
        if !query.isEmpty {
            let rows = rowMatches
            let secs = rows.isEmpty ? sectionMatches : []
            if rows.isEmpty && secs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        ForEach(rows, id: \.key) { r in
                            resultRow(title: String(localized: String.LocalizationValue(r.title)), section: r.section) { open(section: r.section, row: r.key) }
                        }
                        ForEach(secs, id: \.self) { id in
                            resultRow(title: String(localized: String.LocalizationValue(sectionTitle(id))), section: id) { open(section: id, row: nil) }
                        }
                    }
                }.formStyle(.grouped)
            }
        } else if let cat = Self.categories.first(where: { $0.id == selection }) {
            ScrollViewReader { proxy in
                Form { ForEach(cat.sections, id: \.self) { sectionView($0).id("sec:" + $0) } }
                    .formStyle(.grouped)
                    .task(id: nav.pending) { await jump(proxy, cat) }
            }
        } else {
            Color.clear
        }
    }

    /// Sonuca tıklanınca: satıra kaydır, kısa süre vurgula.
    private func jump(_ proxy: ScrollViewProxy, _ cat: Category) async {
        guard let key = nav.pending else { return }
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(key, anchor: .center) }
        if !key.hasPrefix("sec:") {
            nav.highlight = key
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if nav.highlight == key { nav.highlight = nil }
        }
        if nav.pending == key { nav.pending = nil }
    }

    private func resultRow(title: String, section: String, action: @escaping () -> Void) -> some View {
        let cat = category(of: section)
        return Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: cat?.icon ?? "gearshape").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill((Self.tint[cat?.id ?? ""] ?? .accentColor).gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary).lineLimit(2)
                    Text((cat?.title ?? "") + " › " + String(localized: String.LocalizationValue(sectionTitle(section)))).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
