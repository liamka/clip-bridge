import Foundation

/// Слой данных истории. Единственное место, которое знает, где и как она хранится.
/// Не потокобезопасен: вызывать из одного потока (в приложении — главного).
public final class HistoryStore {
    public static let limit = 500

    /// Новые записи первыми.
    public private(set) var items: [ClipItem] = []
    private let fileURL: URL?

    /// - Parameter directory: папка хранения; `nil` — только в памяти (для проверок).
    public init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("history.json")
        if let directory { prepare(directory) }
        load()
    }

    /// Папка по умолчанию: ~/Library/Application Support/ClipBridge.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClipBridge", isDirectory: true)
    }

    /// Добавляет запись. Повтор того же текста поднимается наверх, а не дублируется.
    @discardableResult
    public func add(text: String, sourceName: String?, sourceBundleID: String?,
                    at date: Date = Date()) -> ClipItem {
        items.removeAll { $0.text == text }
        let item = ClipItem(text: text,
                            kind: ClipClassifier.kind(for: text, sourceBundleID: sourceBundleID),
                            sourceName: sourceName, sourceBundleID: sourceBundleID, copiedAt: date)
        items.insert(item, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        return item
    }

    public func delete(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    public func clear() {
        items.removeAll()
    }

    /// Записи в порядке переданных идентификаторов; отсутствующие пропускаются.
    public func items(orderedBy ids: [UUID]) -> [ClipItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func search(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.text.localizedCaseInsensitiveContains(q)
                || ($0.sourceName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    public func save() throws {
        guard let fileURL else { return }
        let data = try JSONEncoder.history.encode(items)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = Array(try JSONDecoder.history.decode([ClipItem].self, from: data).prefix(Self.limit))
        } catch {
            // Повреждённый файл не удаляем — откладываем в сторону и начинаем с пустой истории.
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
        }
    }

    private func prepare(_ directory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}

extension JSONEncoder {
    static var history: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var history: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
