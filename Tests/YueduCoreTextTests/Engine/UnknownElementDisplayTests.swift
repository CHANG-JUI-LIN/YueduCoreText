import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// `display` by tag follows WebKit html.css (iOS 27.2 runtime): it names the
/// block and hidden elements, and every other element keeps CSS's initial
/// `display: inline`. A `font`, `big`, `var` or custom tag used to default to
/// block, splitting its line in three; measured in Safari on iOS 27.2 it stays
/// on the line, as a `span` does.
@Suite @MainActor
struct UnknownElementDisplayTests {

    private static func style(_ body: String) throws -> ComputedStyle {
        let document = try SwiftSoup.parse("<html><body>\(body)</body></html>")
        let root = ComputedStyleTreeBuilder(rules: CSSParser.parse(css: ""), config: BrowserLayoutConfig())
            .buildTree(body: try #require(document.body()))
        func find(_ node: ComputedStyleNode) -> ComputedStyleNode? {
            if node.anchorID == "x" { return node }
            for child in node.children {
                if case .element(let element) = child, let found = find(element) { return found }
            }
            return nil
        }
        return try #require(find(root), "no element #x").style
    }

    private static func layout(_ body: String, css: String = "", mode: ReaderWritingMode) async throws
        -> (pages: [PageFragments], source: NSString) {
        let size = CGSize(width: 300, height: 300)
        var config = BrowserLayoutConfig(renderWidth: size.width, renderHeight: size.height, rootFontSize: 17,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        config.writingMode = mode
        let doc = BrowserLayoutDocument(html: "<html><head></head><body>\(body)</body></html>",
                                        cssTexts: ["body { margin: 0; line-height: 1.5 } " + css], config: config)
        let pages = try await doc.renderPages(containerSize: size)
        return (pages, doc.lastSourceText as NSString)
    }

    /// The run holding each of `texts`, by its first character.
    private static func runs(_ layout: (pages: [PageFragments], source: NSString),
                             _ texts: [String]) throws -> [TextFragment] {
        let fragments = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
        return try texts.map { text in
            let location = layout.source.range(of: text).location
            return try #require(fragments.first { NSLocationInRange(location, $0.sourceRange) }, "\(text)")
        }
    }

    private static func admitted(_ body: String, css: String = "", mode: ReaderWritingMode) -> [UnsupportedFeature] {
        BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body>\(body)</body></html>",
                                            cssTexts: [css], writingMode: mode).unsupportedFeatures
    }

    // MARK: - display by tag

    @Test func elementsHTMLCSSDoesNotNameAreInline() throws {
        for tag in ["font", "big", "var", "dfn", "del", "ins", "strike", "bdi", "bdo", "data", "nobr", "foo", "rtc"] {
            #expect(try Self.style("<p><\(tag) id=\"x\">甲</\(tag)></p>").display == .inline, "\(tag)")
        }
    }

    /// Read off the UA basis: the HTML parser drops some of these from a body
    /// (`frameset`, `frame`), and the cascade never styles a hidden element.
    @Test func elementsHTMLCSSMakesBlockStayBlock() {
        for tag in ["p", "h1", "h2", "h3", "h4", "h5", "h6", "center", "hgroup", "search", "address",
                    "menu", "dir", "xmp", "plaintext", "listing", "details", "summary", "legend",
                    "optgroup", "option", "frameset", "frame"] {
            #expect(UserAgentStyle.basis(for: tag).display == .block, "\(tag)")
        }
    }

    @Test func elementsHTMLCSSHidesAreNotRendered() async throws {
        for tag in ["noscript", "datalist", "noembed", "noframes", "param", "area", "basefont"] {
            let style = UserAgentStyle.basis(for: tag)
            #expect(style.display == .none && style.isHidden, "\(tag)")
        }
        // Measured in a WKWebView, which runs scripts: what a `noscript` holds
        // takes no room.
        let control = try Self.runs(try await Self.layout("<p>甲</p><p>乙</p>", mode: .horizontal), ["甲", "乙"])
        let layout = try await Self.layout("<p>甲</p><noscript><p>無</p></noscript><p>乙</p>", mode: .horizontal)
        #expect(try Self.runs(layout, ["甲", "乙"]).map(\.baselineY) == control.map(\.baselineY))
    }

    // MARK: - layout

    /// Each tag lays its text out exactly as a `span` does: one line, the same
    /// baselines and advances.
    @Test(arguments: ReaderWritingMode.allCases)
    func anElementHTMLCSSDoesNotNameStaysOnTheLine(mode: ReaderWritingMode) async throws {
        let control = try Self.runs(try await Self.layout("<p>甲<span>乙</span>丙</p>", mode: mode), ["甲", "乙", "丙"])
        for tag in ["font", "var", "dfn", "del", "ins", "strike", "bdi", "data", "nobr", "foo"] {
            let layout = try await Self.layout("<p>甲<\(tag)>乙</\(tag)>丙</p>", mode: mode)
            let runs = try Self.runs(layout, ["甲", "乙", "丙"])
            #expect(runs.map(\.baselineY) == control.map(\.baselineY), "\(tag)")
            #expect(runs.map(\.rect) == control.map(\.rect), "\(tag)")
        }
    }

    /// Blocks inside one split it and keep their own lines and margins, and
    /// what it sets reaches them.
    @Test(arguments: ReaderWritingMode.allCases)
    func blocksInsideAnInlineElementKeepTheirLinesAndMargins(mode: ReaderWritingMode) async throws {
        let control = try Self.runs(try await Self.layout("<div><p>甲。</p><p>乙。</p></div>", mode: mode), ["甲", "乙"])
        let layout = try await Self.layout("<font><p>甲。</p><p>乙。</p></font>", css: "font { color: red }", mode: mode)
        let runs = try Self.runs(layout, ["甲", "乙"])
        #expect(runs.map(\.baselineY) == control.map(\.baselineY))
        #expect(runs.map(\.rect) == control.map(\.rect))
        for run in runs {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            run.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect([r, g, b, a] == [1, 0, 0, 1], "\(run.color)")
        }
    }

    /// The white space between an inline element and the block after it makes
    /// no line of its own.
    @Test(arguments: ReaderWritingMode.allCases)
    func whiteSpaceBetweenAnInlineElementAndABlockMakesNoLine(mode: ReaderWritingMode) async throws {
        let control = try Self.runs(try await Self.layout("<div><span>甲</span>\n<p>乙</p></div>", mode: mode), ["甲", "乙"])
        let runs = try Self.runs(try await Self.layout("<div><var>甲</var>\n<p>乙</p></div>", mode: mode), ["甲", "乙"])
        #expect(runs.map(\.baselineY) == control.map(\.baselineY))
        #expect(runs.map(\.rect) == control.map(\.rect))
    }

    // MARK: - admission

    /// A ruby base wrapped in one is a span-like base, admitted as a `span`
    /// base is; it used to be a block and turned the chapter away.
    @Test(arguments: ReaderWritingMode.allCases)
    func aRubyBaseInsideAnInlineElementIsAdmitted(mode: ReaderWritingMode) {
        #expect(Self.admitted("<p><ruby><font>漢</font><rt>かん</rt></ruby></p>", mode: mode).isEmpty)
        #expect(Self.admitted("<p><ruby><span>漢</span><rt>かん</rt></ruby></p>", mode: mode).isEmpty)
    }

    /// And lays out as one: the same text items, the annotation included,
    /// at the same places.
    @Test(arguments: ReaderWritingMode.allCases)
    func aRubyBaseInsideAnInlineElementLaysOutAsASpanBaseDoes(mode: ReaderWritingMode) async throws {
        func items(_ body: String) async throws -> [String] {
            let layout = try await Self.layout(body, mode: mode)
            return DisplayListBuilder.build(for: try #require(layout.pages.first), sourceText: layout.source as String)
                .items.compactMap {
                    guard case .text(let t) = $0 else { return nil }
                    return "\(t.renderedTextOverride ?? t.text) \(t.rect.rawValue) \(t.baselineY)"
                }
        }
        let control = try await items("<p>甲<ruby><span>漢</span><rt>かん</rt></ruby>乙</p>")
        #expect(control.contains { $0.hasPrefix("かん ") }, "\(control)")
        #expect(try await items("<p>甲<ruby><font>漢</font><rt>かん</rt></ruby>乙</p>") == control)
    }

    @Test(arguments: ReaderWritingMode.allCases)
    func anIndentedParagraphStartingWithOneIsAdmitted(mode: ReaderWritingMode) {
        #expect(Self.admitted("<p><font>甲</font>乙</p>", css: "p { text-indent: 2em }", mode: mode).isEmpty)
    }

    /// The engine has no column or caption display; a table holding either is
    /// still turned away, as it was while they defaulted to block.
    @Test func aTableWithACaptionOrColumnsIsStillTurnedAway() {
        let rows = "<tr><td>甲</td></tr>"
        #expect(Self.admitted("<table><caption>表</caption>\(rows)</table>", mode: .horizontal) == [.table])
        #expect(Self.admitted("<table><colgroup><col/></colgroup>\(rows)</table>", mode: .horizontal) == [.table])
        #expect(Self.admitted("<table>\(rows)</table>", mode: .horizontal).isEmpty)
    }
}
