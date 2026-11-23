import AppKit
import Quartz

/// Raf için macOS'un kendi Hızlı Bakış paneli (Boşluk ile aç/kapat, ←/→ ile dosyalar arasında gez).
final class ShelfPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ShelfPreview()
    private var items: [URL] = []

    func toggle(items: [URL], current: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        self.items = items
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = items.firstIndex(of: current) ?? 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { items[index] as NSURL }
}

enum QuickLook {
    static func preview(_ url: URL) { ShelfPreview.shared.toggle(items: ShelfService.shared.urls, current: url) }
}
