import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// `position: absolute` inside a positioned block: a label pinned by `top`
/// and `left` or `right`. Any absolutely positioned box used to send its
/// chapter to the host's fallback. The panel below is a book's own (a row of
/// a character sheet: name, bar, score), and the numbers are WebKit's for it
/// (iOS 27.2): the name 5 from the row's left edge and 15 below its top, the
/// score's 22px box 8 from the right edge, the bar where the padding leaves it.
struct PositionedLayoutTests {

    private let css = """
    body { margin: 0; padding: 0; } p { margin: 0; }
    .item { margin: 6px 0; padding: 8px 30px 8px 80px; background: #fff; position: relative; }
    .name { font-size: 12px; position: absolute; left: 5px; top: 15px; width: 75px; height: 14px; line-height: 14px; }
    .score { font-size: 13px; font-weight: bold; position: absolute; right: 8px; top: 15px; width: 22px; height: 14px;
             line-height: 14px; text-align: center; }
    .bar { width: 100%; height: 14px; background: #ced4da; }
    """
    private let row = "<div class=\"item\"><div class=\"name\">创意</div><div class=\"bar\"></div><div class=\"score\">7</div></div><p>after</p>"

    private func layout(_ body: String, css extra: String = "", width: CGFloat = 350) async throws -> [PageFragments] {
        try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [css + extra],
                                                  width: width, height: 800).0
    }

    private func scan(_ body: String, css: String, writingMode: ReaderWritingMode = .horizontal) -> BrowserLayoutCapabilityResult {
        BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body>\(body)</body></html>", cssTexts: [css],
                                            writingMode: writingMode)
    }

    @Test func labelsArePinnedByTheirInsetsAndTakeNoRoom() async throws {
        let pages = try await layout(row)
        let texts = BrowserLayoutTestSupport.allTextFragments(pages).map(\.rect.rawValue)
        #expect(texts.count == 3)
        let name = texts[0], score = texts[1], after = texts[2]
        #expect(abs(name.minX - 5) < 0.5, "\(name)")
        // The 14px line box starts 15 below the row's padding edge (the row's top, at 6).
        #expect(abs(name.midY - (6 + 15 + 7)) < 1, "\(name)")
        // Centred in the 22px box whose right edge is 8 from the row's.
        #expect(abs(score.midX - (350 - 8 - 11)) < 0.5, "\(score)")
        #expect(abs(score.midY - (6 + 15 + 7)) < 1, "\(score)")
        // The row is as tall as its bar and padding: 6 + 30 + 6.
        #expect(abs(after.minY - 42) < 0.5, "\(after)")
    }

    @Test func aFlexLabelKeepsItsPlace() async throws {
        let flex = ".name { display: flex; align-items: center; } .score { display: inline-flex; align-items: center; justify-content: center; }"
        let plain = BrowserLayoutTestSupport.allTextFragments(try await layout(row)).map(\.rect.rawValue)
        let flexed = BrowserLayoutTestSupport.allTextFragments(try await layout(row, css: flex)).map(\.rect.rawValue)
        #expect(flexed.count == 3)
        #expect(abs(flexed[0].minX - plain[0].minX) < 0.5)
        #expect(abs(flexed[1].midX - plain[1].midX) < 0.5)
        #expect(abs(flexed[2].minY - plain[2].minY) < 0.5)
    }

    /// A panel's title sits in its thick top border: the insets count from the
    /// padding edge, and a box with no width is as wide as its text.
    @Test func aBoxWithNoWidthShrinksToItsTextAndCountsFromThePaddingEdge() async throws {
        let panel = """
        .panel { width: 300px; border: 1px solid #999; border-top: 22px solid #dcdcdc; padding: 18px 19px;
                 position: relative; box-sizing: border-box; }
        .title { position: absolute; left: 8px; top: -16px; font-size: 11px; line-height: 1; }
        .close { position: absolute; right: 8px; top: -16px; font-size: 12px; line-height: 1; }
        """
        let pages = try await layout("<div class=\"panel\"><div class=\"title\">系统载入</div><div class=\"close\">×</div><p>content</p></div>", css: panel)
        let texts = BrowserLayoutTestSupport.allTextFragments(pages).map(\.rect.rawValue)
        #expect(texts.count == 3)
        #expect(abs(texts[0].minX - (1 + 8)) < 0.5, "\(texts[0])")
        #expect(abs(texts[0].midY - (22 - 16 + 5.5)) < 1, "\(texts[0])")
        #expect(abs(texts[1].maxX - (300 - 1 - 8)) < 0.5, "\(texts[1])")
        // The content starts under the border and padding, as if the two were not there.
        #expect(abs(texts[2].minX - 20) < 0.5)
        #expect(texts[2].minY >= 22 + 18 - 0.5)
    }

    @Test func aPercentageWidthIsOfThePaddingBox() async throws {
        let fill = """
        .wrap { position: relative; padding: 0 50px; height: 14px; }
        .fill { position: absolute; top: 0; left: 0; height: 14px; width: 50%; background: #20c997; font-size: 11px;
                line-height: 14px; text-align: center; }
        """
        let pages = try await layout("<div class=\"wrap\"><div class=\"fill\">半</div></div>", css: fill)
        let half = try #require(BrowserLayoutTestSupport.allTextFragments(pages).first).rect.rawValue
        // Half of 350, starting at the padding edge: centred on 87.5.
        #expect(abs(half.midX - 87.5) < 0.5, "\(half)")
    }

    @Test func admissionFollowsWhatIsLaidOut() {
        let item = "<div class=\"item\"><div class=\"name\">a</div><div class=\"bar\"></div></div>"
        #expect(scan(item, css: css).supported)
        // Its containing block is further up than its parent.
        #expect(!scan(item, css: css + ".item { position: static; }").supported)
        // Its place would be where the flow left it.
        #expect(!scan(item, css: css + ".name { top: auto; }").supported)
        #expect(!scan(item, css: css + ".name { left: auto; }").supported)
        #expect(!scan(item, css: css + ".name { top: 10%; }").supported)
        // Among lines of text.
        #expect(!scan("<div class=\"item\">text<div class=\"name\">a</div></div>", css: css).supported)
        #expect(!scan(item, css: css + ".name { position: fixed; }").supported)
        #expect(!scan(item, css: css, writingMode: .verticalRTL).supported)
        // Hidden, it is not laid out at all.
        #expect(scan(item, css: css + ".item { position: static; } .name { display: none; }").supported)
    }

    @Test func scrollModePlacesTheLabelsToo() throws {
        let config = BrowserLayoutConfig(renderWidth: 350, renderHeight: 600, rootFontSize: 17)
        let input = HTMLLayoutDocument(html: "<html><body>\(row)</body></html>", css: [css], configuration: config)
        func rects(_ document: BrowserScrollDocument) -> [CGRect] {
            document.displayList.items.compactMap { item -> CGRect? in
                guard case .text(let text) = item, text.sourceRange.length > 0 else { return nil }
                return text.rect.rawValue
            }
        }
        let eager = rects(try input.prepareContinuous(validateCapabilities: true).makeDocument())
        let demanded = rects(try input.makeViewportSession().layout(in: CGRect(x: 0, y: 0, width: 350, height: 100_000)))
        #expect(eager.count == 3)
        #expect(demanded == eager)
        #expect(abs(try #require(eager.first).minX - 5) < 0.5)
    }
}
