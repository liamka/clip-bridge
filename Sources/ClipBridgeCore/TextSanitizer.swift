import Foundation

/// Убирает невидимые символы, которыми в текст прячут инструкции для агента:
/// zero-width, управляющие направлением письма и теговые символы Unicode.
/// ZWJ (U+200D) оставляем — без него ломаются составные эмодзи.
public enum TextSanitizer {
    static func isHidden(_ v: UInt32) -> Bool {
        switch v {
        case 0x200B, 0x200C, 0x200E, 0x200F: return true      // zero-width, LRM/RLM
        case 0x202A...0x202E: return true                      // bidi embedding/override
        case 0x2060...0x2064: return true                      // word joiner, invisible operators
        case 0x2066...0x2069: return true                      // bidi isolates
        case 0xFEFF: return true                               // BOM / ZWNBSP
        case 0xE0000...0xE007F: return true                    // теговые символы
        default: return false
        }
    }

    public static func clean(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !isHidden($0.value) })
        return String(scalars)
    }
}
