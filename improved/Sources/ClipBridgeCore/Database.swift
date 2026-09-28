import Foundation
import SQLite3

/// Тонкая обёртка над системным SQLite: только то, что нужно истории.
final class Database {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Строка результата запроса.
    struct Row {
        fileprivate let stmt: OpaquePointer

        func text(_ column: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, column) else { return nil }
            return String(cString: c)
        }

        func double(_ column: Int32) -> Double {
            sqlite3_column_double(stmt, column)
        }
    }

    private var db: OpaquePointer?

    init(url: URL) throws {
        let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard status == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "код \(status)"
            sqlite3_close(db)
            db = nil
            throw Failure(description: message)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Несколько команд без параметров.
    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError }
    }

    /// Одна команда с параметрами: String, Double или nil.
    func run(_ sql: String, _ args: [Any?] = []) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError }
    }

    func query<T>(_ sql: String, _ args: [Any?] = [], _ map: (Row) -> T?) throws -> [T] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: map(Row(stmt: stmt)).map { out.append($0) }
            case SQLITE_DONE: return out
            default: throw lastError
            }
        }
    }

    /// Всё или ничего: при ошибке изменения откатываются.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw lastError }
        // SQLITE_TRANSIENT: SQLite копирует строку сам.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case let s as String: sqlite3_bind_text(stmt, index, s, -1, transient)
            case let d as Double: sqlite3_bind_double(stmt, index, d)
            default: sqlite3_bind_null(stmt, index)
            }
        }
        return stmt
    }

    private var lastError: Failure {
        Failure(description: db.map { String(cString: sqlite3_errmsg($0)) } ?? "база закрыта")
    }
}
