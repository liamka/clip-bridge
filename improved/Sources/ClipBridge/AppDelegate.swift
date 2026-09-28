import AppKit
import ServiceManagement
import ClipBridgeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: HistoryModel!
    private var monitor: PasteboardMonitor!
    private var panel: PanelController!
    private var hotKey: HotKey!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CLIPBRIDGE_DATA_DIR — отдельная папка истории для проверок, чтобы не трогать настоящую.
        let dir = ProcessInfo.processInfo.environment["CLIPBRIDGE_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? HistoryStore.defaultDirectory()
        hotKey = HotKey(shortcut: .saved) { [weak self] in self?.panel.toggle() }
        model = HistoryModel(store: HistoryStore(directory: dir), shortcutDisplay: hotKey.shortcut.display)
        panel = PanelController(model: model, hotKey: hotKey)
        monitor = PasteboardMonitor(isPaused: { [weak self] in self?.model.isPaused ?? false }) { [weak self] text, name, bundleID in
            self?.model.capture(text: text, sourceName: name, sourceBundleID: bundleID)
        }
        monitor.start()

        // Клик по значку сразу открывает окно; все настройки — внутри окна.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipBridge")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)

        if !UserDefaults.standard.bool(forKey: "onboardingDismissed") {
            panel.show(anchor: statusItemFrame)
        }
    }

    private var statusItemFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func statusItemClicked() {
        panel.toggle(anchor: statusItemFrame)
    }
}

/// Запуск при входе в систему.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
        } catch {
            NSLog("ClipBridge: запуск при входе не изменён: \(error)")
        }
    }
}
