import CoreText
import Foundation
import UIKit

extension CJKTypography {
    /// Squeezes adjacent punctuation as CLREQ and JLREQ allow.
    ///
    /// CLREQ ("Adjustment of adjacent punctuation marks",
    /// #h-adjustment_of_adjacent_punctuation_marks): whatever the text's overall style,
    /// when a bracket meets another punctuation mark, or brackets repeat, the pair's 2 em
    /// shrink to 1.5 em, and the squeeze keeps each bracket against the text it encloses.
    /// Fixed marks never shrink ("Punctuation width adjustment",
    /// #punctuation_width_adjustment): ：；？！ in vertical text everywhere, and ？！ in
    /// Taiwan and Hong Kong's horizontal text.
    ///
    /// The half em comes first from the blank between the two marks, then, for Chinese,
    /// from the bracket's far side: ？」 loses 」's trailing blank, as nothing may push
    /// into a fixed ？. JLREQ §3.1.4 squeezes only between the marks, and keeps its middle
    /// dots and dividing marks whole: ？」 stays 2 em, while 。」 and ：「 lose the blank
    /// between them.
    ///
    /// Blanks come from the ink of the font that draws each mark, where the position
    /// pass leaves it, so a squeeze never overlaps ink. The squeeze is kerning: an
    /// advance shrinks, no ink moves within its square. Line start and end trimming
    /// (CLREQ allows it) is not done.
    public static func applySpacing(to text: NSMutableAttributedString, style: CJKTypographyStyle,
                                    vertical: Bool, in range: NSRange? = nil) {
        let whole = range ?? NSRange(location: 0, length: text.length)
        guard whole.length > 1 else { return }
        var units = [unichar](repeating: 0, count: whole.length)
        (text.string as NSString).getCharacters(&units, range: whole)
        guard units.contains(where: { CJKSpacing.punctuationClass($0)?.isBracket == true }) else { return }
        // Points already taken from each mark's blank before and after its ink. A blank
        // can serve two pairs: 「's leading blank in 。「？ is first part of the gap after
        // 。, then the room 「 moves back into, so it is spent once.
        var usedLeading: [Int: CGFloat] = [:], usedTrailing: [Int: CGFloat] = [:]
        // Each squeeze: the character whose advance shrinks, by how much.
        var squeezes: [(range: NSRange, amount: CGFloat)] = []
        for offset in 0..<(units.count - 1) {
            guard let a = CJKSpacing.punctuationClass(units[offset]),
                  let b = CJKSpacing.punctuationClass(units[offset + 1]),
                  a.isBracket || b.isBracket else { continue }
            let index = whole.location + offset
            guard let first = CJKSpacing.body(at: index, in: text, style: style, vertical: vertical),
                  let second = CJKSpacing.body(at: index + 1, in: text, style: style, vertical: vertical)
            else { continue }
            let fixedFirst = a.isFixed(style: style, vertical: vertical)
            let fixedSecond = b.isFixed(style: style, vertical: vertical)
            let em = max(first.size, second.size)
            // Never ink against ink.
            let margin = 0.02 * em
            var need = max(0, first.advance + second.advance - 1.5 * em)
            guard need > 0.01 * em else { continue }
            let trailingRoom = fixedFirst ? 0 : max(0, first.trailing - usedTrailing[index, default: 0])
            let leadingRoom = fixedSecond ? 0 : max(0, second.leading - usedLeading[index + 1, default: 0])
            let between = min(need, max(0, trailingRoom + leadingRoom - margin))
            if between > 0 {
                squeezes.append((NSRange(location: index, length: 1), between))
                // The first mark's blank first: no later pair can use it.
                let fromTrailing = min(between, trailingRoom)
                usedTrailing[index, default: 0] += fromTrailing
                usedLeading[index + 1, default: 0] += between - fromTrailing
                need -= between
            }
            guard need > 0.01 * em, style != .japanese else { continue }
            if b == .closing, !fixedSecond {
                let far = min(need, max(0, second.trailing - usedTrailing[index + 1, default: 0] - margin))
                if far > 0 {
                    squeezes.append((NSRange(location: index + 1, length: 1), far))
                    usedTrailing[index + 1, default: 0] += far
                }
            } else if a == .opening, !fixedFirst, let before = CJKTypography.characterBefore(index, in: text),
                      before.location >= whole.location {
                let far = min(need, max(0, first.leading - usedLeading[index, default: 0] - margin))
                if far > 0 {
                    squeezes.append((before, far))
                    usedLeading[index, default: 0] += far
                }
            }
        }
        for squeeze in squeezes {
            CJKTypography.addKern(-squeeze.amount, to: squeeze.range, in: text)
        }
    }
}

/// The classes CLREQ and JLREQ squeeze by, and each mark's blank sides.
enum CJKSpacing {
    enum PunctuationClass: Equatable {
        case opening, closing, stop, comma, middle, dividing

        var isBracket: Bool { self == .opening || self == .closing }

        /// CLREQ's fixed marks, and JLREQ's middle dots and dividing marks, which keep
        /// their spaces in these pairs.
        func isFixed(style: CJKTypographyStyle, vertical: Bool) -> Bool {
            switch self {
            case .middle: return vertical || style == .japanese
            case .dividing: return vertical || style == .traditional || style == .japanese
            default: return false
            }
        }
    }

    /// JLREQ's classes (Appendix A): cl-01 opening brackets, cl-02 closing brackets,
    /// cl-04 dividing punctuation, cl-05 middle dots, cl-06 full stops, cl-07 commas.
    /// Quotation marks are brackets; set in a proportional font they are too narrow to
    /// need a squeeze, and in a full-width one they squeeze like 「」.
    static func punctuationClass(_ unit: unichar) -> PunctuationClass? {
        switch unit {
        // 「『（【〔〖《〈［｛〘〚｟ ‘“«〝
        case 0x300C, 0x300E, 0xFF08, 0x3010, 0x3014, 0x3016, 0x300A, 0x3008, 0xFF3B, 0xFF5B, 0x3018, 0x301A, 0xFF5F,
             0x2018, 0x201C, 0x00AB, 0x301D:
            return .opening
        // 」』）】〕〗》〉］｝〙〛｠ ’”»〞〟
        case 0x300D, 0x300F, 0xFF09, 0x3011, 0x3015, 0x3017, 0x300B, 0x3009, 0xFF3D, 0xFF5D, 0x3019, 0x301B, 0xFF60,
             0x2019, 0x201D, 0x00BB, 0x301E, 0x301F:
            return .closing
        case 0x3002, 0xFF0E: return .stop
        case 0x3001, 0xFF0C: return .comma
        case 0xFF1A, 0xFF1B, 0x30FB: return .middle
        case 0xFF1F, 0xFF01: return .dividing
        default: return nil
        }
    }

    /// A mark's square and the blanks either side of its ink, in points.
    struct Body {
        let size: CGFloat
        let advance: CGFloat
        let leading: CGFloat
        let trailing: CGFloat
    }

    /// The mark at `index` as it will be drawn: in the font that draws it, in its
    /// language, upright or on its side as the orientation pass will set it, and where
    /// the position pass puts it.
    static func body(at index: Int, in text: NSAttributedString, style: CJKTypographyStyle, vertical: Bool) -> Body? {
        let attributes = text.attributes(at: index, effectiveRange: nil)
        guard attributes[CJKTypography.runDelegate] == nil,
              let font = attributes[.font].flatMap(CJKTypography.ctFont) else { return nil }
        let unit = (text.string as NSString).character(at: index)
        guard let drawing = CJKPunctuation.drawingFont(for: unit, in: font) else { return nil }
        let language = attributes[CJKTypography.language] as? String
        let character = String(utf16CodeUnits: [unit], count: 1)
        // A mark on its side keeps its horizontal glyph, turned with the line: its
        // extent along the column is its horizontal one.
        let upright = vertical && CJKTypography.isUpright(character, at: index, in: text)
        guard let ink = PunctuationPlacement.position(of: character, in: drawing, language: language ?? "",
                                                      vertical: upright) else { return nil }
        let moved = CJKPunctuation.placedMarks.contains(unit)
            ? CJKPunctuation.correction(for: unit, in: drawing, language: language, style: style, vertical: vertical)?.along ?? 0
            : 0
        let size = CTFontGetSize(drawing)
        return Body(size: size, advance: ink.advance * size,
                    leading: max(0, ink.inkStart + moved) * size,
                    trailing: max(0, ink.advance - ink.inkEnd - moved) * size)
    }
}
