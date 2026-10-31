import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// width:auto floats get a CSS §10.3.5 shrink-to-fit used width measured from
/// their content: the longest line for text, the intrinsic size for images,
/// clamped to the containing block.
struct BrowserFloatShrinkToFitTests {

    private func makeLayout(
        _ html: String, width: CGFloat = 390,
        imageLoader: ((String) -> UIImage?)? = nil
    ) throws -> BrowserLayoutDocument.BrowserLayoutPipelineResult {
        let config = BrowserLayoutConfig(
            renderWidth: width, renderHeight: 800, rootFontSize: 16,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let doc = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: imageLoader)
        return try doc.makeLayout(containerSize: CGSize(width: width, height: 800))
    }

    @Test func autoWidthTextFloatShrinksToLongestLine() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="float: right;"><p style="margin: 0;">短</p><p style="margin: 0;">较长的一行</p></div>
            <p style="margin: 0;">正文正文正文正文正文正文正文正文正文正文正文正文正文正文正文正文</p>
            </body></html>
            """)
        let floatBox = layout.rootBox.children[0]
        #expect(floatBox.isFloated)
        // 5 full-width characters at 16pt.
        #expect(abs(floatBox.frame.width - 5 * 16) < 1)
        #expect(abs(floatBox.frame.minX - (390 - 5 * 16)) < 1)
    }

    @Test func autoWidthFloatClampsToAvailableWidth() throws {
        let longText = String(repeating: "排", count: 200)
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="float: left;"><p style="margin: 0;">\(longText)</p></div>
            </body></html>
            """)
        let floatBox = layout.rootBox.children[0]
        #expect(abs(floatBox.frame.width - 390) < 0.5)
    }

    @Test func autoWidthFloatContainingImageShrinksToImage() throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 100, height: 50), color: .gray)
        let layout = try makeLayout("""
            <html><body>
            <div style="float: left;"><img src="a.jpg"/><p style="margin: 0;">短</p></div>
            </body></html>
            """, imageLoader: { _ in image })
        let floatBox = layout.rootBox.children[0]
        #expect(abs(floatBox.frame.width - 100) < 0.5)
    }

    @Test func rightFloatedColumnsStackRightToLeft() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="float: right;"><p style="margin: 0;">暁</p><p style="margin: 0;">目</p></div>
            <div style="float: right;"><p style="margin: 0;">三</p><p style="margin: 0;">嶋</p></div>
            <div style="float: right;"><p style="margin: 0;">為</p><p style="margin: 0;">美</p></div>
            </body></html>
            """)
        let columns = layout.rootBox.children.filter(\.isFloated)
        #expect(columns.count == 3)
        // Each column is one full-width character wide; successive right
        // floats march left from the right edge.
        for (index, column) in columns.enumerated() {
            #expect(abs(column.frame.width - 16) < 1)
            #expect(abs(column.frame.minX - (390 - 16 * CGFloat(index + 1))) < 1)
        }
    }

    @Test func nestedFloatStillUnsupportedInScanner() {
        let html = """
        <html><body>
        <div style="float: left;"><div style="float: left;">nested</div></div>
        </body></html>
        """
        let res = BrowserLayoutCapabilityScanner.scan(html: html, cssTexts: [])
        #expect(!res.supported)
        #expect(res.unsupportedFeatures.contains(.float))
    }
}
