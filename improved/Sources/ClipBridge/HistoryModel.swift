import AppKit
import ClipBridgeCore

/// Состояние окна поверх слоя данных. К файлам не обращается — только к HistoryStore.
final class HistoryModel: ObservableObject {
    private let store: HistoryStore

    @Published private(set) var items: [ClipItem] = []
    @Published var query = "" { didSet { refresh() } }
    @Published var selection: Set<UUID> = [] { didSet { syncOrder(old: oldValue) } }
    /// Порядок, в котором пользователь выбирал записи. Он же порядок в контексте.
    @Published private(set) var selectionOrder: [UUID] = []
    @Published var isPaused = false

    /// Строка под курсором клавиатуры (↑/↓). Её показывает предпросмотр, её отмечает пробел.
    @Published var cursor: UUID?
    /// Пробел отмечает строку, только если перед этим ходили стрелками,
    /// иначе он печатается в поиск.
    var cursorActive = false
    /// Меняется, когда окно просит вернуть фокус в поиск.
    @Published private(set) var searchFocusRequest = 0

    /// Панель предпросмотра под списком (⌘Y). Запоминается между запусками.
    @Published var showPreview = UserDefaults.standard.bool(forKey: "showPreview") {
        didSet { UserDefaults.standard.set(showPreview, forKey: "showPreview") }
    }

    /// Идёт запись нового хоткея; `shortcutError` — почему прошлая попытка не удалась.
    @Published var isRecordingShortcut = false
    @Published var shortcutError: String?
    @Published var shortcutDisplay: String

    init(store: HistoryStore, shortcutDisplay: String) {
        self.store = store
        self.shortcutDisplay = shortcutDisplay
        refresh()
    }

    func capture(text: String, sourceName: String?, sourceBundleID: String?) {
        store.add(text: text, sourceName: sourceName, sourceBundleID: sourceBundleID)
        refresh()
    }

    func delete(_ ids: Set<UUID>) {
        store.delete(ids: ids)
        selection.subtract(ids)
        refresh()
    }

    func clearAll() {
        store.clear()
        selection = []
        refresh()
    }

    /// Состояние при каждом открытии окна.
    func reset() {
        query = ""
        selection = []
        cursor = nil
        cursorActive = false
    }

    // MARK: - Клавиатура

    func moveCursor(by delta: Int) {
        guard !items.isEmpty else { return }
        cursorActive = true
        let current = cursor.flatMap { id in items.firstIndex { $0.id == id } }
        let next = current.map { $0 + delta } ?? (delta > 0 ? 0 : items.count - 1)
        cursor = items[min(max(next, 0), items.count - 1)].id
    }

    /// `true`, если пробел ушёл на отметку строки, а не в поиск.
    func toggleCursor() -> Bool {
        guard cursorActive, let cursor else { return false }
        toggle(cursor)
        return true
    }

    /// ⌘1…9: отметить n-ю строку списка.
    func toggle(number n: Int) {
        guard items.indices.contains(n - 1) else { return }
        let id = items[n - 1].id
        cursor = id
        toggle(id)
    }

    func togglePreview() {
        showPreview.toggle()
    }

    /// Печатать, пока фокус в списке: символы уходят в поиск.
    func typeIntoSearch(_ text: String) {
        cursorActive = false
        query += text
        searchFocusRequest += 1
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: - Сборка

    /// Собирает выбранное (или запись под курсором, если выбрано ничего) в markdown.
    func assembledContext(fallback: UUID? = nil) -> String? {
        var ids = selectionOrder
        if ids.isEmpty, let fallback { ids = [fallback] }
        let picked = store.items(orderedBy: ids)
        guard !picked.isEmpty else { return nil }
        return ContextAssembler.markdown(for: picked)
    }

    func text(of id: UUID) -> String? {
        item(id)?.text
    }

    func item(_ id: UUID) -> ClipItem? {
        store.items(orderedBy: [id]).first
    }

    func orderNumber(of id: UUID) -> Int? {
        guard selectionOrder.count > 1, let i = selectionOrder.firstIndex(of: id) else { return nil }
        return i + 1
    }

    private func refresh() {
        items = store.search(query)
        if let cursor, !items.contains(where: { $0.id == cursor }) { self.cursor = nil }
    }

    private func syncOrder(old: Set<UUID>) {
        var order = selectionOrder.filter(selection.contains)
        // Новые записи добавляем в порядке списка (важно для Shift-диапазона).
        let added = selection.subtracting(old)
        order += items.map(\.id).filter(added.contains)
        if order != selectionOrder { selectionOrder = order }
        // Клик мышью переносит курсор на кликнутую строку — её и показывает предпросмотр.
        if added.count == 1, let id = added.first, cursor != id { cursor = id }
    }
}
