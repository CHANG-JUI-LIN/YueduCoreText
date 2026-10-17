import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// Automatic table layout (CSS 2.1 §17, separated borders): column sizing,
/// shrink-to-fit centering, colspan, cell vertical alignment, border-spacing,
/// header/footer reordering and pagination across rows.
struct BrowserTableLayoutTests {

    private let resetCSS = """
        body { margin: 0; padding: 0; line-height: 1; }
        table { border-spacing: 0; margin: 0; }
        td, th { padding: 0; line-height: 1; }
        """

    private func texts(_ html: String, css: String, width: CGFloat = 400, height: CGFloat = 800) async throws
        -> [TextFragment]
    {
        let (pages, _) = try await BrowserLayoutTestSupport.layout(html, cssTexts: [css], width: width, height: height)
        return BrowserLayoutTestSupport.allTextFragments(pages)
    }

    private func fills(_ pages: [PageFragments]) -> [FillFragment] {
        var result: [FillFragment] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill(let f): result.append(f)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        for page in pages { walk(page.fragments) }
        return result
    }

    @Test func twoColumnsRespectExplicitWidth() async throws {
        let css = resetCSS + "\n.w { width: 100px; }"
        let found = try await texts(
            "<html><body><table><tr><td class=\"w\">A</td><td>B</td></tr></table></body></html>",
            css: css
        )
        #expect(found.count == 2)
        #expect(abs(found[0].rect.rawValue.minX - 0) < 0.5)
        #expect(abs(found[0].rect.rawValue.minY - 0) < 0.5)
        #expect(abs(found[1].rect.rawValue.minX - 100) < 0.5)
        #expect(abs(found[1].rect.rawValue.minY - 0) < 0.5)
    }

    @Test func autoWidthTableShrinkWrapsAndCenters() async throws {
        let css = resetCSS + "\n.c { margin-left: auto; margin-right: auto; }"
        let found = try await texts(
            "<html><body><table class=\"c\"><tr><td>AAA</td><td>BBB</td></tr></table></body></html>",
            css: css
        )
        #expect(found.count == 2)
        let contentWidth = found[0].rect.rawValue.width + found[1].rect.rawValue.width
        #expect(abs(found[0].rect.rawValue.minX - (400 - contentWidth) / 2) < 1)
        #expect(abs(found[1].rect.rawValue.maxX - (400 + contentWidth) / 2) < 1)
    }

    @Test func colspanCellSpansAndCentersAcrossColumns() async throws {
        let css = resetCSS + "\n.w { width: 100px; } .ctr { text-align: center; }"
        let found = try await texts(
            """
            <html><body><table>
            <tr><td colspan="2" class="ctr">H</td></tr>
            <tr><td class="w">A</td><td>B</td></tr>
            </table></body></html>
            """,
            css: css
        )
        #expect(found.count == 3)
        let (h, a, b) = (found[0], found[1], found[2])
        let spanCenter = (100 + b.rect.rawValue.width) / 2
        #expect(abs((h.rect.rawValue.minX + h.rect.rawValue.width / 2) - spanCenter) < 1)
        // The spanned row is single-line tall, so the second row starts at 17.
        #expect(abs(a.rect.rawValue.minY - 17) < 0.5)
        #expect(abs(b.rect.rawValue.minX - 100) < 0.5)
    }

    @Test func cellVerticalAlignmentWithinRow() async throws {
        let css = resetCSS + "\n.top { vertical-align: top; } .bot { vertical-align: bottom; }"
        let found = try await texts(
            """
            <html><body><table><tr>
            <td>L1<br>L2</td><td>M</td><td class="top">T</td><td class="bot">B</td>
            </tr></table></body></html>
            """,
            css: css
        )
        let visible = found.filter { $0.rect.rawValue.width > 0 }
        #expect(visible.count == 5)
        // Row height is 2 lines = 34: top at 0, middle at 8.5, bottom at 17.
        #expect(abs(visible[0].rect.rawValue.minY - 0) < 0.5)
        #expect(abs(visible[1].rect.rawValue.minY - 17) < 0.5)
        #expect(abs(visible[2].rect.rawValue.minY - 8.5) < 0.75)
        #expect(abs(visible[3].rect.rawValue.minY - 0) < 0.5)
        #expect(abs(visible[4].rect.rawValue.minY - 17) < 0.5)
    }

    @Test func borderSpacingSeparatesCellsAndRows() async throws {
        let css = """
            body { margin: 0; padding: 0; line-height: 1; }
            table { border-spacing: 10px 4px; margin: 0; }
            td { padding: 0; line-height: 1; }
            .w { width: 100px; }
            """
        let found = try await texts(
            """
            <html><body><table>
            <tr><td class="w">A</td><td>B</td></tr>
            <tr><td class="w">C</td><td>D</td></tr>
            </table></body></html>
            """,
            css: css
        )
        #expect(found.count == 4)
        #expect(abs(found[0].rect.rawValue.minX - 10) < 0.5)
        #expect(abs(found[1].rect.rawValue.minX - 120) < 0.5)
        #expect(abs(found[0].rect.rawValue.minY - 4) < 0.5)
        #expect(abs(found[2].rect.rawValue.minY - (4 + 17 + 4)) < 0.5)
    }

    @Test func footerGroupRendersAfterBody() async throws {
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            """
            <html><body><table>
            <tfoot><tr><td>FOOT</td></tr></tfoot>
            <tbody><tr><td>BODY</td></tr></tbody>
            <thead><tr><td>HEAD</td></tr></thead>
            </table></body></html>
            """,
            cssTexts: [resetCSS], width: 400, height: 800
        )
        let found = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(found.count == 3)
        #expect(abs(found[0].rect.rawValue.minY - 0) < 0.5)
        #expect(abs(found[1].rect.rawValue.minY - 17) < 0.5)
        #expect(abs(found[2].rect.rawValue.minY - 34) < 0.5)
        let ns = doc.lastSourceText as NSString
        let joined = found.map { $0.sourceRange.length > 0 ? ns.substring(with: $0.sourceRange) : "" }.joined()
        #expect(joined == "HEADBODYFOOT")
    }

    @Test func rowBackgroundSpansFullTableWidth() async throws {
        let css = resetCSS + "\n.w { width: 100px; } tr.bg { background-color: #ff0000; }"
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            "<html><body><table><tr class=\"bg\"><td class=\"w\">A</td><td>B</td></tr></table></body></html>",
            cssTexts: [css], width: 400, height: 800
        )
        let foundTexts = BrowserLayoutTestSupport.allTextFragments(pages)
        let tableWidth = try #require(foundTexts.last).rect.rawValue.maxX
        let rowFill = try #require(fills(pages).first { $0.rect.rawValue.width > 50 })
        #expect(abs(rowFill.rect.rawValue.width - tableWidth) < 1)
        #expect(abs(rowFill.rect.rawValue.minX - 0) < 0.5)
    }

    @Test func paginationSplitsBetweenRows() async throws {
        var rows = ""
        for index in 1...10 { rows += "<tr><td class=\"w\">R\(index)</td><td>X</td></tr>" }
        let css = resetCSS + "\n.w { width: 100px; }"
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            "<html><body><table>\(rows)</table></body></html>",
            cssTexts: [css], width: 400, height: 60
        )
        #expect(pages.count == 4)
        let lastPageText = BrowserLayoutTestSupport.visibleText(
            [try #require(pages.last)], sourceText: doc.lastSourceText)
        #expect(lastPageText.contains("R10"))
    }

    @Test func linksInsideCellsStayTappable() async throws {
        let found = try await texts(
            "<html><body><table><tr><td><a href=\"chapter1.xhtml\">GO</a></td></tr></table></body></html>",
            css: resetCSS
        )
        #expect(found.count == 1)
        #expect(found[0].linkTarget == "chapter1.xhtml")
    }

    @Test func cellTextIndentApplies() async throws {
        let css = resetCSS + "\n.i { text-indent: 20px; }"
        let found = try await texts(
            "<html><body><table><tr><td class=\"i\">A</td><td>B</td></tr></table></body></html>",
            css: css
        )
        #expect(found.count == 2)
        #expect(abs(found[0].rect.rawValue.minX - 20) < 0.5)
    }
}
