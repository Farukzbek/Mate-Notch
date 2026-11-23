import SwiftUI
import AppKit

// MARK: - Hızlı notlar

final class QuickNotes: ObservableObject {
    static let shared = QuickNotes()
    private let key = "quickNotes"
    @Published var items: [String]

    init() { items = UserDefaults.standard.stringArray(forKey: "quickNotes") ?? [] }

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.insert(t, at: 0)
        if items.count > 60 { items.removeLast(items.count - 60) }
        save()
    }
    func remove(_ t: String) { items.removeAll { $0 == t }; save() }
    func clear() { items = []; save() }
    private func save() { UserDefaults.standard.set(items, forKey: key) }

    /// Apple Notlar'a yeni not olarak gönderir (macOS bir kez Otomasyon izni sorar).
    func copy(_ t: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
    }

    /// Tüm notları Notlar'a, her biri ayrı not olarak gönderir.
    func sendAllToNotes() { items.reversed().forEach { sendToNotes($0) } }

    func sendToNotes(_ t: String) {
        let esc = t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global().async {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"Notes\" to make new note with properties {body:\"\(esc)\"}")?.executeAndReturnError(&err)
            DispatchQueue.main.async {
                BannerService.shared.post(NotchBanner(icon: err == nil ? "note.text" : "exclamationmark.triangle.fill",
                                                      title: err == nil ? L("Notlar'a gönderildi") : L("Notlar'a gönderilemedi"),
                                                      subtitle: String(t.prefix(40)), tint: err == nil ? .yellow : .orange))
            }
        }
    }
}

struct NotesView: View {
    @ObservedObject var notes = QuickNotes.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").foregroundStyle(.white.opacity(0.5))
                TextField("Bir not yaz, Enter'a bas", text: $text)
                    .textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                    .onSubmit { notes.add(text); text = ""; focused = true }
                if !notes.items.isEmpty {
                    Button { notes.sendAllToNotes() } label: { Text("Hepsini Notlar'a aktar").font(.system(size: 10, weight: .semibold)) }
                        .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.6))
                    Button { notes.clear() } label: { Text("Tümünü sil").font(.system(size: 10, weight: .semibold)) }
                        .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

            if notes.items.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "note.text").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3))
                    Text("Notlar burada görünür").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(notes.items, id: \.self) { n in NoteCard(text: n) }
                    }
                }
            }
        }
        .onChange(of: focused) { _, f in NotchState.shared.inputFocused = f }
        .onDisappear { NotchState.shared.inputFocused = false }
    }
}

struct NoteCard: View {
    let text: String
    @ObservedObject var notes = QuickNotes.shared
    @State private var hover = false
    @State private var copied = false
    var body: some View {
        Text(text).font(.system(size: 11.5)).lineLimit(3).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hover ? 0.13 : 0.08)))
            .overlay(alignment: .topTrailing) {
                if copied {
                    Label("Kopyalandı", systemImage: "checkmark").font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.green).padding(6).transition(.opacity)
                } else if hover {
                    HStack(spacing: 8) {
                        Button { notes.sendToNotes(text) } label: { Image(systemName: "note.text.badge.plus") }.tip(L("Notlar'a aktar"), .top)
                        Button { notes.remove(text) } label: { Image(systemName: "trash") }
                    }
                    .font(.system(size: 10)).buttonStyle(PressStyle()).padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {            // nota tıklayınca panoya kopyalanır
                notes.copy(text)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
            }
            .onHover { hover = $0 }
            .contextMenu {
                Button("Kopyala") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                Button("Notlar uygulamasına gönder") { notes.sendToNotes(text) }
                Divider()
                Button("Sil") { notes.remove(text) }
            }
    }
}

// MARK: - Dünya saati (Sistem sekmesinin altında)

enum WorldClock {
    static let cities: [(id: String, name: String)] = [
        ("Europe/Istanbul", "İstanbul"), ("Europe/London", "London"), ("Europe/Berlin", "Berlin"), ("Europe/Paris", "Paris"),
        ("Europe/Madrid", "Madrid"), ("Europe/Moscow", "Moscow"), ("Africa/Cairo", "Cairo"), ("Asia/Dubai", "Dubai"),
        ("Asia/Kolkata", "Mumbai"), ("Asia/Bangkok", "Bangkok"), ("Asia/Singapore", "Singapore"), ("Asia/Shanghai", "Shanghai"),
        ("Asia/Tokyo", "Tokyo"), ("Asia/Seoul", "Seoul"), ("Australia/Sydney", "Sydney"), ("Pacific/Auckland", "Auckland"),
        ("America/Sao_Paulo", "São Paulo"), ("America/Argentina/Buenos_Aires", "Buenos Aires"), ("America/Mexico_City", "Mexico City"),
        ("America/New_York", "New York"), ("America/Chicago", "Chicago"), ("America/Denver", "Denver"),
        ("America/Los_Angeles", "Los Angeles"), ("America/Toronto", "Toronto"), ("Pacific/Honolulu", "Honolulu"),
    ]
    static var chosen: [(name: String, tz: TimeZone)] {
        (1...3).compactMap { i in
            guard let id = UserDefaults.standard.string(forKey: "clock\(i)"), !id.isEmpty, let tz = TimeZone(identifier: id) else { return nil }
            return (cities.first { $0.id == id }?.name ?? id, tz)
        }
    }
}

struct WorldClockStrip: View {
    var body: some View {
        let list = WorldClock.chosen
        if !list.isEmpty {
            TimelineView(.periodic(from: .now, by: 20)) { ctx in
                HStack(spacing: 8) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, c in
                        let f = DateFormatter()
                        let _ = { f.timeZone = c.tz; f.locale = Locale(identifier: Loc.code); f.dateFormat = "HH:mm" }()
                        let diff = (c.tz.secondsFromGMT(for: ctx.date) - TimeZone.current.secondsFromGMT(for: ctx.date)) / 3600
                        HStack(spacing: 6) {
                            Image(systemName: "clock").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            Text(c.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(f.string(from: ctx.date)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            if diff != 0 { Text(String(format: "%+dh", diff)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)) }
                        }
                        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.07)))
                    }
                }
            }
        }
    }
}
