import Foundation

/// The written form of Chinese a text uses, read from its characters.
public enum ChineseScript: Sendable, Equatable {
    case traditional
    case simplified

    /// Text that simplifying changes holds Traditional characters; text that the reverse
    /// changes holds Simplified ones. Text that both change, or neither, does not say.
    public static func of(_ text: String) -> ChineseScript? {
        switch (changes(text, under: "Hant-Hans"), changes(text, under: "Hans-Hant")) {
        case (true, false): return .traditional
        case (false, true): return .simplified
        default: return nil
        }
    }

    /// Whether the ICU transform `id` changes `text`. A transform that fails changes nothing.
    private static func changes(_ text: String, under id: String) -> Bool {
        (text.applyingTransform(StringTransform(rawValue: id), reverse: false) ?? text) != text
    }
}

/// How CJK text is typeset: where punctuation sits, how much of it may squeeze, and
/// which fonts draw it. CLREQ for Chinese, JLREQ for Japanese.
///
/// It follows the script of the text, not the language a book declares: converters
/// often label Traditional text `zh-cn` (Yuedu Reader's vertical typography plan,
/// decision 2).
public enum CJKTypographyStyle: String, Sendable, Equatable, CaseIterable, Codable {
    /// Taiwan and Hong Kong: punctuation centred in its cell (CLREQ, "Major differences
    /// between horizontal and vertical writing modes",
    /// #major_differences_between_horizontal_and_vertical_writing_modes).
    case traditional
    /// The Mainland: punctuation at the end of the text it follows, bottom left in
    /// horizontal text and top right in vertical text (the same CLREQ section).
    case simplified
    /// Japanese (JLREQ).
    case japanese

    /// The language CoreText is told the text is in, which picks fonts and glyph forms.
    public var languageTag: String {
        switch self {
        case .traditional: return "zh-Hant"
        case .simplified: return "zh-Hans"
        case .japanese: return "ja"
        }
    }

    /// The system font whose punctuation sits where this style puts it. Punctuation in
    /// any other font is measured against it.
    public var referenceFontName: String {
        switch self {
        case .traditional: return "PingFangTC-Regular"
        case .simplified: return "PingFangSC-Regular"
        case .japanese: return "HiraginoSans-W3"
        }
    }

    /// Most of the sample this function reads; detection needs sentences, not chapters.
    public static let sampleLength = 6_000

    /// The style a sample of text calls for, or nil when it does not say.
    ///
    /// Kana make it Japanese. Otherwise each sentence that shows its script votes, and
    /// a clear majority decides: Traditional text holds the odd character that
    /// simplified text uses too (公里 is both), so one sentence never outvotes many.
    public static func detect(in sample: String) -> CJKTypographyStyle? {
        let text = sample.utf16.count > sampleLength
            ? String(sample.prefix(sampleLength))
            : sample
        var kana = 0
        var han = 0
        for scalar in text.unicodeScalars {
            if isKana(scalar) { kana += 1 } else if isHan(scalar) { han += 1 }
        }
        if kana >= 5 && kana * 10 >= kana + han {
            return .japanese
        }
        var traditional = 0
        var simplified = 0
        for sentence in text.split(whereSeparator: { "。！？!?\n\r".contains($0) }) {
            guard sentence.unicodeScalars.contains(where: isHan) else { continue }
            switch ChineseScript.of(String(sentence)) {
            case .traditional: traditional += 1
            case .simplified: simplified += 1
            case nil: break
            }
        }
        let decided = traditional + simplified
        guard decided > 0 else { return nil }
        if traditional * 4 >= decided * 3 { return .traditional }
        if simplified * 4 >= decided * 3 { return .simplified }
        return nil
    }

    /// The style a declared language implies: `zh-TW`, `zh-HK`, `zh-MO` and `zh-Hant`
    /// are Traditional; other Chinese tags Simplified; `ja` Japanese.
    public static func declared(_ languageTag: String?) -> CJKTypographyStyle? {
        guard let tag = languageTag?.lowercased().replacingOccurrences(of: "_", with: "-"),
              !tag.isEmpty else { return nil }
        if tag == "ja" || tag.hasPrefix("ja-") { return .japanese }
        guard tag == "zh" || tag.hasPrefix("zh-") else { return nil }
        let parts = tag.split(separator: "-")
        if parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo") {
            return .traditional
        }
        return .simplified
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Hiragana, katakana, katakana extensions, half-width katakana. The middle dot ・
        // and the long vowel mark ー are left out: Chinese text uses both.
        case 0x3041...0x309F, 0x30A1...0x30FA, 0x30FD...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3134F:
            return true
        default:
            return false
        }
    }
}
