import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Raf: resim dönüştürme / küçültme

enum FileTools {
    static func isImage(_ u: URL) -> Bool { UTType(filenameExtension: u.pathExtension)?.conforms(to: .image) ?? false }

    private static func uniqueURL(_ dir: URL, _ base: String, _ ext: String) -> URL {
        var u = dir.appendingPathComponent(base + "." + ext), n = 1
        while FileManager.default.fileExists(atPath: u.path) { n += 1; u = dir.appendingPathComponent("\(base) \(n)." + ext) }
        return u
    }

    /// Resmi başka biçime çevirir (isteğe bağlı küçültür); yeni dosya aynı klasöre yazılır ve rafa eklenir. Özgün dosyaya dokunulmaz.
    static func convert(_ url: URL, to type: UTType, scale: CGFloat = 1, suffix: String = "") {
        DispatchQueue.global(qos: .userInitiated).async {
            var result: URL?
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil), var img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                if scale < 1, let ctx = CGContext(data: nil, width: Int(CGFloat(img.width) * scale), height: Int(CGFloat(img.height) * scale), bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
                    if let small = ctx.makeImage() { img = small }
                }
                let base = url.deletingPathExtension().lastPathComponent + suffix
                let out = uniqueURL(url.deletingLastPathComponent(), base, type.preferredFilenameExtension ?? "img")
                if let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
                    if CGImageDestinationFinalize(dest) { result = out }
                }
            }
            DispatchQueue.main.async {
                if let r = result {
                    ShelfService.shared.add([r])
                    BannerService.shared.post(NotchBanner(icon: "checkmark.circle.fill", title: L("Dönüştürüldü"), subtitle: r.lastPathComponent, tint: .green))
                } else {
                    BannerService.shared.post(NotchBanner(icon: "exclamationmark.triangle.fill", title: L("Dönüştürülemedi"), subtitle: url.lastPathComponent, tint: .orange))
                }
            }
        }
    }
}

// MARK: - Ekran görüntüsü işaretleme

struct MarkStroke: Identifiable {
    enum Tool: String, CaseIterable { case pen, arrow, box, highlight, redact }
    let id = UUID()
    var tool: Tool
    var color: Color
    var points: [CGPoint]            // 0…1 (görüntüye göre oransal)
}

enum MarkupDrawing {
    static func draw(_ strokes: [MarkStroke], in ctx: GraphicsContext, size: CGSize) {
        let lw = max(2, size.width / 220)
        for s in strokes {
            guard let a = s.points.first, let b = s.points.last else { continue }
            let pa = CGPoint(x: a.x * size.width, y: a.y * size.height), pb = CGPoint(x: b.x * size.width, y: b.y * size.height)
            let rect = CGRect(x: min(pa.x, pb.x), y: min(pa.y, pb.y), width: abs(pa.x - pb.x), height: abs(pa.y - pb.y))
            switch s.tool {
            case .pen:
                var p = Path(); p.move(to: pa)
                for q in s.points.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
                ctx.stroke(p, with: .color(s.color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            case .arrow:
                var p = Path(); p.move(to: pa); p.addLine(to: pb)
                let ang = atan2(pb.y - pa.y, pb.x - pa.x), head = lw * 5
                for d in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                    p.move(to: pb); p.addLine(to: CGPoint(x: pb.x + cos(ang + d) * head, y: pb.y + sin(ang + d) * head))
                }
                ctx.stroke(p, with: .color(s.color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            case .box:
                ctx.stroke(Path(roundedRect: rect, cornerRadius: lw), with: .color(s.color), lineWidth: lw)
            case .highlight:
                ctx.fill(Path(rect), with: .color(s.color.opacity(0.35)))
            case .redact:
                ctx.fill(Path(rect), with: .color(.black))
            }
        }
    }
}

struct MarkupView: View {
    let image: NSImage
    let source: URL?
    var onDone: () -> Void
    @State private var strokes: [MarkStroke] = []
    @State private var tool: MarkStroke.Tool = .arrow
    @State private var color: Color = .red
    @State private var live: MarkStroke?

    private let colors: [Color] = [.red, .yellow, .blue, .green, .white]
    private var aspect: CGFloat { image.size.height > 0 ? image.size.width / image.size.height : 1 }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(MarkStroke.Tool.allCases, id: \.self) { t in
                    Button { tool = t } label: {
                        Image(systemName: icon(t)).frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(tool == t ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08)))
                            .foregroundStyle(tool == t ? Color.white : Color.primary)
                    }.buttonStyle(.plain)
                }
                Divider().frame(height: 18)
                ForEach(colors, id: \.self) { c in
                    Circle().fill(c).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(color == c ? 0.9 : 0.2), lineWidth: color == c ? 2 : 1))
                        .onTapGesture { color = c }
                }
                Spacer()
                Button("Geri al") { _ = strokes.popLast() }.disabled(strokes.isEmpty)
                Button("Panoya kopyala") { copy() }
                Button("Kaydet") { save() }.keyboardShortcut(.defaultAction)
            }
            GeometryReader { geo in
                let w = min(geo.size.width, geo.size.height * aspect), h = w / aspect
                ZStack {
                    Image(nsImage: image).resizable().interpolation(.high)
                    Canvas { ctx, size in MarkupDrawing.draw(strokes + (live.map { [$0] } ?? []), in: ctx, size: size) }
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let p = CGPoint(x: min(1, max(0, v.location.x / w)), y: min(1, max(0, v.location.y / h)))
                    if live == nil { live = MarkStroke(tool: tool, color: color, points: [p]) }
                    else if tool == .pen { live?.points.append(p) }
                    else { live?.points = [live!.points[0], p] }
                }.onEnded { _ in if let l = live, l.points.count > 1 { strokes.append(l) }; live = nil })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14).frame(minWidth: 640, minHeight: 460)
    }

    private func icon(_ t: MarkStroke.Tool) -> String {
        switch t { case .pen: return "pencil.tip"; case .arrow: return "arrow.up.right"; case .box: return "rectangle"
                   case .highlight: return "highlighter"; case .redact: return "rectangle.fill" }
    }

    @MainActor private func rendered() -> NSImage? {
        let px = CGSize(width: image.representations.first.map { CGFloat($0.pixelsWide) } ?? image.size.width,
                        height: image.representations.first.map { CGFloat($0.pixelsHigh) } ?? image.size.height)
        let content = ZStack {
            Image(nsImage: image).resizable()
            Canvas { ctx, size in MarkupDrawing.draw(strokes, in: ctx, size: size) }
        }.frame(width: px.width, height: px.height)
        let r = ImageRenderer(content: content); r.scale = 1
        return r.nsImage
    }

    private func png(_ img: NSImage) -> Data? {
        guard let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func copy() {
        guard let img = rendered() else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img])
        BannerService.shared.post(NotchBanner(icon: "doc.on.clipboard.fill", title: L("Panoya kopyalandı"), subtitle: "", tint: .green))
        onDone()
    }

    private func save() {
        guard let img = rendered(), let data = png(img) else { return }
        let dir = source?.deletingLastPathComponent() ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let base = (source?.deletingPathExtension().lastPathComponent ?? "Ekran Görüntüsü") + " " + L("işaretli")
        var out = dir.appendingPathComponent(base + ".png"), n = 1
        while FileManager.default.fileExists(atPath: out.path) { n += 1; out = dir.appendingPathComponent("\(base) \(n).png") }
        do {
            try data.write(to: out)
            ShelfService.shared.add([out])
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img])
            BannerService.shared.post(NotchBanner(icon: "checkmark.circle.fill", title: L("Kaydedildi ve panoya kopyalandı"), subtitle: out.lastPathComponent, tint: .green))
            onDone()
        } catch {
            BannerService.shared.post(NotchBanner(icon: "exclamationmark.triangle.fill", title: L("Kaydedilemedi"), subtitle: error.localizedDescription, tint: .orange))
        }
    }
}

enum MarkupWindow {
    private static var window: NSWindow?
    static func show(url: URL) { if let img = NSImage(contentsOf: url) { show(image: img, source: url) } }
    static func showClipboard() {
        if let img = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage { show(image: img, source: nil) }
        else { BannerService.shared.post(NotchBanner(icon: "photo", title: L("Panoda görüntü yok"), subtitle: "", tint: .orange)) }
    }
    static func show(image: NSImage, source: URL?) {
        window?.close()
        let w = NSWindow(contentViewController: NSHostingController(rootView: MarkupView(image: image, source: source) { window?.close() }))
        w.title = L("Görüntüyü işaretle")
        w.styleMask = [.titled, .closable, .resizable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 860, height: 620))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
