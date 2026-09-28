import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import ClipBridgeCore

/// Плавающее окно истории. Открывается хоткеем поверх текущего приложения
/// и после сборки возвращает фокус туда, откуда его вызвали, — чтобы сразу нажать ⌘V.
final class PanelController: NSObject, NSWindowDelegate {
    private let model: HistoryModel
    private let hotKey: HotKey
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

    init(model: HistoryModel, hotKey: HotKey) {
        self.model = model
        self.hotKey = hotKey
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
        cancelRecording()
        model.reset()
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
        cancelRecording()
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
            if !NSApp.isActive || NSApp.keyWindow == nil {
                self.cancelRecording()
                panel.orderOut(nil)
            }
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
            onRecordShortcut: { [weak self] in self?.startRecording() },
            onQuit: { NSApp.terminate(nil) }))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        return panel
    }

    // MARK: - Клавиатура

    /// Клавиши окна. Перехватываем до поля поиска и списка, чтобы стрелки и пробел
    /// работали одинаково, где бы ни был фокус. `nil` — клавиша обработана.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let panel, event.window === panel, panel.attachedSheet == nil else { return event }
        if model.isRecordingShortcut { return record(event) }

        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch Int(event.keyCode) {
        case kVK_DownArrow where mods.isEmpty:
            model.moveCursor(by: 1)
            return nil
        case kVK_UpArrow where mods.isEmpty:
            model.moveCursor(by: -1)
            return nil
        case kVK_Space where mods.isEmpty:
            return model.toggleCursor() ? nil : event
        case kVK_ANSI_Y where mods == .command:
            model.togglePreview()
            return nil
        default:
            break
        }
        if mods == .command, let n = Self.digit(event.keyCode) {
            model.toggle(number: n)
            return nil
        }
        // Обычный символ: если фокус не в поиске — печатаем в поиск, а не в список.
        if mods.isSubset(of: .shift), let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
            if panel.firstResponder is NSTextView {
                model.cursorActive = false
                return event
            }
            model.typeIntoSearch(chars)
            return nil
        }
        return event
    }

    private static func digit(_ keyCode: UInt16) -> Int? {
        let codes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        return codes.firstIndex(of: Int(keyCode)).map { $0 + 1 }
    }

    // MARK: - Запись хоткея

    private func startRecording() {
        // Пока пишем, старый хоткей снят — иначе его нажатие закрыло бы окно.
        hotKey.unregister()
        model.shortcutError = nil
        model.isRecordingShortcut = true
    }

    private func record(_ event: NSEvent) -> NSEvent? {
        if Int(event.keyCode) == kVK_Escape {
            cancelRecording()
            return nil
        }
        guard let shortcut = Shortcut(event: event) else {
            model.shortcutError = "Нужен хотя бы один из ⌘, ⌃ или ⌥"
            return nil
        }
        if hotKey.register(shortcut) {
            shortcut.save()
            model.shortcutDisplay = shortcut.display
            model.shortcutError = nil
            model.isRecordingShortcut = false
        } else {
            model.shortcutError = "\(shortcut.display) занято другим приложением — попробуйте другое"
        }
        return nil
    }

    /// Прервать запись и вернуть действующий хоткей.
    private func cancelRecording() {
        guard model.isRecordingShortcut else { return }
        model.isRecordingShortcut = false
        model.shortcutError = nil
        hotKey.register(hotKey.shortcut)
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
