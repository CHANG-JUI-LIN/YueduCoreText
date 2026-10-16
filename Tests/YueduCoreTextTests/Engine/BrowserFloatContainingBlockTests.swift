import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// Floats inside a fixed-width, auto-margined, or otherwise offset container
/// are placed against THEIR containing block's inline edges, and intrusions
/// are projected into each querying container's local coordinates — never
/// against the FloatContext root's axis.
struct BrowserFloatContainingBlockTests {

    private func makeLayout(
        _ html: String, width: CGFloat = 390
    ) throws -> BrowserLayoutDocument.BrowserLayoutPipelineResult {
        let config = BrowserLayoutConfig(
            renderWidth: width, renderHeight: 800, rootFontSize: 16,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let doc = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: nil)
        return try doc.makeLayout(containerSize: CGSize(width: width, height: 800))
    }

    @Test func rightFloatInsideCenteredContainerHugsContainerEdge() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="width: 200px; margin: 0 auto;">
            <div style="float: right; width: 80px;"><p style="margin: 0;">浮</p></div>
            <p style="margin: 0;">正文</p>
            </div>
            </body></html>
            """)
        let container = layout.rootBox.children[0]
        #expect(abs(container.frame.minX - 95) < 0.5)
        let floatBox = container.children[0]
        #expect(floatBox.isFloated)
        // The right edge kisses the container's right content edge (200 - 80),
        // not the viewport's (390 - 80).
        #expect(abs(floatBox.frame.minX - 120) < 0.5)
    }

    @Test func textWrapsAroundFloatInsideCenteredContainer() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="width: 200px; margin: 0 auto;">
            <div style="float: left; width: 80px; height: 40px;"></div>
            <p style="margin: 0; line-height: 20px;">第一行文字第一行文字第一行文字第一行文字第一行文字第一行文字</p>
            </div>
            </body></html>
            """)
        let container = layout.rootBox.children[0]
        let textBox = container.children[1]
        #expect(textBox.lines.count >= 2)
        // Local to the container: an 80-wide left float pushes lines to x=80.
        #expect(abs(textBox.lines[0].contentX - 80) < 0.5)
        #expect(abs(textBox.lines[1].contentX - 80) < 0.5)
    }

    @Test func floatOutsideSiblingRangeDoesNotIntrude() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="width: 100px; float: left;">
            <div style="float: left; width: 50px; height: 200px;"></div>
            <p style="margin: 0;">左侧</p>
            </div>
            <div style="width: 100px; margin-left: 290px;">
            <p style="margin: 0; line-height: 20px;">右侧容器的第一行文字</p>
            </div>
            </body></html>
            """)
        let right = layout.rootBox.children[1]
        #expect(abs(right.frame.minX - 290) < 0.5)
        let textBox = right.children[0]
        #expect(!textBox.lines.isEmpty)
        // The left float's margin box ([0,50] in context coordinates) never
        // overlaps this container's range ([290,390]), so lines start at 0.
        #expect(abs(textBox.lines[0].contentX) < 0.5)
    }

    @Test func centeredContainerFloatExcludesFollowingFullWidthText() throws {
        let layout = try makeLayout("""
            <html><body style="margin: 0;">
            <div style="width: 200px; margin: 0 auto;">
            <div style="float: left; width: 80px; height: 60px;"></div>
            <p style="margin: 0; line-height: 20px;">短行</p>
            </div>
            <p style="margin: 0; line-height: 20px;">后续满宽段落第一行会避开浮动</p>
            </body></html>
            """)
        let sibling = layout.rootBox.children[1]
        #expect(!sibling.lines.isEmpty)
        // The float ([95,175] in context coordinates) still overhangs the band,
        // so the full-width sibling wraps around its right edge.
        #expect(abs(sibling.lines[0].contentX - 175) < 0.5)
    }
}
