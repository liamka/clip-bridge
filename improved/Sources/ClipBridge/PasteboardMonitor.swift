import AppKit
import ClipBridgeCore

/// Следит за системным буфером. macOS не присылает уведомлений об изменении буфера,
/// поэтому, как и все менеджеры буфера, опрашиваем счётчик изменений.
final class PasteboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let onCapture: (_ text: String, _ sourceName: String?, _ sourceBundleID: String?) -> Void

    private let isPaused: () -> Bool

    init(isPaused: @escaping () -> Bool, onCapture: @escaping (String, String?, String?) -> Void) {
        self.isPaused = isPaused
        self.onCapture = onCapture
        // То, что лежало в буфере до запуска, не записываем.
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !isPaused() else { return }

        let types = pasteboard.types?.map(\.rawValue) ?? []
        // Сначала проверяем типы — содержимое скрытых записей даже не читаем.
        if case .reject = CapturePolicy.evaluate(types: types, text: "probe") { return }
        guard case .accept(let text) = CapturePolicy.evaluate(types: types, text: pasteboard.string(forType: .string))
        else { return }

        let source = Self.source(from: pasteboard)
        onCapture(text, source.name, source.bundleID)
    }

    /// Источник: пометка org.nspasteboard.source, если приложение её поставило,
    /// иначе активное приложение в момент копирования.
    private static func source(from pasteboard: NSPasteboard) -> (name: String?, bundleID: String?) {
        if let id = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")),
           !id.isEmpty {
            return (appName(for: id) ?? id, id)
        }
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    private static func appName(for bundleID: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return running.localizedName
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
