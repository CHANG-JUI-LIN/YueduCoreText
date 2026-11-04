import Foundation
import UIKit

/// The shape keywords of `text-emphasis-style` (CSS Text Decoration 3 §3.1).
public enum TextEmphasisShape: Equatable, Sendable {
    case dot, circle, doubleCircle, triangle, sesame
}

/// `text-emphasis-style`, inherited; nil on `ComputedStyle` is `none`.
public enum TextEmphasisStyle: Equatable, Sendable {
    /// `filled` or `open`, with a shape; no shape is `circle` in horizontal
    /// writing and `sesame` in vertical.
    case shape(filled: Bool, shape: TextEmphasisShape?)
    /// A `<string>`: its first grapheme cluster is the mark.
    case string(String)

    /// The mark's characters, as WebKit draws them (CSS Text Decoration 3 §3.1).
    public func mark(vertical: Bool) -> String {
        switch self {
        case .string(let mark):
            return mark
        case .shape(let filled, let shape):
            switch shape ?? (vertical ? .sesame : .circle) {
            case .dot: return filled ? "\u{2022}" : "\u{25E6}"
            case .circle: return filled ? "\u{25CF}" : "\u{25CB}"
            case .doubleCircle: return filled ? "\u{25C9}" : "\u{25CE}"
            case .triangle: return filled ? "\u{25B2}" : "\u{25B3}"
            case .sesame: return filled ? "\u{FE45}" : "\u{FE46}"
            }
        }
    }
}

/// `text-emphasis-position`, inherited: `over` or `under` in horizontal
/// writing, `right` or `left` in vertical. The initial value is `auto`
/// (`over` nil): `over` for Japanese and Korean content, `under` otherwise,
/// and `right` (CSS Text Decoration 4 §3.3; measured, WKWebView iOS 27.2:
/// `ja` and `ko` over, `zh-Hant`, `zh-Hans`, `en`, `mn` and no language under).
public struct TextEmphasisPosition: Equatable, Sendable {
    public var over: Bool?
    public var right: Bool

    public init(over: Bool? = nil, right: Bool = true) {
        self.over = over
        self.right = right
    }

    /// Whether the marks go over the text in horizontal writing, for content
    /// in `language`.
    public func isOver(language: String?) -> Bool {
        if let over { return over }
        let primary = language?.split(separator: "-").first?.lowercased()
        return primary == "ja" || primary == "ko"
    }
}

/// The CSS values of the `text-emphasis` properties.
public enum TextEmphasisValue {
    /// `none`, `[filled | open] || <shape>`, or a string. `.some(nil)` is
    /// `none`; nil drops an invalid declaration. `preserved` keeps a string's case.
    public static func style(_ preserved: String) -> TextEmphasisStyle?? {
        let value = preserved.trimmingCharacters(in: .whitespaces)
        if value.lowercased() == "none" { return .some(nil) }
        if let quote = value.first, quote == "\"" || quote == "'" {
            guard value.count >= 2, value.last == quote else { return nil }
            let inner = String(value.dropFirst().dropLast())
            guard let first = inner.first else { return .some(nil) }
            return .some(.string(String(first)))
        }
        var filled: Bool?
        var shape: TextEmphasisShape?
        for token in value.lowercased().split(whereSeparator: \.isWhitespace) {
            switch token {
            case "filled" where filled == nil: filled = true
            case "open" where filled == nil: filled = false
            case "dot" where shape == nil: shape = .dot
            case "circle" where shape == nil: shape = .circle
            case "double-circle" where shape == nil: shape = .doubleCircle
            case "triangle" where shape == nil: shape = .triangle
            case "sesame" where shape == nil: shape = .sesame
            default: return nil
            }
        }
        guard filled != nil || shape != nil else { return nil }
        return .some(.shape(filled: filled ?? true, shape: shape))
    }

    /// `auto | [ over | under ] && [ right | left ]?` (CSS Text Decoration 4 §3.3).
    public static func position(_ value: String) -> TextEmphasisPosition? {
        if value == "auto" { return TextEmphasisPosition() }
        var over: Bool?
        var right: Bool?
        for token in value.split(whereSeparator: \.isWhitespace) {
            switch token {
            case "over" where over == nil: over = true
            case "under" where over == nil: over = false
            case "right" where right == nil: right = true
            case "left" where right == nil: right = false
            default: return nil
            }
        }
        guard let over else { return nil }
        return TextEmphasisPosition(over: over, right: right ?? true)
    }

    /// The `text-emphasis` shorthand: a style, a colour, or both, in either
    /// order; what it leaves out resets. `color` is `.some(nil)` for
    /// `currentColor`.
    public static func shorthand(_ components: [String], color parseColor: (String) -> UIColor??)
        -> (style: TextEmphasisStyle?, color: UIColor?)? {
        var styleTokens: [String] = []
        var color: UIColor??
        for component in components {
            if let string = style(component), case .some(.string) = string {
                guard styleTokens.isEmpty else { return nil }
                styleTokens.append(component)
            } else if ["none", "filled", "open", "dot", "circle", "double-circle", "triangle", "sesame"]
                .contains(component.lowercased()) {
                styleTokens.append(component)
            } else if color == nil, let parsed = parseColor(component) {
                color = parsed
            } else {
                return nil
            }
        }
        guard !styleTokens.isEmpty || color != nil else { return nil }
        let parsedStyle: TextEmphasisStyle?
        if styleTokens.isEmpty {
            parsedStyle = nil
        } else {
            guard let parsed = style(styleTokens.joined(separator: " ")) else { return nil }
            parsedStyle = parsed
        }
        return (parsedStyle, color ?? nil)
    }
}

/// The characters that take a mark (CSS Text Decoration 3 §3.4, WebKit
/// `canReceiveTextEmphasis`): none on separators, control and format
/// characters, unassigned code points, the word separators WebKit lists, or
/// punctuation other than the symbols it lists. Measured, WKWebView iOS 27.2:
/// ，、。「」！・…— . ! ※, U+00A0 and U+3000 take none; # 1 Ａ ー 々 〇 ＋ take one.
public enum TextEmphasisCharacters {
    private static let wordSeparators: Set<UInt32> = [0x1361, 0x10100, 0x10101, 0x1039F, 0x0F0B, 0x0F0C]
    private static let markedPunctuation: Set<UInt32> = [
        0x23, 0x25, 0x26, 0x40, 0x0609, 0x060A, 0x066A, 0xFF06, 0xFF20, 0xFF03, 0xFF05, 0x303D,
        0x2030, 0x2031, 0x00B6, 0x204B, 0x00A7, 0xFE60, 0xFE6B, 0xFE5F, 0xFE6A, 0x2053, 0x204A,
    ]

    public static func receivesMark(_ scalar: Unicode.Scalar) -> Bool {
        if wordSeparators.contains(scalar.value) { return false }
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format, .unassigned:
            return false
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return markedPunctuation.contains(scalar.value)
        default:
            return true
        }
    }
}
