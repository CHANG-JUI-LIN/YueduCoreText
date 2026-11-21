import Testing
import UIKit
@testable import YueduCoreText

/// `@media` is evaluated against the reader's page. A stylesheet holding one
/// used to send every chapter that linked it to the fallback engine, and the
/// parser dropped every block but the dark palette's.
@MainActor
struct MediaQueryTests {

    private static let phone = CSSMediaEnvironment(viewportWidth: 390, viewportHeight: 800)
    private static let tablet = CSSMediaEnvironment(viewportWidth: 1024, viewportHeight: 1366)

    // MARK: - Evaluation

    @Test(arguments: [
        ("screen", true), ("all", true), ("print", false), ("amzn-kf8", false), ("amzn-mobi", false),
        ("not amzn-kf8", true), ("not screen", false), ("only screen", true),
        ("screen and (max-width: 512px)", true), ("screen and (min-width: 513px)", false),
        ("(max-width: 30em)", true), ("(min-width: 30em)", false),
        ("(min-width: 300px) and (max-width: 400px)", true),
        ("(width: 390px)", true), ("(device-width: 600px)", false),
        ("(orientation: portrait)", true), ("(orientation: landscape)", false),
        ("(prefers-color-scheme: dark)", false), ("(prefers-color-scheme: light)", true),
        ("(hover: hover)", false), ("(hover: none)", true), ("(pointer: coarse)", true),
        ("print, screen", true), ("amzn-et, amzn-kf8", false),
        ("screen and (max-width: 512px), amzn-et, amzn-kf8 and (device-height:1024px) and (device-width: 758px)", true),
        ("SCREEN AND (MAX-WIDTH: 512PX)", true),
        // Not understood: false, as CSS turns it into `not all`.
        ("screen and (flux-capacitor: 1)", false), ("(max-width: wide)", false), ("screen and", false),
        ("", true),
    ])
    func queriesAgainstAPhone(_ query: String, _ expected: Bool) {
        #expect(CSSMediaQuery.matches(query, in: Self.phone) == expected, "\(query)")
    }

    @Test func widthQueriesFollowThePage() {
        #expect(!CSSMediaQuery.matches("screen and (max-width: 512px)", in: Self.tablet))
        #expect(CSSMediaQuery.matches("(min-width: 768px) and (orientation: portrait)", in: Self.tablet))
        // With no viewport known, nothing about its size is true.
        #expect(!CSSMediaQuery.matches("(max-width: 512px)", in: CSSMediaEnvironment()))
        #expect(CSSMediaQuery.matches("screen", in: CSSMediaEnvironment()))
        #expect(CSSMediaQuery.matches("(prefers-color-scheme: dark)", in: CSSMediaEnvironment(prefersDark: true)))
    }

    // MARK: - Parsing

    @Test func rulesKeepTheirQueriesInSourceOrder() {
        let css = """
        p { margin: 0 }
        @media screen and (max-width: 512px) { p { margin: 1em } @media (orientation: portrait) { h1 { color: red } } }
        @supports (display: grid) { p { margin: 9em } }
        h2 { color: blue }
        """
        let rules = CSSParser.parseConditional(css: css, orderOffset: 0).regular
        #expect(rules.map(\.sourceSelector) == ["p", "p", "h1", "h2"])
        #expect(rules.map(\.mediaConditions) == [[], ["screen and (max-width: 512px)"],
                                                 ["screen and (max-width: 512px)", "(orientation: portrait)"], []])
        #expect(rules.map(\.order) == rules.map(\.order).sorted())
        #expect(Set(rules.map(\.order)).count == rules.count)
    }

    @Test func thePublicParseAnswersTheQueries() {
        let css = """
        p { color: black }
        @media screen and (max-width: 512px) { p { margin: 1em } }
        @media amzn-kf8 { p { display: none } }
        @media (prefers-color-scheme: dark) { p { color: white } }
        """
        // No viewport: only the unconditional rule, and the dark one flagged.
        let unknown = CSSParser.parseWithFirstLetter(css: css).regular
        #expect(unknown.map { $0.declarations["color"] } == ["black", "white"])
        #expect(unknown.map(\.isDarkMedia) == [false, true])
        #expect(CSSParser.parse(css: css).count == 1)
        let phone = CSSParser.parse(css: css, media: Self.phone)
        #expect(phone.count == 2)
        #expect(phone.last?.declarations["margin"] == "1em")
    }

    // MARK: - Layout

    private static func leftEdge(of text: String, css: String, width: CGFloat) async throws -> CGFloat {
        let config = BrowserLayoutConfig(renderWidth: width, renderHeight: 600, rootFontSize: 16,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        let doc = BrowserLayoutDocument(html: "<html><body style=\"margin:0\"><p>\(text)</p></body></html>", cssTexts: [css],
                                        config: config, imageLoader: { _ in nil })
        let pages = try await doc.renderPages(containerSize: CGSize(width: width, height: 600))
        let list = DisplayListBuilder.build(for: try #require(pages.first), sourceText: doc.lastSourceText)
        let rects = list.items.compactMap { item -> CGRect? in
            if case .text(let text) = item { return text.rect.rawValue }
            return nil
        }
        return try #require(rects.map(\.minX).min())
    }

    @Test func aMatchingBlockStylesThePageAndAnotherDoesNot() async throws {
        let css = """
        p { margin: 0 }
        @media screen and (max-width: 512px) { p { margin-left: 40px } }
        @media amzn-kf8 { p { margin-left: 90px } }
        @media (prefers-color-scheme: dark) { p { margin-left: 70px } }
        """
        #expect(abs(try await Self.leftEdge(of: "narrow", css: css, width: 390) - 40) < 0.5)
        #expect(abs(try await Self.leftEdge(of: "wide", css: css, width: 800)) < 0.5)
    }

    @Test func aStylesheetWithMediaIsNoLongerRejected() {
        let html = "<html><body><p class=\"a\">x</p></body></html>"
        func scan(_ css: String, width: CGFloat) -> BrowserLayoutCapabilityResult {
            let input = CSSFrontendInput(html: html, stylesheets: [
                AuthorStylesheet(source: .linked(href: "a.css"), text: css, sourceOrder: 0,
                                 currentCompatibilityOrder: 0, currentCompatibilityOnly: false, media: nil, isAlternate: false)])
            return BrowserLayoutCapabilityScanner.scan(input: input, configuration: BrowserLayoutConfig(renderWidth: width, renderHeight: 600))
        }
        #expect(scan("@media (prefers-color-scheme: dark) { .a { color: white } }", width: 390).supported)
        #expect(scan("@media amzn-kf8 { .a { position: absolute } }", width: 390).supported)
        // What a matching block declares is judged like any other rule; one
        // that does not match this page is not.
        let positioned = "@media screen and (max-width: 512px) { .a { position: absolute } }"
        #expect(scan(positioned, width: 390).unsupportedFeatures == [.positioned])
        #expect(scan(positioned, width: 800).supported)
    }
}
