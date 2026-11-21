import SwiftUI

/// Ayarlar araması: bir sonuca tıklanınca ilgili satıra kaydırılır ve kısa süre vurgulanır.
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var pending: String?      // kaydırılacak satır anahtarı
    @Published var highlight: String?    // vurgulanan satır
}

struct SRow: ViewModifier {
    let key: String
    @ObservedObject private var nav = SettingsNav.shared
    func body(content: Content) -> some View {
        content
            .id(key)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(nav.highlight == key ? 0.22 : 0))
                    .padding(.horizontal, -8).padding(.vertical, -4)
                    .animation(.easeInOut(duration: 0.35), value: nav.highlight)
            )
    }
}

extension View {
    func srow(_ key: String) -> some View { modifier(SRow(key: key)) }
}
