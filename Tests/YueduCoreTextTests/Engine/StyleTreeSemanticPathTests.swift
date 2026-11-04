import SwiftSoup
import Testing
@testable import YueduCoreText

/// The style tree names each element by its semantic path as it walks down the DOM. That
/// path is the one worked out from the element itself, hidden siblings counted.
struct StyleTreeSemanticPathTests {
    private func nodes(_ root: ComputedStyleNode) -> [ComputedStyleNode] {
        [root] + root.children.flatMap { child -> [ComputedStyleNode] in
            if case .element(let node) = child { return nodes(node) }
            return []
        }
    }

    @Test func theWalkNamesEachElementAsTheElementItselfWould() throws {
        let html = """
            <html><body><p id="lead">一<ruby>二<rt>に</rt></ruby>三<span class="gone">消</span>\
            <ruby id="r">四<rt>し</rt></ruby></p><div><p>五</p><p class="gone">六</p><p>七<em>八<b>九</b></em></p></div>\
            </body></html>
            """
        var metrics = LayoutMetrics()
        let result = try CurrentCSSFrontend().buildStyleTree(
            html: html, cssTexts: [".gone { display: none; }"], config: BrowserLayoutConfig(), metrics: &metrics)
        let walked = nodes(result.rootNode).compactMap { $0.semanticElement?.semanticPath }

        // Held: an element reaches its parent only while the document lives.
        let document = try SwiftSoup.parse(html)
        let body = try #require(document.body())
        let expected = try body.getAllElements().array().filter { !$0.hasClass("gone") }
            .map { SwiftSoupHTMLSemanticAdapter.snapshot($0).semanticPath }
        #expect(walked.count == 11)
        #expect(walked == expected)
    }
}
