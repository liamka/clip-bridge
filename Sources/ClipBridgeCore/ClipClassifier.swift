import Foundation

/// Определяет вид записи: ссылка, код или обычный текст.
/// Язык кода не угадываем — это ненадёжно.
public enum ClipClassifier {
    /// Приложения, из которых копируют почти только код и команды.
    static let codeApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "com.sublimetext.4",
    ]
    static let codeAppPrefixes = ["com.jetbrains."]
    static let linkSchemes: Set<String> = ["http", "https", "ftp", "file"]

    public static func kind(for text: String, sourceBundleID: String?) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLink(trimmed) { return .link }
        if let id = sourceBundleID,
           codeApps.contains(id) || codeAppPrefixes.contains(where: id.hasPrefix) {
            return .code
        }
        return looksLikeCode(trimmed) ? .code : .text
    }

    static func isLink(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(where: \.isWhitespace),
              let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              linkSchemes.contains(scheme) else { return false }
        return scheme == "file" || url.host != nil
    }

    /// Грубая эвристика: большинство непустых строк заканчиваются
    /// синтаксическими символами или начинаются с отступа.
    static func looksLikeCode(_ s: String) -> Bool {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return false }
        let enders: Set<Character> = ["{", "}", ";", ")", "(", "]", ","]
        let codeLike = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return (t.last.map(enders.contains) ?? false)
                || line.hasPrefix("    ") || line.hasPrefix("\t")
                || t.hasPrefix("//") || t.hasPrefix("#!") || t.hasPrefix("$ ")
        }
        return Double(codeLike.count) / Double(lines.count) >= 0.5
    }
}
