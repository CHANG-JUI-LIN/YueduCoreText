import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText
import YueduCoreTextTypography

/// A flex container with several items: each child element, and each run of
/// text between them, is an item sized and placed by `FlexLayout`. Such a
/// container used to send its chapter to the host's fallback.
///
/// Type is PingFang SC at 20px with `line-height: 1`: a Han character is a
/// 20px square, so widths and positions can be read off the markup.
struct FlexItemsTests {

    private let reset = "body { margin: 0; padding: 0; line-height: 1; } p, div, span, h3 { margin: 0; font-size: 20px; font-weight: normal; }"

    private func layout(_ body: String, css: String, width: CGFloat = 400, height: CGFloat = 800) async throws -> [PageFragments] {
        try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [reset + css],
                                                  width: width, height: height).0
    }

    private func rects(_ body: String, css: String, width: CGFloat = 400) async throws -> [CGRect] {
        BrowserLayoutTestSupport.allTextFragments(try await layout(body, css: css, width: width)).map(\.rect.rawValue)
    }

    private func fills(_ pages: [PageFragments]) -> [CGRect] {
        var result: [CGRect] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill(let fill): result.append(fill.rect.rawValue)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        for page in pages { walk(page.fragments) }
        return result
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }

    @Test func itemsSitSideBySideInSourceOrder() async throws {
        let found = try await rects("<div class=\"f\"><span>甲乙</span>丙<p>丁戊己</p></div>", css: ".f { display: flex; }")
        #expect(found.count == 3)
        #expect(found.map(\.minX).elementsEqual([0, 40, 60], by: close), "\(found)")
        #expect(found.allSatisfy { close($0.minY, 0) })
    }

    @Test func whiteSpaceBetweenItemsTakesNoRoom() async throws {
        let found = try await rects("<div class=\"f\">\n  <span>甲</span>\n  <span>乙</span>\n</div>", css: ".f { display: flex; }")
        #expect(found.map(\.minX).elementsEqual([0, 20], by: close), "\(found)")
    }

    @Test(arguments: [("flex-start", [0.0, 40.0, 80.0]), ("center", [140.0, 180.0, 220.0]), ("flex-end", [280.0, 320.0, 360.0]),
                      ("space-between", [0.0, 180.0, 360.0]), ("space-around", [46.667, 180.0, 313.333]),
                      ("space-evenly", [70.0, 180.0, 290.0])])
    func justifyContentSharesOutTheFreeSpace(_ value: String, _ expected: [Double]) async throws {
        let found = try await rects("<div class=\"f\"><span>甲乙</span><span>丙丁</span><span>戊己</span></div>",
                                    css: ".f { display: flex; justify-content: \(value); }")
        #expect(found.map(\.minX).elementsEqual(expected.map { CGFloat($0) }, by: close), "\(value): \(found)")
    }

    @Test func gapsSeparateItems() async throws {
        let found = try await rects("<div class=\"f\"><span>甲</span><span>乙</span><span>丙</span></div>",
                                    css: ".f { display: flex; gap: 10px; }")
        #expect(found.map(\.minX).elementsEqual([0, 30, 60], by: close), "\(found)")
    }

    @Test func growingItemsShareTheLine() async throws {
        // `flex: 1` is a basis of 0: the line is split evenly whatever the items hold.
        let even = try await rects("<div class=\"f\"><div class=\"i\">甲</div><div class=\"i\">乙丙丁</div></div>",
                                   css: ".f { display: flex; } .i { flex: 1; }")
        #expect(even.map(\.minX).elementsEqual([0, 200], by: close), "\(even)")
        // `flex-grow` on one item gives it what the others leave.
        let pages = try await layout("<div class=\"f\"><div>甲</div><div class=\"g\">乙</div><div>丙</div></div>",
                                     css: ".f { display: flex; } .g { flex-grow: 1; background: #ccc; }")
        let plate = try #require(fills(pages).first)
        #expect(close(plate.minX, 20) && close(plate.width, 360), "\(plate)")
        #expect(close(BrowserLayoutTestSupport.allTextFragments(pages)[2].rect.rawValue.minX, 380))
    }

    @Test func widthsAndBasesSizeItems() async throws {
        let css = ".f { display: flex; } .a { width: 100px; } .b { flex-basis: 25%; } .c { width: 40%; box-sizing: border-box; padding: 0 10px; }"
        let found = try await rects("<div class=\"f\"><div class=\"a\">甲</div><div class=\"b\">乙</div><div class=\"c\">丙</div><div>丁</div></div>", css: css)
        #expect(found.map(\.minX).elementsEqual([0, 100, 210, 360], by: close), "\(found)")
    }

    @Test func itemsShrinkToFitDownToTheirLongestWord() async throws {
        // 30 characters and a label of 4 on a line of 400: the text gives up
        // what is missing in proportion to its size, the label too, until it
        // would be narrower than `label`, which no line break divides.
        let long = String(repeating: "字", count: 30)
        let pages = try await layout("<div class=\"f\"><div class=\"a\">\(long)</div><div class=\"b\">label</div></div>",
                                     css: ".f { display: flex; } .a { background: #eee; } .b { background: #ccc; }")
        let plates = fills(pages)
        let label = try #require(BrowserLayoutTestSupport.allTextFragments(pages).last)
        #expect(plates.count == 2)
        #expect(close(plates[0].width + plates[1].width, 400), "\(plates)")
        #expect(close(plates[1].width, label.rect.rawValue.width), "the label is exactly its word: \(plates[1]) \(label.rect.rawValue)")
        #expect(BrowserLayoutTestSupport.allTextFragments(pages).count > 2, "the long text wraps")
        // Told not to shrink, it keeps its width and the other item pays.
        let fixed = try await layout("<div class=\"f\"><div class=\"a\">\(long)</div><div class=\"b\">標籤標籤</div></div>",
                                     css: ".f { display: flex; } .a { background: #eee; } .b { flex-shrink: 0; background: #ccc; }")
        #expect(fills(fixed).map(\.width).elementsEqual([320, 80], by: close), "\(fills(fixed))")
    }

    @Test func aWrappingContainerStartsANewLine() async throws {
        let css = ".f { display: flex; flex-wrap: wrap; gap: 6px 10px; } .i { width: 150px; }"
        let found = try await rects("<div class=\"f\"><div class=\"i\">甲</div><div class=\"i\">乙</div><div class=\"i\">丙</div></div><p>後</p>", css: css)
        #expect(found.map(\.minX).elementsEqual([0, 160, 0, 0], by: close), "\(found)")
        #expect(found.map(\.minY).elementsEqual([0, 0, 26, 46], by: close), "\(found)")
    }

    @Test func itemsAreAlignedAcrossTheirLine() async throws {
        let tall = "<div class=\"t\">高<br/>高<br/>高</div>"
        func shortTop(_ align: String, _ extra: String = "") async throws -> CGFloat {
            let found = try await rects("<div class=\"f\">\(tall)<div class=\"s\">矮</div></div>",
                                        css: ".f { display: flex; align-items: \(align); } \(extra)")
            return try #require(found.last).minY
        }
        #expect(close(try await shortTop("flex-start"), 0))
        #expect(close(try await shortTop("center"), 20))
        #expect(close(try await shortTop("flex-end"), 40))
        #expect(close(try await shortTop("flex-start", ".s { align-self: flex-end; }"), 40))
        #expect(close(try await shortTop("flex-start", ".s { margin-top: auto; }"), 40))
        // Stretched, the default, the short item's box is the line's height.
        let pages = try await layout("<div class=\"f\">\(tall)<div class=\"s\">矮</div></div>",
                                     css: ".f { display: flex; } .s { background: #ccc; }")
        #expect(close(try #require(fills(pages).first).height, 60))
    }

    @Test func anAutoMarginPushesTheRestToTheEnd() async throws {
        let found = try await rects("<div class=\"f\"><span>甲</span><span class=\"r\">乙</span><span>丙</span></div>",
                                    css: ".f { display: flex; } .r { margin-left: auto; }")
        #expect(found.map(\.minX).elementsEqual([0, 360, 380], by: close), "\(found)")
    }

    @Test func aColumnStacksItemsWithoutCollapsingMargins() async throws {
        let css = ".f { display: flex; flex-direction: column; } .f p { margin: 10px 0; }"
        let found = try await rects("<div class=\"f\"><p>甲</p><p>乙</p></div><p>後</p>", css: css)
        // 10 + 20 + 10, then 10 + 20 + 10: the margins between the items add up.
        #expect(found.map(\.minY).elementsEqual([10, 50, 80], by: close), "\(found)")
    }

    @Test func aColumnAlignsEachItemAcrossIt() async throws {
        let css = ".f { display: flex; flex-direction: column; align-items: center; } .e { align-self: flex-end; } .b { background: #ccc; }"
        let pages = try await layout("<div class=\"f\"><div class=\"b\">甲乙</div><div class=\"e\">丙</div></div>", css: css)
        let found = BrowserLayoutTestSupport.allTextFragments(pages).map(\.rect.rawValue)
        #expect(found.map(\.minX).elementsEqual([180, 380], by: close), "\(found)")
        // Not stretched, an item is as wide as its content.
        #expect(close(try #require(fills(pages).first).width, 40))
    }

    @Test func aColumnWithAHeightPlacesItsItemsAlongIt() async throws {
        func tops(_ justify: String, _ extra: String = "") async throws -> [CGFloat] {
            let css = ".f { display: flex; flex-direction: column; height: 200px; justify-content: \(justify); } \(extra)"
            return try await rects("<div class=\"f\"><div>甲</div><div class=\"b\">乙</div></div><p>後</p>", css: css).map(\.minY)
        }
        #expect(try await tops("flex-start").elementsEqual([0, 20, 200], by: close))
        #expect(try await tops("center").elementsEqual([80, 100, 200], by: close))
        #expect(try await tops("flex-end").elementsEqual([160, 180, 200], by: close))
        #expect(try await tops("space-between").elementsEqual([0, 180, 200], by: close))
        #expect(try await tops("flex-start", ".b { margin-top: auto; }").elementsEqual([0, 180, 200], by: close))
    }

    @Test func aRowWithAHeightCentresItsItems() async throws {
        let found = try await rects("<div class=\"f\"><span>甲</span><span>乙</span></div>",
                                    css: ".f { display: flex; height: 100px; align-items: center; justify-content: center; }")
        #expect(found.map(\.minY).elementsEqual([40, 40], by: close), "\(found)")
        #expect(found.map(\.minX).elementsEqual([180, 200], by: close), "\(found)")
    }

    @Test func aNestedContainerIsAnItem() async throws {
        let css = ".f { display: flex; } .c { display: flex; flex-direction: column; flex: 1; align-items: flex-end; }"
        let found = try await rects("<div class=\"f\"><div>甲</div><div class=\"c\"><div>乙</div><div>丙丁</div></div></div>", css: css)
        #expect(found.map(\.minX).elementsEqual([0, 380, 360], by: close), "\(found)")
        #expect(found.map(\.minY).elementsEqual([0, 0, 20], by: close), "\(found)")
    }

    @Test func anInlineContainerIsAsWideAsItsItems() async throws {
        let found = try await rects("<p>前<span class=\"f\"><span>甲</span><span>乙</span></span>後</p>",
                                    css: ".f { display: inline-flex; gap: 10px; }")
        #expect(found.count == 4)
        #expect(found.map(\.minX).elementsEqual([0, 20, 50, 70], by: close), "\(found)")
    }

    /// The items of a line sit side by side: a line that does not fit what is
    /// left of the page moves to the next one whole.
    @Test func aLineOfSeveralItemsMovesToTheNextPageWhole() async throws {
        let tall = "<div>高<br/>高<br/>高</div>"
        let pages = try await layout("<p style=\"height: 60px\">前</p><div class=\"f\">\(tall)<div>矮</div></div>",
                                     css: ".f { display: flex; }", height: 100)
        #expect(pages.count == 2)
        // (A `<br>` is a fragment of no width.)
        let second = BrowserLayoutTestSupport.allTextFragments([pages[1]]).map(\.rect.rawValue).filter { $0.width > 0 }
        #expect(second.count == 4, "\(second)")
        #expect(BrowserLayoutTestSupport.allTextFragments([pages[0]]).count == 1)
        #expect(close(second.map(\.minY).min() ?? -1, 0))
    }

    /// A column, like a block, breaks between its items.
    @Test func aColumnBreaksBetweenItsItems() async throws {
        let pages = try await layout("<div class=\"f\"><div>甲<br/>甲<br/>甲</div><div>乙<br/>乙<br/>乙</div></div>",
                                     css: ".f { display: flex; flex-direction: column; }", height: 100)
        #expect(pages.count == 2)
        func inked(_ page: PageFragments) -> Int {
            BrowserLayoutTestSupport.allTextFragments([page]).filter { $0.rect.rawValue.width > 0 }.count
        }
        #expect(inked(pages[0]) == 5)
        #expect(inked(pages[1]) == 1)
    }

    /// Two items side by side, each longer than a page: every line is on a
    /// page, inside it, and the pages hold both items' text.
    @Test func aLineTallerThanAPageKeepsAllItsText() async throws {
        let left = (0..<12).map { "左\($0 % 10)" }.joined(separator: "<br/>")
        let right = (0..<12).map { "右\($0 % 10)" }.joined(separator: "<br/>")
        let pages = try await layout("<div class=\"f\"><div>\(left)</div><div>\(right)</div></div><p>後</p>",
                                     css: ".f { display: flex; }", height: 100)
        let inked = pages.map { page in
            BrowserLayoutTestSupport.allTextFragments([page]).map(\.rect.rawValue).filter { $0.width > 0 }
        }
        #expect(inked.reduce(0) { $0 + $1.count } == 25)
        for (index, rects) in inked.enumerated() {
            #expect(rects.allSatisfy { $0.minY >= -0.5 && $0.maxY <= 100.5 }, "page \(index): \(rects)")
        }
        // Both columns run down the same pages.
        #expect(inked.prefix(2).allSatisfy { rects in rects.contains { $0.minX < 1 } && rects.contains { $0.minX > 30 } },
                "\(inked)")
    }

    /// The cells of a table row sit side by side as flex items do.
    @Test func aTableRowTallerThanAPageKeepsAllItsText() async throws {
        let left = (0..<12).map { "左\($0 % 10)" }.joined(separator: "<br/>")
        let right = (0..<12).map { "右\($0 % 10)" }.joined(separator: "<br/>")
        let pages = try await layout("<table><tr><td>\(left)</td><td>\(right)</td></tr></table><p>後</p>",
                                     css: "table { border-spacing: 0; } td { padding: 0; vertical-align: top; font-size: 20px; }", height: 100)
        let inked = pages.map { page in
            BrowserLayoutTestSupport.allTextFragments([page]).map(\.rect.rawValue).filter { $0.width > 0 }
        }
        #expect(inked.reduce(0) { $0 + $1.count } == 25)
        for (index, rects) in inked.enumerated() {
            #expect(rects.allSatisfy { $0.minY >= -0.5 && $0.maxY <= 100.5 }, "page \(index): \(rects)")
        }
    }

    /// A row that fits a page and meets its end goes to the next one whole.
    @Test func aTableRowMovesToTheNextPageWhole() async throws {
        let pages = try await layout("<p style=\"height: 60px\">前</p><table><tr><td>甲<br/>甲<br/>甲</td><td>乙</td></tr></table>",
                                     css: "table { border-spacing: 0; } td { padding: 0; vertical-align: top; font-size: 20px; }", height: 100)
        #expect(pages.count == 2)
        let second = BrowserLayoutTestSupport.allTextFragments([pages[1]]).map(\.rect.rawValue).filter { $0.width > 0 }
        #expect(second.count == 4 && second.allSatisfy { $0.minY >= -0.5 }, "\(second)")
    }

    private static func picture(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pictureLayout(_ body: String, css: String, height: CGFloat = 800) async throws -> [PageFragments] {
        try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [reset + css],
                                                  width: 400, height: height,
                                                  imageLoader: { _ in Self.picture(100, 50) }).0
    }

    @Test func aPictureIsAnItemBesideText() async throws {
        let pages = try await pictureLayout("<div class=\"f\"><img src=\"a.png\"/><div class=\"t\">說明</div></div>",
                                            css: ".f { display: flex; align-items: center; gap: 10px; }")
        let image = try #require(BrowserLayoutTestSupport.allImageFragments(pages).first).rect.rawValue
        let text = try #require(BrowserLayoutTestSupport.allTextFragments(pages).first).rect.rawValue
        #expect(close(image.minX, 0) && close(image.width, 100) && close(image.height, 50), "\(image)")
        #expect(close(text.minX, 110) && close(text.midY, image.midY), "\(text)")
    }

    @Test func aPictureIsCentredInAColumnWithAHeight() async throws {
        let css = ".f { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 300px; }"
        let pages = try await pictureLayout("<div class=\"f\"><img src=\"a.png\"/><p>圖說</p></div>", css: css)
        let image = try #require(BrowserLayoutTestSupport.allImageFragments(pages).first).rect.rawValue
        let text = try #require(BrowserLayoutTestSupport.allTextFragments(pages).first).rect.rawValue
        #expect(close(image.midX, 200) && close(image.minY, 115) && close(image.width, 100), "\(image)")
        #expect(close(text.midX, 200) && close(text.minY, 165), "\(text)")
    }

    /// Stretched, the default, a picture fills a column's width and keeps its
    /// proportions, and across a row takes the line's height at its own width
    /// (measured, WebKit iOS 27.2: 120×80 becomes 366×244 and 120×127.5).
    @Test func aStretchedPictureFillsTheCrossAxis() async throws {
        let column = try await pictureLayout("<div class=\"f\"><img src=\"a.png\"/><p>圖說</p></div>",
                                             css: ".f { display: flex; flex-direction: column; }")
        let wide = try #require(BrowserLayoutTestSupport.allImageFragments(column).first).rect.rawValue
        #expect(close(wide.width, 400) && close(wide.height, 200), "\(wide)")
        let row = try await pictureLayout("<div class=\"f\"><img src=\"a.png\"/><div>一<br/>二<br/>三<br/>四</div></div>",
                                          css: ".f { display: flex; }")
        let tall = try #require(BrowserLayoutTestSupport.allImageFragments(row).first).rect.rawValue
        #expect(close(tall.width, 100) && close(tall.height, 80), "\(tall)")
    }

    /// Max-content widths are measured in the fonts the text is shaped in: with
    /// the app's CJK typography, Han text is set in its language's font, and an
    /// item measured in another came out a hair too narrow for its own text.
    @Test func anItemIsAsWideAsItsTextIsShaped() async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<div style=\"display:flex;justify-content:space-between\"><span>左邊</span><span>中間</span><span>右邊</span></div>",
            rootFamilies: [], cjk: .traditional)
        let found = BrowserLayoutTestSupport.allTextFragments(layout.pages)
        #expect(found.count == 3, "each item is one line: \(found.map(\.rect.rawValue))")
    }
}
