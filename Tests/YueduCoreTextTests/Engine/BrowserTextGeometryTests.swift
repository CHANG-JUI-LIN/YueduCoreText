import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreText
import YueduCoreTextTypography

@Suite("Browser text geometry")
struct BrowserTextGeometryTests {
    /// Selections, highlights and narration use these rects. After punctuation squeezed
    /// by a negative kern, each character's rect starts where its glyph does.
    @Test("Rects follow the glyphs after a squeezed mark")
    func rectsAfterSqueeze() {
        let font = UIFont.systemFont(ofSize: 20)
        let attributed = NSMutableAttributedString(string: "國？」國國", attributes: [.font: font])
        CJKTypography.apply(to: attributed, style: .traditional, vertical: false)
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let item = DisplayTextItem(
            sourceRange: NSRange(location: 0, length: 5), nodeID: 1, linkTarget: nil, writingMode: .horizontal,
            rect: .init(rawValue: CGRect(x: 0, y: 0, width: width, height: 30)),
            baselineY: 25, font: font, color: .black, text: attributed.string, ctLine: line)
        let list = DisplayList(items: [.text(item)])
        var origins: [CGFloat] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            var positions = [CGPoint](repeating: .zero, count: CTRunGetGlyphCount(run))
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            origins += positions.map(\.x)
        }
        origins.append(width)
        for index in 0..<5 {
            let rect = BrowserTextGeometry.rects(in: list, range: NSRange(location: index, length: 1)).first ?? .null
            #expect(abs(rect.minX - origins[index]) < 0.01 && abs(rect.maxX - origins[index + 1]) < 0.01,
                    "index \(index): \(rect.minX)...\(rect.maxX), glyphs \(origins[index])...\(origins[index + 1])")
        }
        // A tap in the 國 after the squeezed 」 selects that 國.
        let tap = CGPoint(x: origins[3] + 2, y: 15)
        #expect(BrowserTextGeometry.range(at: tap, in: list, source: attributed.string as NSString) == NSRange(location: 3, length: 1))
    }
}
