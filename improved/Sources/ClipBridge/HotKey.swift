import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш: код клавиши и модификаторы в формате Carbon.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌃⌘V: почти нигде не занят, в отличие от ⇧⌘V («вставить без оформления»).
    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | cmdKey))

    private static let keyCodeKey = "hotKeyCode", modifiersKey = "hotKeyModifiers"

    static var saved: Shortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: keyCodeKey) != nil else { return .default }
        return Shortcut(keyCode: UInt32(d.integer(forKey: keyCodeKey)), modifiers: UInt32(d.integer(forKey: modifiersKey)))
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: Self.modifiersKey)
    }

    /// Из нажатия. `nil` — нет ни ⌘, ни ⌃, ни ⌥: такое сочетание перехватило бы обычный ввод.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(carbon))
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Как в меню macOS: ⌃⌥⇧⌘ и клавиша.
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Пробел", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Имя клавиши по латинской раскладке, чтобы при русской не показывать «⌃⌘М».
    private static func keyName(_ keyCode: UInt32) -> String {
        if let name = specialKeys[Int(keyCode)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { buffer in
            UCKeyTranslate(buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Глобальный хоткей через Carbon. Не требует разрешения «Универсальный доступ».
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var shortcut: Shortcut

    init(shortcut: Shortcut, action: @escaping () -> Void) {
        self.action = action
        self.shortcut = shortcut
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handler)
        if !register(shortcut) {
            NSLog("ClipBridge: хоткей \(shortcut.display) не зарегистрирован")
        }
    }

    /// Заменяет сочетание. `false` — занято другим приложением; тогда хоткея нет,
    /// и вызывающий сам решает, вернуть ли прежний.
    @discardableResult
    func register(_ new: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x434C_4252), id: 1) // 'CLBR'
        guard RegisterEventHotKey(new.keyCode, new.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
        else { return false }
        shortcut = new
        return true
    }

    /// Снимает хоткей, например на время записи нового сочетания.
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
