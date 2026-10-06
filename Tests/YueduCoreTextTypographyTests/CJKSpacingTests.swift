import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("CJK typography: adjacent punctuation")
struct CJKSpacingTests {
    private static let size: CGFloat = 20

    /// The text a pair sits in, through the whole CJK pass, as an engine shapes it.
    private func shaped(_ pair: String, style: CJKTypographyStyle, vertical: Bool) -> NSAttributedString {
        let han = style == .traditional ? "國" : "国"
        let text = NSMutableAttributedString(string: han + pair + han,
                                             attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        CJKTypography.apply(to: text, style: style, vertical: vertical)
        if vertical { CJKTypography.applyOrientation(to: text) }
        return text
    }

    /// The pair's advance, in ems: its glyphs' advances, kerns included. Caret offsets
    /// (`CTLineGetOffsetForStringIndex`) put the boundary after a kerned glyph halfway
    /// through the kern, and glyph positions of upright and sideways runs live in
    /// different spaces, so neither can measure a squeeze.
    private func advance(of text: NSAttributedString) -> CGFloat {
        var total: CGFloat = 0
        for run in CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as! [CTRun] {
            let glyphs = CTRunGetGlyphCount(run)
            var advances = [CGSize](repeating: .zero, count: glyphs)
            var indices = [CFIndex](repeating: 0, count: glyphs)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for (advance, index) in zip(advances, indices) where index == 1 || index == 2 { total += advance.width }
        }
        return total / Self.size
    }

    /// The extent along the line of one character's ink, drawn where the line puts it.
    private func inkSpan(of index: Int, in text: NSAttributedString, vertical: Bool) -> ClosedRange<CGFloat>? {
        let colour = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let shaped = NSMutableAttributedString(attributedString: text)
        shaped.addAttribute(colour, value: CGColor(gray: 0, alpha: 0), range: NSRange(location: 0, length: shaped.length))
        shaped.addAttribute(colour, value: CGColor(gray: 0, alpha: 1), range: NSRange(location: index, length: 1))
        let line = CTLineCreateWithAttributedString(shaped)
        let scale: CGFloat = 4
        let length = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let along = Int((length + Self.size) * scale), across = Int(Self.size * 2.5 * scale)
        let width = vertical ? across : along, height = vertical ? along : across
        var pixels = [UInt8](repeating: 0, count: width * height)
        let origin = CGPoint(x: vertical ? Self.size * 1.25 : Self.size / 2,
                             y: vertical ? CGFloat(height) / scale - Self.size / 2 : Self.size)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: origin.x, y: origin.y)
            if vertical { context.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) }
            context.textPosition = .zero
            CTLineDraw(line, context)
        }
        var span: ClosedRange<CGFloat>?
        for row in 0..<height {
            for column in 0..<width where pixels[row * width + column] < 128 {
                let x = (CGFloat(column) + 0.5) / scale, y = (CGFloat(height - row) - 0.5) / scale
                let position = vertical ? origin.y - y : x - origin.x
                span = span.map { min($0.lowerBound, position)...max($0.upperBound, position) } ?? position...position
            }
        }
        return span
    }

    /// Whether the ink of the marks at `index` and `index + 1` overlaps, or touches, when
    /// the line is drawn.
    private func inkOverlaps(_ text: NSAttributedString, at index: Int = 1, vertical: Bool) -> Bool {
        guard let first = inkSpan(of: index, in: text, vertical: vertical),
              let second = inkSpan(of: index + 1, in: text, vertical: vertical) else { return true }
        return first.upperBound >= second.lowerBound
    }

    static let pairs = ["：「", "？」", "。」", "」「", "、「", "（「", "」」", "「「", "」）"]

    @Test("Chinese pairs shrink to 1.5 em, ink never touching", arguments: [
        (CJKTypographyStyle.traditional, true), (.traditional, false), (.simplified, true), (.simplified, false),
    ])
    func chinese(style: CJKTypographyStyle, vertical: Bool) {
        for pair in Self.pairs {
            let text = shaped(pair, style: style, vertical: vertical)
            let label = "\(style) vertical=\(vertical) \(pair): \(advance(of: text)) em"
            #expect(abs(advance(of: text) - 1.5) <= 0.06, "\(label)")
            #expect(!inkOverlaps(text, vertical: vertical), "ink overlaps: \(label)")
        }
    }

    @Test("Japanese pairs squeeze only between the marks (JLREQ)", arguments: [true, false])
    func japanese(vertical: Bool) {
        for pair in Self.pairs {
            let text = shaped(pair, style: .japanese, vertical: vertical)
            let label = "japanese vertical=\(vertical) \(pair): \(advance(of: text)) em"
            // ？ keeps its whole square and 」 its far blank: nothing is squeezed.
            let expected: CGFloat = pair == "？」" ? 2 : 1.5
            #expect(abs(advance(of: text) - expected) <= 0.06, "\(label)")
            #expect(!inkOverlaps(text, vertical: vertical), "ink overlaps: \(label)")
        }
    }

    @Test("Marks without a bracket keep their squares")
    func noBracketNoSqueeze() {
        for pair in ["。，", "？！", "：。"] {
            #expect(abs(advance(of: shaped(pair, style: .simplified, vertical: false)) - 2) <= 0.01, "\(pair)")
        }
    }

    @Test("Runs of marks never put ink against ink: each blank is spent once", arguments: [
        (CJKTypographyStyle.traditional, true), (.traditional, false), (.simplified, true), (.simplified, false),
        (.japanese, true), (.japanese, false),
    ])
    func runsOfMarks(style: CJKTypographyStyle, vertical: Bool) {
        for run in ["。「？", "？「？", "」「「", "？」」", "（「『", "】【。", "《《", "……】", "。，"] {
            let text = shaped(run, style: style, vertical: vertical)
            for index in 1..<(run.utf16.count) {
                #expect(!inkOverlaps(text, at: index, vertical: vertical),
                        "ink overlaps: \(style) vertical=\(vertical) \(run) at \(index)")
            }
        }
    }

    @Test("Quotation marks are brackets: full-width ones squeeze, proportional ones never grow", arguments: [
        (CJKTypographyStyle.traditional, true), (.traditional, false), (.simplified, true), (.simplified, false),
        (.japanese, true), (.japanese, false),
    ])
    func quotationMarks(style: CJKTypographyStyle, vertical: Bool) {
        // 〝 is full-width in every CJK system font, 〟 in Hiragino (PingFang has none:
        // CoreText's fallback draws it, out of this pass's reach). “”‘’ are proportional
        // across the line and, where the font has vertical forms, a full square down a
        // column.
        for pair in style == .japanese ? ["：〝", "〟。", "。〟", "〟〝"] : ["：〝", "。〝", "〝「"] {
            let text = shaped(pair, style: style, vertical: vertical)
            let label = "\(style) vertical=\(vertical) \(pair): \(advance(of: text)) em"
            #expect(abs(advance(of: text) - 1.5) <= 0.06, "\(label)")
            #expect(!inkOverlaps(text, vertical: vertical), "ink overlaps: \(label)")
        }
        for pair in ["：“", "。”", "”，", "‘“", "”’", "？“"] {
            let text = shaped(pair, style: style, vertical: vertical)
            let label = "\(style) vertical=\(vertical) \(pair): \(advance(of: text)) em"
            #expect(advance(of: text) <= (vertical ? 2.01 : 1.56), "\(label)")
            #expect(!inkOverlaps(text, vertical: vertical), "ink overlaps: \(label)")
        }
    }

    @Test("The room before a bracket comes from the whole character before it, even outside the BMP")
    func farSideBeforeSupplementaryHan() {
        // 「？ with a fixed ？: 「 moves back into its own leading blank, which shortens the
        // character before it. 𠀀 (U+20000) is two UTF-16 units and one glyph.
        func width(_ before: String, _ squeezed: Bool) -> CGFloat {
            let text = NSMutableAttributedString(string: "國\(before)「？國", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
            if squeezed {
                CJKTypography.apply(to: text, style: .traditional, vertical: false)
            } else {
                CJKTypography.applyFonts(to: text, style: .traditional)
                CJKTypography.applyPositions(to: text, style: .traditional, vertical: false)
            }
            return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil))
        }
        for before in ["𠀀", "國"] {
            let saved = (width(before, false) - width(before, true)) / Self.size
            #expect(saved > 0.4 && saved <= 0.5, "\(before): saved \(saved) em")
        }
        // CoreText kerns a combining sequence by no rule a squeeze could rely on: it is
        // left whole.
        let saved = (width("e\u{301}", false) - width("e\u{301}", true)) / Self.size
        #expect(saved >= 0 && saved < 0.05, "e + U+0301: saved \(saved) em")
    }

    @Test("A squeeze adds to the kern already there")
    func kernAccumulates() {
        let plain = shaped("」「", style: .simplified, vertical: false)
        let spaced = NSMutableAttributedString(string: "国」「国", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        spaced.addAttribute(.kern, value: 3, range: NSRange(location: 1, length: 1))
        CJKTypography.apply(to: spaced, style: .simplified, vertical: false)
        let squeezed = plain.attribute(.kern, at: 1, effectiveRange: nil) as? CGFloat ?? 0
        #expect(squeezed < 0)
        #expect(abs((spaced.attribute(.kern, at: 1, effectiveRange: nil) as? CGFloat ?? 0) - (squeezed + 3)) < 0.001)
    }
}
