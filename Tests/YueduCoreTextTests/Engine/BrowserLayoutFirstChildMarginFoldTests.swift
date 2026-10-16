import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// A first-child margin folds through margin-less ancestors up to the chapter
/// start (CSS 2.1 §8.3.1): the fold runs inside the child's own layout, so the
/// parent must re-account the grown margin it consumed earlier as zero.
struct BrowserLayoutFirstChildMarginFoldTests {

    /// rootFontSize 17: h1 = 34pt font/line, `margin-top: 1em` = 34pt.
    private let baseCSS = """
        body { margin: 0; padding: 0; line-height: 1; }
        div, section { margin: 0; padding: 0; line-height: 1; }
        h1 { font-size: 2em; line-height: 1; margin-top: 1em; margin-bottom: 0; }
        p { margin: 0; padding: 0; line-height: 1; }
        """

    private func firstTextY(_ html: String, css: String) async throws -> CGFloat {
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            html, cssTexts: [css], width: 375, height: 800
        )
        return try #require(BrowserLayoutTestSupport.allTextFragments(pages).first).rect.rawValue.minY
    }

    @Test func foldsThroughOnePlainAncestor() async throws {
        let y = try await firstTextY(
            "<html><body><div><h1>Title</h1><p>Body</p></div></body></html>",
            css: baseCSS
        )
        #expect(abs(y - 34) < 0.5)
    }

    @Test func foldsThroughMultiplePlainAncestors() async throws {
        let y = try await firstTextY(
            "<html><body><section><div><h1>Title</h1><p>Body</p></div></section></body></html>",
            css: baseCSS
        )
        #expect(abs(y - 34) < 0.5)
    }

    @Test func directChildFoldStillWorks() async throws {
        let y = try await firstTextY(
            "<html><body><h1>Title</h1><p>Body</p></body></html>",
            css: baseCSS
        )
        #expect(abs(y - 34) < 0.5)
    }

    @Test func grownMarginCollapsesWithPreviousSiblingMargin() async throws {
        let css = baseCSS + "\np { margin-bottom: 0.5em; }"
        let (pages, _) = try await BrowserLayoutTestSupport.layout(
            "<html><body><p>Intro</p><div><h1>Title</h1></div></body></html>",
            cssTexts: [css], width: 375, height: 800
        )
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(texts.count == 2)
        // p at 0 (its own margins are 0/8.5 at flow start); the div's grown
        // 34pt top margin wins the collapse against p's 8.5pt bottom margin.
        #expect(abs(texts[0].rect.rawValue.minY - 0) < 0.5)
        #expect(abs(texts[1].rect.rawValue.minY - (17 + 34)) < 0.5)
    }

    @Test func foldStopsAtAncestorPadding() async throws {
        let css = baseCSS + "\n.padded { padding-top: 5px; }"
        let y = try await firstTextY(
            "<html><body><div class=\"padded\"><h1>Title</h1></div></body></html>",
            css: css
        )
        // Padding blocks the fold, so the h1 margin applies inside the div.
        #expect(abs(y - (5 + 34)) < 0.5)
    }
}
