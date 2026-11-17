import AppKit
import SwiftUI

/// Ekrandaki herhangi bir pikselin rengini seçip hex kodunu panoya kopyalar (sistemin büyüteçli örnekleyicisi).
final class ColorPickService {
    static let shared = ColorPickService()
    private var sampler: NSColorSampler?

    func pick() {
        NotchController.shared.close()                       // notch seçimin önüne girmesin
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let s = NSColorSampler()
            self.sampler = s
            NSApp.activate(ignoringOtherApps: true)
            s.show { color in
                self.sampler = nil
                guard let c = color?.usingColorSpace(.sRGB) else { return }   // Esc ile iptal
                let hex = String(format: "#%02X%02X%02X",
                                 Int((c.redComponent * 255).rounded()),
                                 Int((c.greenComponent * 255).rounded()),
                                 Int((c.blueComponent * 255).rounded()))
                ClipboardService.shared.copyText(hex, color: Color(nsColor: c))
                NSSound(named: "Pop")?.play()
            }
        }
    }
}
