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

    /// A box sized to its text still holds it: the width measured from content
    /// is rounded up to the unit.
    @Test func aBoxSizedToItsTextDoesNotBreakIt() async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p><span class=\"b\">\(String(repeating: "字", count: 7))</span></p>",
            css: "html { font-size: 14pt; } .b { display: inline-block; }")
        #expect(BrowserLayoutTestSupport.allTextFragments(layout.pages).count == 1)
    }
}

/// Columns their text fills exactly, against WKWebView iOS 27.2 (the app's fixture S021:
/// `html { max-height: 28em; font-size: 14pt }`, Hiragino Mincho). What decides the last
/// character: the font's pair kerning, which WebKit does not apply down a column, and the
/// sliver a ruby's annotation adds when it is as wide as its base.
struct ExactFitColumnTests {
    private static let css = """
        html { max-height: 28em; font-size: 14pt; font-family: "HiraMinProN-W3"; }
        body { margin: 0 } p { margin: 0 } rt { font-size: 50% }
        """
    private static let filler = String(repeating: "字", count: 40)

    /// The characters of the base text in the paragraph's first column.
    private func firstColumn(_ body: String) async throws -> Int {
        let layout = try await BrowserLayoutTestSupport.webKitReference(body, css: Self.css, vertical: true, lang: "ja", rootFamilies: [])
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.font.pointSize > 12 }
        let right = try #require(texts.map(\.rect.rawValue.maxX).max())
        return texts.filter { abs($0.rect.rawValue.maxX - right) < 1 }.reduce(0) { $0 + $1.sourceRange.length }
    }

    @Test func plainTextFillsTheColumn() async throws {
        #expect(try await firstColumn("<p>\(Self.filler)</p>") == 28)
        // か before 、 and く before つ are kerned pairs in this font; a column holds 28 all the same.
        #expect(try await firstColumn("<p>どか、くつろげて、束の間の命を、束の間でも住みよくせねばならぬ。ここに詩人</p>") == 28)
    }

    @Test(arguments: [
        ("<ruby>角<rt>かど</rt></ruby>", 1, 28),       // as wide as its base: one sliver still fits
        ("<ruby>智<rt>ち</rt></ruby>", 1, 28),         // narrower than its base
        ("<ruby>山路<rt>やまみち</rt></ruby>", 2, 27),  // as wide as two characters: two slivers
        ("<ruby>山<rt>やま</rt></ruby><ruby>路<rt>みち</rt></ruby>", 2, 27),
        ("<ruby>情<rt>じょう</rt></ruby>", 1, 27),      // wider than its base
    ])
    func aRubyAsWideAsItsBaseTakesASliverMore(_ ruby: String, _ base: Int, _ expected: Int) async throws {
        // The column's base characters: the ruby's and the 字 that follow it.
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p>\(ruby)\(Self.filler)</p>", css: Self.css, vertical: true, lang: "ja", rootFamilies: [])
        let source = layout.doc.lastSourceText as NSString
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.font.pointSize > 12 }
        let right = try #require(texts.map(\.rect.rawValue.maxX).max())
        let filler = texts.filter { abs($0.rect.rawValue.maxX - right) < 1 }
            .reduce(0) { $0 + (source.substring(with: $1.sourceRange).filter { $0 == "字" }.count) }
        #expect(filler + base == expected, "\(ruby): \(filler) + \(base)")
    }
}

/// A box sized to its text holds it on one line, whatever the line's own rules add:
/// the width is measured the way the line is shaped.
struct ShrinkToFitShapingTests {
    private static let css = """
        html { font-size: 14pt; font-family: "HiraMinProN-W3"; } body { margin: 0 } p { margin: 0 } rt { font-size: 50% }
        .b { display: inline-block; } .f { float: left; }
        """

    private func baseLines(_ body: String, vertical: Bool) async throws -> Int {
        let layout = try await BrowserLayoutTestSupport.webKitReference(body, css: Self.css, vertical: vertical, lang: "ja", rootFamilies: [])
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.font.pointSize > 12 }
        // One baseline per line (a ruby's base has a box of its own height on the same one).
        return Set(texts.map { ($0.baselineY / 4).rounded() }).count
    }

    /// Down a column the font's pair kerning is off (どか、 is 56px, kerned 55.07).
    @Test(arguments: ["<p><span class=\"b\">どか、くつろげて</span></p>", "<div class=\"f\">どか、くつろげて</div>"])
    func kernedPairsInAVerticalBox(_ body: String) async throws {
        #expect(try await baseLines(body, vertical: true) == 1)
    }

    /// A ruby as wide as its base is a sliver wider than the base.
    @Test(arguments: [false, true])
    func aRubyInABox(vertical: Bool) async throws {
        let body = "<p><span class=\"b\"><ruby>山路<rt>やまみち</rt></ruby>を<ruby>登<rt>のぼ</rt></ruby>りながら</span></p>"
        #expect(try await baseLines(body, vertical: vertical) == 1)
    }
}
