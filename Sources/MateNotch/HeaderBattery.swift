import SwiftUI

/// Açık notchun sağ üstünde yalnızca Macin pili görünür; tıklanınca bir şey açılmaz.
/// Üzerine gelince bağlı cihazların (kulaklık, fare, klavye…) pil seviyeleri küçük bir kartta çıkar.
struct HeaderBattery: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var devices = DeviceBatteryService.shared
    @AppStorage(Pref.headerDeviceBattery) var showDevices = true
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: Self.symbol(level: battery.level, plugged: battery.pluggedIn))
            Text("\(battery.level)%").monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(battery.pluggedIn ? .green : (battery.level <= 20 ? .red : .white.opacity(0.6)))
        .contentShape(Rectangle())
        .background(HoverTracker { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = h && showDevices } })
        .overlay(alignment: .topTrailing) {
            if hovering { card.offset(y: 26).transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing))) }
        }
        .zIndex(hovering ? 20 : 0)
    }

    /// Seviyeye göre pil simgesi (100/75/50/25/0); şarjdayken yıldırımlı.
    static func symbol(level: Int, plugged: Bool) -> String {
        if plugged { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var card: some View {
        let list = devices.devices.filter { $0.percent != nil }
        return VStack(alignment: .leading, spacing: 7) {
            if list.isEmpty {
                Text("Pil bilgisi veren bağlı cihaz yok")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(list) { d in
                    HStack(spacing: 8) {
                        Image(systemName: d.icon).font(.system(size: 11)).frame(width: 16).foregroundStyle(.white.opacity(0.7))
                        Text(d.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 14)
                        if d.charging { Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.green) }
                        Text("\(d.percent ?? 0)%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle((d.percent ?? 100) <= 20 ? .red : .white)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(minWidth: 170, alignment: .leading)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .allowsHitTesting(false)
    }
}
