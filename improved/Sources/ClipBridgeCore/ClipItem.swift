import Foundation

public enum ClipKind: String, Codable, Sendable {
    case text, link, code
}

/// Одна запись истории буфера.
public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var kind: ClipKind
    /// Имя приложения, из которого скопировано (как его видит пользователь).
    public var sourceName: String?
    public var sourceBundleID: String?
    public var copiedAt: Date

    public init(id: UUID = UUID(), text: String, kind: ClipKind,
                sourceName: String?, sourceBundleID: String?, copiedAt: Date) {
        self.id = id
        self.text = text
        self.kind = kind
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt
    }
}
