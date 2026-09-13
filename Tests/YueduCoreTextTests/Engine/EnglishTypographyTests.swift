import Testing
import UIKit
import SwiftSoup
@testable import YueduCoreText

struct EnglishTypographyTests {
    func tree(_ css: String, _ body: String, root: String = "") throws -> ComputedStyleNode {
        let document = try SwiftSoup.parse("<html \(root)><head><style>\(css)</style></head><body>\(body)</body></html>")
        let builder = ComputedStyleTreeBuilder(rules: CSSParser.parse(css: css), config: BrowserLayoutConfig(rootFontSize: 20))
        return builder.buildTree(body: try #require(document.body()))
    }
    func nodes(_ root: ComputedStyleNode) -> [ComputedStyleNode] {
        [root] + root.children.flatMap { child in
            if case .element(let node) = child { return nodes(node) }
            return []
        }
    }
    @Test func siblingSelectorsUseElementSiblings() throws {
        let root = try tree("p {text-indent:0} p + p {text-indent:24px} h2 + p {text-indent:12px} h2 ~ p {color:red}",
            "<p>A</p> \n<p>B</p><h2>Heading</h2> \n<p>C</p><div>D</div><p>E</p>")
        let paragraphs = nodes(root).filter { $0.tag == "p" }
        #expect(paragraphs.map(\.style.textIndent) == [.length(.px(0)), .length(.px(24)), .length(.px(12)), .length(.px(0))])
        #expect(paragraphs[3].style.color == .red)
    }
    @Test func indentUnitsAndInheritance() throws {
        #expect(CSSTextIndent.parse("12pt") == .length(.pt(12)))
        #expect(CSSTextIndent.parse("-1em") == .length(.em(-1)))
        let root = try tree("html {font-size:24px; text-indent:2em; line-height:1.25} p {font-size:12px} .inherit {text-indent:inherit} .initial {text-indent:initial} .unset {text-indent:unset}",
            "<p class='inherit'>A</p><p class='initial'>B</p><p class='unset'>C</p>")
        #expect(root.style.fontSize == 24)
        let p = nodes(root).filter { $0.tag == "p" }
        #expect(p[0].style.textIndent == .length(.px(48)))
        #expect(p[1].style.textIndent == .initial)
        #expect(p[2].style.textIndent == .length(.px(48)))
        #expect(p[0].style.lineHeight == 15)
    }
    @Test func stylesheetOrdersAreGlobal() {
        let rules = CurrentCSSFrontendSupport.parseRules(in: ["p{color:red} p{color:green}", "p{color:blue}"])
        #expect(rules.map(\.order) == [0, 1, 2])
    }
    @Test func explicitLineHeightIsNotInkHeight() {
        var style = ComputedStyle(fontSize: 20, fontFamilies: ["Georgia"], lineHeight: 16)
        style.configLineSpacing = 3
        let text = "The early morning sunlight warmed the quiet garden while birds gathered beside the fountain."
        let lines = InlineLayout.layoutLines(runs: [InlineRun(text: text, style: style)], context: InlineFormattingContext(containingInlineSize: 130, rootFontSize: 20, lineHeight: 16, writingMode: .horizontal, sourceText: text, fontResolver: nil, floatContext: nil, blockOffsetY: 0))
        #expect(lines.count > 2)
        #expect(abs(lines[1].baseline - lines[0].baseline - 19) < 0.01)
    }
    @Test func firstLetterSurvivesProductionFrontend() throws {
        var metrics = LayoutMetrics()
        let result = try CurrentCSSFrontend().buildStyleTree(html: "<p id='lead'>“<em>Z</em>ebra walks through the garden.</p>", cssTexts: ["p::first-letter {font-size:320%;color:#737778;float:left;line-height:0.7;margin:-0.3225em 0.05em -0.3245em 0}"], config: BrowserLayoutConfig(rootFontSize:20), metrics:&metrics)
        let initial = nodes(result.rootNode).first { $0.tag == "::first-letter" }
        #expect(initial != nil)
        #expect(initial?.style.fontSize == 64)
    }
    @Test func automaticHyphenationProducesPresentationOnlyGlyph() async throws {
        let html = "<html lang='en'><head><style>body {margin:0; font-family:Georgia;font-size:20px} p {margin:0;hyphens:auto}</style></head><body><p>Extraordinary imagination illuminates extraordinary possibilities.</p></body></html>"
        var metrics = LayoutMetrics()
        let styled = try CurrentCSSFrontend().buildStyleTree(html: html, cssTexts: [], config: BrowserLayoutConfig(), metrics: &metrics)
        let paragraph = try #require(nodes(styled.rootNode).first { $0.tag == "p" })
        print("ENGLISH_STYLE", paragraph.style.language as Any, paragraph.style.hyphens)
        let attr = NSAttributedString(string: "Extraordinary imagination illuminates extraordinary possibilities.", attributes: InlineLayout.textAttributes(for: paragraph.style))
        let breaks = CoreTextLineBreaker().breakLines(attributed: attr, maxWidth:180)
        for line in breaks { print("ENGLISH_BREAK", line.range, line.width, line.presentation?.string as Any, line.generatedHyphen) }
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(html, width:180)
        #expect(!doc.lastSourceText.contains("-"))
        let fragments = BrowserLayoutTestSupport.allTextFragments(pages)
        // A generated hyphen has a glyph, but consumes no additional source character.
        #expect(fragments.contains { fragment in
            if case .linear(let range) = fragment.sourceMapping { return range.length > fragment.sourceRange.length }
            return false
        })
    }

    @Test func authoredMinimumHeightPreservesChapterHeadingSpace() async throws {
        let (pages, _) = try await BrowserLayoutTestSupport.layout("<style>body {margin:0} .heading {min-height:12em;margin-bottom:2em} p {margin:0}</style><div class='heading'>Title</div><p>Text</p>", width:300, height:600, rootFontSize:20)
        let text = try #require(BrowserLayoutTestSupport.allTextFragments(pages).last)
        #expect(abs(text.rect.minY - 280) < 0.01)
    }
    @Test func lineHeightInheritanceKeepsValueKinds() throws {
        for (value, expected) in [("1.5", CGFloat(15)), ("150%", 30), ("1.5em",30), ("30px",30), ("22.5pt",30)] {
            let root = try tree("body {font-size:20px;line-height:\(value)} p {font-size:10px}", "<p>A</p>")
            #expect(nodes(root).last?.style.lineHeight == expected)
        }
    }
    @Test func invalidIndentDoesNotEraseAuthoredValue() throws {
        let root = try tree("p {text-indent:24px;text-indent:banana} p {text-indent:invalid}", "<p>A</p>")
        #expect(nodes(root).last?.style.textIndent == .length(.px(24)))
        #expect(CSSTextIndent.declaration("1em hanging") == .unsupported)
        #expect(CSSTextIndent.declaration("banana") == nil)
    }
    @Test func mixedInlineIndentAndNegativeAvailableWidth() async throws {
        let input = "<style>body {margin:0;font-size:20px} p {margin:0;text-indent:-20px;line-height:24px}</style><p><em>Alpha</em> beta gamma delta epsilon zeta eta theta iota kappa lambda mu.</p>"
        let doc = BrowserLayoutDocument(html: input, cssTexts: [], config: BrowserLayoutConfig(renderWidth:120, renderHeight:48, rootFontSize:20))
        let layout = try doc.makeLayout(containerSize: CGSize(width:120,height:48))
        func boxes(_ box: BlockBox) -> [BlockBox] { [box] + box.children.flatMap(boxes) }
        let paragraph = try #require(boxes(layout.rootBox).first { $0.lines.count > 1 })
        #expect(paragraph.lines.first?.contentX == -20)
        #expect(paragraph.lines.dropFirst().allSatisfy { $0.contentX == 0 })
        let pages = try await doc.renderPages(containerSize: CGSize(width:120,height:48))
        #expect(pages.count > 1)
        #expect(BrowserLayoutTestSupport.allTextFragments(Array(pages.dropFirst())).allSatisfy { $0.rect.minX >= 0 })
    }
    @Test func languageAndSoftHyphenPolicy() throws {
        let text = "representation representation"
        func lines(_ value: String, _ policy: String, language: String?) -> [CoreTextLineBreaker.LineBreak] {
            var style = ComputedStyle(fontSize:20,fontFamilies:["Georgia"])
            style.hyphens = policy; style.language = language
            return CoreTextLineBreaker().breakLines(attributed:NSAttributedString(string:value,attributes:InlineLayout.textAttributes(for:style)),maxWidth:95)
        }
        #expect(lines(text,"auto",language:nil).allSatisfy { !$0.generatedHyphen })
        #expect(lines(text,"none",language:"en").allSatisfy { !$0.generatedHyphen })
        let manual = lines("repre\u{00AD}sentation", "manual", language:"en")
        #expect(manual.first?.presentation?.string == "repre-")
        #expect(manual.first?.range == NSRange(location:0,length:6))
        #expect(manual.first?.generatedHyphen == false)
        #expect(lines("repre\u{00AD}sentation", "none", language:"en").count == 1)
        let root = try tree("", "<p lang='de'>A<span lang=''>B</span></p>", root:"xml:lang='en'")
        let elements = nodes(root)
        #expect(elements.first?.style.language == "en")
        #expect(elements.first { $0.tag == "p" }?.style.language == "de")
        #expect(elements.last?.style.language == nil)
    }
    @Test func firstLetterFloatPreservesCharactersAndFollowingFont() async throws {
        let html = "<style>body {margin:0;font-size:20px} p {margin:0;line-height:24px} p:first-letter {font-size:320%;float:left;line-height:0.7;margin:-0.3225em 0.05em -0.3245em 0;color:red}</style><p>“Z<em>ebra walks through the garden.</em></p><p>Following paragraph.</p>"
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(html,width:260,rootFontSize:20)
        #expect(doc.lastSourceText == "“Zebra walks through the garden.Following paragraph.")
        let fragments = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(fragments.contains { $0.font.pointSize == 64 && $0.sourceRange == NSRange(location:0,length:2) })
        #expect(fragments.last?.font.pointSize == 20)
    }

    @Test func authoredOrderAndDarkRulesDoNotLeak() throws {
        let html = "<html><head><style>p{color:red}</style><link rel='stylesheet' href='last.css'></head><body><p>A</p></body></html>"
        let sheets = [
            AuthorStylesheet(source:.inline(nodeOrdinal:0),text:"p{color:red}",sourceOrder:0,currentCompatibilityOrder:nil,currentCompatibilityOnly:false,media:nil,isAlternate:false),
            AuthorStylesheet(source:.linked(href:"last.css"),text:"p{color:blue} @media(prefers-color-scheme:dark) {p{color:red}}",sourceOrder:1,currentCompatibilityOrder:nil,currentCompatibilityOnly:false,media:nil,isAlternate:false)
        ]
        var metrics = LayoutMetrics()
        let result = try CurrentCSSFrontend().buildStyleTree(input:CSSFrontendInput(html:html,stylesheets:sheets),config:BrowserLayoutConfig(),metrics:&metrics)
        #expect(nodes(result.rootNode).last?.style.color == .blue)
    }
    @Test @MainActor func lastLineAlignmentAndHyphenDrawingUsePresentation() async throws {
        let html = "<html lang='en'><body><p>Extraordinary imagination illuminates extraordinary possibilities.</p></body></html>"
        let css = ["body{margin:0;font-family:Georgia;font-size:20px} p{margin:0;hyphens:auto;text-align:justify;text-align-last:right}"]
        let doc = HTMLLayoutDocument(html:html,css:css,configuration:BrowserLayoutConfig(renderWidth:180,renderHeight:400))
        let session = try doc.makePageSession(); try await session.finish()
        let list = DisplayListBuilder.build(for:try #require(session.completedPages.first),sourceText:session.sourceText)
        let texts = list.items.compactMap { if case .text(let text) = $0 { return text }; return nil }
        #expect(texts.contains { $0.attributedText.string.hasSuffix("-") && !$0.text.hasSuffix("-") })
        let last = try #require(texts.last)
        #expect(abs(last.rect.maxX - 180) < 0.01)
        #expect(!session.sourceText.contains("-"))
        for text in texts {
            #expect(NSMaxRange(text.sourceRange) <= (session.sourceText as NSString).length)
            let hit = list.sourceRange(at:CGPoint(x:text.rect.rawValue.midX,y:text.rect.rawValue.midY),sourceText:session.sourceText)
            #expect(hit != nil)
        }
    }

    @Test func overflowingWordRetainsFollowingSourceWhitespace() async throws {
        let text = "Oversized indent still emits every source unit in order."
        let (pages, document) = try await BrowserLayoutTestSupport.layout(
            "<style>body{margin:0}p{margin:0;text-indent:500px}</style><p>\(text)</p>", width:200)
        let ns = document.lastSourceText as NSString
        let fragments = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(fragments.map { ns.substring(with:$0.sourceRange) }.joined() == text)
    }

    @Test func diagnosticsTraceTheProductionCascadeWithoutChapterText() throws {
        var events: [CSSFrontendDiagnostic] = []
        let document = BrowserLayoutDocument(html:"<p id='trace'>Private chapter sentence.</p>",
            cssTexts:["p{font-size:20px;text-indent:12pt} p:hover{color:red}"],
            config:BrowserLayoutConfig(onDiagnostic:{events.append($0)}))
        _ = try document.makeLayout(containerSize:CGSize(width:200,height:200))
        #expect(events.contains { $0.message.contains("matched selector=p") && $0.stylesheet != nil })
        #expect(events.contains { $0.message.contains("unsupported selector=p:hover") })
        #expect(events.contains { $0.message.contains("layoutNode=") && $0.semanticPath?.contains("p[") == true })
        #expect(events.contains { $0.message.contains("baseline=") && $0.message.contains("source=") })
        #expect(events.allSatisfy { !$0.message.contains("Private chapter sentence") })
    }

    @Test func nonbreakingSpaceAndEmergencyWrappingRemainDistinct() throws {
        var style = ComputedStyle(fontSize:20,fontFamilies:["Georgia"])
        style.hyphens = "none"
        let text = "Alpha\u{00A0}Beta gamma—delta co-operate"
        let attributed = NSAttributedString(string:text,attributes:InlineLayout.textAttributes(for:style))
        let lines = CoreTextLineBreaker().breakLines(attributed:attributed,maxWidth:130)
        #expect(lines.dropLast().allSatisfy { ![5,6].contains(NSMaxRange($0.range)) })
        #expect(lines.map { (text as NSString).substring(with:$0.range) }.joined() == text)
        let long = "representation"
        let normal = CoreTextLineBreaker().breakLines(attributed:NSAttributedString(string:long,attributes:InlineLayout.textAttributes(for:style)),maxWidth:70)
        style.overflowWrap = "anywhere"
        let emergency = CoreTextLineBreaker().breakLines(attributed:NSAttributedString(string:long,attributes:InlineLayout.textAttributes(for:style)),maxWidth:70)
        #expect(normal.count == 1)
        #expect(emergency.count > 1)
        #expect(emergency.allSatisfy { !$0.generatedHyphen })
    }

}
