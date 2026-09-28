import Foundation

/// Слой данных истории. Единственное место, которое знает, где и как она хранится.
/// Каждое изменение сразу пишется в SQLite: на диск уходит одна запись, а не вся история.
/// Не потокобезопасен: вызывать из одного потока (в приложении — главного).
public final class HistoryStore {
    public static let limit = 500
    static let fileName = "history.sqlite"
    /// Файл прежних версий. Переносится в базу при первом запуске и удаляется.
    static let legacyFileName = "history.json"

    /// Новые записи первыми. Копия базы в памяти — для поиска и отрисовки.
    public private(set) var items: [ClipItem] = []
    private var db: Database?

    /// - Parameter directory: папка хранения; `nil` — только в памяти (для проверок).
    public init(directory: URL?) {
        guard let directory else { return }
        prepare(directory)
        db = Self.open(in: directory)
        load()
        if items.isEmpty { importLegacy(from: directory) }
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
        let evicted = items.dropFirst(Self.limit).map(\.id)
        items.removeLast(evicted.count)
        write {
            try $0.run("DELETE FROM items WHERE text = ?", [text])
            try Self.insert(item, into: $0)
            for id in evicted { try $0.run("DELETE FROM items WHERE id = ?", [id.uuidString]) }
        }
        return item
    }

    public func delete(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        write { db in
            for id in ids { try db.run("DELETE FROM items WHERE id = ?", [id.uuidString]) }
        }
    }

    public func clear() {
        items.removeAll()
        write { try $0.run("DELETE FROM items") }
        // Сжимаем файл, чтобы удалённое не оставалось в свободных страницах.
        try? db?.execute("VACUUM")
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

    // MARK: - База

    /// Открывает базу. Повреждённый файл не удаляем — откладываем в сторону и начинаем с пустой.
    /// Не открылась и новая — работаем только в памяти.
    private static func open(in directory: URL) -> Database? {
        let url = directory.appendingPathComponent(fileName)
        for attempt in 0..<2 {
            do {
                return try setUp(url)
            } catch {
                NSLog("ClipBridge: база истории не открылась: \(error)")
                guard attempt == 0 else { break }
                moveAside(url, in: directory)
            }
        }
        return nil
    }

    private static func setUp(_ url: URL) throws -> Database {
        let fm = FileManager.default
        // Файл создаём сами с правами 600: SQLite создал бы его по umask (обычно 644).
        // Служебный журнал SQLite получает те же права, что и основной файл.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let db = try Database(url: url)
        let check = try db.query("PRAGMA quick_check") { $0.text(0) }
        guard check == ["ok"] else { throw Database.Failure(description: "quick_check: \(check)") }
        try db.execute("""
            PRAGMA secure_delete = ON;
            CREATE TABLE IF NOT EXISTS items (
                seq INTEGER PRIMARY KEY,
                id TEXT NOT NULL UNIQUE,
                text TEXT NOT NULL,
                kind TEXT NOT NULL,
                source_name TEXT,
                source_bundle_id TEXT,
                copied_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS items_text ON items(text);
            """)
        return db
    }

    private static func moveAside(_ url: URL, in directory: URL) {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        try? fm.moveItem(at: url, to: directory.appendingPathComponent("history.corrupt-\(stamp).sqlite"))
        try? fm.removeItem(at: directory.appendingPathComponent(fileName + "-journal"))
    }

    /// `seq` растёт с каждой вставкой, поэтому порядок по нему — от старых к новым.
    private static func insert(_ item: ClipItem, into db: Database) throws {
        try db.run("""
            INSERT INTO items (id, text, kind, source_name, source_bundle_id, copied_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, [item.id.uuidString, item.text, item.kind.rawValue,
                  item.sourceName, item.sourceBundleID, item.copiedAt.timeIntervalSince1970])
    }

    private func load() {
        guard let db else { return }
        do {
            items = try db.query("""
                SELECT id, text, kind, source_name, source_bundle_id, copied_at
                FROM items ORDER BY seq DESC LIMIT ?
                """, [Double(Self.limit)]) { row in
                guard let id = row.text(0).flatMap(UUID.init(uuidString:)), let text = row.text(1) else { return nil }
                return ClipItem(id: id, text: text, kind: row.text(2).flatMap(ClipKind.init(rawValue:)) ?? .text,
                                sourceName: row.text(3), sourceBundleID: row.text(4),
                                copiedAt: Date(timeIntervalSince1970: row.double(5)))
            }
        } catch {
            NSLog("ClipBridge: история не прочитана: \(error)")
        }
    }

    /// Переносит history.json прежних версий в базу. Повреждённый файл откладывается в сторону.
    private func importLegacy(from directory: URL) {
        let fm = FileManager.default
        let url = directory.appendingPathComponent(Self.legacyFileName)
        guard let db, let data = try? Data(contentsOf: url) else { return }
        guard let old = try? JSONDecoder.history.decode([ClipItem].self, from: data) else {
            let aside = directory.appendingPathComponent("history.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.moveItem(at: url, to: aside)
            return
        }
        let kept = Array(old.prefix(Self.limit))
        do {
            try db.transaction {
                for item in kept.reversed() { try Self.insert(item, into: db) }
            }
            items = kept
            try fm.removeItem(at: url)
        } catch {
            NSLog("ClipBridge: history.json не перенесён: \(error)")
        }
    }

    private func write(_ body: (Database) throws -> Void) {
        guard let db else { return }
        do {
            try db.transaction { try body(db) }
        } catch {
            NSLog("ClipBridge: не удалось сохранить историю: \(error)")
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

extension JSONDecoder {
    static var history: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
