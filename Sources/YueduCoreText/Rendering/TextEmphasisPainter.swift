import CoreText
import UIKit
import YueduCoreTextTypography

/// Draws a text item's emphasis marks as WebKit does (`FontCascade::drawEmphasisMarks`):
/// one mark on each character that takes one (`TextEmphasisCharacters`), the
/// first of its cluster, upright in both writing modes. Everything happens in
/// the item's own frame: x along the line from its inline start, y from its
/// baseline toward the under side (down; left in vertical-rl).
///
/// Along the line, a horizontal mark's ink is centred on its character's ink,
/// a vertical one's on the middle of its character's advance (WebKit
/// `offsetToMiddleOfGlyph`). Across it, a horizontal mark stands on its
/// baseline and a vertical one is centred on its line (`TextEmphasisLayout`).
enum TextEmphasisPainter {

    /// `cellWidth` and `cellMiddle` place a 縦中横 cell's one mark: the
    /// item's width, and its middle from its baseline.
    static func draw(
        _ paint: TextEmphasisPaint, textColor: UIColor, vertical: Bool,
        line: CTLine, string: NSAttributedString, cellWidth: CGFloat = 0, cellMiddle: CGFloat = 0,
        in context: CGContext
    ) {
        let markFont = paint.font as CTFont
        let markCharacters = Array(paint.mark.utf16)
        var markGlyphs = [CGGlyph](repeating: 0, count: markCharacters.count)
        guard CTFontGetGlyphsForCharacters(markFont, markCharacters, &markGlyphs, markCharacters.count),
              let markGlyph = markGlyphs.first else { return }
        var glyph = markGlyph
        var markInk = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(markFont, .horizontal, &glyph, &markInk, 1)

        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor((paint.color ?? textColor).cgColor)
        // The text matrix is not graphics state: drawing the line left its
        // position at the line's end, which would shift every mark by it.
        context.textMatrix = .identity
        if paint.cell {
            // The item is the cell's text, drawn horizontally from its inline
            // start and baseline; the mark goes on the column's centre line,
            // which is the cell's middle, `offset` toward its under side.
            context.translateBy(x: cellWidth / 2 - paint.offset, y: cellMiddle)
            context.translateBy(x: -markInk.midX, y: markInk.midY)
            context.scaleBy(x: 1, y: -1)
            var position = CGPoint.zero
            CTFontDrawGlyphs(markFont, &glyph, &position, 1, context)
            return
        }
        let centres = vertical ? advanceCentres(line: line, string: string) : inkCentres(line: line, string: string)
        guard !centres.isEmpty else { return }
        // Every mark in one call: one call per mark cost 0.1 ms each.
        context.translateBy(x: 0, y: paint.offset)
        let positions: [CGPoint]
        if vertical {
            // Back upright, each mark's ink centred on its line and on its
            // character's advance, which runs down the turned frame.
            context.rotate(by: -.pi / 2)
            positions = centres.map { CGPoint(x: -markInk.midX, y: -($0 + markInk.midY)) }
        } else {
            positions = centres.map { CGPoint(x: $0 - markInk.midX, y: 0) }
        }
        context.scaleBy(x: 1, y: -1)
        let glyphs = [CGGlyph](repeating: glyph, count: positions.count)
        CTFontDrawGlyphs(markFont, glyphs, positions, positions.count, context)
    }

    /// How far the item's marks may reach, in its page coordinates, for
    /// culling: a mark's whole em either side of its line, and a point more.
    static func extent(of item: DisplayTextItem) -> CGRect {
        guard let paint = item.textEmphasis else { return .null }
        let size = paint.font.pointSize + 1
        let rect = item.rect.rawValue
        if paint.cell {
            return CGRect(x: rect.midX - paint.offset - size, y: rect.midY - size, width: 2 * size, height: 2 * size)
        }
        if item.writingMode == .horizontal {
            return CGRect(x: rect.minX - size, y: item.baselineY + paint.offset - size,
                          width: rect.width + 2 * size, height: 2 * size)
        }
        return CGRect(x: item.baselineY - paint.offset - size, y: rect.minY - size,
                      width: 2 * size, height: rect.height + 2 * size)
    }

    /// The characters of `string` that take a mark: the start of each
    /// composed character sequence whose first scalar does.
    static func markedRanges(in string: NSAttributedString) -> [NSRange] {
        let text = string.string as NSString
        var result: [NSRange] = []
        var index = 0
        while index < text.length {
            let range = text.rangeOfComposedCharacterSequence(at: index)
            if let scalar = text.substring(with: range).unicodeScalars.first,
               TextEmphasisCharacters.receivesMark(scalar) {
                result.append(range)
            }
            index = NSMaxRange(range)
        }
        return result
    }

    /// Each marked character's ink centre along a horizontal line.
    private static func inkCentres(line: CTLine, string: NSAttributedString) -> [CGFloat] {
        var firstGlyph: [Int: CGFloat] = [:]
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0,
                  let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { continue }
            let font = value as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            var inks = [CGRect](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, &inks, count)
            // A glyph with no ink (a space the font draws blank) centres on its origin.
            for index in 0..<count where firstGlyph[indices[index]] == nil {
                firstGlyph[indices[index]] = positions[index].x + (inks[index].isEmpty ? 0 : inks[index].midX)
            }
        }
        return markedRanges(in: string).compactMap { firstGlyph[$0.location] }
    }

    /// Each marked character's advance middle along a vertical line.
    private static func advanceCentres(line: CTLine, string: NSAttributedString) -> [CGFloat] {
        markedRanges(in: string).map { range in
            let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
            let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(range), nil)
            return (start + end) / 2
        }
    }
}
