import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("Glyph boundaries")
struct GlyphBoundaryTests {
    private static let size: CGFloat = 20

    /// 國？」國國 with 」 squeezed against ？ (Traditional: ？ is fixed, so 」 gives up
    /// its far side): the kern on 」 is about half an em.
    private func squeezed(vertical: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "國？」國國", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        CJKTypography.apply(to: text, style: .traditional, vertical: vertical)
        if vertical { CJKTypography.applyOrientation(to: text) }
        return text
    }

    /// Where each character's glyph starts along a left-to-right line: the advances,
    /// kerns included, of the glyphs before it. Upright and sideways runs report
    /// positions in different spaces; advances are along the line in both.
    private func glyphStarts(_ line: CTLine, count: Int) -> [CGFloat] {
        var advances: [(index: CFIndex, width: CGFloat)] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let glyphs = CTRunGetGlyphCount(run)
            var widths = [CGSize](repeating: .zero, count: glyphs)
            var indices = [CFIndex](repeating: 0, count: glyphs)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &widths)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            advances += zip(indices, widths).map { ($0.0, $0.1.width) }
        }
        return (0...count).map { index in advances.filter { $0.index < index }.reduce(0) { $0 + $1.width } }
    }

    @Test("After a negative kern the boundary is where the next glyph starts", arguments: [false, true])
    func afterSqueeze(vertical: Bool) throws {
        let text = squeezed(vertical: vertical)
        let kern = try #require(text.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat)
        #expect(kern < -0.4 * Self.size)
        let line = CTLineCreateWithAttributedString(text)
        let starts = glyphStarts(line, count: text.length)
        // CoreText's own boundary lies half the kern inside the glyph after 」.
        #expect(CTLineGetOffsetForStringIndex(line, 3, nil) - starts[3] > 0.2 * Self.size)
        for index in 0...text.length {
            #expect(abs(GlyphBoundary.offset(line, at: index) - starts[index]) < 0.01,
                    "vertical=\(vertical) index \(index): \(GlyphBoundary.offset(line, at: index)) vs \(starts[index])")
        }
    }

    @Test("Letter spacing, no kern and right-to-left text keep CoreText's boundaries")
    func otherwiseCoreText() {
        let spaced = NSMutableAttributedString(string: "國國國", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        spaced.addAttribute(.kern, value: 4, range: NSRange(location: 0, length: 3))
        let plain = NSAttributedString(string: "Hello 國", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        let hebrew = NSMutableAttributedString(string: "אבגד", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        hebrew.addAttribute(.kern, value: -3, range: NSRange(location: 1, length: 1))
        for text in [spaced, plain, hebrew] {
            let line = CTLineCreateWithAttributedString(text)
            for index in 0...text.length {
                #expect(GlyphBoundary.offset(line, at: index) == CTLineGetOffsetForStringIndex(line, index, nil),
                        "\(text.string) index \(index)")
            }
        }
    }

    @Test("A hit lands on the nearest boundary as the glyphs stand")
    func hits() {
        let text = squeezed(vertical: false)
        let line = CTLineCreateWithAttributedString(text)
        let starts = glyphStarts(line, count: text.length)
        // In the right half of 」's narrowed square: after 」, though CoreText, which
        // still counts half the kern inside 」, answers before it.
        let lateInBracket = starts[2] + (starts[3] - starts[2]) * 0.75
        #expect(GlyphBoundary.index(line, at: lateInBracket) == 3)
        // Just inside the 國 after it: before that 國.
        #expect(GlyphBoundary.index(line, at: starts[3] + 1) == 3)
        // Far from any squeeze: CoreText's answer.
        let middle = (starts[4] + starts[5]) / 2 + 1
        #expect(GlyphBoundary.index(line, at: middle) == CTLineGetStringIndexForPosition(line, CGPoint(x: middle, y: 0)))
    }
}
