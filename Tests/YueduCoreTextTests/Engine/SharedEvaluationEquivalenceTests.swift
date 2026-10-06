import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// Admission and layout share one parse of a chapter. These tests hold that the
/// shared path judges exactly what the standalone scanner judged, and lays out
/// exactly what a fresh parse lays out.
struct SharedEvaluationEquivalenceTests {

    // MARK: - Admission facts

    private static var scanConfig: BrowserLayoutConfig { BrowserLayoutConfig(fontFamilies: ["PingFangSC-Regular"], isBold: false) }
    private static var layoutConfig: BrowserLayoutConfig {
        var config = BrowserLayoutConfig(renderWidth: 366, renderHeight: 776, rootFontSize: 19,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .darkGray, backgroundColor: .white)
        config.lineHeight = 1.5
        config.paragraphSpacing = 8
        config.isBold = true
        config.defaultTextAlignment = .justified
        return config
    }

    private static func expectSameVerdict(_ input: CSSFrontendInput, _ label: String,
                                          sourceLocation: SourceLocation = #_sourceLocation) {
        for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
            for (name, config) in [("scan", scanConfig), ("layout", layoutConfig)] {
                let reference = ReferenceCapabilityScanner.scan(input: input, writingMode: mode, configuration: config)
                let shared = BrowserLayoutCapabilityScanner.scan(input: input, writingMode: mode, configuration: config)
                #expect(shared == reference, Comment(rawValue: "\(label) mode=\(mode) config=\(name)"), sourceLocation: sourceLocation)
            }
        }
    }

    private static func input(_ html: String, css: [String] = []) -> CSSFrontendInput {
        .currentCompatibility(html: html, cssTexts: css)
    }

    @Test func rulesMatchingOnlyHeadElementsAreStillJudged() {
        // The cascade never styles <head>; the standalone scanner matched every element.
        Self.expectSameVerdict(Self.input(
            "<html><head><title>t</title></head><body><p>x</p></body></html>",
            css: ["title { display: flex }"]), "head-only rule")
        let verdict = BrowserLayoutCapabilityScanner.scan(input: Self.input(
            "<html><head><title>t</title></head><body><p>x</p></body></html>",
            css: ["title { display: flex }"]))
        #expect(verdict.unsupportedFeatures == [.unknownBlockDisplay])
    }

    @Test func rulesMatchingOnlyHiddenDescendantsAreStillJudged() {
        let html = """
        <html><body><div style="display:none"><p class="deep">hidden</p></div>
        <section hidden><span class="attr">x</span></section><p>visible</p></body></html>
        """
        Self.expectSameVerdict(Self.input(html, css: [".deep { position: absolute }"]), "hidden descendant rule")
        Self.expectSameVerdict(Self.input(html, css: [".attr { flex: 1 }"]), "hidden-attribute descendant rule")
        let verdict = BrowserLayoutCapabilityScanner.scan(input: Self.input(html, css: [".deep { position: absolute }", ".attr { gap: 1px }"]))
        #expect(verdict.unsupportedFeatures == [.positioned, .flexGrid])
    }

    @Test func inlineStylesInsideHiddenSubtreesAreJudged() {
        let html = "<html><body><div style=\"display:none\"><p style=\"position: fixed\">x</p></div><p>y</p></body></html>"
        Self.expectSameVerdict(Self.input(html), "inline style in hidden subtree")
        #expect(BrowserLayoutCapabilityScanner.scan(input: Self.input(html)).unsupportedFeatures == [.positioned])
    }

    @Test func unmatchedRulesAreIgnored() {
        let html = "<html><body><p>plain</p></body></html>"
        Self.expectSameVerdict(Self.input(html, css: ["table { display: table } .x { position: absolute }"]), "unmatched rules")
        #expect(BrowserLayoutCapabilityScanner.scan(input: Self.input(html, css: [".x { position: absolute }"])).supported)
    }

    @Test func darkMediaAndFirstLetterRulesAreNotJudged() {
        let html = "<html><body><p class=\"lead\">Drop cap paragraph text.</p></body></html>"
        let css = """
        @media (prefers-color-scheme: dark) { .lead { display: grid } }
        .lead::first-letter { float: left; font-size: 300% }
        """
        Self.expectSameVerdict(Self.input(html, css: [css]), "dark media + first-letter")
        // The @media text itself is reported; the dark block's grid and the drop cap's float are not.
        #expect(BrowserLayoutCapabilityScanner.scan(input: Self.input(html, css: [css])).unsupportedFeatures == [.mediaQueries])
    }

    @Test func importantDeclarationsAndOrderAreJudged() {
        let html = "<html><body><p class=\"a\">x</p><p class=\"b\">y</p></body></html>"
        let css = ".b { width: calc(100% - 2em) } .a { position: sticky !important; display: table }"
        Self.expectSameVerdict(Self.input(html, css: [css]), "important + order")
        // Rule order, then declaration order within a rule, normal before important.
        #expect(BrowserLayoutCapabilityScanner.scan(input: Self.input(html, css: [css])).unsupportedFeatures
                == [.calcOrModernFunctions, .unknownBlockDisplay, .positioned])
    }

    @Test func mediaQueriesInInlineSheetsAreJudgedUnderAuthoredOrder() {
        let html = "<html><head><style>@media print { p { margin: 0 } }</style></head><body><p>x</p></body></html>"
        let authored = CSSFrontendInput(html: html, stylesheets: [
            AuthorStylesheet(source: .inline(nodeOrdinal: 0), text: "p { margin: 0 }", sourceOrder: 0,
                             currentCompatibilityOrder: nil, currentCompatibilityOnly: false, media: nil, isAlternate: false)
        ])
        Self.expectSameVerdict(authored, "authored order inline media")
        Self.expectSameVerdict(Self.input(html), "compatibility inline media")
        #expect(BrowserLayoutCapabilityScanner.scan(input: authored).unsupportedFeatures == [.mediaQueries])
    }

    @Test func domFeaturesRubyFloatsAndTextIndentAgree() {
        let html = """
        <html><body>
        <p style="text-indent: 2em">indented</p>
        <img src="a.png" style="float: left; width: 40%">
        <div class="wrap">floated block</div>
        <ruby>漢<rt>kan</rt></ruby>
        <svg><image href="b.png"/></svg>
        <table><tr><td>cell</td></tr></table>
        <math><mi>x</mi></math><script>1</script>
        </body></html>
        """
        Self.expectSameVerdict(Self.input(html, css: [".wrap { float: right }", "p { text-indent: 1em }"]), "dom features")
    }

    @Test func fontRequestsFollowTheCascadeConfiguration() {
        let html = "<html><body><p><em>a</em><strong>b</strong></p><p style=\"font-family: Serif\">c</p></body></html>"
        Self.expectSameVerdict(Self.input(html, css: ["p { font-family: 'Noto Sans' }"]), "font requests")
    }

    @Test func markupWithoutParseableBodyStillJudgesSheets() {
        Self.expectSameVerdict(Self.input("", css: ["@media screen { p { margin: 0 } }"]), "empty markup")
    }

    @Test func verticalModeDeclarationsAgree() {
        let html = "<html><body><p class=\"v\">縦</p></body></html>"
        Self.expectSameVerdict(Self.input(html, css: [".v { -epub-writing-mode: vertical-rl; text-combine-upright: all; min-height: 2em }"]), "vertical declarations")
        Self.expectSameVerdict(Self.input(html, css: [".v { writing-mode: horizontal-tb }"]), "vertical override")
    }

    /// Real chapters dumped by the app (`YUEDU_FRONTEND_INPUT_DIR`), when present.
    @Test func dumpedChaptersAgree() throws {
        guard let dir = ProcessInfo.processInfo.environment["YUEDU_FRONTEND_INPUT_DIR"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted()
        #expect(!files.isEmpty)
        for file in files {
            let (id, input) = try FrontendStageProbeTests.load(URL(fileURLWithPath: dir).appendingPathComponent(file))
            Self.expectSameVerdict(input, id)
        }
    }

    // MARK: - Layout from the shared style tree

    private static func digest(_ items: [DisplayItem]) -> [String] {
        items.map { item in
            switch item {
            case .text(let t):
                return "t \(t.nodeID) \(t.sourceRange) \(t.rect.rawValue) \(t.font.pointSize) \(t.text)"
            case .fill(let f):
                return "f \(f.nodeID) \(f.rect.rawValue)"
            case .image(let i):
                return "i \(i.nodeID) \(i.rect.rawValue) \(i.source)"
            }
        }
    }

    private static func expectSameLayout(_ input: CSSFrontendInput, _ label: String,
                                         sourceLocation: SourceLocation = #_sourceLocation) throws {
        let config = layoutConfig
        let fresh = try HTMLLayoutDocument(input: input, configuration: config)
            .prepareContinuous(validateCapabilities: false).makeDocument()
        let evaluation = try BrowserChapterDocument(input: input).evaluate(configuration: config)
        let shared = try HTMLLayoutDocument(evaluation: evaluation)
            .prepareContinuous(validateCapabilities: false).makeDocument()
        #expect(shared.contentHeight == fresh.contentHeight, Comment(rawValue: label), sourceLocation: sourceLocation)
        #expect(shared.sourceText == fresh.sourceText, Comment(rawValue: label), sourceLocation: sourceLocation)
        #expect(shared.anchorOffsets == fresh.anchorOffsets, Comment(rawValue: label), sourceLocation: sourceLocation)
        #expect(digest(shared.displayList.items) == digest(fresh.displayList.items), Comment(rawValue: label), sourceLocation: sourceLocation)
        #expect(!shared.displayList.items.isEmpty, Comment(rawValue: label), sourceLocation: sourceLocation)
    }

    @Test func layoutFromEvaluationMatchesFreshParse() throws {
        let html = """
        <html><head><style>p { margin: 0 0 1em; text-indent: 2em } .note { font-size: 0.8em }</style></head>
        <body><h1 id="top">Title</h1><p>First paragraph with <em>emphasis</em> and a <a href="#n1">link</a>.</p>
        <p class="note">Second paragraph.</p><aside epub:type="footnote" id="n1">Note body</aside></body></html>
        """
        try Self.expectSameLayout(Self.input(html), "synthetic chapter")
    }

    @Test func dumpedChaptersLayOutTheSame() throws {
        guard let dir = ProcessInfo.processInfo.environment["YUEDU_FRONTEND_INPUT_DIR"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted()
        for file in files {
            let (id, input) = try FrontendStageProbeTests.load(URL(fileURLWithPath: dir).appendingPathComponent(file))
            let config = Self.layoutConfig
            let evaluation = try BrowserChapterDocument(input: input).evaluate(configuration: config)
            guard evaluation.capabilities.supported else { continue }
            try Self.expectSameLayout(input, id)
        }
    }

    @Test func layoutRejectsChangedCascadeInputs() throws {
        let input = Self.input("<html><body><p>x</p></body></html>")
        let evaluation = try BrowserChapterDocument(input: input).evaluate(configuration: Self.layoutConfig)
        var geometryOnly = Self.layoutConfig
        geometryOnly.renderWidth = 500
        geometryOnly.fontResolver = { _, _, _, _ in nil }
        #expect(evaluation.accepts(geometryOnly))
        var changedFont = Self.layoutConfig
        changedFont.rootFontSize = 23
        #expect(!evaluation.accepts(changedFont))
    }

    @Test func evaluationMetricsCarryTheParseStages() throws {
        let input = Self.input("<html><body><p>x</p></body></html>")
        let evaluation = try BrowserChapterDocument(input: input).evaluate(configuration: Self.layoutConfig)
        let stages = evaluation.preparedFrontend?.stages ?? [:]
        for stage in ["htmlParse", "cssCollect", "cssParse", "styleTree"] {
            #expect(stages[stage] != nil, "missing \(stage)")
        }
        let session = try BrowserLayoutDocument(input: input, config: Self.layoutConfig,
                                                preparedFrontend: evaluation.preparedFrontend)
        var metrics = LayoutMetrics()
        _ = try session.makeLayout(containerSize: CGSize(width: 390, height: 800), metrics: &metrics)
        for stage in ["htmlParse", "cssParse", "styleTree", "boxTree", "layout"] {
            #expect(metrics.stages[stage] != nil, "missing \(stage) in pipeline metrics")
        }
    }
}
