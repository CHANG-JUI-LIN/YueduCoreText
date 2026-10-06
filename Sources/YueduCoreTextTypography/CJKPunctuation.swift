import CoreText
import Foundation
import UIKit

extension CJKTypography {
    /// Fonts, then punctuation positions: the CJK pass both engines run over text
    /// they are about to shape. Vertical orientation is a separate pass, as only
    /// vertical text needs it.
    public static func apply(to text: NSMutableAttributedString, style: CJKTypographyStyle,
                             vertical: Bool, in range: NSRange? = nil) {
        applyFonts(to: text, style: style, in: range)
        applyPositions(to: text, style: style, vertical: vertical, in: range)
    }

    /// Moves 、。，．：；？！ to where the style puts them when the font that draws
    /// them puts them elsewhere.
    ///
    /// CLREQ ("Major differences between horizontal and vertical writing modes",
    /// #major_differences_between_horizontal_and_vertical_writing_modes): Taiwan and
    /// Hong Kong centre these pause and stop marks in their square; the Mainland puts
    /// them at the end of the text they follow, lower left in horizontal text and upper
    /// right in vertical text. JLREQ §3.1.4 puts 、。 in the same corners and centres
    /// ：；？！. Each style's system font already sets them so (measured 2026-10-06),
    /// so the style's font is the target: a mark in another font — PingFang SC in a
    /// Traditional book, an embedded Japanese face in a Chinese one — is measured and
    /// moved by the difference. A mark already in the style's font is left alone.
    ///
    /// The move keeps the mark's advance: across the line by `baselineOffset`, along
    /// it by a pair of opposite kerns, so nothing else on the line shifts.
    public static func applyPositions(to text: NSMutableAttributedString, style: CJKTypographyStyle,
                                      vertical: Bool, in range: NSRange? = nil) {
        let whole = range ?? NSRange(location: 0, length: text.length)
        guard whole.length > 0 else { return }
        var units = [unichar](repeating: 0, count: whole.length)
        (text.string as NSString).getCharacters(&units, range: whole)
        guard units.contains(where: CJKPunctuation.placedMarks.contains) else { return }
        struct Move { let index: Int; let along: CGFloat; let across: CGFloat }
        var moves: [Move] = []
        // One check per font run: this runs on every paragraph a layout shapes, and most
        // marks are already in their style's own font, which `applyFonts` chose.
        text.enumerateAttribute(.font, in: whole) { value, run, _ in
            guard let font = value.flatMap(ctFont), !CJKPunctuation.isReference(font, for: style) else { return }
            var corrections: [String: (along: CGFloat, across: CGFloat)?] = [:]
            for index in run.location..<NSMaxRange(run) {
                let unit = units[index - whole.location]
                guard CJKPunctuation.placedMarks.contains(unit),
                      text.attribute(runDelegate, at: index, effectiveRange: nil) == nil else { continue }
                // The language CoreText will shape the mark in: `applyFonts` tags CJK text
                // with the style's, and a font's language forms can already place it.
                let markLanguage = text.attribute(language, at: index, effectiveRange: nil) as? String
                let key = "\(unit)|\(markLanguage ?? "")"
                if corrections[key] == nil {
                    corrections[key] = CJKPunctuation.drawingFont(for: unit, in: font).flatMap { markFont in
                        CJKPunctuation.correction(for: unit, in: markFont, language: markLanguage,
                                                  style: style, vertical: vertical)
                            .map { (along: $0.along * CTFontGetSize(markFont), across: $0.across * CTFontGetSize(markFont)) }
                    }
                }
                guard let move = corrections[key] ?? nil else { continue }
                moves.append(Move(index: index, along: move.along, across: move.across))
            }
        }
        for move in moves {
            let existing = (text.attribute(.baselineOffset, at: move.index, effectiveRange: nil) as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? 0
            // Across: up a horizontal line is up; up a vertical line, turned clockwise, is right.
            let raise = vertical ? move.across : -move.across
            text.addAttribute(.baselineOffset, value: existing + raise, range: NSRange(location: move.index, length: 1))
            // Along: the mark's own advance stays; the gap before it grows by as much as
            // the gap after it shrinks. A mark that opens its range has nothing before it.
            guard move.index > whole.location, move.along != 0 else { continue }
            addKern(move.along, at: move.index - 1, in: text)
            addKern(-move.along, at: move.index, in: text)
        }
    }

    private static func addKern(_ amount: CGFloat, at index: Int, in text: NSMutableAttributedString) {
        let existing = (text.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)
            .map { CGFloat($0.doubleValue) } ?? 0
        text.addAttribute(.kern, value: existing + amount, range: NSRange(location: index, length: 1))
    }
}

/// Where pause and stop marks sit in their square, and how far a font is from its style.
enum CJKPunctuation {
    /// 、。，．：；？！: the marks CLREQ and JLREQ place by region.
    static let placedMarks: Set<unichar> = [0x3001, 0x3002, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF01]

    /// Whether `font` is the style's own font at its weight and slant, which sets marks
    /// where the style puts them.
    static func isReference(_ font: CTFont, for style: CJKTypographyStyle) -> Bool {
        CTFontCopyPostScriptName(CJKFontLookup.standIn(for: style, like: font) as CTFont)
            == CTFontCopyPostScriptName(font)
    }

    /// The convention a style's marks are told apart from: Traditional text against the
    /// Mainland's corners, every other style against Taiwan's centres.
    static func other(than style: CJKTypographyStyle) -> CJKTypographyStyle {
        style == .traditional ? .simplified : .traditional
    }

    /// The font CoreText draws `mark` with in a run of `font`: the font itself, or the
    /// first font of its cascade that has it. nil when only the system's fallback does.
    static func drawingFont(for mark: unichar, in font: CTFont) -> CTFont? {
        var unit = mark
        var glyph: CGGlyph = 0
        for member in CJKFontLookup.stack(of: font).fonts
        where CTFontGetGlyphsForCharacters(member, &unit, &glyph, 1) && glyph != 0 {
            return member
        }
        return nil
    }

    /// How far, in ems, `mark` in `font`, shaped in `language`, must move to sit where
    /// `style`'s font sets it; nil when it already follows the style.
    ///
    /// A font follows the style when its mark lies nearer the style's font's than the
    /// other convention's: fonts of one convention still differ by design — Hiragino
    /// Sans sets a vertical ， 0.14 em further right than PingFang SC, both in the
    /// corner — and an embedded face keeps its design unless it follows another region.
    static func correction(for mark: unichar, in font: CTFont, language: String?, style: CJKTypographyStyle,
                           vertical: Bool) -> (along: CGFloat, across: CGFloat)? {
        let reference = CJKFontLookup.standIn(for: style, like: font) as CTFont
        if language == style.languageTag, CTFontCopyPostScriptName(reference) == CTFontCopyPostScriptName(font) {
            return nil
        }
        let character = String(utf16CodeUnits: [mark], count: 1)
        let otherStyle = other(than: style)
        let otherReference = CJKFontLookup.standIn(for: otherStyle, like: font) as CTFont
        guard let target = PunctuationPlacement.position(of: character, in: reference,
                                                         language: style.languageTag, vertical: vertical),
              let elsewhere = PunctuationPlacement.position(of: character, in: otherReference,
                                                            language: otherStyle.languageTag, vertical: vertical),
              let actual = PunctuationPlacement.position(of: character, in: font,
                                                         language: language ?? "", vertical: vertical)
        else { return nil }
        func distance(_ a: PunctuationPlacement.Position, _ b: PunctuationPlacement.Position) -> CGFloat {
            hypot(a.along - b.along, a.across - b.across)
        }
        guard distance(actual, target) > distance(actual, elsewhere) else { return nil }
        return (target.along - actual.along, target.across - actual.across)
    }
}

/// Where a character's ink sits in its square, measured from a drawing: the
/// character between two 田, drawn as the engines draw a line — turned clockwise
/// for vertical text, with vertical forms — and found in the pixels.
enum PunctuationPlacement {
    /// Ems from the square's centre. `along` is positive later in the line; `across`
    /// is positive below a horizontal line and right of a vertical one. The square's
    /// centre across the line is the centre of 田's ink in the same font.
    struct Position: Equatable { let along: CGFloat; let across: CGFloat }

    private struct Key: Hashable {
        let font: String
        let slant: CGFloat
        let language: String
        let character: String
        let vertical: Bool
    }
    nonisolated(unsafe) private static var cache: [Key: Position?] = [:]
    private static let lock = NSLock()
    private static let em: CGFloat = 64

    static func position(of character: String, in font: CTFont, language: String, vertical: Bool) -> Position? {
        var matrix = CTFontGetMatrix(font)
        let key = Key(font: CTFontCopyPostScriptName(font) as String, slant: matrix.c, language: language,
                      character: character, vertical: vertical)
        if let cached = lock.withLock({ cache[key] }) { return cached }
        let measured = measure(character, CTFontCreateCopyWithAttributes(font, em, &matrix, nil), language, vertical)
        lock.withLock { cache[key] = measured }
        return measured
    }

    private static func measure(_ character: String, _ font: CTFont, _ language: String, _ vertical: Bool) -> Position? {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black.cgColor]
        if !language.isEmpty { attributes[CJKTypography.language] = language }
        if vertical { attributes[CJKTypography.verticalForms] = true }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "田" + character + "田", attributes: attributes))
        let edges = (0...3).map { CTLineGetOffsetForStringIndex(line, $0, nil) }
        // Room for three squares along the line and two across it.
        let alongSpan = Int(edges[3] + em), acrossSpan = Int(em * 2.5)
        let width = vertical ? acrossSpan : alongSpan, height = vertical ? alongSpan : acrossSpan
        var pixels = [UInt8](repeating: 0, count: width * height)
        let origin = CGPoint(x: vertical ? em * 1.25 : em / 2, y: vertical ? CGFloat(height) - em / 2 : em)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: origin.x, y: origin.y)
            // Vertical: along the line runs down the page and up the line is right,
            // as `ReaderDisplayListDrawer` and a vertical CTFrame both turn it.
            if vertical { context.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) }
            context.textPosition = .zero
            CTLineDraw(line, context)
            return true
        }
        guard drew else { return nil }
        // Ink boxes per square, in drawing coordinates (y up), in one pass: row 0 of the
        // buffer is the top.
        var boxes = [CGRect](repeating: .null, count: 3)
        for row in 0..<height {
            let y = CGFloat(height - row) - 0.5
            for column in 0..<width where pixels[row * width + column] < 128 {
                let x = CGFloat(column) + 0.5
                let along = vertical ? origin.y - y : x - origin.x
                guard let square = (0..<3).first(where: { along >= edges[$0] && along <= edges[$0 + 1] }) else { continue }
                boxes[square] = boxes[square].union(CGRect(x: x, y: y, width: 0, height: 0))
            }
        }
        guard !boxes.contains(where: \.isNull) else { return nil }
        let (before, mark, after) = (boxes[0], boxes[1], boxes[2])
        // The square's centre is midway between the two 田, both ways, as a reader sees it.
        let centre = CGPoint(x: (before.midX + after.midX) / 2, y: (before.midY + after.midY) / 2)
        if vertical {
            return Position(along: (centre.y - mark.midY) / em, across: (mark.midX - centre.x) / em)
        }
        return Position(along: (mark.midX - centre.x) / em, across: (centre.y - mark.midY) / em)
    }
}
