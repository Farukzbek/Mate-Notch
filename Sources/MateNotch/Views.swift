import SwiftUI
import EventKit
import AppKit

// MARK: - Root

enum Activity: String {
    case record, charge, timer, music, idle, privacy, download, focus
}

struct RootView: View {
    @ObservedObject var state = NotchState.shared
    @ObservedObject var media = MediaService.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var capture = CaptureService.shared
    @ObservedObject var lyrics = LyricsService.shared
    @ObservedObject var clip = ClipboardService.shared
    @ObservedObject var hud = HUDService.shared
    @ObservedObject var bn = BannerService.shared
    @ObservedObject var privacy = PrivacyService.shared
    @ObservedObject var downloads = DownloadService.shared
    @ObservedObject var focus = FocusService.shared
    @AppStorage(Pref.hudStyle) var hudStyle = "bar"
    @AppStorage(Pref.liveActivities) var liveActivities = true
    @AppStorage(Pref.lyricsEnabled) var lyricsOn = false
    @AppStorage(Pref.lyricsInNotch) var lyricsInNotch = true
    @AppStorage(Pref.closedIconIdle) var closedIconIdle = false
    @AppStorage(Pref.closedIcon) var closedIconName = "equalizer"
    @AppStorage(Pref.uiScale) var uiScale = 1.0
    @AppStorage(Pref.pillLines) var pillLines = 1
    @AppStorage(Pref.bgStyle) var bgStyle = "black"
    @AppStorage(Pref.bgColor) var bgHex = "#1F2A44"
    @AppStorage(Pref.styleCollapsed) var styleCollapsed = false
    @AppStorage(Pref.glassDensity) var glassDensity = 0.35
    @AppStorage(Pref.glassClear) var glassClear = true
    @AppStorage(Pref.collapsedExtraW) var exW = 0.0
    @AppStorage(Pref.collapsedExtraH) var exH = 0.0

    var showPill: Bool {
        guard lyricsOn, lyricsInNotch, media.isPlaying, case .synced = lyrics.state else { return false }
        return true
    }

    var activity: Activity? {
        if capture.recording { return .record }
        if privacy.active { return .privacy }
        guard liveActivities else { return nil }
        if battery.flash { return .charge }
        if timer.running { return .timer }
        if downloads.active { return .download }
        if media.isPlaying { return .music }
        if focus.active { return .focus }
        if closedIconIdle && closedIconName != "none" { return .idle }
        return nil
    }

    var body: some View {
        let g = state.geometry
        let open = state.isOpen
        let banner = bn.current != nil
        let pill = !open && (showPill || clip.justCopied || hud.visible || banner)
        let extra = (clip.justCopied || hud.visible || banner) ? Layout.pillExtra(1) : Layout.pillExtra(pillLines)
        let pillW: CGFloat = hud.visible ? (hudStyle == "bar" ? 250 : 170) : (banner ? 330 : Layout.pillMinW)
        let u = open ? CGFloat(uiScale) : 1
        let base0 = max(40, g.notchWidth + CGFloat(exW))
        let ch = max(12, g.notchHeight + CGFloat(exH))
        let base = activity != nil ? base0 + Layout.sideW * 2 : base0
        let w = open ? Layout.openW : (pill ? max(base, pillW) : base)
        let h = open ? g.notchHeight / u + Layout.bodyH : ch + (pill ? extra : 0)

        ZStack(alignment: .top) {
            let shape = NotchShape(top: open ? 16 : 6, bottom: open ? 30 : (pill ? 18 : 11))
            if open || (styleCollapsed && bgStyle != "black") {
                NotchBackground(shape: shape, style: bgStyle, color: Color(hex: bgHex),
                                accent: media.accent, hasTrack: media.track != nil,
                                glassDensity: glassDensity, glassClear: glassClear)
            } else {
                shape.fill(Color.black)
            }
            if open && media.isPlaying && bgStyle == "black" {
                NotchShape(top: 16, bottom: 30)
                    .fill(LinearGradient(colors: [media.accent.opacity(0.30), .clear],
                                         startPoint: .topLeading, endPoint: .bottom))
                    .transition(.opacity)
            }
            if open {
                // Sabit boyutlu içerik: kabuk küçülürken yeniden yerleşim (layout) yapılmaz, sadece kırpılır.
                OpenContent()
                    .frame(width: Layout.openW, height: g.notchHeight / u + Layout.bodyH, alignment: .top)
                    .overlay(alignment: .bottom) {   // notch açıkken de geri bildirim (sistem göstergesi gizliyse)
                        if hud.visible {
                            HUDBanner().frame(height: 30).fixedSize(horizontal: true, vertical: false)
                                .background(Capsule().fill(.black.opacity(0.6)))
                                .padding(.bottom, 10).transition(.opacity)
                        }
                    }
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.08)),
                                            removal: .opacity.animation(.easeIn(duration: 0.16))))
            } else if let a = activity {
                CollapsedContent(activity: a)
                    .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.18)))
            }
            if pill {
                Group { if hud.visible { HUDBanner() } else if banner { BannerView() } else if clip.justCopied { CopiedBanner() } else { LyricPill() } }
                    .frame(height: extra)
                    .padding(.top, ch)
                    .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.18)))
            }
        }
        .onChange(of: pill) { _, v in state.pillVisible = v }
        .onChange(of: CGSize(width: w, height: h)) { _, sz in if !open { state.hotSize = sz } }
        .onChange(of: open) { _, o in if !o { state.hotSize = CGSize(width: w, height: h) } }
        .onAppear { state.hotSize = CGSize(width: w, height: h) }
        .frame(width: w, height: h, alignment: .top)
        .clipShape(NotchShape(top: open ? 16 : 6, bottom: open ? 30 : (pill ? 18 : 11)))
        .background(
            NotchShape(top: open ? 16 : 6, bottom: open ? 30 : (pill ? 18 : 11))
                .fill((open || styleCollapsed) && bgStyle == "glass" ? Color.clear : Color.black)
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 12, y: 6)
        )
        .scaleEffect(u, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Açılış: hafif yaylı. Kapanış: aşım (overshoot) yok, yumuşak ve kritik sönümlü.
        .animation(open ? .spring(response: 0.42, dampingFraction: 0.8)
                        : .spring(response: 0.5, dampingFraction: 0.88), value: open)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: activity)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: pill)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Collapsed live activities

struct CollapsedContent: View {
    let activity: Activity
    @AppStorage(Pref.showArtwork) var showArtwork = true
    @ObservedObject var state = NotchState.shared
    @ObservedObject var media = MediaService.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var privacy = PrivacyService.shared
    @ObservedObject var downloads = DownloadService.shared
    @ObservedObject var focusState = FocusService.shared
    @AppStorage(Pref.collapsedExtraW) var exW = 0.0
    @AppStorage(Pref.collapsedExtraH) var exH = 0.0

    var body: some View {
        let g = state.geometry
        let wing = max(24, Layout.sideW + CGFloat(exW) / 2)        // kapalı notch daralınca kanatlar da daralır
        HStack(spacing: 0) {
            left.frame(width: wing - 8, alignment: .center)
            Spacer(minLength: g.notchWidth - 16)
            right.frame(width: wing - 8, alignment: .center)
        }
        .padding(.horizontal, 8)
        .frame(height: max(12, g.notchHeight + CGFloat(exH)))
    }

    static func short(_ b: Int64) -> String {
        let mb = Double(b) / 1_048_576
        return mb >= 1024 ? String(format: "%.1fG", mb / 1024) : String(format: "%.0fM", mb)
    }

    @ViewBuilder var left: some View {
        switch activity {
        case .idle:
            Color.clear.frame(width: 1, height: 1)
        case .privacy:
            if privacy.camera { Image(systemName: "video.fill").foregroundStyle(.green).font(.system(size: 13, weight: .semibold)) }
            else { Color.clear.frame(width: 1, height: 1) }
        case .download:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue).font(.system(size: 14, weight: .semibold))
                .symbolEffect(.pulse)
        case .focus:
            Image(systemName: "moon.fill").foregroundStyle(.purple).font(.system(size: 13, weight: .semibold))
        case .music:
            Group {
                if showArtwork, let a = media.artwork {
                    Image(nsImage: a).resizable().scaledToFill()
                } else {
                    ZStack { Color.white.opacity(0.12); Image(systemName: "music.note").font(.system(size: 11)) }
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        case .record:
            Image(systemName: "record.circle.fill").foregroundStyle(.red).font(.system(size: 14, weight: .semibold))
        case .timer:
            Image(systemName: "timer").foregroundStyle(.orange).font(.system(size: 14, weight: .semibold))
        case .charge:
            Image(systemName: "bolt.fill").foregroundStyle(.green).font(.system(size: 14, weight: .bold))
        }
    }

    @ViewBuilder var right: some View {
        switch activity {
        case .music:
            HStack(spacing: 4) {                       // Odak açıksa ay simgesi müzik göstergesinin yanında
                if focusState.active { Image(systemName: "moon.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.purple) }
                ClosedIconView(playing: media.isPlaying, color: media.accent)
            }
        case .idle: ClosedIconView(playing: false, color: .white.opacity(0.65))
        case .privacy:
            if privacy.mic { Image(systemName: "mic.fill").foregroundStyle(.orange).font(.system(size: 13, weight: .semibold)) }
            else { Color.clear.frame(width: 1, height: 1) }
        case .download:
            Text(Self.short(downloads.bytes)).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.blue)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        case .focus: Color.clear.frame(width: 1, height: 1)
        case .record:
            Text("KAYIT").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.red)
        case .timer:
            Text(timer.label).font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(.orange)
        case .charge:
            Text("\(battery.level)%").font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
        }
    }
}

/// Çekirdek animasyon (CALayer) ile çizilir: animasyon çizim sunucusunda döner, uygulama CPU'su ~0.
struct ClosedIconView: View {
    let playing: Bool
    let color: Color
    @AppStorage(Pref.closedIcon) var name = "equalizer"

    var body: some View {
        let icon = ClosedIcon(rawValue: name) ?? .equalizer
        switch icon {
        case .equalizer: Equalizer(active: playing, color: color)
        case .none: Color.clear.frame(width: 1, height: 1)
        default:
            Image(systemName: icon.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative.reversing, isActive: playing && icon == .waveform)
                .symbolEffect(.pulse, isActive: playing && icon != .waveform)
        }
    }
}

struct Equalizer: NSViewRepresentable {
    let active: Bool
    let color: Color
    func makeNSView(context: Context) -> EQView { EQView() }
    func updateNSView(_ v: EQView, context: Context) { v.update(active: active, color: NSColor(color)) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EQView, context: Context) -> CGSize? { CGSize(width: 21, height: 20) }
}

final class EQView: NSView {
    private var bars: [CALayer] = []
    private var isActive = false
    private let peaks: [CGFloat] = [17, 11, 18, 13]
    private let durations: [Double] = [0.42, 0.51, 0.36, 0.60]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let l = CALayer(); l.cornerRadius = 1.5
            layer?.addSublayer(l); bars.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        for (i, l) in bars.enumerated() {
            l.bounds = CGRect(x: 0, y: 0, width: 3, height: 5)
            l.position = CGPoint(x: 1.5 + CGFloat(i) * 5.5, y: bounds.midY)
        }
        apply()
    }

    func update(active: Bool, color: NSColor) {
        for l in bars { l.backgroundColor = color.withAlphaComponent(0.95).cgColor }
        guard active != isActive || bars.first?.animation(forKey: "eq") == nil && active else { return }
        isActive = active
        apply()
    }

    private func apply() {
        for (i, l) in bars.enumerated() {
            l.removeAnimation(forKey: "eq")
            guard isActive else { continue }
            let a = CABasicAnimation(keyPath: "bounds.size.height")
            a.fromValue = 5; a.toValue = peaks[i]
            a.duration = durations[i]; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(a, forKey: "eq")
        }
    }
}

// MARK: - Open content

struct OpenContent: View {
    @ObservedObject var state = NotchState.shared
    @ObservedObject var battery = BatteryService.shared
    @AppStorage(Pref.showShelf) var showShelf = true
    @AppStorage(Pref.showClipboard) var showClipboard = true
    @AppStorage(Pref.showTimer) var showTimer = true
    @AppStorage(Pref.showStats) var showStats = true
    @AppStorage(Pref.showAI) var showAI = true
    @AppStorage(Pref.uiScale) var uiScale = 1.0

    var tabs: [Tab] { _ = (showShelf, showClipboard, showTimer, showStats, showAI); return Tab.visible().filter { $0 != .ai } }

    var body: some View {
        let g = state.geometry
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { t in
                    TabButton(tab: t, selected: state.tab == t, leading: t == tabs.first) {
                        withAnimation(.snappy(duration: 0.25)) { state.tab = t }
                    }
                }
                Spacer(minLength: g.hasNotch ? (g.notchWidth + 8) / CGFloat(uiScale) : 12)
                HStack(spacing: 10) {
                    if showAI {
                        Button { withAnimation(.snappy(duration: 0.25)) { state.tab = .ai } } label: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(state.tab == .ai ? Color.white : .white.opacity(0.5))
                        }.buttonStyle(.plain).morph("Yapay Zeka")
                    }
                    Button { state.pinned.toggle() } label: {
                        Image(systemName: state.pinned ? "pin.fill" : "pin")
                            .foregroundStyle(state.pinned ? Color.yellow : .white.opacity(0.5))
                    }.buttonStyle(.plain).morph(state.pinned ? "Bırak" : "Sabitle")
                    Button { SettingsWindow.show() } label: {
                        Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.5))
                    }.buttonStyle(.plain).morph("Ayarlar")
                    HStack(spacing: 3) {
                        Image(systemName: battery.pluggedIn ? "battery.100.bolt" : "battery.75")
                        Text("\(battery.level)%").monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(battery.pluggedIn ? .green : .white.opacity(0.6))
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 26)
            .frame(height: g.notchHeight / CGFloat(uiScale))
            .zIndex(5)   // etiketler gövdenin üstünde çizilsin

            Group {
                switch state.tab {
                case .home: HomeView()
                case .ai: AIView()
                case .shelf: ShelfView()
                case .clipboard: ClipboardView()
                case .timer: TimerView()
                case .stats: StatsView()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(state.tab)
            .transition(.opacity)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Home

struct HomeView: View {
    @AppStorage(Pref.showCalendar) var showCalendar = true
    @AppStorage(Pref.calDate) var calDate = true
    @AppStorage(Pref.calEvent) var calEvent = true
    @AppStorage(Pref.qbCaffeinate) var qbCaffeinate = true
    @AppStorage(Pref.qbTimer) var qbTimer = true
    @AppStorage(Pref.qbCapture) var qbCapture = true
    @AppStorage(Pref.qbColor) var qbColor = true

    @AppStorage(Pref.weatherEnabled) var weatherOn = false

    var hasSide: Bool { (showCalendar && (calDate || calEvent)) || weatherOn || qbCaffeinate || qbTimer || qbCapture || qbColor }

    var body: some View {
        HStack(spacing: 20) {
            MediaCard().frame(maxWidth: .infinity).layoutPriority(0)
            if hasSide { SideColumn().frame(width: 176).layoutPriority(1) }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

struct MediaCard: View {
    @AppStorage(Pref.showArtwork) var showArtwork = true
    @ObservedObject var media = MediaService.shared
    @State private var dragFraction: Double?

    var body: some View {
        if let t = media.track {
            HStack(alignment: .top, spacing: 16) {
                if showArtwork {
                Group {
                    if let a = media.artwork {
                        Image(nsImage: a).resizable().scaledToFill()
                    } else {
                        ZStack { Color.white.opacity(0.1); Image(systemName: "music.note").font(.title) }
                    }
                }
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: media.accent.opacity(0.5), radius: 14, y: 4)
                .scaleEffect(media.isPlaying ? 1 : 0.92)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(t.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(t.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    CardLyric().padding(.top, 5)
                    Spacer(minLength: 2)
                    scrubber(t)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 24, height: 1)
                        Spacer(minLength: 0)
                        HStack(spacing: 22) {
                        Button { media.previous() } label: { Image(systemName: "backward.fill") }.tip("Önceki", .top)
                        Button { media.togglePlay() } label: {
                            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20))
                        }.tip(media.isPlaying ? "Duraklat" : "Oynat", .top)
                        Button { media.next() } label: { Image(systemName: "forward.fill") }.tip("Sonraki", .top)
                        }
                        Spacer(minLength: 0)
                        LyricsToggle()
                    }
                    .buttonStyle(PressStyle())
                    .font(.system(size: 15))
                }
                .frame(height: 128, alignment: .top)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list").font(.system(size: 26)).foregroundStyle(.white.opacity(0.35))
                Text("Müzik çalmıyor").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                Text("Apple Music veya Spotify aç").font(.system(size: 10)).foregroundStyle(.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func scrubber(_ t: Track) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let pos = media.position
            let frac = dragFraction ?? (t.duration > 0 ? pos / t.duration : 0)
            HStack(spacing: 8) {
                Text(formatTime(frac * t.duration)).frame(width: 32, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white).frame(width: max(4, geo.size.width * frac))
                    }
                    .frame(height: dragFraction == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(1, max(0, $0.location.x / geo.size.width)) }
                        .onEnded { v in
                            let f = min(1, max(0, v.location.x / geo.size.width))
                            media.seek(to: f * t.duration)
                            dragFraction = nil
                        })
                    .animation(.snappy(duration: 0.15), value: dragFraction == nil)
                }
                .frame(height: 12)
                Text(formatTime(t.duration)).frame(width: 32, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SideColumn: View {
    @ObservedObject var weather = WeatherService.shared
    @AppStorage(Pref.weatherEnabled) var weatherOn = false
    @ObservedObject var capture = CaptureService.shared
    @AppStorage(Pref.captureMode) var captureMode = "area"
    @AppStorage(Pref.showCalendar) var showCalendar = true
    @AppStorage(Pref.calDate) var calDate = true
    @AppStorage(Pref.calEvent) var calEvent = true
    @AppStorage(Pref.qbCaffeinate) var qbCaffeinate = true
    @AppStorage(Pref.qbTimer) var qbTimer = true
    @AppStorage(Pref.qbCapture) var qbCapture = true
    @AppStorage(Pref.qbColor) var qbColor = true
    @ObservedObject var cal = CalendarService.shared
    @ObservedObject var caf = CaffeinateService.shared
    @ObservedObject var timer = TimerService.shared

    static func fmt(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = pattern
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showCalendar && (calDate || calEvent) {
                VStack(alignment: .leading, spacing: 7) {
                    if calDate {
                        TimelineView(.periodic(from: .now, by: 60)) { ctx in
                            HStack(spacing: 9) {
                                Text(Self.fmt(ctx.date, "d"))
                                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(Self.fmt(ctx.date, "EEEE")).font(.system(size: 11, weight: .semibold))
                                    Text(Self.fmt(ctx.date, "MMMM yyyy")).font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    } else {
                        Label("Sıradaki", systemImage: "calendar")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                    }
                    if calEvent { eventRow }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
            }

            if weatherOn, let t = weather.temp {
                HStack(spacing: 9) {
                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(t)°").font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                        Text([weather.city.components(separatedBy: ",").first ?? "", weather.text].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
            }
            if qbCaffeinate || qbTimer || qbCapture || qbColor {
                HStack(spacing: 6) {
                    if qbCaffeinate {
                        QuickButton(icon: "cup.and.saucer.fill", on: caf.active, tint: .orange, help: "Uyanık tut") { caf.toggle() }
                    }
                    if qbTimer {
                        QuickButton(icon: "timer", on: timer.running, tint: .orange, help: "25 dk odak") {
                            if timer.running { timer.pause() } else { timer.set(minutes: 25); timer.start() }
                        }
                    }
                    if qbColor {
                        QuickButton(icon: "eyedropper", on: false, tint: .pink, help: "Renk seç") { ColorPickService.shared.pick() }
                    }
                    if qbCapture {
                        QuickButton(icon: CaptureService.icon(captureMode, recording: capture.recording),
                                    on: capture.recording, tint: .red,
                                    help: CaptureService.label(captureMode, recording: capture.recording)) { capture.run() }
                    }
                }
            }
        }
    }

    @ViewBuilder var eventRow: some View {
        if let e = cal.events.first {
            HStack(spacing: 7) {
                Capsule().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title ?? "Etkinlik").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(eventTime(e)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
            }
        } else {
            Text(cal.denied ? "Takvim izni yok" : "Yaklaşan etkinlik yok")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
        }
    }

    func eventTime(_ e: EKEventAlias) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        if e.startDate <= Date() { return "Şimdi · \(f.string(from: e.endDate)) bitiş" }
        let mins = Int(e.startDate.timeIntervalSinceNow / 60)
        if mins < 60 { return "\(mins) dk sonra" }
        return f.string(from: e.startDate)
    }
}

struct QuickButton: View {
    let icon: String
    let on: Bool
    let tint: Color
    let help: String      // üzerine gelince simgenin yerini alan yazı
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .opacity(hovering ? 0 : 1).scaleEffect(hovering ? 0.5 : 1)
                Text(help).font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
                    .padding(.horizontal, 4)
                    .opacity(hovering ? 1 : 0).scaleEffect(hovering ? 1 : 0.6)
            }
            .frame(maxWidth: .infinity).frame(height: 34)
            .foregroundStyle(on ? .black : .white.opacity(0.85))
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? tint : .white.opacity(hovering ? 0.16 : 0.1)))
        }
        .buttonStyle(PressStyle())
        .background(HoverTracker { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { hovering = h } })
    }
}

// MARK: - Shelf

struct ShelfView: View {
    @ObservedObject var shelf = ShelfService.shared
    var body: some View {
        HStack(spacing: 12) {
            ShelfZone()
            AirDropZone()
        }
    }
}

/// Dosyayı buraya sürükle → AirDrop alıcı seçicisi açılır. Tıklayınca raftaki tüm dosyalar gönderilir.
struct AirDropZone: View {
    @ObservedObject var shelf = ShelfService.shared
    @ObservedObject var state = NotchState.shared
    @State private var dropTargeted = false
    private var targeted: Bool { dropTargeted || state.airdropHover }
    @State private var hovering = false

    var body: some View {
        // Düğme (Button) yok: tıklama ve sürükle-bırak, en üstteki AppKit hedefi (FileDropTarget) tarafından karşılanır.
        // Arkada kalan bir hedef, üstündeki düğme yüzünden sürüklemeyi hiç alamıyordu.
        ZStack {
            VStack(spacing: 7) {
                AirDropGlyph()
                    .foregroundStyle(targeted ? .white : Color(red: 0.35, green: 0.70, blue: 1.0))
                    .frame(width: 40, height: 40)
                    .scaleEffect(targeted ? 1.18 : 1)
                Text("AirDrop").font(.system(size: 12, weight: .semibold))
                Text(shelf.urls.isEmpty ? "Dosyayı buraya sürükle" : (hovering ? "Raftakileri gönder" : "Buraya sürükle\nveya tıkla"))
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(width: 118).frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(targeted ? Color(red: 0.1, green: 0.45, blue: 0.95).opacity(0.55)
                                   : Color(red: 0.1, green: 0.45, blue: 0.95).opacity(hovering ? 0.22 : 0.14))
            )
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(red: 0.35, green: 0.70, blue: 1.0).opacity(targeted ? 0.9 : 0.35), lineWidth: 1.2))
        }
        .frame(width: 118).frame(maxHeight: .infinity)
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .overlay(FileDropTarget(name: "airdrop", onTargeted: { dropTargeted = $0 },
                                onDrop: { AirDrop.send($0) },
                                onClick: { AirDrop.send(shelf.urls) }))
    }
}

/// Dosya bırakma alanı (AppKit NSDraggingDestination): SwiftUI'nin onDrop'una göre nonactivating panelde daha güvenilir.
/// Sürüklenen dosya adreslerini doğrudan sürükleme panosundan okur.
struct FileDropTarget: NSViewRepresentable {
    var name = ""
    var onTargeted: (Bool) -> Void
    var onDrop: ([URL]) -> Void
    var onClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DropView {
        let v = DropView(); v.onTargeted = onTargeted; v.onDrop = onDrop; v.onClick = onClick
        if name == "airdrop" { DropView.airdrop = v }
        return v
    }
    func updateNSView(_ v: DropView, context: Context) { v.onTargeted = onTargeted; v.onDrop = onDrop; v.onClick = onClick }
}

final class DropView: NSView {
    /// AirDrop kutusunun görünümü: sürükleme izleyicisi imlecin bunun üstünde olup olmadığına bakar.
    static weak var airdrop: DropView?
    var screenRect: NSRect? {
        guard let w = window else { return nil }
        return w.convertToScreen(convert(bounds, to: nil))
    }
    var onTargeted: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(sender).isEmpty else { return [] }
        onTargeted?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func mouseDown(with event: NSEvent) { if let c = onClick { c() } else { super.mouseDown(with: event) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingExited(_ sender: NSDraggingInfo?) { onTargeted?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted?(false)
        let list = urls(sender)
        guard !list.isEmpty else { return false }
        DispatchQueue.main.async { self.onDrop?(list) }
        return true
    }
}

/// AirDrop halkaları (SF Symbols'te yok): merkez nokta + altı açık iki halka.
struct AirDropGlyph: View {
    var body: some View {
        ZStack {
            Circle().frame(width: 7, height: 7)
            Circle().trim(from: 0.09, to: 0.91).stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .frame(width: 22, height: 22).rotationEffect(.degrees(90))
            Circle().trim(from: 0.09, to: 0.91).stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .frame(width: 38, height: 38).rotationEffect(.degrees(90))
        }
    }
}

struct ShelfZone: View {
    @ObservedObject var shelf = ShelfService.shared
    @State private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.18))
                .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? Color.accentColor.opacity(0.12) : .clear))
            if shelf.urls.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 24))
                    Text("Dosyaları buraya sürükle").font(.system(size: 12))
                    Text("Sonra istediğin yere geri sürükle").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                }.foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(shelf.urls, id: \.self) { u in ShelfItem(url: u) }
                        }.padding(12)
                    }
                    .frame(maxHeight: .infinity)
                    // Temizle düğmesi rafın en altında, içeriklerden ayrı
                    HStack {
                        Text("\(shelf.urls.count) dosya").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Button { withAnimation(.snappy) { shelf.clear() } } label: {
                            Label("Rafı temizle", systemImage: "trash").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 10).frame(height: 22)
                                .background(Capsule().fill(.white.opacity(0.1)))
                        }.buttonStyle(PressStyle())
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
        }
        .background(FileDropTarget(onTargeted: { targeted = $0 }, onDrop: { shelf.add($0) }))
    }
}

struct ShelfItem: View {
    let url: URL
    @ObservedObject var shelf = ShelfService.shared
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 46, height: 46)
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).frame(width: 68)
        }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("AirDrop ile gönder") { AirDrop.send([url]) }
            Button("Raftan kaldır") { shelf.remove(url) }
        }
    }
}

// MARK: - Clipboard

struct CopiedBanner: View {
    @ObservedObject var clip = ClipboardService.shared
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Kopyalandı").fontWeight(.semibold).foregroundStyle(.white)
            if let c = clip.lastColor {
                Circle().fill(c).frame(width: 12, height: 12).overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
            }
            if !clip.lastPreview.isEmpty {
                Text(clip.lastPreview).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .font(.system(size: 12, design: .rounded))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardView: View {
    @ObservedObject var clip = ClipboardService.shared
    @State private var copied: UUID?

    var body: some View {
        if clip.items.isEmpty {
            VStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 24))
                Text("Kopyaladıkların burada görünür").font(.system(size: 12))
                Text("Şifre yöneticisi kopyaları kaydedilmez").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
            }.foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack {
                    Text("\(clip.items.count) öğe").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button { withAnimation(.snappy) { clip.clear() } } label: {
                        Label("Tümünü sil", systemImage: "trash").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }.buttonStyle(PressStyle())
                }
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(clip.items) { item in
                            ClipRow(item: item, copied: $copied)
                                .transition(.asymmetric(insertion: .opacity,
                                                        removal: .opacity.combined(with: .move(edge: .trailing))))
                        }
                    }
                    .animation(.snappy(duration: 0.25), value: clip.items)
                }
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    @Binding var copied: UUID?
    @ObservedObject var clip = ClipboardService.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                clip.copy(item)
                copied = item.id
                let id = item.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == id { copied = nil } }
            } label: {
                let isCopied = copied == item.id
                HStack {
                    // Yazı küçülüp yerine "Kopyalandı" gelir; süre dolunca isim geri büyür
                    ZStack(alignment: .leading) {
                        Text(item.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1).font(.system(size: 12))
                            .scaleEffect(isCopied ? 0.5 : 1, anchor: .leading).opacity(isCopied ? 0 : 1)
                        Label("Kopyalandı", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                            .scaleEffect(isCopied ? 1 : 0.5, anchor: .leading).opacity(isCopied ? 1 : 0)
                    }
                    Spacer()
                    if !hovering && !isCopied {
                        Text(item.date, style: .relative).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: copied)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            if hovering {
                Button { withAnimation(.snappy(duration: 0.25)) { clip.remove(item) } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(PressStyle())
                .morph("Sil")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.13 : 0.07)))
        .background(HoverTracker { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } })
        .contextMenu {
            Menu("Yapay zeka ile…") {
                ForEach([AIAction.summarize, .fix, .rewrite, .toTR, .toEN, .explain]) { a in
                    Button(a.title) { AIState.shared.start(a, text: item.text) }
                }
            }
            Divider()
            Button("Sil", role: .destructive) { clip.remove(item) }
            Button("Tümünü sil", role: .destructive) { clip.clear() }
        }
    }
}

// MARK: - Timer

struct TimerView: View {
    @ObservedObject var timer = TimerService.shared
    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: timer.total > 0 ? timer.remaining / timer.total : 0)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.remaining)
                Text(timer.label).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach([5, 10, 25, 45], id: \.self) { m in
                        Button("\(m) dk") { timer.set(minutes: m) }
                            .buttonStyle(PressStyle()).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(.white.opacity(Int(timer.total / 60) == m ? 0.22 : 0.09)))
                    }
                }
                HStack(spacing: 10) {
                    Button { timer.running ? timer.pause() : timer.start() } label: {
                        Label(timer.running ? "Duraklat" : "Başlat", systemImage: timer.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).frame(height: 32)
                            .background(Capsule().fill(Color.orange)).foregroundStyle(.black)
                    }.buttonStyle(PressStyle())
                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise").frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }.buttonStyle(PressStyle()).tip("Sıfırla", .top)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stats

struct StatsView: View {
    @ObservedObject var stats = StatsService.shared
    var body: some View {
        HStack(spacing: 14) {
            ring("İŞLEMCİ", stats.cpu, .green)
            ring("BELLEK", stats.mem, .blue)
            ring("DİSK", stats.disk, .purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("CPU GEÇMİŞİ").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                Sparkline(values: stats.cpuHistory).stroke(Color.green, lineWidth: 1.8)
                    .frame(maxHeight: .infinity)
            }
            .padding(10).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
            .overlay(alignment: .topTrailing) {
                Button { CleanerWindow.show() } label: {
                    Label("Önbellek temizle", systemImage: "sparkles").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(PressStyle()).padding(7)
            }
        }
        .onAppear { stats.retain() }
        .onDisappear { stats.release() }
    }

    func ring(_ title: String, _ v: Double, _ c: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: v).stroke(c, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(.easeOut(duration: 0.6), value: v)
                Text("\(Int(v * 100))%").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            }.frame(width: 72, height: 72)
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct Sparkline: Shape {
    var values: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: r.maxY - r.height * CGFloat(v))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(Pref.openOnHover) var openOnHover = true
    @AppStorage(Pref.hoverDelay) var hoverDelay = 0.15
    @AppStorage(Pref.closeDelay) var closeDelay = 0.18
    @AppStorage(Pref.hotPadding) var hotPadding = 0.0
    @AppStorage(Pref.liveActivities) var live = true
    @AppStorage(Pref.haptics) var haptics = true
    @AppStorage(Pref.showShelf) var showShelf = true
    @AppStorage(Pref.showClipboard) var showClipboard = true
    @AppStorage(Pref.showTimer) var showTimer = true
    @AppStorage(Pref.showStats) var showStats = true
    @AppStorage(Pref.lyricsEnabled) var lyricsOn = false
    @AppStorage(Pref.lyricsInNotch) var lyricsInNotch = true
    @AppStorage(Pref.uiScale) var uiScale = 1.0
    @AppStorage(Pref.pillLines) var pillLines = 1
    @AppStorage(Pref.showArtwork) var showArtwork = true
    @AppStorage(Pref.showCalendar) var showCalendar = true
    @AppStorage(Pref.calDate) var calDate = true
    @AppStorage(Pref.calEvent) var calEvent = true
    @AppStorage(Pref.qbCaffeinate) var qbCaffeinate = true
    @AppStorage(Pref.qbTimer) var qbTimer = true
    @AppStorage(Pref.qbCapture) var qbCapture = true
    @AppStorage(Pref.qbColor) var qbColor = true
    @AppStorage(Pref.captureMode) var captureMode = "area"
    @AppStorage(Pref.captureClipboard) var captureClipboard = true
    @AppStorage(Pref.bgStyle) var bgStyle = "black"
    @AppStorage(Pref.bgColor) var bgHex = "#1F2A44"
    @AppStorage(Pref.styleCollapsed) var styleCollapsed = false
    @AppStorage(Pref.glassDensity) var glassDensity = 0.35
    @AppStorage(Pref.glassClear) var glassClear = true
    @AppStorage(Pref.autoUpdateCheck) var autoUpdateCheck = true
    @AppStorage(Pref.autoUpdateInstall) var autoUpdateInstall = true
    @ObservedObject var updater = UpdateService.shared
    @AppStorage(Pref.closedIcon) var closedIcon = "equalizer"
    @AppStorage(Pref.closedIconIdle) var closedIconIdle = false
    @AppStorage(Pref.hudVolume) var hudVolume = true
    @AppStorage(Pref.hudBrightness) var hudBrightness = true
    @AppStorage(Pref.hudKeyboard) var hudKeyboard = true
    @AppStorage(Pref.hudStyle) var hudStyle = "bar"
    @AppStorage(Pref.hudDuration) var hudDuration = 1.6
    @AppStorage(Pref.hudHideSystem) var hudHideSystem = false
    @AppStorage(Pref.hudStep) var hudStep = 6.0
    @ObservedObject var hud = HUDService.shared
    @AppStorage(Pref.bannerBluetooth) var bannerBluetooth = true
    @AppStorage(Pref.privacyIndicator) var privacyIndicator = true
    @AppStorage(Pref.focusIndicator) var focusIndicator = false
    @AppStorage(Pref.downloadIndicator) var downloadIndicator = false
    @AppStorage(Pref.weatherEnabled) var weatherEnabled = false
    @ObservedObject var focusSvc = FocusService.shared
    @ObservedObject var weatherSvc = WeatherService.shared
    @State private var cityQuery = UserDefaults.standard.string(forKey: Pref.weatherCity) ?? ""
    @AppStorage(Pref.collapsedExtraW) var exW = 0.0
    @AppStorage(Pref.collapsedExtraH) var exH = 0.0
    // Seçici kendi hassas rengini tutar; hex yalnızca kayda yazılır (geri okunmaz) → sürüklerken renk kaymaz
    @State private var pickerColor = Color(hex: UserDefaults.standard.string(forKey: Pref.bgColor) ?? "#1F2A44")
    @State private var loginItem = LaunchAtLogin.enabled

    var body: some View {
        Form {
            Section("Görünüm") {
                HStack {
                    Text("Boyut")
                    Slider(value: $uiScale, in: 0.8...1.3, step: 0.05)
                    Text("\(Int((uiScale * 100).rounded()))%").monospacedDigit().frame(width: 50)
                    Button("Sıfırla") { uiScale = 1.0 }.disabled(uiScale == 1.0)
                }
                Toggle("Albüm kapağını göster", isOn: $showArtwork)
                HStack {
                    Text("Kapalı notch genişliği")
                    Slider(value: $exW, in: -60...80, step: 2, onEditingChanged: { NotchController.shared.previewCollapsed(editing: $0) })
                    Text(exW == 0 ? "Varsayılan" : (exW > 0 ? "+\(Int(exW)) pt" : "−\(Int(-exW)) pt")).monospacedDigit().frame(width: 70)
                }
                HStack {
                    Text("Kapalı notch yüksekliği")
                    Slider(value: $exH, in: -14...24, step: 1, onEditingChanged: { NotchController.shared.previewCollapsed(editing: $0) })
                    Text(exH == 0 ? "Varsayılan" : (exH > 0 ? "+\(Int(exH)) pt" : "−\(Int(-exH)) pt")).monospacedDigit().frame(width: 70)
                }
                Text("Eksi değerler kapalı notch'u küçültür. Notch'lu Mac'lerde ortadaki kısım donanımdır, o küçülmez; küçülme yanlardaki kanatlarda ve notch'suz Mac'lerde görünür. Kaydırırken notch geçici olarak kapalı hâlde gösterilir.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Arka plan", selection: $bgStyle) {
                    Text("Siyah (notch ile bütünleşik)").tag("black")
                    Text("Düz renk").tag("color")
                    Text("Albüm rengi").tag("album")
                    if #available(macOS 26, *) { Text("Liquid Glass").tag("glass") }
                }
                if bgStyle == "glass" {
                    Picker("Cam tipi", selection: $glassClear) {
                        Text("Şeffaf (iOS Liquid Glass)").tag(true)
                        Text("Buzlu").tag(false)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("Cam yoğunluğu")
                        Slider(value: $glassDensity, in: 0...1, step: 0.05)
                        Text("\(Int(glassDensity * 100))%").monospacedDigit().frame(width: 50)
                    }
                    Text("Yoğunluk arttıkça cam koyulaşır ve yazılar daha okunaklı olur. Düşük yoğunlukta arkadaki duvar kâğıdı daha çok görünür.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if bgStyle == "color" {
                    ColorPicker("Renk", selection: $pickerColor, supportsOpacity: false)
                        .onChange(of: pickerColor) { _, c in bgHex = c.hexString }
                }
                Toggle("Kapalıyken de uygula", isOn: $styleCollapsed).disabled(bgStyle == "black")
                    .collapsesNotch()
                    .onChange(of: styleCollapsed) { _, _ in NotchController.shared.showCollapsedResult() }
                Text("Kapalıyken notch varsayılan olarak siyah kalır (donanım notch'uyla bütünleşir); bu seçenek açılırsa seçtiğin stil kapalı hâle de uygulanır. Fiziksel notch'un olduğu kısım her zaman siyah görünür.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Davranış") {
                Toggle("Üzerine gelince aç (kapalıysa tıkla)", isOn: $openOnHover)
                HStack { Text("Açılma gecikmesi"); Slider(value: $hoverDelay, in: 0...0.6); Text("\(Int(hoverDelay * 1000)) ms").monospacedDigit().frame(width: 60) }
                HStack { Text("Kapanma gecikmesi"); Slider(value: $closeDelay, in: 0...1.5, step: 0.05); Text("\(Int(closeDelay * 1000)) ms").monospacedDigit().frame(width: 60) }
                HStack { Text("Açılma alanı"); Slider(value: $hotPadding, in: 0...80, step: 2, onEditingChanged: { NotchController.shared.hotPreview(editing: $0) }); Text(hotPadding == 0 ? "Notch" : "+\(Int(hotPadding)) pt").monospacedDigit().frame(width: 60) }
                Color.clear.frame(height: 0).onChange(of: hotPadding) { _, _ in NotchController.shared.hotPreview(editing: nil) }
                Text("Açılma alanı: fare notch'a bu kadar yaklaşınca açılır (yanlara ve aşağıya doğru genişler). Kapanma gecikmesi: fare notch'tan çıktıktan ne kadar sonra kapanacağı.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Canlı etkinlikler (müzik, zamanlayıcı, şarj)", isOn: $live)
                Toggle("Dokunsal geri bildirim", isOn: $haptics)
                Toggle("Girişte otomatik başlat", isOn: Binding(get: { loginItem }, set: { loginItem = $0; LaunchAtLogin.set($0) }))
            }
            Section("Yapay Zeka") { AISettingsSection() }
            Section("Bakım") {
                Button("Önbellek Temizleyiciyi aç…") { CleanerWindow.show() }
                Text("Gereksiz önbellek ve günlük dosyalarını neye ait olduklarıyla listeler; sen onaylamadan hiçbir şey silmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Güncellemeler") {
                HStack {
                    Text("Sürüm \(updater.current)")
                    Spacer()
                    Text(updater.status).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Güncellemeleri otomatik denetle", isOn: $autoUpdateCheck)
                Toggle("Yeni sürümü otomatik kur ve yeniden başlat", isOn: $autoUpdateInstall).disabled(!autoUpdateCheck)
                HStack {
                    Button("Şimdi denetle") { updater.check() }.disabled(updater.busy)
                    if updater.available != nil { Button("Şimdi kur") { updater.install() } }
                }
                Text("Sürümler GitHub'dan (Farukzbek/Mate-Notch) denetlenir. İndirilen paketin sağlama toplamı ve imzası doğrulanır. Kayıt sürerken veya notch açıkken kurulum beklenir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kapalı notch simgesi") {
                Picker("Müzik göstergesi", selection: $closedIcon) {
                    ForEach(ClosedIcon.allCases) { i in Label(i.title, systemImage: i.symbol).tag(i.rawValue) }
                }
                .collapsesNotch()
                .onChange(of: closedIcon) { _, _ in NotchController.shared.showCollapsedResult() }
                Toggle("İçerik oynatılmıyorken de simgeyi göster", isOn: $closedIconIdle)
                    .disabled(closedIcon == "none")
                    .collapsesNotch()
                    .onChange(of: closedIconIdle) { _, _ in NotchController.shared.showCollapsedResult() }
                Text("Müzik çalarken notch'un sağında görünür; ses dalgası ve diğer simgeler çalarken hareket eder. Sözler açık ya da kapalı olsun gösterge her zaman görünür. Bu ayarlarla uğraşırken notch kapalı hâlde gösterilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ses ve parlaklık göstergesi") {
                Toggle("Ses değişikliklerini notch'ta göster", isOn: $hudVolume).collapsesNotch()
                Toggle("Parlaklık değişikliklerini notch'ta göster", isOn: $hudBrightness).collapsesNotch()
                Toggle("Klavye aydınlatması değişikliklerini göster", isOn: $hudKeyboard)
                    .disabled(!hud.keyboardAvailable).collapsesNotch()
                Picker("Gösterge stili", selection: $hudStyle) {
                    Text("Çubuk + yüzde").tag("bar")
                    Text("Yalnızca yüzde").tag("percent")
                    Text("Yalnızca simge").tag("icon")
                }
                .collapsesNotch()
                .onChange(of: hudStyle) { _, _ in NotchController.shared.showCollapsedResult(); HUDService.shared.preview(.volume) }
                HStack {
                    Text("Gösterge süresi")
                    Slider(value: $hudDuration, in: 0.8...4, step: 0.1)
                    Text(String(format: "%.1f sn", hudDuration)).monospacedDigit().frame(width: 50)
                }.collapsesNotch()
                HStack {
                    Text("Önizle")
                    Button("Ses") { NotchController.shared.showCollapsedResult(); HUDService.shared.preview(.volume) }
                    Button("Parlaklık") { NotchController.shared.showCollapsedResult(); HUDService.shared.preview(.brightness) }
                    if hud.keyboardAvailable { Button("Klavye") { NotchController.shared.showCollapsedResult(); HUDService.shared.preview(.keyboard) } }
                }
                Toggle("Tuşları Mate Notch işlesin: sistem göstergesi gizlenir, adım ayarlanır (deneysel)", isOn: $hudHideSystem)
                    .onChange(of: hudHideSystem) { _, _ in HUDService.shared.applyHideSystem(userInitiated: true) }
                HStack {
                    Text("Tuş başına değişim")
                    Slider(value: $hudStep, in: 1...20, step: 1)
                    Text("%\(Int(hudStep))").monospacedDigit().frame(width: 40)
                }
                .disabled(!hudHideSystem).opacity(hudHideSystem ? 1 : 0.5)
                if !hudHideSystem {
                    Text("Ses açma/kısma ve parlaklık açma/kısma tuşlarının her basışta kaç yüzde değişeceği. Bu ayar yalnızca yukarıdaki seçenek açıkken geçerli (tuşları Mate Notch işlediği için).")
                        .font(.caption).foregroundStyle(.orange)
                }
                if hudHideSystem && hud.axWaiting {
                    Button("Erişilebilirlik ayarlarını aç") { NSWorkspace.shared.open(HUDService.accessibilityURL) }
                }
                if !hud.hideStatus.isEmpty { Text(hud.hideStatus).font(.caption).foregroundStyle(hudHideSystem ? .green : .orange) }
                Text("Bu seçenek açıkken ses, parlaklık ve klavye ışığı tuşlarını Mate Notch işler: macOS'un ekran ortasındaki karesi çıkmaz, ses/parlaklık adımı yukarıdaki yüzdeyle değişir (⇧⌥ ile dörtte biri). Klavye ışığı macOS'un kendi adımında (≈%6) kalır. Klavye ışığının boşta kalınca kendiliğinden kısılması/geri açılması için gösterge çıkmaz. Erişilebilirlik izni ister. Kapatınca tuşlar normale döner. Parlaklık ve klavye ışığı için macOS'un özel arayüzleri kullanılır; yerleşik ekranlarda çalışır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Göstergeler ve bildirimler") {
                Toggle("Bluetooth kulaklık bağlanınca bildir (AirPods pil durumu dahil)", isOn: $bannerBluetooth)
                Toggle("Kamera / mikrofon kullanımdayken göster", isOn: $privacyIndicator).collapsesNotch()
                Toggle("Odak (Rahatsız Etmeyin) açıkken ay simgesi göster", isOn: $focusIndicator).collapsesNotch()
                    .onChange(of: focusIndicator) { _, on in if on { FocusService.shared.enable() } else { FocusService.shared.refresh() } }
                if focusIndicator && !focusSvc.status.isEmpty { Text(focusSvc.status).font(.caption).foregroundStyle(.secondary) }
                Toggle("İndirme ilerlemesini göster (İndirilenler klasörü)", isOn: $downloadIndicator).collapsesNotch()
                Toggle("Hava durumunu göster (Ana Sayfa)", isOn: $weatherEnabled)
                    .onChange(of: weatherEnabled) { _, _ in WeatherService.shared.refresh() }
                if weatherEnabled {
                    HStack {
                        TextField("Şehir (ör. İstanbul)", text: $cityQuery).onSubmit { WeatherService.shared.search(cityQuery) }
                        Button("Ara") { WeatherService.shared.search(cityQuery) }
                    }
                    if !weatherSvc.searchStatus.isEmpty { Text(weatherSvc.searchStatus).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Kamera/mikrofon göstergesi izin gerektirmez. Odak ve İndirilenler için macOS bir kez izin sorar. Hava durumu Open-Meteo'dan gelir (anahtar gerekmez); yalnızca seçtiğin şehrin adı/konumu gönderilir, Mac'inin konumu kullanılmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ana Sayfa") {
                Toggle("Takvim kartı", isOn: $showCalendar)
                Toggle("Bugünün tarihini göster", isOn: $calDate).disabled(!showCalendar)
                Toggle("Sıradaki etkinliği göster", isOn: $calEvent).disabled(!showCalendar)
                Toggle("Uyanık tut düğmesi", isOn: $qbCaffeinate)
                Toggle("25 dk odak düğmesi", isOn: $qbTimer)
                Toggle("Ekran görüntüsü düğmesi", isOn: $qbCapture)
                Toggle("Renk seçici düğmesi (ekrandan renk al, hex kodunu kopyala)", isOn: $qbColor)
            }
            Section("Ekran görüntüsü butonu") {
                Picker("Buton ne yapsın", selection: $captureMode) {
                    Text("Seçilen alanın görüntüsü").tag("area")
                    Text("Tam ekran görüntüsü").tag("full")
                    Text("Video kaydı (tekrar basınca durur)").tag("video")
                    Text("Sistem çekim aracı (⇧⌘5)").tag("tool")
                }
                Toggle("Görüntüyü panoya kopyala (kapalıysa Masaüstü'ne kaydet)", isOn: $captureClipboard)
                    .disabled(captureMode == "video" || captureMode == "tool")
                Text("Video kayıtları her zaman Masaüstü'ne .mov olarak kaydedilir. Kayıt sırasında notch'ta kırmızı \"KAYIT\" görünür. İlk kullanımda macOS Ekran Kaydı izni isteyebilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mate Lyrics") {
                Toggle("Şarkı sözlerini göster", isOn: $lyricsOn)
                Toggle("Notch'ta anlık söz satırı", isOn: $lyricsInNotch).disabled(!lyricsOn)
                    .collapsesNotch()
                    .onChange(of: lyricsInNotch) { _, _ in NotchController.shared.showCollapsedResult() }
                Picker("Notch'ta kaç satır görünsün", selection: $pillLines) {
                    Text("1 satır").tag(1)
                    Text("2 satır (anlık + sonraki)").tag(2)
                }
                .pickerStyle(.segmented).disabled(!lyricsOn || !lyricsInNotch)
                .collapsesNotch()
                .onChange(of: pillLines) { _, _ in NotchController.shared.showCollapsedResult() }
                Text("Söz satırı Ana Sayfa'da şarkı adının altında görünür; oradaki 💬 düğmesiyle de açıp kapatabilirsin. Sözler lrclib.net'ten gelir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sekmeler") {
                Toggle("Raf", isOn: $showShelf)
                Toggle("Pano geçmişi", isOn: $showClipboard)
                Toggle("Zamanlayıcı", isOn: $showTimer)
                Toggle("Sistem durumu", isOn: $showStats)
            }
            Section("Kısayol") {
                Text("⌃⌥Space — Mate Notch'u aç / kapat")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, maxWidth: 520, minHeight: 320, maxHeight: .infinity)
    }
}


// MARK: - Mate Lyrics entegrasyonu

struct LyricPill: View {
    @ObservedObject var lyrics = LyricsService.shared
    @ObservedObject var media = MediaService.shared
    @AppStorage(Pref.pillLines) var pillLines = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let lines: [LyricLine] = { if case .synced(let l) = lyrics.state { return l } else { return [] } }()
            let idx = lyrics.index(in: lines, at: media.position) ?? -1
            VStack(spacing: 2) {
                ForEach(0..<(pillLines >= 2 ? 2 : 1), id: \.self) { o in
                    let i = idx + o
                    let valid = lines.indices.contains(i)
                    let raw = valid ? lines[i].text : " "
                    let text = raw == "♪" ? "♪  ♪  ♪" : raw
                    Text(text)
                        .font(.system(size: o == 0 ? 12.5 : 11, weight: o == 0 ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(o == 0 ? (raw == "♪" ? 0.45 : 0.95) : 0.38))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity)
                        .id(valid ? lines[i].id : -1000 - i)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: idx)
        }
    }
}

/// Ana sayfadaki müzik kartında şarkı adının altındaki tek satır söz.
struct CardLyric: View {
    @ObservedObject var lyrics = LyricsService.shared
    @ObservedObject var media = MediaService.shared
    @AppStorage(Pref.lyricsEnabled) var on = false
    @State private var browse = 0                 // kaydırarak gezinme: çalan satıra göre kaç satır ötede
    @State private var lastBrowse = Date.distantPast
    @State private var hoverRow: Int?
    @State private var plainTop = 0               // senkronsuz sözlerde ilk görünen satır

    /// Yalnızca sözü olan (senkron) veya enstrümantal şarkılarda göster; "söz yok" yazısı yok, alan hiç açılmaz.
    var visible: Bool {
        guard on else { return false }
        switch lyrics.state {
        case .synced, .instrumental: return true
        case .plain(let rows): return rows.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        default: return false
        }
    }

    var body: some View {
        Group {
            if visible { block.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading))) }
        }
        .animation(.smooth(duration: 0.4), value: visible)
        .onChange(of: lyrics.state) { _, _ in browse = 0; plainTop = 0 }
        // Kaydırmayı bırakınca 3 sn sonra çalan satıra geri dön
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if browse != 0, Date().timeIntervalSince(lastBrowse) > 3 { withAnimation(.snappy) { browse = 0 } }
        }
    }

    var block: some View {
        Group {
            switch lyrics.state {
            case .synced(let lines): syncedBlock(lines)
            case .plain(let rows): plainBlock(rows)
            default: dim("Enstrümantal")
            }
        }
        .lineLimit(1).minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
        .clipped()
    }

    func syncedBlock(_ lines: [LyricLine]) -> some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let idx = lyrics.index(in: lines, at: media.position) ?? -1
            let center = idx + browse
            VStack(alignment: .leading, spacing: 0) {
                ForEach([-1, 0, 1], id: \.self) { o in
                    slot(lines, center + o, current: center + o == idx, browsing: browse != 0 && o == 0)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(hoverRow == o + 1 ? 0.10 : 0)))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: center)
        }
        .overlay(LyricInteraction(
            onScroll: { scroll($0, lines) },
            onClick: { click($0, lines) },
            onHover: { hoverRow = $0 },
            menu: { menu($0, lines) }))
    }

    /// Senkronu olmayan sözler: yalnızca AÇIK notch'ta, durağan metin olarak (kaydırılabilir). Kapalı notch'ta gösterilmez.
    func plainBlock(_ rows: [String]) -> some View {
        let lines = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { o in
                let i = plainTop + o
                Text(lines.indices.contains(i) ? lines[i] : " ")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(hoverRow == o ? 0.10 : 0)))
            }
        }
        .overlay(LyricInteraction(
            onScroll: { plainTop = min(max(plainTop + $0, 0), max(0, lines.count - 3)) },
            onClick: { _ in },
            onHover: { hoverRow = $0 },
            menu: { row in
                let m = NSMenu()
                let i = plainTop + row
                if lines.indices.contains(i) {
                    let t = lines[i]
                    m.addItem(ActionItem("Bu satırı Türkçeye çevir") { AIState.shared.start(.toTR, text: t) })
                    m.addItem(ActionItem("Bu satırı açıkla") { AIState.shared.start(.explain, text: t) })
                }
                let info = NSMenuItem(title: "Senkronsuz söz (zamanlaması yok)", action: nil, keyEquivalent: ""); info.isEnabled = false
                m.addItem(info)
                return m
            }))
    }

    private func currentIndex(_ lines: [LyricLine]) -> Int { lyrics.index(in: lines, at: media.position) ?? -1 }

    /// Yukarı/aşağı kaydırma: satırlar arasında gezin (çalan satır değişmez, müzik kesilmez).
    private func scroll(_ d: Int, _ lines: [LyricLine]) {
        let idx = currentIndex(lines)
        let target = min(max(idx + browse + d, 0), lines.count - 1)
        browse = target - idx
        lastBrowse = Date()
    }

    /// Satıra tıkla: şarkıyı o satırın zamanına sar.
    private func click(_ row: Int, _ lines: [LyricLine]) {
        let i = currentIndex(lines) + browse + (row - 1)
        guard lines.indices.contains(i) else { return }
        media.seek(to: max(0, lines[i].time - lyrics.offset))
        withAnimation(.snappy) { browse = 0 }
    }

    private func menu(_ row: Int, _ lines: [LyricLine]) -> NSMenu {
        let m = NSMenu()
        let i = currentIndex(lines) + browse + (row - 1)
        if lines.indices.contains(i), lines[i].text != "♪" {
            let t = lines[i].text
            m.addItem(ActionItem("Bu satırı Türkçeye çevir") { AIState.shared.start(.toTR, text: t) })
            m.addItem(ActionItem("Bu satırı açıkla") { AIState.shared.start(.explain, text: t) })
            m.addItem(.separator())
        }
        m.addItem(ActionItem("Sözleri öne al (+0,25 sn)") { lyrics.adjust(by: 0.25) })
        m.addItem(ActionItem("Sözleri geciktir (−0,25 sn)") { lyrics.adjust(by: -0.25) })
        let info = NSMenuItem(title: String(format: "Senkron farkı: %+.2f sn", lyrics.offset), action: nil, keyEquivalent: "")
        info.isEnabled = false
        m.addItem(info)
        return m
    }

    /// Çalan satır parlak; gezinirken seçili satır biraz parlar; diğerleri sönük.
    func slot(_ lines: [LyricLine], _ i: Int, current: Bool, browsing: Bool) -> some View {
        let valid = lines.indices.contains(i)
        let raw = valid ? lines[i].text : " "
        let text = raw == "♪" ? "♪  ♪  ♪" : raw
        return Text(text)
            .font(.system(size: current ? 13.5 : 11.5, weight: current ? .bold : .medium, design: .rounded))
            .foregroundStyle(.white.opacity(current ? 1 : (browsing ? 0.66 : 0.32)))
            .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
            .id(valid ? lines[i].id : -1000 - i)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
    }

    func dim(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
    }
}

/// Menü öğesi + kapanış (blok).
final class ActionItem: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { block() }
}

/// Söz bloğunun üstündeki görünmez katman: dikey kaydırma, satıra tıklama, üzerine gelme ve sağ tık menüsü.
/// (Üstteki SwiftUI düğmeleri/jestleri bu olayları almaz; o yüzden tek bir AppKit katmanı hepsini karşılar.)
struct LyricInteraction: NSViewRepresentable {
    var onScroll: (Int) -> Void           // +1: sonraki satıra, −1: öncekine
    var onClick: (Int) -> Void            // satır sırası 0...2
    var onHover: (Int?) -> Void
    var menu: (Int) -> NSMenu
    func makeNSView(context: Context) -> LyricInteractionView { let v = LyricInteractionView(); apply(v); return v }
    func updateNSView(_ v: LyricInteractionView, context: Context) { apply(v) }
    private func apply(_ v: LyricInteractionView) { v.onScroll = onScroll; v.onClick = onClick; v.onHover = onHover; v.menuProvider = menu }
}

final class LyricInteractionView: NSView {
    var onScroll: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onHover: ((Int?) -> Void)?
    var menuProvider: ((Int) -> NSMenu)?
    private var accum: CGFloat = 0
    private let rowHeight: CGFloat = 16

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func row(_ e: NSEvent) -> Int { min(2, max(0, Int(convert(e.locationInWindow, from: nil).y / rowHeight))) }

    override func scrollWheel(with e: NSEvent) {
        guard abs(e.scrollingDeltaY) >= abs(e.scrollingDeltaX) else { super.scrollWheel(with: e); return }
        // Parmak yukarı = sonraki satırlar (içerik parmakla birlikte kayar)
        accum += -(e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 12)
        let step: CGFloat = 14
        while accum >= step { onScroll?(1); accum -= step }
        while accum <= -step { onScroll?(-1); accum += step }
        if e.phase == .ended || e.phase == .cancelled { accum = 0 }
    }
    override func mouseDown(with e: NSEvent) { onClick?(row(e)) }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(row(event)) }
    override func mouseMoved(with e: NSEvent) { onHover?(row(e)) }
    override func mouseExited(with e: NSEvent) { onHover?(nil) }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
}

/// Sözleri Ana Sayfa'dan aç/kapat.
struct LyricsToggle: View {
    @AppStorage(Pref.lyricsEnabled) var on = false
    var body: some View {
        Button { withAnimation(.smooth(duration: 0.4)) { on.toggle() } } label: {
            Image(systemName: on ? "quote.bubble.fill" : "quote.bubble")
                .foregroundStyle(on ? Color.white : .white.opacity(0.45))
        }
        .buttonStyle(PressStyle())
        .frame(width: 24, height: 24)     // kapsül (24 pt) sığsın, alttan/üstten kırpılmasın
        .morph(on ? "Sözleri kapat" : "Sözleri aç", trailing: true)
    }
}

// MARK: - Hover etiketleri

/// NSTrackingArea(.activeAlways): panel tuşa odaklanmamış (nonactivating) olsa da hover güvenilir çalışır.
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> TrackerView { let v = TrackerView(); v.onChange = onChange; return v }
    func updateNSView(_ v: TrackerView, context: Context) { v.onChange = onChange }
}

final class TrackerView: NSView {
    var onChange: ((Bool) -> Void)?
    private var inside = false

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(recheck), name: .mouseTick, object: nil)
        } else {
            set(false)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    /// Enter/exit olayları hızlı harekette kaçabilir: durumu her zaman farenin gerçek konumundan doğrula.
    @objc func recheck() {
        guard let w = window, w.isVisible else { set(false); return }
        set(bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private func set(_ v: Bool) {
        guard v != inside else { return }
        inside = v
        onChange?(v)
    }

    override func mouseEntered(with event: NSEvent) { recheck() }
    override func mouseExited(with event: NSEvent) { set(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct Tip: ViewModifier {
    let text: String
    let edge: VerticalEdge
    @State private var hovering = false
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .background(HoverTracker { hovering = $0 })
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                if show {
                    Text(text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.95)))
                        .fixedSize()
                        .offset(y: edge == .bottom ? 24 : -24)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: edge == .bottom ? .top : .bottom)))
                }
            }
            .zIndex(show ? 10 : 0)
            .task(id: hovering) {
                if hovering {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    if !Task.isCancelled { withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { show = true } }
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { show = false }
                }
            }
    }
}

extension View {
    func tip(_ text: String, _ edge: VerticalEdge = .bottom) -> some View { modifier(Tip(text: text, edge: edge)) }
}


/// Üzerine gelince simge yazıya dönüşür. Yazı düzene dahil değil (komşuları itmez), simgenin üstünde büyür.
struct TabButton: View {
    let tab: Tab
    let selected: Bool
    var leading = false          // soldaki ilk sekme: yazı sağa doğru açılır, notch kenarından taşmaz
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule().fill(.white.opacity(selected ? 0.18 : 0)).frame(width: 32, height: 26)
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .white : .white.opacity(0.45))
                    .opacity(hovering ? 0 : 1)
                    .scaleEffect(hovering ? 0.6 : 1)
            }
            .frame(width: 32, height: 26)
            .overlay(alignment: leading ? .leading : .center) {
                if hovering {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Capsule().fill(Color(white: 0.22)))
                        .transition(.scale(scale: 0.5, anchor: leading ? .leading : .center).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .background(HoverTracker { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { hovering = h } })
        .zIndex(hovering ? 10 : 0)
    }
}


/// Küçük simge butonları: üzerine gelince simgenin üstünde yazı kapsülü açılır (düzeni itmez, tıklamayı engellemez).
struct Morph: ViewModifier {
    let text: String
    var trailing = false       // kenardaki butonlar: yazı kapsülü içeri (sola) doğru açılır, taşmaz
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .overlay(alignment: trailing ? .trailing : .center) {
                if hovering {
                    Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(Color(white: 0.24)))
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .background(HoverTracker { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { hovering = h } })
            .zIndex(hovering ? 10 : 0)
    }
}

extension View { func morph(_ text: String, trailing: Bool = false) -> some View { modifier(Morph(text: text, trailing: trailing)) } }


// MARK: - Yapay zeka sekmesi

struct AIView: View {
    @ObservedObject var ai = AIState.shared
    @ObservedObject var svc = AIService.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AIAction.chips) { a in
                        Button { ai.run(a) } label: {
                            Label(a.title, systemImage: a.icon).font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 9).frame(height: 24)
                                .background(Capsule().fill(.white.opacity(0.11)))
                        }.buttonStyle(PressStyle()).disabled(ai.busy)
                    }
                    if MediaService.shared.track != nil {
                        Button { ai.run(.song) } label: {
                            Label(AIAction.song.title, systemImage: AIAction.song.icon).font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(.white.opacity(0.11)))
                        }.buttonStyle(PressStyle()).disabled(ai.busy)
                    }
                    Button { ai.ocr() } label: {
                        Label("Ekrandan metin", systemImage: "text.viewfinder").font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(.white.opacity(0.11)))
                    }.buttonStyle(PressStyle()).disabled(ai.busy)
                }
            }
            .frame(height: 24)

            HStack(spacing: 6) {
                TextField("Metin yaz, panodan al veya bir şey sor…", text: $ai.input)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { ai.run(.ask) }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.09)))
                Button {
                    if let t = ClipboardService.shared.items.first?.text { ai.input = t }
                } label: { Image(systemName: "doc.on.clipboard").frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.09))) }
                    .buttonStyle(PressStyle()).morph("Panodan al")
                Button { ai.run(.ask) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 28, height: 28).background(Circle().fill(.white))
                }.buttonStyle(PressStyle()).disabled(ai.busy).morph("Sor")
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06))
                if ai.busy {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Düşünüyor…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)) }
                        .padding(12)
                } else if let e = ai.error {
                    Text(e).font(.system(size: 11.5)).foregroundStyle(.orange).padding(12)
                } else if ai.output.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bir eylem seç ya da soru sor").font(.system(size: 12, weight: .medium))
                        Text(svc.active() == .onDevice ? "Cihaz içi Apple modeli kullanılıyor (veri Mac'inden çıkmaz)"
                                                       : "\(svc.active().title) kullanılıyor")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                        if svc.active() == .onDevice, let p = svc.onDeviceProblem {
                            Text(p).font(.system(size: 10.5)).foregroundStyle(.orange)
                        }
                    }.padding(12)
                } else {
                    ScrollView(showsIndicators: false) {
                        Text(ai.output).font(.system(size: 12.5)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 26)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 8) {
                            Text(ai.providerLabel).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                            Button { ClipboardService.shared.copyText(ai.output) } label: {
                                Label("Kopyala", systemImage: "doc.on.doc").font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(.white.opacity(0.14)))
                            }.buttonStyle(PressStyle())
                        }.padding(7)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: focused) { _, f in NotchState.shared.inputFocused = f }
        .onDisappear { NotchState.shared.inputFocused = false }
    }
}

// MARK: - Yapay zeka ayarları

struct AISettingsSection: View {
    @ObservedObject var svc = AIService.shared
    @AppStorage(Pref.aiProvider) var provider = "auto"
    @AppStorage(Pref.showAI) var showAI = true

    var body: some View {
        Toggle("Yapay zeka sekmesi ve düğmesi", isOn: $showAI)
        Picker("Kullanılacak model", selection: $provider) {
            Text("Otomatik (bağlı bulut model varsa o, yoksa cihaz içi)").tag("auto")
            Text("Cihaz içi (Apple)").tag("onDevice")
            ForEach([AIProvider.claude, .openai, .gemini]) { p in Text(p.title).tag(p.rawValue) }
        }
        HStack {
            Text("Cihaz içi model").font(.callout)
            Spacer()
            if let p = svc.onDeviceProblem { Text(p).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
            else { Text("Hazır ✓ (anahtar gerekmez, veri Mac'inden çıkmaz)").font(.caption).foregroundStyle(.green) }
        }
        ForEach([AIProvider.claude, .openai, .gemini]) { p in ProviderRow(provider: p) }
        Text("Bulut modeli bağlamazsan tüm yapay zeka özellikleri cihaz içi Apple modeliyle çalışır. Bulut model bağlarsan metinler o sağlayıcıya gönderilir; API anahtarın Mac'in Anahtarlığı'nda saklanır ve kullandıkça kendi hesabından ücretlendirilir.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct ProviderRow: View {
    let provider: AIProvider
    @ObservedObject var svc = AIService.shared
    @State private var key = ""

    var body: some View {
        let _ = svc.revision
        let connected = svc.hasKey(provider)
        let busy = svc.busy.contains(provider.rawValue)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.title).font(.headline)
                Spacer()
                Text(svc.status[provider.rawValue] ?? (connected ? "Bağlı ✓" : "Bağlı değil"))
                    .font(.caption).foregroundStyle(connected ? .green : .secondary).lineLimit(2).multilineTextAlignment(.trailing)
            }
            if connected {
                HStack {
                    Picker("Model", selection: Binding(get: { svc.model(provider) }, set: { svc.setModel($0, provider) })) {
                        ForEach(modelList, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Yenile") { Task { await svc.refreshModels(provider) } }
                    Button("Bağlantıyı kes", role: .destructive) { svc.disconnect(provider) }
                }
            } else {
                HStack {
                    SecureField("API anahtarını yapıştır", text: $key)
                    Button(busy ? "Bağlanıyor…" : "Bağla") {
                        let k = key; key = ""
                        Task { await svc.connect(provider, key: k) }
                    }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                Text("Anahtarı \(provider.keyPage) adresinden alabilirsin.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .task { if connected, svc.models[provider.rawValue] == nil { await svc.refreshModels(provider) } }
    }

    var modelList: [String] {
        var l = svc.models[provider.rawValue] ?? []
        let cur = svc.model(provider)
        if !l.contains(cur) { l.insert(cur, at: 0) }
        return l
    }
}


/// Kapalı notch'u etkileyen ayar satırları: fare satırın üstündeyken notch kapalı hâlde gösterilir,
/// satırdan ayrılınca (kısa bir gecikmeyle) ayar önizlemesi için yeniden açılır.
extension View {
    func collapsesNotch() -> some View {
        onHover { NotchController.shared.previewCollapsed(editing: $0, hold: 1.5) }
    }
}
