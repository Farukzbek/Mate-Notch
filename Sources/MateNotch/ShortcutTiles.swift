import SwiftUI
import AppKit

// MARK: - Kestirmeler sekmesi: Apple Kestirmeler'den seçtiğin kestirmeleri kendi simgeleri ve renkleriyle notch'ta tek tıkla çalıştır.
// (Kestirmeler uygulaması simgeleri dışarıya vermediği için simge ve renk burada seçilir.)

struct ShortcutTile: Codable, Identifiable, Equatable {
    var name: String            // Kestirmeler'deki tam ad (çalıştırmak için kullanılır)
    var icon: String            // SF Symbol adı
    var color: String           // ShortcutPalette anahtarı
    var id: String { name }
}

enum ShortcutPalette {
    static let colors: [(id: String, color: Color)] = [
        ("red", Color(red: 1.00, green: 0.36, blue: 0.34)), ("orange", Color(red: 1.00, green: 0.62, blue: 0.20)),
        ("yellow", Color(red: 1.00, green: 0.82, blue: 0.25)), ("green", Color(red: 0.30, green: 0.80, blue: 0.45)),
        ("teal", Color(red: 0.25, green: 0.78, blue: 0.80)), ("blue", Color(red: 0.25, green: 0.52, blue: 1.00)),
        ("purple", Color(red: 0.62, green: 0.40, blue: 0.95)), ("pink", Color(red: 1.00, green: 0.42, blue: 0.65)),
        ("gray", Color(red: 0.55, green: 0.58, blue: 0.64)),
    ]
    static func color(_ id: String) -> Color { colors.first { $0.id == id }?.color ?? colors[5].color }

    static let symbols = [
        "bolt.fill", "lightbulb.fill", "lightbulb.slash.fill", "bed.double.fill", "moon.fill", "sun.max.fill", "house.fill", "lock.fill", "lock.open.fill",
        "music.note", "play.fill", "headphones", "phone.fill", "message.fill", "envelope.fill", "camera.fill", "mic.fill", "location.fill",
        "car.fill", "bus.fill", "airplane", "wifi", "battery.100", "alarm.fill", "timer", "calendar", "cart.fill", "creditcard.fill",
        "fork.knife", "cup.and.saucer.fill", "flame.fill", "drop.fill", "leaf.fill", "heart.fill", "star.fill", "bell.fill",
        "gamecontroller.fill", "tv.fill", "desktopcomputer", "printer.fill", "doc.fill", "folder.fill", "trash.fill", "paperplane.fill",
        "globe", "map.fill", "figure.walk", "dumbbell.fill", "pills.fill", "fan.fill", "thermometer.medium", "power",
        "sparkles", "wand.and.stars", "scissors", "gift.fill", "book.fill", "washer.fill", "lamp.desk.fill", "light.max",
    ]
}

final class ShortcutTiles: ObservableObject {
    static let shared = ShortcutTiles()
    private let key = "shortcutTiles"
    @Published var tiles: [ShortcutTile] = []
    @Published var running: String?                 // şu an çalışan kestirme
    @Published var result: [String: Bool] = [:]     // son çalıştırma: başarılı mı (kısa süre gösterilir)

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode([ShortcutTile].self, from: d) { tiles = t }
    }
    private func save() { if let d = try? JSONEncoder().encode(tiles) { UserDefaults.standard.set(d, forKey: key) } }

    func upsert(_ t: ShortcutTile) {
        if let i = tiles.firstIndex(where: { $0.name == t.name }) { tiles[i] = t } else { tiles.append(t) }
        save()
    }
    func remove(_ t: ShortcutTile) { tiles.removeAll { $0.name == t.name }; save() }
    func move(_ t: ShortcutTile, by d: Int) {
        guard let i = tiles.firstIndex(of: t), tiles.indices.contains(i + d) else { return }
        tiles.swapAt(i, i + d); save()
    }

    /// Kestirmeyi çalıştırır; bitince başarılı/başarısız göstergesi çıkar.
    func run(_ t: ShortcutTile) {
        guard running == nil else { return }
        running = t.name
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["run", t.name]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        p.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.running = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { self.result[t.name] = proc.terminationStatus == 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { self.result[t.name] = nil } }
            }
        }
        do { try p.run() } catch {
            running = nil
            result[t.name] = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.result[t.name] = nil }
        }
    }
}

struct ShortcutsTabView: View {
    @ObservedObject var store = ShortcutTiles.shared
    @State private var editing: ShortcutTile?
    @State private var isNew = false
    private let cols = [GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 12)]

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(store.tiles) { t in TileButton(tile: t, onEdit: { isNew = false; editing = t }) }
                    addTile
                }
                .padding(.vertical, 4)
            }
            if let t = editing {
                TileEditor(tile: t, isNew: isNew, onDone: { editing = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: editing == nil)
    }

    private var addTile: some View {
        Button { pick() } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.white.opacity(0.25))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.55)))
                Text("Ekle").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    /// Kestirmeler'deki henüz eklenmemiş kestirmeleri listeler; seçilince simge/renk düzenleyicisi açılır.
    private func pick() {
        ShortcutsService.list { names in
            let have = Set(store.tiles.map(\.name))
            let free = names.filter { !have.contains($0) }
            if names.isEmpty { PopMenu.show([ClosureMenuItem(L("Kısayol bulunamadı")) {}]); return }
            if free.isEmpty { PopMenu.show([ClosureMenuItem(L("Tüm kestirmeler eklendi")) {}]); return }
            PopMenu.show(free.map { n in ClosureMenuItem(n) { isNew = true; editing = ShortcutTile(name: n, icon: "bolt.fill", color: "blue") } })
        }
    }
}

struct TileButton: View {
    let tile: ShortcutTile
    var onEdit: () -> Void
    @ObservedObject var store = ShortcutTiles.shared
    @State private var hover = false

    var body: some View {
        let c = ShortcutPalette.color(tile.color)
        let busy = store.running == tile.name
        let res = store.result[tile.name]
        Button { store.run(tile) } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [c, c.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: c.opacity(hover ? 0.55 : 0.25), radius: hover ? 9 : 4, y: 2)
                    if busy { ProgressView().controlSize(.small).tint(.white) }
                    else if let ok = res {
                        Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: tile.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 54, height: 54)
                .scaleEffect(hover ? 1.05 : 1)
                Text(tile.name).font(.system(size: 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .background(HoverTracker { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hover = h } })
        .contextMenu {
            Button("Simgeyi ve rengi düzenle") { onEdit() }
            Button("Sola taşı") { store.move(tile, by: -1) }
            Button("Sağa taşı") { store.move(tile, by: 1) }
            Divider()
            Button("Kaldır") { withAnimation { store.remove(tile) } }
        }
    }
}

struct TileEditor: View {
    @State var tile: ShortcutTile
    let isNew: Bool
    var onDone: () -> Void
    @ObservedObject var store = ShortcutTiles.shared
    private let symCols = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10)

    var body: some View {
        let c = ShortcutPalette.color(tile.color)
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c)
                    .frame(width: 66, height: 66)
                    .overlay(Image(systemName: tile.icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white))
                Text(tile.name).font(.system(size: 10.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center).frame(width: 90)
                HStack(spacing: 8) {
                    Button { onDone() } label: { Text("Vazgeç").font(.system(size: 11, weight: .medium)).frame(width: 52, height: 24).background(Capsule().fill(.white.opacity(0.12))) }
                    Button { store.upsert(tile); onDone() } label: {
                        Text(isNew ? "Ekle" : "Kaydet").font(.system(size: 11, weight: .semibold)).frame(width: 52, height: 24)
                            .foregroundStyle(.black).background(Capsule().fill(.white))
                    }
                }.buttonStyle(PressStyle())
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(ShortcutPalette.colors, id: \.id) { item in
                        Button { withAnimation(.easeOut(duration: 0.15)) { tile.color = item.id } } label: {
                            Circle().fill(item.color).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(.white.opacity(tile.color == item.id ? 0.95 : 0), lineWidth: 2).padding(-3))
                        }.buttonStyle(PressStyle())
                    }
                }
                ScrollView {
                    LazyVGrid(columns: symCols, spacing: 6) {
                        ForEach(ShortcutPalette.symbols, id: \.self) { s in
                            Button { tile.icon = s } label: {
                                Image(systemName: s).font(.system(size: 13)).frame(width: 30, height: 30)
                                    .foregroundStyle(tile.icon == s ? .black : .white.opacity(0.85))
                                    .background(RoundedRectangle(cornerRadius: 8).fill(tile.icon == s ? Color.white : .white.opacity(0.08)))
                            }.buttonStyle(PressStyle())
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.8))
    }
}
