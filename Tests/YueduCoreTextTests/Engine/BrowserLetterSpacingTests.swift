import CoreText
import Testing
import UIKit
@testable import YueduCoreText

/// `letter-spacing` tracking (CSS 2.1 §6.1): every glyph's advance shifts by
/// the value, the trailing glyph included, so a 2-glyph line with -4px spacing
/// narrows by 8. Asserted on the shaped line's typographic width. Negative
/// values are the interesting case — EPUB title pages tighten display type
/// with them.
struct BrowserLetterSpacingTests {

    private static func layout(
        _ html: String,
        readerLetterSpacing: CGFloat = 0
    ) async throws -> (pages: [PageFragments], doc: BrowserLayoutDocument) {
        var config = BrowserLayoutConfig(
            renderWidth: 300, renderHeight: 400, rootFontSize: 10,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        config.letterSpacing = readerLetterSpacing
        let doc = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: nil)
        let pages = try await doc.renderPages(containerSize: CGSize(width: 300, height: 400))
        return (pages, doc)
    }

    /// Fragments keyed by their source text, in document order.
    private static func byText(
        _ pages: [PageFragments], doc: BrowserLayoutDocument
    ) -> [String: TextFragment] {
        let ns = doc.lastSourceText as NSString
        var result: [String: TextFragment] = [:]
        for f in BrowserLayoutTestSupport.allTextFragments(pages).sorted(by: {
            $0.sourceRange.location < $1.sourceRange.location
        }) {
            guard case .linear = f.sourceMapping, f.sourceRange.length > 0,
                  f.sourceRange.location + f.sourceRange.length <= ns.length
            else { continue }
            result[ns.substring(with: f.sourceRange)] = f
        }
        return result
    }

    /// Typographic advance of the shaped line that draws `text`.
    private static func width(
        of text: String, in map: [String: TextFragment]
    ) throws -> CGFloat {
        let fragment = try #require(map[text], "fragment missing for \(text)")
        let ctLine = try #require(fragment.ctLine, "ctLine missing for \(text)")
        return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
    }

    @Test func negativeLetterSpacingTightensEachAdvance() async throws {
        let plain = try await Self.layout(
            "<body style=\"margin:0\"><p style=\"margin:0;font-size:40px\">世界</p></body>")
        let tightened = try await Self.layout(
            "<body style=\"margin:0\"><p style=\"margin:0;font-size:40px;letter-spacing:-0.1em\">世界</p></body>")
        let plainWidth = try Self.width(of: "世界", in: Self.byText(plain.pages, doc: plain.doc))
        let tightWidth = try Self.width(of: "世界", in: Self.byText(tightened.pages, doc: tightened.doc))
        // -0.1em at 40px = -4 per glyph, trailing glyph included: 2 × 4 = 8.
        #expect(abs((plainWidth - tightWidth) - 8) < 0.75)
    }

    @Test func letterSpacingEmInheritsAsAbsoluteLength() async throws {
        // A child at a different font-size inherits the COMPUTED px value
        // (WebKit), not a re-resolved em.
        let spaced = try await Self.layout(
            "<body style=\"margin:0\"><div style=\"margin:0;font-size:40px;letter-spacing:-0.1em\"><p style=\"margin:0;font-size:20px\">世界</p></div></body>")
        let plain = try await Self.layout(
            "<body style=\"margin:0\"><div style=\"margin:0;font-size:40px\"><p style=\"margin:0;font-size:20px\">世界</p></div></body>")
        let spacedWidth = try Self.width(of: "世界", in: Self.byText(spaced.pages, doc: spaced.doc))
        let plainWidth = try Self.width(of: "世界", in: Self.byText(plain.pages, doc: plain.doc))
        // Inherited -4px per glyph (computed on the 40px div), not -2px (0.1em of 20).
        #expect(abs((plainWidth - spacedWidth) - 8) < 0.75)
    }

    @Test func authoredLetterSpacingWinsOverReaderDefault() async throws {
        let spaced = try await Self.layout(
            "<body style=\"margin:0\"><p style=\"margin:0;font-size:40px;letter-spacing:-0.1em\">世界</p><p style=\"margin:0;font-size:40px\">獻上</p></body>",
            readerLetterSpacing: 3)
        let plain = try await Self.layout(
            "<body style=\"margin:0\"><p style=\"margin:0;font-size:40px\">世界</p><p style=\"margin:0;font-size:40px\">獻上</p></body>")
        let spacedMap = Self.byText(spaced.pages, doc: spaced.doc)
        let plainMap = Self.byText(plain.pages, doc: plain.doc)
        let authored = try Self.width(of: "世界", in: plainMap) - Self.width(of: "世界", in: spacedMap)
        let readerDefault = try Self.width(of: "獻上", in: spacedMap) - Self.width(of: "獻上", in: plainMap)
        // The authored -0.1em rules the first paragraph (2 × -4); the reader's
        // +3 only reaches paragraphs with no authored value (2 × 3).
        #expect(abs(authored - 8) < 0.75)
        #expect(abs(readerDefault - 6) < 0.75)
    }
}
