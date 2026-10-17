import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// A floated parent establishes a BFC, so its own margin never collapses
/// with its first in-flow child's margin (CSS 2.1 §8.3.1): the child margin
/// applies inside the float, and a negative one sticks out above it.
struct BrowserLayoutFirstChildMarginFoldTests {

    private let baseCSS = """
        body { margin: 0; padding: 0; line-height: 1; }
        div { margin: 0; padding: 0; line-height: 1; }
        p { margin: 0; padding: 0; line-height: 1; }
        """

    private func firstTextY(_ html: String, css: String) async throws -> CGFloat {
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            html, cssTexts: [css], width: 375, height: 800
        )
        return try #require(BrowserLayoutTestSupport.allTextFragments(pages).first).rect.rawValue.minY
    }

    @Test func floatParentKeepsFirstChildNegativeMargin() async throws {
        let css = baseCSS + "\n.f { float: right; width: 1em; margin-top: 120px; } .n { margin-top: -4px; }"
        let y = try await firstTextY(
            "<html><body><div class=\"f\"><p class=\"n\">x</p></div></body></html>",
            css: css
        )
        // A float is a BFC: no fold, the -4px child margin sticks out above it.
        #expect(abs(y - (120 - 4)) < 0.5)
    }

    @Test func floatParentKeepsFirstChildPositiveMargin() async throws {
        let css = baseCSS + "\n.f { float: right; width: 1em; margin-top: 120px; } .n { margin-top: 10px; }"
        let y = try await firstTextY(
            "<html><body><div class=\"f\"><p class=\"n\">x</p></div></body></html>",
            css: css
        )
        // Without a fold the child margin applies inside the float's content box.
        #expect(abs(y - (120 + 10)) < 0.5)
    }
}
