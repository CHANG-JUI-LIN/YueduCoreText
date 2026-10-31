import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// An inline image taller than a full page scales to the fragment BEFORE line
/// breaking, so text alignment sees the scaled width — not the intrinsic one.
struct BrowserLayoutInlineImageFitTests {

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

    @Test func oversizedInlineImageCentersWithScaledWidth() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 246, height: 1400), color: .gray)
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            chapterHTML, cssTexts: [chapterCSS], width: 375, height: 800,
            imageLoader: { _ in image }
        )
        let images = BrowserLayoutTestSupport.allImageFragments(pages)
        #expect(images.count == 1)
        let rect = try #require(images.first).rect.rawValue
        // Scaled to the 800pt page height, aspect preserved.
        #expect(abs(rect.height - 800) < 0.5)
        #expect(abs(rect.width - 246 * 800 / 1400) < 0.5)
        // Centered within the 367.5pt content box (1% body margins) using the
        // SCALED width: 3.75 + (367.5 - 140.57) / 2.
        #expect(abs(rect.minX - (3.75 + (367.5 - 246 * 800 / 1400) / 2)) < 0.5)
    }

    @Test func fittingInlineImageStillCentersWithIntrinsicWidth() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 100, height: 50), color: .gray)
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            chapterHTML, cssTexts: [chapterCSS], width: 375, height: 800,
            imageLoader: { _ in image }
        )
        let images = BrowserLayoutTestSupport.allImageFragments(pages)
        #expect(images.count == 1)
        let rect = try #require(images.first).rect.rawValue
        #expect(abs(rect.width - 100) < 0.5)
        #expect(abs(rect.minX - (3.75 + (367.5 - 100) / 2)) < 0.5)
    }
}
