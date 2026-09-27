import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ClipBridgeCore

/// Плавающее окно истории. Открывается хоткеем поверх текущего приложения
/// и после сборки возвращает фокус туда, откуда его вызвали, — чтобы сразу нажать ⌘V.
final class PanelController: NSObject, NSWindowDelegate {
    private let model: HistoryModel
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?

    init(model: HistoryModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameter anchor: рамка значка в строке меню на экране; `nil` — открыть по центру.
    func toggle(anchor: NSRect? = nil) {
        isVisible ? close(returnFocus: true) : show(anchor: anchor)
    }

    func show(anchor: NSRect? = nil) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.query = ""
        model.selection = []
        if let anchor {
            // Под значком, прижато к краю экрана.
            let size = panel.frame.size
            let visible = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame
                ?? NSScreen.main?.visibleFrame ?? .zero
            let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 4))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close(returnFocus: Bool) {
        panel?.orderOut(nil)
        if returnFocus { previousApp?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Окно как у Spotlight: ушли в другое приложение — прячемся.
        // Свои окна (сохранение файла, подтверждения) окно не закрывают.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, NSApp.modalWindow == nil,
                  panel.attachedSheet == nil, !(NSApp.keyWindow is NSSavePanel),
                  NSApp.keyWindow !== panel else { return }
            if !NSApp.isActive || NSApp.keyWindow == nil { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "ClipBridge"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.setFrameAutosaveName("ClipBridgePanel.v2")
        panel.contentView = NSHostingView(rootView: HistoryView(
            model: model,
            onAssemble: { [weak self] text in self?.deliver(text) },
            onCopyOne: { [weak self] text in self?.deliver(text) },
            onSaveFile: { [weak self] text in self?.saveToFile(text) },
            onClose: { [weak self] in self?.close(returnFocus: true) },
            onQuit: { NSApp.terminate(nil) }))
        return panel
    }

    /// Кладёт текст в буфер с пометкой «своё», чтобы он не вернулся в историю.
    private func deliver(_ text: String) {
        Clipboard.write(text)
        close(returnFocus: true)
    }

    private func saveToFile(_ text: String) {
        let save = NSSavePanel()
        save.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        save.nameFieldStringValue = "context.md"
        save.beginSheetModal(for: panel!) { response in
            guard response == .OK, let url = save.url else { return }
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
                Clipboard.write(text)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

enum Clipboard {
    static func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType(CapturePolicy.ownMarkerType)], owner: nil)
        pb.setString(text, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType(CapturePolicy.ownMarkerType))
    }
}
