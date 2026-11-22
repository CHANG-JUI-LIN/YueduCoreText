import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// The `<html>` element's own margins, padding and maximum size shape the
/// page: `<body>` is laid out in what they leave. They used to be ignored,
/// and a book that caps its columns with `html { max-height: 28em }` ran its
/// text the page's full height.
///
/// `webKitReference` pages are 366 wide horizontally, and 776 tall in vertical
/// text; type is 17px, a Han character a 17px square.
struct RootElementBoxTests {

    private func rects(_ body: String, css: String, vertical: Bool = false) async throws -> [CGRect] {
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            body, css: "body { margin: 0 } p { margin: 0; line-height: 17px } " + css, vertical: vertical)
        return BrowserLayoutTestSupport.allTextFragments(layout.pages).map(\.rect.rawValue)
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }

    @Test func aMaximumWidthAndAutoMarginsCentreThePage() async throws {
        // 170 of content and 17 of padding either side: 204, centred in 366.
        let found = try await rects("<p>甲</p><p style=\"text-align: right\">乙</p>",
                                    css: "html { max-width: 170px; margin: 34px auto 0; padding: 0 17px; }")
        #expect(found.count == 2)
        #expect(close(found[0].minX, 81 + 17) && close(found[0].minY, 34), "\(found)")
        #expect(close(found[1].maxX, 81 + 17 + 170), "\(found)")
    }

    @Test func inVerticalTextAMaximumHeightCapsAndCentresTheColumns() async throws {
        // Columns 170 long with 17 of padding above and below: 204, centred in 776.
        let found = try await rects("<p>甲</p><p style=\"text-align: right\">乙</p>",
                                    css: "html { max-height: 170px; margin: auto 34px; padding: 17px 0; }", vertical: true)
        #expect(found.count == 2)
        #expect(close(found[0].minY, 286 + 17), "\(found)")
        #expect(close(found[1].maxY, 286 + 17 + 170), "\(found)")
        // The block-start margin: 34 in from the page's right edge.
        #expect(close(found[0].maxX, 3000 - 34), "\(found)")
    }

    @Test func columnsBreakAtTheMaximum() async throws {
        let found = try await rects("<p>\(String(repeating: "字", count: 25))</p>",
                                    css: "html { max-height: 170px; }", vertical: true)
        #expect(found.count == 3, "ten characters to a column: \(found)")
        #expect(found.allSatisfy { $0.maxY <= 170.5 })
    }

    /// The inset holds on every page, and the block-start margin is the
    /// chapter's start only.
    @Test func theInsetHoldsOnLaterPages() async throws {
        let body = (0..<12).map { "<p>行\($0 % 10)</p>" }.joined()
        let css = "body { margin: 0 } p { margin: 0; line-height: 20px; font-size: 20px } html { margin: 30px 0 0 50px; }"
        let pages = try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [css],
                                                              width: 400, height: 100).0
        #expect(pages.count == 3)
        for page in pages {
            let found = BrowserLayoutTestSupport.allTextFragments([page]).map(\.rect.rawValue)
            #expect(found.allSatisfy { close($0.minX, 50) }, "page \(page.index): \(found)")
        }
        let first = BrowserLayoutTestSupport.allTextFragments([pages[0]]).map(\.rect.rawValue)
        let second = BrowserLayoutTestSupport.allTextFragments([pages[1]]).map(\.rect.rawValue)
        #expect(close(first.map(\.minY).min() ?? -1, 30))
        #expect(close(second.map(\.minY).min() ?? -1, 0))
    }

    /// The usual reset gives `<html>` no box: nothing is resolved for it.
    @Test func aResetIsNoBox() {
        var style = ComputedStyle(fontSize: 17, fontFamilies: [], color: .black, backgroundColor: nil, textAlign: .natural)
        style.height = .percent(1)
        #expect(!RootElementBox.hasBox(style))
        style.maxHeight = .em(28)
        #expect(RootElementBox.hasBox(style))
    }
}
