import AppKit
import ClipBridgeCore

/// Состояние окна поверх слоя данных. К файлам не обращается — только к HistoryStore.
final class HistoryModel: ObservableObject {
    private let store: HistoryStore
    private var saveWork: DispatchWorkItem?

    @Published private(set) var items: [ClipItem] = []
    @Published var query = "" { didSet { refresh() } }
    @Published var selection: Set<UUID> = [] { didSet { syncOrder(old: oldValue) } }
    /// Порядок, в котором пользователь выбирал записи. Он же порядок в контексте.
    @Published private(set) var selectionOrder: [UUID] = []
    @Published var isPaused = false

    init(store: HistoryStore) {
        self.store = store
        refresh()
    }

    func capture(text: String, sourceName: String?, sourceBundleID: String?) {
        store.add(text: text, sourceName: sourceName, sourceBundleID: sourceBundleID)
        refresh()
        scheduleSave()
    }

    func delete(_ ids: Set<UUID>) {
        store.delete(ids: ids)
        selection.subtract(ids)
        refresh()
        scheduleSave()
    }

    func clearAll() {
        store.clear()
        selection = []
        refresh()
        scheduleSave()
    }

    /// Собирает выбранное (или запись под курсором, если выбрано ничего) в markdown.
    func assembledContext(fallback: UUID? = nil) -> String? {
        var ids = selectionOrder
        if ids.isEmpty, let fallback { ids = [fallback] }
        let picked = store.items(orderedBy: ids)
        guard !picked.isEmpty else { return nil }
        return ContextAssembler.markdown(for: picked)
    }

    func text(of id: UUID) -> String? {
        store.items(orderedBy: [id]).first?.text
    }

    func orderNumber(of id: UUID) -> Int? {
        guard selectionOrder.count > 1, let i = selectionOrder.firstIndex(of: id) else { return nil }
        return i + 1
    }

    func flush() {
        saveWork?.cancel()
        save()
    }

    private func refresh() {
        items = store.search(query)
    }

    private func syncOrder(old: Set<UUID>) {
        var order = selectionOrder.filter(selection.contains)
        // Новые записи добавляем в порядке списка (важно для Shift-диапазона).
        let added = selection.subtracting(old)
        order += items.map(\.id).filter(added.contains)
        if order != selectionOrder { selectionOrder = order }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        do { try store.save() } catch { NSLog("ClipBridge: не удалось сохранить историю: \(error)") }
    }
}
