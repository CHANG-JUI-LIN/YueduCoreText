import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("CJK punctuation compression")
struct CJKTypographyProcessorTests {
    @Test("ellipsis and closing bracket ink bounds never overlap")
    func ellipsisAndClosingBracketInkBoundsNeverOverlap() throws {
        let font = UIFont.systemFont(ofSize: 20)
        let input = NSAttributedString(
            string: "……】",
            attributes: [.font: font]
        )

        let output = CJKTypographyProcessor.apply(to: input)
        let line = CTLineCreateWithAttributedString(output)
        let inkRects = glyphInkRectsByStringIndex(in: line)

        for index in 0..<(output.length - 1) {
            let currentRect = try #require(inkRects[index])
            let nextRect = try #require(inkRects[index + 1])
            let inkGap = nextRect.minX - currentRect.maxX

            #expect(
                inkGap >= 0,
                "Adjacent punctuation overlaps by \(-inkGap)pt at pair \(index)"
            )
        }
    }

    @Test("common punctuation pairs preserve visible ink separation")
    func commonPunctuationPairsPreserveVisibleInkSeparation() throws {
        let font = UIFont.systemFont(ofSize: 20)
        let samples = ["。，", "】【，", "】【", "《《", "？！", "……】"]

        for sample in samples {
            let output = CJKTypographyProcessor.apply(
                to: NSAttributedString(
                    string: sample,
                    attributes: [.font: font]
                )
            )
            let line = CTLineCreateWithAttributedString(output)
            let inkRects = glyphInkRectsByStringIndex(in: line)

            for index in 0..<(output.length - 1) {
                let currentRect = try #require(inkRects[index])
                let nextRect = try #require(inkRects[index + 1])
                #expect(
                    nextRect.minX >= currentRect.maxX,
                    "\(sample) overlaps at UTF-16 pair \(index)"
                )
            }
        }
    }

    @Test("punctuation still compresses when the shaped glyphs have removable space")
    func punctuationStillCompressesWhenSafe() throws {
        let font = UIFont.systemFont(ofSize: 20)
        let input = NSAttributedString(
            string: "】【。",
            attributes: [.font: font]
        )

        let output = CJKTypographyProcessor.apply(to: input)
        let kern = try #require(
            output.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        )

        #expect(kern < 0)
        #expect(kern > -font.pointSize)
        #expect(output.length == input.length)
    }

    private func glyphInkRectsByStringIndex(in line: CTLine) -> [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let fontValue = attributes[kCTFontAttributeName] else {
                continue
            }
            let font = fontValue as! CTFont

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var stringIndices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)
            CTRunGetStringIndices(run, CFRangeMake(0, 0), &stringIndices)

            for glyphIndex in 0..<count {
                var glyph = glyphs[glyphIndex]
                let bounds = CTFontGetBoundingRectsForGlyphs(
                    font,
                    .horizontal,
                    &glyph,
                    nil,
                    1
                )
                result[stringIndices[glyphIndex]] = bounds.offsetBy(
                    dx: positions[glyphIndex].x,
                    dy: positions[glyphIndex].y
                )
            }
        }
        return result
    }
}
