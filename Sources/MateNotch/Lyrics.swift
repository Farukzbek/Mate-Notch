import Foundation
import Combine

// Mate Lyrics ile aynı altyapı: sözler lrclib.net'ten (ücretsiz, anahtar gerekmez) gelir.

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

enum LyricsState: Equatable {
    case idle, loading
    case synced([LyricLine])
    case plain([String])
    case instrumental, notFound
}

final class LyricsService: ObservableObject {
    static let shared = LyricsService()
    @Published private(set) var state: LyricsState = .idle
    @Published var offset: Double = 0          // saniye; + sözleri geciktirir (Mate Lyrics'teki gibi parça başına)
    private var cache: [String: LyricsState] = [:]
    private var currentKey: String?
    private var task: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()
    private let offsetsKey = "lyricOffsets"

    var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.lyricsEnabled) }

    func start() {
        MediaService.shared.$track.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] t in self?.load(t) }.store(in: &bag)
        // Ayar sonradan açılırsa çalan şarkı için yükle
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.enabled, self.currentKey == nil else { return }
                self.load(MediaService.shared.track)
            }.store(in: &bag)
    }

    private func key(_ t: Track) -> String { "\(t.player.rawValue)|\(t.title)|\(t.artist)" }

    func load(_ track: Track?) {
        guard enabled, let track else {
            if track == nil { currentKey = nil; state = .idle }
            return
        }
        let k = key(track)
        guard k != currentKey else { return }
        currentKey = k
        task?.cancel()
        offset = (UserDefaults.standard.dictionary(forKey: offsetsKey)?[k] as? Double) ?? 0
        if let c = cache[k] { state = c; return }
        state = .loading
        task = Task { [weak self] in
            for delay in [0, 3, 8] as [UInt64] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
                guard !Task.isCancelled, let self, self.currentKey == k else { return }
                if let r = await Self.fetch(track) {
                    guard !Task.isCancelled, self.currentKey == k else { return }
                    self.cache[k] = r
                    await MainActor.run { self.state = r }
                    return
                }
            }
            guard !Task.isCancelled, let self, self.currentKey == k else { return }
            await MainActor.run { self.state = .notFound }
            self.currentKey = nil   // şarkı tekrar gelince yeniden denensin
        }
    }

    func adjust(by d: Double) {
        offset = (offset + d * 100).rounded() / 100
        guard let k = currentKey else { return }
        var all = UserDefaults.standard.dictionary(forKey: offsetsKey) ?? [:]
        all[k] = offset
        UserDefaults.standard.set(all, forKey: offsetsKey)
    }

    /// Şu an söylenen satırın indeksi.
    func index(in lines: [LyricLine], at position: Double) -> Int? {
        let t = position + offset
        var lo = 0, hi = lines.count - 1, ans: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    // MARK: Ağ

    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
        let albumName: String?
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": "MateNotch/0.2 (Mate Studios)"]
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    private enum Response<T> { case ok(T), notFound, failed }

    private static func request<T: Decodable>(_ url: URL) async -> Response<T> {
        guard let (data, response) = try? await session.data(from: url),
              let code = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        if code == 404 { return .notFound }
        guard code == 200, let v = try? JSONDecoder().decode(T.self, from: data) else { return .failed }
        return .ok(v)
    }

    // MARK: - Kayıt seçimi (Mate Lyrics 1.9.1 ile aynı mantık)

    /// Bir LRCLIB kaydının değerlendirmesi. LRCLIB'i herkes düzenleyebiliyor: bazı kayıtlarda başka şarkının sözleri
    /// ya da saçma zamanlar var (ör. BLOK3 - ESKİSİ GİBİ: 27 satır şarkının 57–64. saniyelerine sıkışmış, sözler başka
    /// bir şarkıya ait; doğru sözler senkronsuz kayıtta). Bu yüzden "senkronlu olan kazanır" yetmez.
    private struct Candidate {
        /// Küçük olan iyi: geçerli senkron < düz söz < enstrümantal < zamanı bozuk kaydın düz sözü (son çare)
        enum Kind: Int { case syncedOK = 0, plain = 1, instrumental = 2, suspicious = 3 }
        let kind: Kind
        let state: LyricsState
        let albumMatch: Bool
        let diff: Double

        func isBetter(than o: Candidate) -> Bool {
            if kind != o.kind { return kind.rawValue < o.kind.rawValue }
            if albumMatch != o.albumMatch { return albumMatch }
            return diff < o.diff
        }
    }

    /// Senkron zamanlar şarkıya uyuyor mu? Sözler şarkının büyük kısmına yayılmalı ve şarkı dışına taşmamalı.
    static func timingsPlausible(_ lines: [LyricLine], duration: Double) -> Bool {
        guard duration > 0 else { return true }
        guard let first = lines.first?.time, let last = lines.last?.time else { return false }
        return last <= duration + 30 && (last - first) >= duration * 0.3
    }

    private static func fold(_ s: String?) -> String {
        (s ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func candidate(from r: Record, track: Track) -> Candidate? {
        let diff = abs((r.duration ?? track.duration) - track.duration)
        let album = !fold(track.album).isEmpty && fold(r.albumName) == fold(track.album)
        var suspicious = false
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                if timingsPlausible(lines, duration: track.duration) {
                    return Candidate(kind: .syncedOK, state: .synced(lines), albumMatch: album, diff: diff)
                }
                suspicious = true
            }
        }
        if let plain = r.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return Candidate(kind: suspicious ? .suspicious : .plain, state: .plain(plain.components(separatedBy: "\n")),
                             albumMatch: album, diff: diff)
        }
        if r.instrumental == true {
            return Candidate(kind: .instrumental, state: .instrumental, albumMatch: album, diff: diff)
        }
        return nil
    }

    /// nil = ağ hatası (tekrar dene); .notFound = gerçekten söz yok.
    static func fetch(_ t: Track) async -> LyricsState? {
        var best: Candidate?
        func consider(_ c: Candidate?) {
            guard let c else { return }
            if best == nil || c.isBetter(than: best!) { best = c }
        }

        // 1) Birebir eşleşme (süre dahil). Geçerli senkronsa hemen kullan; değilse aday olarak sakla.
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            .init(name: "track_name", value: t.title), .init(name: "artist_name", value: t.artist),
            .init(name: "album_name", value: t.album), .init(name: "duration", value: String(Int(t.duration.rounded()))),
        ]
        var reachable = true
        switch await request(get.url!) as Response<Record> {
        case .ok(let r):
            let c = candidate(from: r, track: t)
            if c?.kind == .syncedOK { return c?.state }
            consider(c)
        case .notFound: break
        case .failed: reachable = false
        }

        // 2) Arama: "- Remastered", "(feat. ...)" gibi ekleri temizleyip adayları değerlendir.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [.init(name: "track_name", value: cleaned(t.title)), .init(name: "artist_name", value: t.artist)]
        let res: Response<[Record]> = await request(search.url!)
        if case .failed = res { return nil }
        if case .ok(let list) = res {
            // Süre sınırı geniş: LRCLIB'de bazen tek kayıt var ve süresi birkaç sn farklı; kayma olursa menüden ince ayar yapılır.
            for r in list where abs((r.duration ?? 0) - t.duration) < 10 { consider(candidate(from: r, track: t)) }
        }
        if let best { return best.state }
        return reachable ? .notFound : nil
    }

    private static func cleaned(_ name: String) -> String {
        var s = name
        if let r = s.range(of: " - ") { s = String(s[..<r.lowerBound]) }
        s = s.replacingOccurrences(of: #"\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)

    static func parseLRC(_ text: String) -> [LyricLine] {
        var items: [(Double, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let ms = timeTag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = ms.last else { continue }
            let lyric = ns.substring(from: last.range.upperBound).trimmingCharacters(in: .whitespaces)
            for m in ms {
                let mi = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let se = Double(ns.substring(with: m.range(at: 2))) ?? 0
                items.append((mi * 60 + se, lyric.isEmpty ? "♪" : lyric))
            }
        }
        items.sort { $0.0 < $1.0 }
        var lines: [LyricLine] = []
        for (t, s) in items where !(s == "♪" && lines.last?.text == "♪") {
            lines.append(LyricLine(id: lines.count, time: t, text: s))
        }
        return lines
    }
}
