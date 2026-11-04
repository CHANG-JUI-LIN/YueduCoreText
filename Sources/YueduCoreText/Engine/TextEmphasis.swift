import CoreText
import Foundation
import UIKit

/// The shape keywords of `text-emphasis-style` (CSS Text Decoration 3 §3.1).
enum TextEmphasisShape: Equatable {
    case dot, circle, doubleCircle, triangle, sesame
}

/// `text-emphasis-style`, inherited; nil on `ComputedStyle` is `none`.
enum TextEmphasisStyle: Equatable {
    /// `filled` or `open`, with a shape; no shape is `circle` in horizontal
    /// writing and `sesame` in vertical.
    case shape(filled: Bool, shape: TextEmphasisShape?)
    /// A `<string>`: its first grapheme cluster is the mark.
    case string(String)

    /// The mark's characters, as WebKit draws them (CSS Text Decoration 3 §3.1).
    func mark(vertical: Bool) -> String {
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
struct TextEmphasisPosition: Equatable {
    var over: Bool? = nil
    var right = true

    /// Whether the marks go over the text in horizontal writing, for content
    /// in `language`.
    func isOver(language: String?) -> Bool {
        if let over { return over }
        let primary = language?.split(separator: "-").first?.lowercased()
        return primary == "ja" || primary == "ko"
    }
}

/// The CSS values of the `text-emphasis` properties.
enum TextEmphasisValue {
    /// `none`, `[filled | open] || <shape>`, or a string. `.some(nil)` is
    /// `none`; nil drops an invalid declaration. `preserved` keeps a string's case.
    static func style(_ preserved: String) -> TextEmphasisStyle?? {
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
    static func position(_ value: String) -> TextEmphasisPosition? {
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
    static func shorthand(_ components: [String], color parseColor: (String) -> UIColor??)
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
enum TextEmphasisCharacters {
    private static let wordSeparators: Set<UInt32> = [0x1361, 0x10100, 0x10101, 0x1039F, 0x0F0B, 0x0F0C]
    private static let markedPunctuation: Set<UInt32> = [
        0x23, 0x25, 0x26, 0x40, 0x0609, 0x060A, 0x066A, 0xFF06, 0xFF20, 0xFF03, 0xFF05, 0x303D,
        0x2030, 0x2031, 0x00B6, 0x204B, 0x00A7, 0xFE60, 0xFE6B, 0xFE5F, 0xFE6A, 0x2053, 0x204A,
    ]

    static func receivesMark(_ scalar: Unicode.Scalar) -> Bool {
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

/// The marks a text run draws: one per character that takes one, centred on
/// it, on the side `offset` points to (`TextEmphasisPainter`).
struct TextEmphasisPaint {
    let mark: String
    /// Half the text's size, in the font the text's own cascade draws the
    /// mark in (WebKit `emphasisMarkFontData`).
    let font: UIFont
    /// nil is the text's own colour, which a theme change recolours with it.
    let color: UIColor?
    /// From the baseline toward the under side (down; left in vertical-rl):
    /// horizontally the mark's baseline, vertically the line through its centre.
    let offset: CGFloat
    /// One mark for the whole text, on its column's centre line, centred on
    /// its em square: a 縦中横 cell, whose text is drawn horizontally. WebKit
    /// gives each cell one mark, punctuation too (measured, iOS 27.2: `12`,
    /// `123` and `!?` cells each one, where `傍點` takes them).
    var cell = false

    func recolored(_ color: UIColor?) -> TextEmphasisPaint {
        TextEmphasisPaint(mark: mark, font: font, color: color, offset: offset, cell: cell)
    }
}

/// Where a run's marks go and how much room they take, as WebKit places them
/// (`TextBoxPainter`, `InlineLevelBox` annotations; measured, WKWebView iOS
/// 27.2, the app's S001i and S001j fixtures). The mark is the text's font at
/// half its size; its height is its content area, its ascent and descent each
/// rounded up. It sits outside the text's content box, on its side:
/// - horizontally, under: its baseline the text's descent and its own ascent
///   below the text's; over: the text's ascent and its own descent above;
/// - vertically, its centre line half the text's content area and half its
///   own height right of the central baseline (left for `left`).
/// The line grows to hold it: 17px PingFang with Hiragino's ﹅ at 1.5 is 35.25
/// tall (25.5 without), with Helvetica's • 36.25.
enum TextEmphasisLayout {
    struct Placement {
        /// The mark is on the line's over side (above; right in vertical-rl).
        let over: Bool
        /// How far from the baseline (horizontal) or the central baseline
        /// (vertical) the mark's far edge reaches, on its side.
        let reach: CGFloat
        let paint: TextEmphasisPaint
    }

    static func placement(style: ComputedStyle, font: UIFont, vertical: Bool, fonts: InlineFontCache) -> Placement? {
        guard let emphasis = style.textEmphasisStyle else { return nil }
        let mark = emphasis.mark(vertical: vertical)
        guard !mark.isEmpty else { return nil }
        let markFont = fonts.markFont(mark, style: style, text: font)
        let markExtent = InlineLayout.roundedContentExtent(markFont)
        let markHeight = markExtent.ascent + markExtent.descent
        let text = InlineLayout.roundedContentExtent(font)
        let over = vertical ? style.textEmphasisPosition.right
            : style.textEmphasisPosition.isOver(language: style.language)
        let reach: CGFloat
        let offset: CGFloat
        if vertical {
            let half = (text.ascent + text.descent) / 2
            reach = half + markHeight
            offset = (half + markHeight / 2) * (over ? -1 : 1)
        } else if over {
            reach = text.ascent + markHeight
            offset = -(text.ascent + markExtent.descent)
        } else {
            reach = text.descent + markHeight
            offset = text.descent + markExtent.ascent
        }
        let paint = TextEmphasisPaint(mark: mark, font: markFont,
                                      color: style.textEmphasisColor ?? style.color, offset: offset)
        return Placement(over: over, reach: reach, paint: paint)
    }

    /// Whether `run` draws marks its style asks for: text or a 縦中横 cell, not
    /// a generated counter or quotation mark, a picture or an inline-block.
    /// A ruby base takes them only on the side its annotation leaves free.
    static func marks(_ run: InlineRun) -> Bool {
        run.style.textEmphasisStyle != nil && run.decorationEdge == nil && !run.isGeneratedText
            && run.atomic == nil && run.inlineBlock == nil
    }

    /// `runs` with the marks their styles ask for (`placement`).
    static func mark(_ runs: [LineRun], writingMode: ReaderWritingMode,
                     font resolveFont: (ComputedStyle) -> UIFont, fonts: InlineFontCache) -> [LineRun] {
        guard runs.contains(where: { $0.style.textEmphasisStyle != nil }) else { return runs }
        let vertical = writingMode != .horizontal
        return runs.map { run in
            guard run.style.textEmphasisStyle != nil, !run.isDecorationEdge, run.generatedText == nil,
                  run.atomic == nil, run.inlineBlock == nil, run.width > 0,
                  let placement = placement(style: run.style, font: resolveFont(run.style), vertical: vertical,
                                            fonts: fonts),
                  !(run.ruby != nil && placement.over)
            else { return run }
            var run = run
            run.textEmphasis = placement.paint
            run.textEmphasis?.cell = run.combined != nil
            return run
        }
    }

    /// The font `text`'s cascade draws `mark` in at half `text`'s size, the
    /// publication's fallbacks and then the system's, as in WebKit.
    static func markFont(_ mark: String, text: UIFont, language: String?) -> UIFont {
        let half = ReaderFontCascade.withoutReaderFallbacks(text).withSize(text.pointSize / 2)
        var attributes: [NSAttributedString.Key: Any] = [.font: half]
        if let language { attributes[kCTLanguageAttributeName as NSAttributedString.Key] = language }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: mark, attributes: attributes))
        guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
              let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName]
        else { return half }
        return value as! CTFont as UIFont
    }
}
