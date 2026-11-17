import Foundation
import Security
import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Sağlayıcılar

enum AIProvider: String, CaseIterable, Identifiable {
    case onDevice, claude, openai, gemini
    var id: String { rawValue }
    var title: String {
        switch self {
        case .onDevice: return "Cihaz içi (Apple)"
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        }
    }
    var keyPage: String {
        switch self {
        case .claude: return "console.anthropic.com/settings/keys"
        case .openai: return "platform.openai.com/api-keys"
        case .gemini: return "aistudio.google.com/apikey"
        case .onDevice: return ""
        }
    }
    /// Bağlanınca model listesi sağlayıcıdan çekilir; bu yalnızca liste alınamazsa kullanılan yedek.
    var fallbackModel: String {
        switch self {
        case .claude: return "claude-haiku-5-5"
        case .openai: return "gpt-5.4-mini"
        case .gemini: return "gemini-3.8-flash"
        case .onDevice: return ""
        }
    }
}

struct AIError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

// MARK: - Anahtarlık (API anahtarları düz metin olarak saklanmaz)

enum Keychain {
    static let service = "online.matestudios.matenotch"
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func get(_ account: String) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ value: String, _ account: String) {
        delete(account)
        var q = base(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ account: String) { SecItemDelete(base(account) as CFDictionary) }
}

// MARK: - Servis

final class AIService: ObservableObject {
    static let shared = AIService()
    @Published var revision = 0                       // anahtar/model değişince arayüz yenilensin
    @Published var status: [String: String] = [:]     // sağlayıcı → durum metni
    @Published var models: [String: [String]] = [:]   // sağlayıcı → model listesi
    @Published var busy: Set<String> = []

    func hasKey(_ p: AIProvider) -> Bool { Keychain.get(p.rawValue) != nil }
    func model(_ p: AIProvider) -> String { UserDefaults.standard.string(forKey: "aiModel_\(p.rawValue)") ?? p.fallbackModel }
    func setModel(_ m: String, _ p: AIProvider) { UserDefaults.standard.set(m, forKey: "aiModel_\(p.rawValue)"); revision += 1 }

    /// Cihaz içi model kullanılamıyorsa nedeni (kullanılabiliyorsa nil).
    var onDeviceProblem: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .unavailable(let reason) = SystemLanguageModel.default.availability {
                switch reason {
                case .deviceNotEligible: return "Bu Mac Apple Intelligence'ı desteklemiyor."
                case .appleIntelligenceNotEnabled: return "Apple Intelligence kapalı: Sistem Ayarları › Apple Intelligence ve Siri'den aç."
                case .modelNotReady: return "Apple Intelligence modeli hâlâ indiriliyor, biraz sonra dene."
                @unknown default: return "Cihaz içi model şu an kullanılamıyor."
                }
            }
            return nil
        }
        #endif
        return "Cihaz içi model için macOS 26 ve Apple Intelligence gerekir."
    }

    /// Hangi model kullanılacak: ayara göre; bağlı olmayan bir bulut seçilmişse cihaz içine düşer.
    func active() -> AIProvider {
        let pref = UserDefaults.standard.string(forKey: Pref.aiProvider) ?? "auto"
        if let p = AIProvider(rawValue: pref), p == .onDevice || hasKey(p) { return p }
        if pref == "auto" { for p in [AIProvider.claude, .openai, .gemini] where hasKey(p) { return p } }
        return .onDevice
    }

    // MARK: Tamamlama

    func complete(system: String, prompt: String) async throws -> (text: String, provider: AIProvider) {
        let p = active()
        switch p {
        case .onDevice: return (try await onDevice(system: system, prompt: prompt), p)
        case .claude, .openai, .gemini: return (try await cloud(p, system: system, prompt: prompt), p)
        }
    }

    private func onDevice(system: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let problem = onDeviceProblem { throw AIError("\(problem) Ya da Ayarlar'dan bir bulut model (Claude, ChatGPT, Gemini) bağla.") }
            let session = LanguageModelSession(instructions: system)
            let r = try await session.respond(to: String(prompt.prefix(6000)))   // cihaz içi modelin bağlam sınırı küçük
            return r.content
        }
        #endif
        throw AIError("Cihaz içi model bu macOS sürümünde yok. Ayarlar'dan bir bulut model bağla.")
    }

    private func cloud(_ p: AIProvider, system: String, prompt: String) async throws -> String {
        guard let key = Keychain.get(p.rawValue) else { throw AIError("\(p.title) bağlı değil") }
        let model = self.model(p)
        var req: URLRequest
        var body: [String: Any]
        switch p {
        case .claude:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": 1500, "system": system,
                    "messages": [["role": "user", "content": prompt]]]
        case .openai:
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]]
        default:
            let m = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
            req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent")!)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = ["systemInstruction": ["parts": [["text": system]]],
                    "contents": [["role": "user", "parts": [["text": prompt]]]]]
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await Self.send(req, provider: p)
        let text: String?
        switch p {
        case .claude:
            text = ((json["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined())
        case .openai:
            text = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        default:
            text = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined()
        }
        guard let t = text, !t.isEmpty else { throw AIError("Modelden boş yanıt geldi") }
        return t
    }

    private static func send(_ req: URLRequest, provider: AIProvider) async throws -> [String: Any] {
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw AIError("Bağlanılamadı (internet?)") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else {
            if code == 401 || code == 403 { throw AIError("API anahtarı geçersiz veya yetkisiz (\(code))") }
            if code == 429 { throw AIError("İstek sınırına takıldın veya kotan bitti (429)") }
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(code)"
            throw AIError(msg)
        }
        return json
    }

    // MARK: Bağlama

    /// Anahtarı kaydeder, modelleri sağlayıcıdan çeker, uygun bir model seçer ve kısa bir testle doğrular.
    func connect(_ p: AIProvider, key: String) async {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        await MainActor.run { busy.insert(p.rawValue); status[p.rawValue] = "Bağlanıyor…" }
        Keychain.set(k, p.rawValue)
        do {
            let list = try await fetchModels(p)
            await MainActor.run {
                models[p.rawValue] = list
                if !list.contains(model(p)) { setModel(Self.pickDefault(p, from: list) ?? p.fallbackModel, p) }
            }
            _ = try await cloud(p, system: "Kısa yanıt ver.", prompt: "Sadece 'tamam' yaz.")
            await MainActor.run { status[p.rawValue] = "Bağlandı ✓" }
        } catch {
            Keychain.delete(p.rawValue)
            await MainActor.run { status[p.rawValue] = "Bağlanamadı: \(error.localizedDescription)" }
        }
        await MainActor.run { busy.remove(p.rawValue); revision += 1 }
    }

    func disconnect(_ p: AIProvider) {
        Keychain.delete(p.rawValue)
        status[p.rawValue] = nil
        models[p.rawValue] = nil
        revision += 1
    }

    func refreshModels(_ p: AIProvider) async {
        guard hasKey(p) else { return }
        if let list = try? await fetchModels(p) {
            await MainActor.run { models[p.rawValue] = list; revision += 1 }
        }
    }

    func fetchModels(_ p: AIProvider) async throws -> [String] {
        guard let key = Keychain.get(p.rawValue) else { throw AIError("Anahtar yok") }
        var req: URLRequest
        switch p {
        case .claude:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        default:
            req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        req.timeoutInterval = 20
        let json = try await Self.send(req, provider: p)
        var ids: [String]
        switch p {
        case .claude, .openai:
            ids = (json["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        default:
            ids = (json["models"] as? [[String: Any]])?.compactMap { m -> String? in
                guard let n = m["name"] as? String,
                      (m["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { return nil }
                return n.replacingOccurrences(of: "models/", with: "")
            } ?? []
        }
        if p == .openai {
            let bad = ["audio", "realtime", "transcribe", "tts", "image", "embedding", "moderation", "whisper", "search", "dall", "davinci", "babbage", "computer-use"]
            ids = ids.filter { ($0.hasPrefix("gpt-") || $0.hasPrefix("chatgpt") || $0.range(of: #"^o\d"#, options: .regularExpression) != nil) && !bad.contains(where: $0.contains) }
        }
        if p == .gemini {
            let bad = ["embedding", "image", "tts", "live", "aqa", "vision", "robotics", "native-audio"]
            ids = ids.filter { $0.hasPrefix("gemini") && !bad.contains(where: $0.contains) }
        }
        ids = Array(Set(ids)).sorted(by: >)
        guard !ids.isEmpty else { throw AIError("Model listesi boş") }
        return ids
    }

    /// Hızlı ve ucuz bir model seç: Claude → haiku, ChatGPT → mini, Gemini → flash.
    static func pickDefault(_ p: AIProvider, from list: [String]) -> String? {
        switch p {
        case .claude: return list.first { $0.contains("haiku") } ?? list.first
        case .openai: return list.first { $0.contains("mini") && !$0.contains("nano") } ?? list.first
        case .gemini: return list.first { $0.contains("flash") && !$0.contains("lite") } ?? list.first
        case .onDevice: return nil
        }
    }
}

// MARK: - Eylemler

enum AIAction: String, CaseIterable, Identifiable {
    case summarize, fix, rewrite, toTR, toEN, explain, day, ask
    var id: String { rawValue }
    static var chips: [AIAction] { [.summarize, .fix, .rewrite, .toTR, .toEN, .explain, .day] }

    var title: String {
        switch self {
        case .summarize: return "Özetle"
        case .fix: return "Düzelt"
        case .rewrite: return "Yeniden yaz"
        case .toTR: return "Türkçeye çevir"
        case .toEN: return "İngilizceye çevir"
        case .explain: return "Açıkla"
        case .day: return "Günümü özetle"
        case .ask: return "Sor"
        }
    }
    var icon: String {
        switch self {
        case .summarize: return "text.alignleft"
        case .fix: return "checkmark.seal"
        case .rewrite: return "pencil.and.outline"
        case .toTR, .toEN: return "character.bubble"
        case .explain: return "questionmark.bubble"
        case .day: return "calendar"
        case .ask: return "paperplane"
        }
    }
    var system: String {
        switch self {
        case .summarize: return "Verilen metni Türkçe, kısa ve net özetle. Giriş cümlesi yazma, doğrudan özeti ver."
        case .fix: return "Metindeki yazım ve dil bilgisi hatalarını düzelt. Anlamı, dili ve üslubu değiştirme. Yalnızca düzeltilmiş metni ver, açıklama ekleme."
        case .rewrite: return "Metni daha akıcı, net ve profesyonel olacak şekilde yeniden yaz. Metnin dilini koru. Yalnızca yeni metni ver."
        case .toTR: return "Verilen metni doğal bir Türkçeye çevir. Yalnızca çeviriyi ver."
        case .toEN: return "Translate the given text into natural English. Output only the translation."
        case .explain: return "Verilen metni sade Türkçe ile açıkla. Hata mesajı veya kod ise nedenini ve olası çözümünü kısaca anlat."
        case .day: return "Kullanıcının takvim etkinliklerine bakarak kısa bir günlük plan özeti çıkar ve varsa dikkat edilecek şeyleri belirt. Türkçe, en fazla 5 cümle."
        case .ask: return "Soruya kısa, net ve doğru cevap ver. Kullanıcı Türkçe yazdıysa Türkçe cevap ver. Emin değilsen bunu belirt."
        }
    }
}

// MARK: - Durum (arayüzün kullandığı)

final class AIState: ObservableObject {
    static let shared = AIState()
    @Published var input = ""
    @Published var output = ""
    @Published var busy = false
    @Published var error: String?
    @Published var providerLabel = ""

    /// Başka bir yerden (ör. pano satırı) başlat: AI sekmesine geçip çalıştırır.
    func start(_ action: AIAction, text: String) {
        input = text
        NotchState.shared.tab = .ai
        NotchController.shared.open()
        run(action, text: text)
    }

    func run(_ action: AIAction, text: String? = nil) {
        guard !busy else { return }
        var prompt: String
        if action == .day {
            prompt = Self.dayPrompt()
            guard !prompt.isEmpty else { output = "Yaklaşan etkinliğin yok. 🎉"; error = nil; providerLabel = ""; return }
        } else {
            var source = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
            if source.isEmpty { source = ClipboardService.shared.items.first?.text ?? "" }
            guard !source.isEmpty else { error = "Önce bir metin yaz veya bir şey kopyala"; return }
            if action != .ask { input = source }
            prompt = source
        }
        busy = true; error = nil; output = ""
        Task {
            do {
                let r = try await AIService.shared.complete(system: action.system, prompt: prompt)
                await MainActor.run {
                    self.output = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.providerLabel = r.provider == .onDevice ? "Cihaz içi · Apple" : "\(r.provider.title) · \(AIService.shared.model(r.provider))"
                    self.busy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; self.busy = false }
            }
        }
    }

    static func dayPrompt() -> String {
        let events = CalendarService.shared.events
        guard !events.isEmpty else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM EEEE HH:mm"
        return "Yaklaşan takvim etkinliklerim:\n" + events.map { "- \($0.title ?? "Etkinlik") (\(f.string(from: $0.startDate)))" }.joined(separator: "\n")
    }
}
