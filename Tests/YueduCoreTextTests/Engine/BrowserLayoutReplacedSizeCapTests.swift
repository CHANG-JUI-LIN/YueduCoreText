import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// CSS max-height/max-width on replaced elements, including viewport-relative
/// (vh/vw) lengths, are applied when the used size is resolved — before line
/// breaking and text alignment consume the size.
struct BrowserLayoutReplacedSizeCapTests {

    private let chapterCSS = """
        body{padding: 0%;margin-top: 0%;margin-bottom: 0%;margin-left: 1%;margin-right: 1%;line-height:1.2;text-align: justify;}
        div {margin:0px;padding:0px;line-height:1.2;text-align: justify;}
        .center{text-align:center !important;text-indent:0em;}
        """

    private let chapterHTML = """
        <html><body>
          <div>
            <div class="center duokan-image-single"><img alt="chapter1" src="chapter1.jpg"/></div>
          </div>
        </body></html>
        """

    @Test func authoredMaxHeightCapsOversizedInlineImageBeforeAlignment() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 246, height: 1400), color: .gray)
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            chapterHTML, cssTexts: [chapterCSS + "\nimg { max-height: 95vh !important; }"],
            width: 375, height: 800,
            imageLoader: { _ in image }
        )
        let images = BrowserLayoutTestSupport.allImageFragments(pages)
        #expect(images.count == 1)
        let rect = try #require(images.first).rect.rawValue
        // 95vh = 760pt of the 800pt page; the cap decides the used size,
        // aspect preserved, and centering uses the capped width.
        #expect(abs(rect.height - 760) < 0.5)
        #expect(abs(rect.width - 246 * 760 / 1400) < 0.5)
        #expect(abs(rect.minX - (3.75 + (367.5 - 246 * 760 / 1400) / 2)) < 0.5)
    }

    @Test func authoredMaxWidthResolvesVwAgainstTheViewport() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 300, height: 400), color: .gray)
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            chapterHTML, cssTexts: [chapterCSS + "\nimg { max-width: 50vw !important; }"],
            width: 375, height: 800,
            imageLoader: { _ in image }
        )
        let images = BrowserLayoutTestSupport.allImageFragments(pages)
        #expect(images.count == 1)
        let rect = try #require(images.first).rect.rawValue
        // 50vw = 187.5pt of the 375pt viewport, aspect preserved; the 250pt
        // height needs no page fit, so the vw cap alone decides the geometry.
        #expect(abs(rect.width - 187.5) < 0.5)
        #expect(abs(rect.height - 250) < 0.5)
        #expect(abs(rect.minX - (3.75 + (367.5 - 187.5) / 2)) < 0.5)
    }
}
