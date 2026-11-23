import AppKit
import QuickLookThumbnailing

/// Raftaki dosyalar için gerçek önizleme küçük resmi (resim, PDF, video, belge…). Bulunamazsa nil: dosya simgesi gösterilir.
enum Thumbnails {
    private static var cache: [URL: NSImage] = [:]

    static func image(for url: URL) async -> NSImage? {
        if let c = cache[url] { return c }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 92, height: 92), scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) else { return nil }
        let img = rep.nsImage
        if cache.count > 80 { cache.removeAll() }
        cache[url] = img
        return img
    }
}
