import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// The collapsing border model (CSS 2.1 §17.6.2) and three table shapes that
/// used to send a chapter to the host's fallback: `border-collapse: collapse`
/// (36 chapters of the test corpus), a lone `display: table-cell`, an
/// `inline-table` around plain content, and `<colgroup>`.
struct BrowserTableCollapseTests {

    private let reset = """
        body { margin: 0; padding: 0; line-height: 1; }
        table { border-collapse: collapse; margin: 0; }
        td, th { padding: 0; line-height: 1; }
        """

    private func layout(_ body: String, css: String, width: CGFloat = 400) async throws -> [PageFragments] {
        try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [css],
                                                  width: width, height: 800).0
    }

    private func fills(_ pages: [PageFragments]) -> [FillFragment] {
        var result: [FillFragment] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill(let fill): result.append(fill)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        for page in pages { walk(page.fragments) }
        return result
    }

    private func scan(_ body: String, css: String) -> BrowserLayoutCapabilityResult {
        BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body>\(body)</body></html>", cssTexts: [css])
    }

    // MARK: - Geometry

    /// Cells meet at the grid lines with nothing between them; each holds half
    /// of the border on each of its sides, and the table half of its outer one.
    @Test func cellsShareTheirBordersAndTheTableHoldsHalfOfTheOuterOne() async throws {
        let css = reset + " td { border: 2px solid black; width: 100px; height: 20px; }"
        let pages = try await layout("<table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table>", css: css)
        let cells = fills(pages).filter { $0.borderTop.isCentredOnEdge || $0.borderLeft.isCentredOnEdge }
        #expect(cells.count == 4)
        let rects = cells.map(\.rect.rawValue).sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
        // The table's own border is half of the outer 2px; the first cell starts after it.
        #expect(abs(rects[0].minX - 1) < 0.01 && abs(rects[0].minY - 1) < 0.01)
        // 100px of content plus half a border on each side.
        #expect(abs(rects[0].width - 102) < 0.01)
        #expect(abs(rects[1].minX - rects[0].maxX) < 0.01, "no spacing between collapsed cells")
        #expect(abs(rects[2].minY - rects[0].maxY) < 0.01)
        #expect(abs(rects[0].height - 22) < 0.01)
    }

    @Test func separatedTablesAreUntouched() async throws {
        let css = "body { margin: 0; line-height: 1; } table { border-spacing: 4px; margin: 0; } td { padding: 0; border: 2px solid black; width: 100px; }"
        let pages = try await layout("<table><tr><td>A</td><td>B</td></tr></table>", css: css)
        let cells = fills(pages).filter { $0.borderTop.isVisible }
        #expect(cells.count == 2)
        #expect(cells.allSatisfy { !$0.borderTop.isCentredOnEdge && $0.borderTop.width == 2 })
        let rects = cells.map(\.rect.rawValue).sorted { $0.minX < $1.minX }
        #expect(abs(rects[1].minX - rects[0].maxX - 4) < 0.01)
    }

    /// A timeline table: a narrow date column sized `width: 25%` beside a long
    /// text column, in a table as wide as the page. The date column was shrunk
    /// with the text column, to one character per line.
    @Test func aColumnWithAWidthKeepsItWhenTheTableIsTooNarrowForItsContent() async throws {
        let css = reset + " table { width: 100%; } .date { width: 25%; }"
        let long = String(repeating: "一段很長的說明文字，", count: 12)
        let pages = try await layout("<table><tr><td class=\"date\">洪武十年</td><td>\(long)</td></tr></table>", css: css)
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        let date = try #require(texts.first)
        // The whole date on one line, in a column a quarter of the 400pt page.
        #expect(texts.filter { abs($0.rect.rawValue.minX - date.rect.rawValue.minX) < 0.5 && $0.rect.rawValue.minX < 100 }.count == 1)
        let rest = texts.dropFirst().map(\.rect.rawValue.minX).min() ?? 0
        #expect(abs(rest - 100) < 1, "the text column starts where the 25% column ends: \(rest)")
    }

    // MARK: - Which border wins

    @Test func everyGridEdgeIsPaintedOnceByOneCell() async throws {
        let css = reset + " td { border: 1px solid black; width: 50px; }"
        let pages = try await layout("<table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table>", css: css)
        let cells = fills(pages).filter { $0.borderTop.isCentredOnEdge }
            .sorted { ($0.rect.rawValue.minY, $0.rect.rawValue.minX) < ($1.rect.rawValue.minY, $1.rect.rawValue.minX) }
        #expect(cells.count == 4)
        // Top and left always; right at the end of a row; bottom in the last row.
        #expect(cells.map { $0.borderRight.isVisible } == [false, true, false, true])
        #expect(cells.map { $0.borderBottom.isVisible } == [false, false, true, true])
        #expect(cells.allSatisfy { $0.borderTop.width == 1 && $0.borderLeft.width == 1 })
        // The table paints no border of its own.
        #expect(fills(pages).filter { $0.borderTop.isVisible && !$0.borderTop.isCentredOnEdge }.isEmpty)
    }

    @Test func theWiderBorderWinsAndItsColourWithIt() async throws {
        let css = reset + " td { border: 1px solid black; width: 50px; } .thick { border-right: 3px solid red; }"
        let pages = try await layout("<table><tr><td class=\"thick\">A</td><td>B</td></tr></table>", css: css)
        let cells = fills(pages).filter { $0.borderTop.isCentredOnEdge }.sorted { $0.rect.rawValue.minX < $1.rect.rawValue.minX }
        #expect(cells.count == 2)
        // The edge between them is the left cell's 3px red, painted by the right cell as its left.
        #expect(cells[1].borderLeft.width == 3)
        #expect(cells[1].borderLeft.color == UIColor.red)
        // Half of it widens each cell.
        #expect(abs(cells[0].rect.rawValue.width - (50 + 0.5 + 1.5)) < 0.01)
        #expect(abs(cells[1].rect.rawValue.width - (50 + 1.5 + 0.5)) < 0.01)
    }

    @Test func rowAndTableBordersReachTheEdgesTheyTouch() async throws {
        let css = reset + " table { border: 4px solid blue; } tr { border-bottom: 2px solid red; } td { width: 50px; }"
        let pages = try await layout("<table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table>", css: css)
        let cells = fills(pages).filter { $0.borderTop.isCentredOnEdge || $0.borderLeft.isCentredOnEdge || $0.borderBottom.isCentredOnEdge }
            .sorted { ($0.rect.rawValue.minY, $0.rect.rawValue.minX) < ($1.rect.rawValue.minY, $1.rect.rawValue.minX) }
        #expect(cells.count == 4)
        // The table's border is the outside of the grid.
        #expect(cells[0].borderTop.width == 4 && cells[0].borderTop.color == UIColor.blue)
        #expect(cells[0].borderLeft.width == 4)
        #expect(cells[1].borderRight.width == 4)
        // The first row's bottom border is the edge between the rows; no cell has a border between columns.
        #expect(cells[2].borderTop.width == 2 && cells[2].borderTop.color == UIColor.red)
        #expect(!cells[1].borderLeft.isVisible)
        // The last row's bottom: the table's 4px beats the row's 2px.
        #expect(cells[3].borderBottom.width == 4 && cells[3].borderBottom.color == UIColor.blue)
    }

    // MARK: - Paint

    @Test func aCollapsedBorderIsDrawnCentredOnItsGridLine() async throws {
        let css = reset + " td { border: 4px solid black; width: 60px; height: 30px; }"
        let pages = try await layout("<table><tr><td></td><td></td></tr></table>", css: css)
        let list = DisplayListBuilder.build(for: try #require(pages.first))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 60), format: format).image { context in
            DisplayListDrawer.draw(list, in: context.cgContext)
        }
        let bitmap = try #require(image.cgImage)
        let data = try #require(bitmap.dataProvider?.data as Data?)
        func inked(x: Int, y: Int) -> Bool { data[y * bitmap.bytesPerRow + x * 4 + 3] > 128 }
        // Table border 2 (half of 4); cells are 64 wide: grid lines at x = 2, 66, 130.
        // The middle line's border covers 64..<68, and nothing beside it.
        #expect(inked(x: 64, y: 20) && inked(x: 67, y: 20))
        #expect(!inked(x: 62, y: 20) && !inked(x: 70, y: 20))
        // The outer left border covers 0..<4.
        #expect(inked(x: 0, y: 20) && inked(x: 3, y: 20) && !inked(x: 6, y: 20))
    }

    // MARK: - Admission

    @Test func aCollapsedTableIsAdmitted() {
        let result = scan("<table><thead><tr><th>H</th></tr></thead><tbody><tr><td>A</td></tr></tbody></table>",
                          css: "table { border-collapse: collapse; } td, th { border: 1px solid #111; }")
        #expect(result.supported, "\(result.unsupportedFeatures)")
    }

    @Test func columnElementsAreNoReasonToFallBack() {
        let result = scan("<table><colgroup><col></col><col></col></colgroup><tbody><tr><td>A</td><td>B</td></tr></tbody></table>", css: "")
        #expect(result.supported, "\(result.unsupportedFeatures)")
    }

    @Test func whatTablesStillFallBack() {
        #expect(scan("<table><tr><td rowspan=\"2\">A</td><td>B</td></tr><tr><td>C</td></tr></table>", css: "").unsupportedFeatures == [.table])
        #expect(scan("<table><tr><td><table><tr><td>A</td></tr></table></td></tr></table>", css: "").unsupportedFeatures == [.table])
        #expect(scan("<table><caption>T</caption><tr><td>A</td></tr></table>", css: "").unsupportedFeatures == [.table])
    }

    // MARK: - A cell without a table

    /// `div.tupian { display: table-cell }` around a picture: the anonymous
    /// table is as wide as the picture, and a cell takes no margin.
    @Test func aLoneCellIsABoxAsWideAsItsContent() async throws {
        let css = "body { margin: 0; line-height: 1; } p { margin: 0; } .cell { display: table-cell; margin: 30px; background: #eee; }"
        let result = scan("<p>before</p><div class=\"cell\">AB</div><p>after</p>", css: css)
        #expect(result.supported, "\(result.unsupportedFeatures)")
        let pages = try await layout("<p>before</p><div class=\"cell\">AB</div><p>after</p>", css: css)
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(texts.count == 3)
        let box = try #require(fills(pages).first { $0.color != .clear })
        // No margin: the box starts at the left edge, right under the paragraph before it.
        #expect(abs(box.rect.rawValue.minX) < 0.01)
        #expect(abs(box.rect.rawValue.minY - texts[0].rect.rawValue.maxY) < 0.5)
        // Shrink-to-fit: as wide as its two letters, not the page.
        #expect(abs(box.rect.rawValue.width - texts[1].rect.rawValue.width) < 0.5)
        #expect(texts[2].rect.rawValue.minY >= box.rect.rawValue.maxY - 0.5)
    }

    @Test func cellsSideBySideShareOneRow() async throws {
        let css = "body { margin: 0; line-height: 1; } .cell { display: table-cell; width: 80px; }"
        let pages = try await layout("<div><span class=\"cell\">A</span> <span class=\"cell\">B</span></div>", css: css)
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(texts.count == 2)
        #expect(abs(texts[0].rect.rawValue.minY - texts[1].rect.rawValue.minY) < 0.01)
        #expect(abs(texts[1].rect.rawValue.minX - 80) < 0.5)
    }

    // MARK: - inline-table

    /// A chat bubble: `display: inline-table` around text is one anonymous
    /// cell, a shrink-to-fit box on the line.
    @Test func anInlineTableAroundTextIsABoxOnTheLine() async throws {
        let css = "body { margin: 0; line-height: 1; } p { margin: 0; } .bubble { display: inline-table; padding: 8px 12px; background: #ddd; }"
        let body = "<p>x<span class=\"bubble\">hello</span></p>"
        let result = scan(body, css: css)
        #expect(result.supported, "\(result.unsupportedFeatures)")
        let pages = try await layout(body, css: css)
        let bubble = try #require(fills(pages).first { $0.color != .clear })
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        let hello = try #require(texts.last)
        #expect(abs(bubble.rect.rawValue.width - (hello.rect.rawValue.width + 24)) < 0.5)
        #expect(bubble.rect.rawValue.minX > 0, "after the x on the same line")
    }

    @Test func anInlineTableWithRowsStillFallsBack() {
        let css = ".t { display: inline-table; } .r { display: table-row; } .c { display: table-cell; }"
        #expect(scan("<div class=\"t\"><div class=\"r\"><div class=\"c\">A</div></div></div>", css: css).unsupportedFeatures == [.table])
    }
}
