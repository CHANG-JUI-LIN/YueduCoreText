import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// Explicit block heights resolve for every absolute unit, not just px
/// literals; percentages keep the indefinite-containing-block auto behavior.
struct BrowserBlockExplicitHeightTests {

    private func makeLayout(
        _ html: String, width: CGFloat = 390, height: CGFloat = 800
    ) throws -> BrowserLayoutDocument.BrowserLayoutPipelineResult {
        let config = BrowserLayoutConfig(
            renderWidth: width, renderHeight: height, rootFontSize: 16,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let doc = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: nil)
        return try doc.makeLayout(containerSize: CGSize(width: width, height: height))
    }

    @Test func emHeightIsHonored() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="height: 4.2em; font-size: 16px;"><p style="margin: 0; line-height: 20px;">一行</p></div>
            </body></html>
            """)
        let box = layout.rootBox.children[0]
        #expect(abs(box.frame.height - 4.2 * 16) < 0.5)
    }

    @Test func remAndPtHeightsAreHonored() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="height: 2rem;"><p style="margin: 0;">a</p></div>
            <div style="height: 30pt;"><p style="margin: 0;">b</p></div>
            </body></html>
            """)
        #expect(abs(layout.rootBox.children[0].frame.height - 32) < 0.5)
        #expect(abs(layout.rootBox.children[1].frame.height - 40) < 0.5)
    }

    @Test func vhHeightResolvesAgainstViewport() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="height: 50vh;"><p style="margin: 0;">a</p></div>
            </body></html>
            """, height: 800)
        #expect(abs(layout.rootBox.children[0].frame.height - 400) < 0.5)
    }

    @Test func percentHeightStaysAuto() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="height: 50%;"><p style="margin: 0; line-height: 20px;">一行</p></div>
            </body></html>
            """)
        // No definite containing-block height: the box sizes to its content.
        #expect(abs(layout.rootBox.children[0].frame.height - 20) < 0.5)
    }
}
