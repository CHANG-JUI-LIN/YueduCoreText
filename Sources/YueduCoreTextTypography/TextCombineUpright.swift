import CoreText
import Foundation
import UIKit

/// CSS Writing Modes `text-combine-upright` (inherited): in vertical text, set a short
/// run horizontally in one upright cell, 縦中横. `digits` is from Level 4. Only what
/// the author wrote combines; nothing is combined automatically.
public enum TextCombineUpright: Equatable, Sendable {
    case none
    case all
    /// Each run of at most this many ASCII digits, 2 to 4.
    case digits(Int)
    case unsupported(String)

    /// `text-combine-upright`, and the prefixed `-epub-text-combine-horizontal` and
    /// `-ms-text-combine-horizontal`, which take the same values.
    public static func parse(_ raw: String) -> TextCombineUpright {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = value.split(whereSeparator: \.isWhitespace)
        switch words.first {
        case "none": return words.count == 1 ? .none : .unsupported(value)
        case "all": return words.count == 1 ? .all : .unsupported(value)
        case "digits":
            if words.count == 1 { return .digits(2) }
            if words.count == 2, let count = Int(words[1]), (2...4).contains(count) { return .digits(count) }
            return .unsupported(value)
        default: return .unsupported(value)
        }
    }

    /// The older `-webkit-text-combine` and `-epub-text-combine`: `horizontal` combines
    /// the whole run.
    public static func parseLegacy(_ raw: String) -> TextCombineUpright {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "none": return .none
        case "horizontal": return .all
        default: return .unsupported(value)
        }
    }

    public var isSupported: Bool {
        if case .unsupported = self { return false }
        return true
    }

    /// The parts of one text node, in order, each combined or not. `all` combines the
    /// whole node, as browsers do per text node; `digits` combines each run of ASCII
    /// digits no longer than its count, and leaves longer runs and everything else.
    public func segments(of text: String) -> [(text: String, combined: Bool)] {
        switch self {
        case .none, .unsupported: return [(text, false)]
        case .all: return [(text, true)]
        case .digits(let count):
            var result: [(text: String, combined: Bool)] = []
            var current = ""
            var currentIsDigits = false
            func flush() {
                guard !current.isEmpty else { return }
                result.append((current, currentIsDigits && current.count <= count))
                current = ""
            }
            for character in text {
                let isDigit = character.isASCII && character.isNumber
                if isDigit != currentIsDigits { flush() }
                currentIsDigits = isDigit
                current.append(character)
            }
            flush()
            // Neighbouring text that stays as it is goes back together.
            var merged: [(text: String, combined: Bool)] = []
            for segment in result {
                if let last = merged.last, !last.combined, !segment.combined {
                    merged[merged.count - 1].text += segment.text
                } else {
                    merged.append(segment)
                }
            }
            return merged
        }
    }
}

/// The text of one 縦中横 cell, as both engines draw it.
public enum CombinedUpright {
    /// CSS Writing Modes 3 §9.1.3: the glyphs are composed horizontally, ignoring
    /// letter-spacing, and fit within 1 em. Only fonts, colours and language carry over;
    /// a composition wider than the cell is scaled horizontally into it. Width variants
    /// (`hwid`, `twid`, `qwid`) are not tried.
    public static func line(_ text: NSAttributedString, em: CGFloat) -> CTLine {
        let kept: [NSAttributedString.Key] = [.font, .foregroundColor, NSAttributedString.Key(kCTLanguageAttributeName as String)]
        let composed = NSMutableAttributedString(string: text.string)
        let whole = NSRange(location: 0, length: composed.length)
        text.enumerateAttributes(in: whole) { attributes, range, _ in
            composed.addAttributes(attributes.filter { kept.contains($0.key) }, range: range)
        }
        var line = CTLineCreateWithAttributedString(composed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard width > em, width > 0 else { return line }
        let scale = em / width
        composed.enumerateAttribute(.font, in: whole) { value, range, _ in
            guard let value, let font = CJKTypography.ctFont(value) else { return }
            var matrix = CTFontGetMatrix(font).concatenating(CGAffineTransform(scaleX: scale, y: 1))
            composed.addAttribute(.font, value: CTFontCreateCopyWithAttributes(font, 0, &matrix, nil), range: range)
        }
        line = CTLineCreateWithAttributedString(composed)
        return line
    }
}
