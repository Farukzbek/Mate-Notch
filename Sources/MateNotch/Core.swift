import AppKit
import SwiftUI
import Combine

// MARK: - Geometry

struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens[0]
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchGeometry(screenFrame: screen.frame,
                                 notchWidth: screen.frame.width - l.width - r.width + 4,
                                 notchHeight: screen.safeAreaInsets.top,
                                 hasNotch: true)
        }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screenFrame: screen.frame, notchWidth: 180, notchHeight: menuBar, hasNotch: false)
    }
}

enum Layout {
    static let openW: CGFloat = 640
    static let bodyH: CGFloat = 196
    static let panelW: CGFloat = 940
    static let panelH: CGFloat = 440
    static let sideW: CGFloat = 54
    static func pillExtra(_ lines: Int) -> CGFloat { lines >= 2 ? 50 : 30 }
    static var pillExtra: CGFloat { pillExtra(UserDefaults.standard.integer(forKey: Pref.pillLines)) }
    static let pillMinW: CGFloat = 330
}

// MARK: - State

enum Tab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, timer, stats, ai
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .ai: return "sparkles"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .timer: return "timer"
        case .stats: return "chart.bar.xaxis"
        }
    }
    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .ai: return "Yapay Zeka"
        case .shelf: return "Raf"
        case .clipboard: return "Pano"
        case .timer: return "Zamanlayıcı"
        case .stats: return "Sistem"
        }
    }
}

extension Tab {
    static func visible() -> [Tab] {
        let d = UserDefaults.standard
        return allCases.filter {
            switch $0 {
            case .home: return true
            case .shelf: return d.bool(forKey: Pref.showShelf)
            case .clipboard: return d.bool(forKey: Pref.showClipboard)
            case .timer: return d.bool(forKey: Pref.showTimer)
            case .stats: return d.bool(forKey: Pref.showStats)
            case .ai: return d.bool(forKey: Pref.showAI)
            }
        }
    }
}

final class NotchState: ObservableObject {
    static let shared = NotchState()
    @Published var isOpen = false
    @Published var tab: Tab = .home
    @Published var pinned = false
    @Published var geometry = NotchGeometry.current()
    @Published var pillVisible = false
    var dragging = false
    var inputFocused = false     // yazı alanında yazarken notch kapanmasın
    var previewHold = false      // Ayarlar penceresi açıkken notch açık kalır (canlı önizleme)
}

enum Pref {
    static let openOnHover = "openOnHover"
    static let hoverDelay = "hoverDelay"
    static let closeDelay = "closeDelay"
    static let hotPadding = "hotPadding"
    static let liveActivities = "liveActivities"
    static let haptics = "haptics"
    static let showShelf = "showShelf"
    static let showClipboard = "showClipboard"
    static let showTimer = "showTimer"
    static let showStats = "showStats"
    static let uiScale = "uiScale"
    static let styleCollapsed = "styleCollapsed"
    static let showAI = "showAI"
    static let aiProvider = "aiProvider"
    static let autoUpdateCheck = "autoUpdateCheck"
    static let autoUpdateInstall = "autoUpdateInstall"
    static let closedIcon = "closedIcon"
    static let closedIconIdle = "closedIconIdle"
    static let glassDensity = "glassDensity"
    static let glassClear = "glassClear"
    static let collapsedExtraW = "collapsedExtraW"
    static let collapsedExtraH = "collapsedExtraH"
    static let showCalendar = "showCalendar"
    static let calDate = "calDate"
    static let calEvent = "calEvent"
    static let qbCaffeinate = "qbCaffeinate"
    static let qbTimer = "qbTimer"
    static let qbCapture = "qbCapture"
    static let qbColor = "qbColor"
    static let pillLines = "pillLines"
    static let captureMode = "captureMode"
    static let captureClipboard = "captureClipboard"
    static let bgStyle = "bgStyle"
    static let bgColor = "bgColor"
    static let showArtwork = "showArtwork"
    static let lyricsEnabled = "lyricsEnabled"
    static let lyricsInNotch = "lyricsInNotch"

    static func register() {
        UserDefaults.standard.register(defaults: [
            openOnHover: true, hoverDelay: 0.15, liveActivities: true, haptics: true,
            showShelf: true, showClipboard: true, showTimer: true, showStats: true,
            lyricsEnabled: false, lyricsInNotch: true,
            closeDelay: 0.18, hotPadding: 0.0, styleCollapsed: false, showAI: true, aiProvider: "auto", autoUpdateCheck: true, autoUpdateInstall: true, closedIcon: "equalizer", closedIconIdle: false, glassDensity: 0.35, glassClear: true, collapsedExtraW: 0.0, collapsedExtraH: 0.0, uiScale: 1.0, pillLines: 1,
            showCalendar: true, calDate: true, calEvent: true, qbCaffeinate: true, qbTimer: true, qbCapture: true, qbColor: true, showArtwork: true, captureMode: "area", captureClipboard: true, bgStyle: "black", bgColor: "#1F2A44",
        ])
    }
}

// MARK: - Shape

struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        // Şekil küçülürken yarıçaplar sığmazsa yol kendi üstüne katlanır (kapanırken takılma gibi görünür): sıkıştır.
        let top = max(0, min(self.top, r.height / 2, r.width / 4))
        let bottom = max(0, min(self.bottom, r.height - top, r.width / 2 - top))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Helpers

extension NSImage {
    func averageColor() -> Color? {
        guard let tiff = tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let f = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)])
        guard let out = f?.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Color(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255)
    }
}

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

/// Açık notch'un arka planı. Kapalıyken her zaman siyah (donanım notch'uyla bütünleşmesi için).
struct NotchBackground: View {
    let shape: NotchShape
    let style: String
    let color: Color
    let accent: Color
    let hasTrack: Bool
    var glassDensity: Double = 0.35      // 0 = tamamen şeffaf, 1 = koyu
    var glassClear = true                // true: şeffaf (iOS Liquid Glass tarzı), false: buzlu

    var body: some View {
        switch style {
        case "glass":
            if #available(macOS 26, *) {
                // Cam şekli ekranın üstünden dışarı uzatılır: cam kenar çizgisi (rim) ekran dışında kalır,
                // notch üst kenarda çizgisiz, ekrana bitişik durur.
                GeometryReader { geo in
                    Color.clear
                        .glassEffect((glassClear ? Glass.clear : Glass.regular).tint(Color.black.opacity(glassDensity * 0.7)), in: shape)
                        .frame(width: geo.size.width, height: geo.size.height + 16)
                        .position(x: geo.size.width / 2, y: (geo.size.height + 16) / 2 - 16)
                }
            } else {
                shape.fill(.ultraThinMaterial)
            }
        case "color":
            shape.fill(color)
        case "album":
            ZStack {
                shape.fill(Color.black)
                shape.fill(LinearGradient(colors: hasTrack ? [accent.opacity(0.85), accent.opacity(0.35)]
                                                            : [Color.gray.opacity(0.35), Color.gray.opacity(0.15)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        default:
            shape.fill(Color.black)
        }
    }
}

/// Kapalı notch'un sağ tarafındaki "çalıyor" göstergesi seçenekleri.
enum ClosedIcon: String, CaseIterable, Identifiable {
    case equalizer, waveform, musicNote, airpods, headphones, speaker, homepod, appleLogo, heart, sparkles, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .equalizer: return "Equalizer (çubuklar)"
        case .waveform: return "Ses dalgası"
        case .musicNote: return "Müzik notası"
        case .airpods: return "AirPods Pro"
        case .headphones: return "Kulaklık"
        case .speaker: return "Hoparlör"
        case .homepod: return "HomePod"
        case .appleLogo: return "Apple logosu"
        case .heart: return "Kalp"
        case .sparkles: return "Işıltı"
        case .none: return "Hiçbiri"
        }
    }
    var symbol: String {
        switch self {
        case .equalizer: return "chart.bar.fill"
        case .waveform: return "waveform"
        case .musicNote: return "music.note"
        case .airpods: return "airpods.pro"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .homepod: return "homepod.fill"
        case .appleLogo: return "applelogo"
        case .heart: return "heart.fill"
        case .sparkles: return "sparkles"
        case .none: return "nosign"
        }
    }
}
