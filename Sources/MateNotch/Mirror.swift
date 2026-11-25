import AVFoundation
import SwiftUI
import AppKit

// MARK: - Kamera aynası: macOS'ta kamera uygulaması olmadığı için, yüzüne bakmak istediğinde notch'ta canlı ayna.
// Kamera yalnızca sekme açıkken çalışır; sekmeden çıkınca ya da notch kapanınca kapatılır (kamera ışığı söner).

final class MirrorService: ObservableObject {
    static let shared = MirrorService()
    enum State { case idle, starting, running, denied, noCamera }
    @Published var state: State = .idle
    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "matenotch.mirror")       // oturuma tüm erişim bu seri kuyruktan
    private let photoOutput = AVCapturePhotoOutput()
    private var photoDelegate: PhotoSaver?                            // çekim bitene kadar tutulur
    private var configured = false
    private var mirrored = true
    private var wantRunning = false

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    func setMirrored(_ m: Bool) {
        guard m != mirrored || !configured else { return }
        mirrored = m
        queue.async { self.applyMirror() }
    }

    private func applyMirror() {                         // yalnızca `queue` üzerinde
        guard let c = previewLayer.connection, c.isVideoMirroringSupported else { return }
        session.beginConfiguration()
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = mirrored
        session.commitConfiguration()
    }

    func start() {
        wantRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            state = .starting
            AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { ok ? self.run() : (self.state = .denied) } }
        default: state = .denied
        }
    }

    private func run() {
        state = .starting
        queue.async {
            if !self.configured {
                let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video)
                guard let dev, let input = try? AVCaptureDeviceInput(device: dev) else {
                    DispatchQueue.main.async { self.state = .noCamera }; return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
                self.session.commitConfiguration()
                self.configured = true
            }
            guard self.wantRunning else { return }               // sekme bu arada kapandıysa başlatma
            if !self.session.isRunning { self.session.startRunning() }
            self.applyMirror()
            DispatchQueue.main.async { self.state = self.session.isRunning ? .running : .noCamera }
        }
    }

    /// Fotoğraf çeker: Masaüstü'ne JPEG olarak kaydeder, panoya kopyalar ve rafa ekler. `mirrored` açıksa kayıt aynadaki gibi (sağ-sol ters) olur.
    func takePhoto(flipped: Bool, done: @escaping (URL?) -> Void) {
        queue.async {
            guard self.session.isRunning, self.photoOutput.connection(with: .video) != nil else { DispatchQueue.main.async { done(nil) }; return }
            let saver = PhotoSaver(flip: flipped) { url in
                DispatchQueue.main.async { self.photoDelegate = nil; done(url) }
            }
            self.photoDelegate = saver
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: saver)
        }
    }

    func stop() {
        wantRunning = false
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { if self.state != .denied && self.state != .noCamera { self.state = .idle } }
        }
    }
}

/// Önizleme katmanı servise ait ve bir kez oluşturulur: sekme her açıldığında yeni bir katmanı oturuma bağlamak,
/// oturum çalışırken bağlantı listesini değiştirip çökmeye yol açıyordu (NSFastEnumerationMutationHandler).
struct CameraPreview: NSViewRepresentable {
    let mirrored: Bool

    func makeNSView(context: Context) -> HostView {
        let v = HostView()
        v.attach(MirrorService.shared.previewLayer)
        return v
    }
    func updateNSView(_ v: HostView, context: Context) {
        MirrorService.shared.setMirrored(mirrored)
        v.attach(MirrorService.shared.previewLayer)
    }

    final class HostView: NSView {
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer = CALayer() }
        required init?(coder: NSCoder) { fatalError() }
        private weak var hosted: CALayer?
        func attach(_ l: CALayer) {
            if hosted !== l { l.removeFromSuperlayer(); layer?.addSublayer(l); hosted = l }
            l.frame = bounds
        }
        override func layout() { super.layout(); hosted?.frame = bounds }
    }
}

final class PhotoSaver: NSObject, AVCapturePhotoCaptureDelegate {
    let flip: Bool
    let done: (URL?) -> Void
    init(flip: Bool, done: @escaping (URL?) -> Void) { self.flip = flip; self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), var img = NSImage(data: data) else { done(nil); return }
        if flip { img = Self.flipped(img) }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { done(nil); return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("Ayna \(f.string(from: Date())).jpg")
        do { try jpg.write(to: url) } catch { done(nil); return }
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img])
            ShelfService.shared.add([url])
        }
        done(url)
    }

    private static func flipped(_ img: NSImage) -> NSImage {
        let out = NSImage(size: img.size)
        out.lockFocus()
        let t = NSAffineTransform(); t.translateX(by: img.size.width, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat()
        img.draw(in: NSRect(origin: .zero, size: img.size))
        out.unlockFocus()
        return out
    }
}

struct MirrorView: View {
    @ObservedObject var mirror = MirrorService.shared
    @AppStorage("mirrorFlip") var flipped = true       // ayna gibi: sağ-sol ters
    @AppStorage("mirrorLight") var light = false       // halka ışık
    @AppStorage("mirrorLightLevel") var lightLevel = 1.0     // 0,2…1: ışığın parlaklığı
    @AppStorage("mirrorLightWidth") var lightWidth = 12.0    // 4…20 pt: ışığın kalınlığı
    @AppStorage("mirrorLightColor") var lightColor = "white" // white / yellow / blue

    private var lightTint: Color {
        switch lightColor {
        case "yellow": return Color(red: 1.0, green: 0.82, blue: 0.40)     // sıcak ışık
        case "blue": return Color(red: 0.55, green: 0.76, blue: 1.0)       // soğuk ışık
        default: return .white
        }
    }
    @State private var flash = false                         // çekim anında beyaz parlama
    @State private var shot: URL?                            // son çekilen fotoğraf (küçük önizleme)

    var body: some View {
        ZStack {
            Group {
                switch mirror.state {
                case .running, .starting:
                    CameraPreview(mirrored: flipped)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.8))
                        .overlay(alignment: .bottom) {                        // fotoğraf çek: altta ortada, biraz büyük
                            if mirror.state == .running {
                                Button { snap() } label: {
                                    Image(systemName: "camera.fill").font(.system(size: 15, weight: .semibold))
                                        .frame(width: 40, height: 40).foregroundStyle(.black)
                                        .background(Circle().fill(.white.opacity(0.92)))
                                        .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1).padding(3))
                                }
                                .buttonStyle(PressStyle()).tip(L("Fotoğraf çek"), .top).padding(.bottom, 8)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {                // sağ-sol çevir: sağ alt köşede
                            if mirror.state == .running {
                                toggle("arrow.left.and.right.righttriangle.left.righttriangle.right", on: flipped, tip: L("Sağ-sol çevir")) { flipped.toggle() }
                                    .padding(8)
                            }
                        }
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white).opacity(flash ? 0.9 : 0).allowsHitTesting(false) }
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)       // dar ve uzun: yüzü ortada, yanlarda boşluk
                        .background {
                            // Halka ışık: kameranın DIŞINDA çizilir, kamera çerçevesinin boyutu ve konumu ışık açılıp kapanınca değişmez
                            RoundedRectangle(cornerRadius: 12 + lightWidth, style: .continuous)
                                .fill(lightTint.opacity(light ? 0.2 + 0.8 * lightLevel : 0))
                                .shadow(color: lightTint.opacity(light ? 0.55 * lightLevel : 0), radius: light ? lightWidth : 0)
                                .padding(-lightWidth)
                        }
                        .padding(.vertical, 10)                          // ışık için sabit pay (yerleşim ışıkla değişmez)
                case .denied:
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.4))
                        Text("Kamera izni gerekli").font(.system(size: 11, weight: .semibold))
                        Button("Kamera ayarlarını aç") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                case .noCamera:
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash").font(.system(size: 24)).foregroundStyle(.white.opacity(0.4))
                        Text("Kamera bulunamadı").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                case .idle:
                    Color.clear
                }
            }
            if mirror.state == .running && light {
                // Işık ayarları: kameranın solunda, yalnızca ışık açıkken
                HStack(spacing: 14) {
                    lightSlider("sun.max", $lightLevel, 0.2...1, tip: L("Işık seviyesi"))
                    lightSlider("circle.dashed", Binding(get: { (lightWidth - 4) / 16 }, set: { lightWidth = 4 + 16 * $0 }), 0...1, tip: L("Işık kalınlığı"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 26)
                .transition(.opacity)
            }
            if mirror.state == .running {
                // Sağ sütun: ışık düğmesi üstte; açılınca renkler (beyaz / sarı / mavi) klasör gibi aşağı doğru iner
                VStack(spacing: 12) {
                    toggle("sun.max.fill", on: light, tip: L("Işık")) { light.toggle() }
                        .zIndex(2)                                        // renkler bu düğmenin altından çıkar / altına girer
                    // Renkler her zaman yerleşimde; açılış/kapanış konum + saydamlık + ölçek animasyonuyla (geçiş yerine, güvenilir çalışır)
                    ForEach(Array([("white", Color.white, L("Beyaz")), ("yellow", Color(red: 1.0, green: 0.82, blue: 0.40), L("Sarı")), ("blue", Color(red: 0.55, green: 0.76, blue: 1.0), L("Mavi"))].enumerated()), id: \.element.0) { i, item in
                        Button { withAnimation(.easeOut(duration: 0.2)) { lightColor = item.0 } } label: {
                            Circle().fill(item.1).frame(width: 24, height: 24)
                                .overlay(Circle().stroke(.white.opacity(lightColor == item.0 ? 0.95 : 0.0), lineWidth: 2).padding(-3.5))
                        }
                        .buttonStyle(PressStyle()).tip(item.2, .top, trailing: true)
                        .offset(y: light ? 0 : -CGFloat(i + 1) * 36)
                        .opacity(light ? 1 : 0)
                        .scaleEffect(light ? 1 : 0.5)
                        .allowsHitTesting(light)
                        .animation(.spring(response: 0.45, dampingFraction: 0.68).delay(light ? Double(i) * 0.06 : Double(2 - i) * 0.03), value: light)
                        .zIndex(Double(1 - i) * 0.1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 14).padding(.trailing, 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { mirror.start() }
        .onDisappear { mirror.stop() }
    }

    private func snap() {
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.08)) { flash = false }
        MirrorService.shared.takePhoto(flipped: flipped) { url in
            if let url {
                shot = url
                BannerService.shared.post(NotchBanner(icon: "camera.fill", title: L("Fotoğraf kaydedildi"), subtitle: L("Masaüstü, pano ve raf"), tint: .green))
            } else {
                BannerService.shared.post(NotchBanner(icon: "exclamationmark.triangle.fill", title: L("Fotoğraf çekilemedi"), subtitle: "", tint: .orange))
            }
        }
    }

    private func lightSlider(_ icon: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, tip: String) -> some View {
        VStack(spacing: 8) {
            VSlider(value: Binding(get: { (value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound) },
                                   set: { value.wrappedValue = range.lowerBound + $0 * (range.upperBound - range.lowerBound) }), tint: .white.opacity(0.9))
                .frame(width: 30, height: 120)
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
        }
        .tip(tip, .top, leading: true)
    }

    private func toggle(_ icon: String, on: Bool, tip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(on ? .black : .white)
                .background(Circle().fill(on ? Color.white : Color.black.opacity(0.55)))
        }
        .buttonStyle(PressStyle()).tip(tip, .top)
    }
}
