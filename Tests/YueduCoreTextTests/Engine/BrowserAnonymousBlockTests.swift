import Testing
import UIKit
@testable import YueduCoreText

/// CSS 2.1 §9.2.1.1: an anonymous block box inherits inheritable properties
/// only. Non-inheritable declarations of the parent (float, margins, width)
/// must not leak into the anonymous wrapper — a leaked `float: right` makes
/// the wrapper itself a float that occludes following siblings' line bands.
struct BrowserAnonymousBlockTests {

    private static func fragmentY(
        _ html: String, needle: String
    ) async throws -> (needle: CGRect, all: [(String, CGRect)]) {
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            html, cssTexts: [], width: 300, height: 800, rootFontSize: 10)
        let ns = doc.lastSourceText as NSString
        var all: [(String, CGRect)] = []
        var found = CGRect.zero
        for f in BrowserLayoutTestSupport.allTextFragments(pages).sorted(by: {
            $0.sourceRange.location < $1.sourceRange.location
        }) {
            guard case .linear = f.sourceMapping, f.sourceRange.length > 0,
                f.sourceRange.location + f.sourceRange.length <= ns.length
            else { continue }
            let text = ns.substring(with: f.sourceRange)
            all.append((text, f.rect.rawValue))
            if text == needle { found = f.rect.rawValue }
        }
        return (found, all)
    }

    /// <br/> between two block paragraphs inside a `float: right` container
    /// occupies exactly one empty line; the paragraph after it must sit right
    /// below the break, with no extra gap from a mis-floated anonymous box.
    @Test func brBetweenBlocksInFloatKeepsSingleLineGap() async throws {
        let html = """
            <body style="margin:0">
            <div style="float:right;width:3em;font-size:1.2em;line-height:1.2;margin-top:1em">
              <p style="margin:0;line-height:1em">暁</p>
              <br/>
              <p style="margin:0;line-height:1em">な</p>
            </div>
            </body>
            """
        let (_, all) = try await Self.fragmentY(html, needle: "な")
        var byText: [String: CGRect] = [:]
        for (text, rect) in all { byText[text] = rect }
        let a = try #require(byText["暁"], "暁 fragment missing")
        let br = try #require(byText["\n"], "br fragment missing")
        let na = try #require(byText["な"], "な fragment missing")
        // 暁: y=12 h=12 (margin-top 1em at 12px font); br: one 1.2×12 line;
        // な must follow immediately: 12 + 12 + 14.4 = 38.4.
        #expect(abs(a.minY - 12) < 0.01)
        #expect(abs(br.minY - (a.minY + a.height)) < 0.01)
        #expect(abs(na.minY - (br.minY + br.height)) < 0.01)
    }

    /// A plain-text run between two blocks (no <br/>) becomes an anonymous
    /// block; it must not inherit the parent's width/margins/float either.
    @Test func anonymousTextBlockInFloatStaysInFlow() async throws {
        let html = """
            <body style="margin:0">
            <div style="float:right;width:5em;font-size:10px;line-height:1;margin-top:1em">
              <p style="margin:0">A</p>
              bare
              <p style="margin:0">B</p>
            </div>
            </body>
            """
        let (_, all) = try await Self.fragmentY(html, needle: "B")
        var byText: [String: CGRect] = [:]
        for (text, rect) in all { byText[text] = rect }
        let a = try #require(byText["A"], "A fragment missing")
        let bare = try #require(byText["bare"], "bare fragment missing")
        let b = try #require(byText["B"], "B fragment missing")
        #expect(abs(bare.minY - (a.minY + a.height)) < 0.01)
        #expect(abs(b.minY - (bare.minY + bare.height)) < 0.01)
    }
}
