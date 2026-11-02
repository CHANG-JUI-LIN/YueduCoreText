import Testing
@testable import YueduCoreText

/// A document's principal writing mode is `<body>`'s `writing-mode`, inherited from
/// `<html>` (CSS Writing Modes 3 §8). Hosts read it to lay each document out in its own
/// mode: a Calibre conversion's generated table of contents declares none inside a
/// book whose chapters are `html.calibre { writing-mode: vertical-rl }`.
@Suite
struct PrincipalWritingModeTests {

    private static func mode(_ html: String, css: [String] = []) throws -> ReaderWritingMode? {
        try BrowserChapterDocument(input: .currentCompatibility(html: html, cssTexts: css)).principalWritingMode
    }

    private static func page(html htmlAttributes: String = "", body bodyAttributes: String = "",
                             head: String = "", content: String = "<p>x</p>") -> String {
        "<html \(htmlAttributes)><head>\(head)</head><body \(bodyAttributes)>\(content)</body></html>"
    }

    @Test func calibreClassOnHtml() throws {
        let css = ".calibre { writing-mode: vertical-rl }"
        #expect(try Self.mode(Self.page(html: #"class="calibre""#), css: [css]) == .verticalRTL)
    }

    @Test func calibreGeneratedTableOfContentsDeclaresNothing() throws {
        let toc = Self.page(body: #"id="calibre_generated_inline_toc" class="calibre2""#,
                            content: #"<h2 class="calibre3">目錄</h2><ul><li><a href="a.xhtml">一</a></li></ul>"#)
        #expect(try Self.mode(toc, css: [".calibre2 { display: block } .calibre3 { font-weight: bold }"]) == nil)
    }

    @Test func classOnBody() throws {
        #expect(try Self.mode(Self.page(body: #"class="v""#), css: [".v { writing-mode: vertical-rl }"]) == .verticalRTL)
    }

    @Test func inlineStyleOnHtmlAndOnBody() throws {
        #expect(try Self.mode(Self.page(html: #"style="writing-mode: vertical-rl""#)) == .verticalRTL)
        #expect(try Self.mode(Self.page(body: #"style="-epub-writing-mode: vertical-rl""#)) == .verticalRTL)
    }

    @Test func styleElementInHead() throws {
        let head = "<style>html { -webkit-writing-mode: vertical-rl }</style>"
        #expect(try Self.mode(Self.page(head: head)) == .verticalRTL)
    }

    @Test func prefixedSpellingsAreAliases() throws {
        for key in ["writing-mode", "-webkit-writing-mode", "-epub-writing-mode"] {
            #expect(try Self.mode(Self.page(), css: ["body { \(key): vertical-rl }"]) == .verticalRTL, "\(key)")
        }
    }

    @Test func bodyOverridesHtml() throws {
        let css = "html { writing-mode: vertical-rl } body { writing-mode: horizontal-tb }"
        #expect(try Self.mode(Self.page(), css: [css]) == .horizontal)
    }

    @Test func bodyInheritsHtml() throws {
        #expect(try Self.mode(Self.page(), css: ["html { writing-mode: vertical-rl } body { margin: 0 }"]) == .verticalRTL)
        #expect(try Self.mode(Self.page(), css: ["html { writing-mode: vertical-rl } body { writing-mode: inherit }"])
                == .verticalRTL)
    }

    @Test func explicitHorizontalIsADeclaration() throws {
        #expect(try Self.mode(Self.page(), css: ["body { writing-mode: horizontal-tb }"]) == .horizontal)
    }

    @Test func importantBeatsSpecificityAndInlineStyle() throws {
        let css = "body { writing-mode: vertical-rl !important } body.h { writing-mode: horizontal-tb }"
        #expect(try Self.mode(Self.page(body: #"class="h" style="writing-mode: horizontal-tb""#), css: [css])
                == .verticalRTL)
    }

    @Test func specificityThenSourceOrder() throws {
        let css = "body.v { writing-mode: vertical-rl } body { writing-mode: horizontal-tb }"
        #expect(try Self.mode(Self.page(body: #"class="v""#), css: [css]) == .verticalRTL)
        let later = "body { writing-mode: vertical-rl } body { writing-mode: horizontal-tb }"
        #expect(try Self.mode(Self.page(), css: [later]) == .horizontal)
    }

    @Test func inlineStyleBeatsNormalRules() throws {
        #expect(try Self.mode(Self.page(body: #"style="writing-mode: horizontal-tb""#),
                              css: ["body { writing-mode: vertical-rl }"]) == .horizontal)
    }

    @Test func aRuleOnAnInnerElementIsNotTheDocumentsMode() throws {
        let content = #"<p>x</p><div class="poem"><p>詩</p></div>"#
        #expect(try Self.mode(Self.page(content: content), css: [".poem { writing-mode: vertical-rl }"]) == nil)
    }

    @Test func svgSpellings() throws {
        #expect(try Self.mode(Self.page(), css: ["body { -epub-writing-mode: tb-rl }"]) == .verticalRTL)
        #expect(try Self.mode(Self.page(), css: ["body { -epub-writing-mode: lr-tb }"]) == .horizontal)
    }

    @Test func anUnsupportedValueIsIgnored() throws {
        let css = "body { writing-mode: vertical-rl } body { writing-mode: vertical-lr }"
        #expect(try Self.mode(Self.page(), css: [css]) == .verticalRTL)
        #expect(try Self.mode(Self.page(), css: ["body { writing-mode: sideways-lr }"]) == nil)
    }

    @Test func noDeclaration() throws {
        #expect(try Self.mode(Self.page()) == nil)
        #expect(try Self.mode("<p>no html or body tags</p>") == nil)
    }

    @Test func darkMediaRulesDoNotDecide() throws {
        let css = "@media (prefers-color-scheme: dark) { body { writing-mode: vertical-rl } }"
        #expect(try Self.mode(Self.page(), css: [css]) == nil)
    }
}
