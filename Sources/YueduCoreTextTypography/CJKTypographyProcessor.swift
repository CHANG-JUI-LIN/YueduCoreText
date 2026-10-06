import CoreText
import UIKit

/// The legacy renderer's punctuation post-processor.
///
/// Called after the CJK pass (`CJKTypography.apply`), it turns ASCII quotes into curly
/// quotes and draws them in Georgia. Each replacement is one UTF-16 unit for one, so the
/// offsets reading progress uses stay put.
///
/// The punctuation lists drive line breaking: `protectedLineBreakOffset` keeps closing
/// marks off a line's start and opening marks off its end. Spacing between adjacent marks
/// is `CJKTypography.applySpacing`'s, by CLREQ's and JLREQ's classes.
public enum CJKTypographyProcessor {

    // MARK: - Line breaking classes

    /// Closing brackets, pause and stop marks, and the ellipsis: they may not start a line.
    public static let closingMarks: Set<Unicode.Scalar> = [
        "」", "』", "）", "】", "〕", "｝", "〉", "》",
        "。", "．", "，", "、", "；", "：", "！", "？",
        "\u{2026}", // …
    ]

    /// Opening brackets: they may not end a line.
    public static let openingMarks: Set<Unicode.Scalar> = [
        "「", "『", "（", "【", "〔", "｛", "〈", "《",
    ]

    /// Line-start prohibition: punctuation that should not appear at the beginning of a line (typically closing marks)
    public static let lineStartForbidden: Set<Unicode.Scalar> = closingMarks

    /// Line-end prohibition: punctuation that should not appear at the end of a line (typically opening marks)
    public static let lineEndForbidden: Set<Unicode.Scalar> = openingMarks

    // MARK: - Public API

    /// Whether the character is an opening bracket.
    public static func isOpening(_ char: Character) -> Bool {
        guard let first = char.unicodeScalars.first else { return false }
        return openingMarks.contains(first)
    }

    /// Whether the character is a closing mark.
    public static func isClosing(_ char: Character) -> Bool {
        guard let first = char.unicodeScalars.first else { return false }
        return closingMarks.contains(first)
    }

    public static func protectedLineBreakOffset(
        _ proposedOffset: Int,
        in string: String,
        lowerBound: Int
    ) -> Int {
        let nsString = string as NSString
        let length = nsString.length
        guard length > 0 else { return proposedOffset }

        var adjusted = min(max(proposedOffset, lowerBound), length)
        adjusted = avoidSurrogateSplit(at: adjusted, in: nsString, lowerBound: lowerBound)

        if adjusted < length,
           let next = unicodeScalar(atUTF16Offset: adjusted, in: string),
           lineStartForbidden.contains(next),
           adjusted > lowerBound {
            adjusted = avoidSurrogateSplit(at: adjusted - 1, in: nsString, lowerBound: lowerBound)
        }

        if adjusted > lowerBound,
           let previous = unicodeScalar(beforeUTF16Offset: adjusted, in: string),
           lineEndForbidden.contains(previous) {
            adjusted = avoidSurrogateSplit(at: adjusted - previous.utf16.count, in: nsString, lowerBound: lowerBound)
        }

        return max(lowerBound, adjusted)
    }

    /// Applies smart punctuation normalization.
    public static func apply(to attrStr: NSAttributedString) -> NSAttributedString {
        applySmartPunctuation(to: attrStr)
    }

    // MARK: - Smart Punctuation

    /// Converts ASCII straight quotes to Unicode curly quotes.
    /// " -> “ / ” (U+201C / U+201D)
    /// ' -> ‘ / ’ (U+2018 / U+2019) with apostrophe detection for English contractions and possessives.
    public static func normalizeEnglishPunctuation(_ text: String) -> String {
        var result = ""
        var isOpeningDouble = true
        var isOpeningSingle = true
        let chars = Array(text)

        for i in chars.indices {
            let ch = chars[i]
            if ch == "\"" {
                let isOpening = openingQuoteDecision(at: i, in: chars) ?? isOpeningDouble
                result.append(isOpening ? "\u{201C}" : "\u{201D}")
                isOpeningDouble = !isOpening
            } else if ch == "'" {
                if isEnglishApostrophe(at: i, in: chars, isInsideSingleQuote: !isOpeningSingle) {
                    result.append("\u{2019}")
                } else {
                    let isOpening = openingQuoteDecision(at: i, in: chars) ?? isOpeningSingle
                    result.append(isOpening ? "\u{2018}" : "\u{2019}")
                    isOpeningSingle = !isOpening
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private static func openingQuoteDecision(at index: Array<Character>.Index, in chars: [Character]) -> Bool? {
        let previous = index > chars.startIndex ? chars[chars.index(before: index)] : nil
        let nextIndex = chars.index(after: index)
        let next = nextIndex < chars.endIndex ? chars[nextIndex] : nil

        if let next, next.isWhitespace {
            return false
        }
        if next == nil {
            return false
        }
        if previous == nil || previous?.isWhitespace == true {
            return true
        }
        if let previous, isOpeningQuoteBoundary(previous) {
            return true
        }
        if let previous, let next, isQuoteLeadInBoundary(previous), !isClosingQuoteBoundary(next) {
            return true
        }
        if let previous, isClosingQuoteBoundary(previous) {
            return false
        }
        if let next, isClosingQuoteBoundary(next) {
            return false
        }
        return nil
    }

    private static func isEnglishApostrophe(
        at index: Array<Character>.Index,
        in chars: [Character],
        isInsideSingleQuote: Bool
    ) -> Bool {
        let previous = index > chars.startIndex ? chars[chars.index(before: index)] : nil
        let nextIndex = chars.index(after: index)
        let next = nextIndex < chars.endIndex ? chars[nextIndex] : nil

        if isASCIIAlphaNumeric(previous), isASCIIAlphaNumeric(next) {
            return true
        }

        if isInsideSingleQuote {
            return false
        }

        return isASCIIAlphaNumeric(previous) && (next == nil || isApostropheTrailingBoundary(next))
    }

    private static func isASCIIAlphaNumeric(_ character: Character?) -> Bool {
        guard let character,
              let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }
        switch scalar.value {
        case 0x0030...0x0039, 0x0041...0x005A, 0x0061...0x007A:
            return true
        default:
            return false
        }
    }

    private static func isQuoteLeadInBoundary(_ character: Character) -> Bool {
        switch character {
        case ",", ":", ";", "，", "：", "；":
            return true
        default:
            return false
        }
    }

    private static func isOpeningQuoteBoundary(_ character: Character) -> Bool {
        switch character {
        case "(", "[", "{", "<", "「", "『", "（", "【", "《", "〈", "\u{2014}", "\u{2013}":
            return true
        default:
            return false
        }
    }

    private static func isClosingQuoteBoundary(_ character: Character) -> Bool {
        if character.isWhitespace {
            return true
        }
        switch character {
        case ".", ",", "!", "?", ":", ";", ")", "]", "}", ">", "。", "，", "！", "？", "：", "；",
             "）", "】", "》", "〉":
            return true
        default:
            return false
        }
    }

    private static func isApostropheTrailingBoundary(_ character: Character?) -> Bool {
        guard let character else { return true }
        if character.isWhitespace {
            return true
        }
        return isClosingQuoteBoundary(character)
    }

    /// Applies smart punctuation to an NSAttributedString in-place.
    /// All replacements are 1 UTF-16 code unit → 1 UTF-16 code unit (all BMP),
    /// so attribute ranges are preserved without adjustment.
    private static func applySmartPunctuation(to attrStr: NSAttributedString) -> NSAttributedString {
        let original = attrStr.string
        let normalized = normalizeEnglishPunctuation(original)
        guard normalized != original || containsSmartQuote(original) else { return attrStr }

        let result = NSMutableAttributedString(string: normalized)
        attrStr.enumerateAttributes(
            in: NSRange(location: 0, length: attrStr.length),
            options: []
        ) { attrs, range, _ in
            result.setAttributes(attrs, range: range)
        }
        applyLatinQuoteFont(in: result)
        return result
    }

    private static func containsSmartQuote(_ text: String) -> Bool {
        text.unicodeScalars.contains { isSmartQuoteScalar($0) }
    }

    private static func applyLatinQuoteFont(in result: NSMutableAttributedString) {
        let scalars = Array(result.string.unicodeScalars)
        let utf16Offsets = buildUTF16OffsetMap(for: result.string)
        guard scalars.count == utf16Offsets.count else { return }

        for (scalar, utf16Offset) in zip(scalars, utf16Offsets) {
            guard isSmartQuoteScalar(scalar) else { continue }

            let currentFont = result.attribute(.font, at: utf16Offset, effectiveRange: nil) as? UIFont
            let size = currentFont?.pointSize ?? 17
            guard let quoteFont = latinQuoteFont(matching: currentFont, size: size) else { continue }

            result.addAttribute(.font, value: quoteFont, range: NSRange(location: utf16Offset, length: scalar.utf16.count))
        }
    }

    private static func isSmartQuoteScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2018, 0x2019, 0x201C, 0x201D:
            return true
        default:
            return false
        }
    }

    private static func latinQuoteFont(matching font: UIFont?, size: CGFloat) -> UIFont? {
        let base = UIFont(name: "Georgia", size: size)
        guard let base else { return nil }
        guard let font else { return base }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
            traits.insert(.traitBold)
        }
        if font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
            traits.insert(.traitItalic)
        }
        guard !traits.isEmpty else { return base }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    // MARK: - Private helpers

    private static func avoidSurrogateSplit(
        at offset: Int,
        in nsString: NSString,
        lowerBound: Int
    ) -> Int {
        guard offset > lowerBound, offset < nsString.length else { return offset }
        let previous = nsString.character(at: offset - 1)
        let current = nsString.character(at: offset)
        if CFStringIsSurrogateHighCharacter(previous) && CFStringIsSurrogateLowCharacter(current) {
            return offset - 1
        }
        return offset
    }

    private static func unicodeScalar(atUTF16Offset offset: Int, in string: String) -> Unicode.Scalar? {
        let index = String.Index(utf16Offset: offset, in: string)
        guard index < string.endIndex else { return nil }
        return string[index].unicodeScalars.first
    }

    private static func unicodeScalar(beforeUTF16Offset offset: Int, in string: String) -> Unicode.Scalar? {
        guard offset > 0 else { return nil }
        let index = String.Index(utf16Offset: offset, in: string)
        guard index > string.startIndex else { return nil }
        return string[string.index(before: index)].unicodeScalars.first
    }

    /// Builds a mapping array from Unicode scalar index → UTF-16 code unit offset
    private static func buildUTF16OffsetMap(for string: String) -> [Int] {
        var map: [Int] = []
        map.reserveCapacity(string.unicodeScalars.count)
        var utf16Offset = 0
        for scalar in string.unicodeScalars {
            map.append(utf16Offset)
            utf16Offset += scalar.utf16.count
        }
        return map
    }
}
