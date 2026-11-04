import Testing
import UIKit
@testable import YueduCoreText

struct BrowserLayoutRubySubsetTests {
    private func tree(
        _ body: String,
        css: [String] = [],
        writingMode: ReaderWritingMode = .horizontal
    ) throws -> ComputedStyleNode {
        var metrics = LayoutMetrics()
        return try LegacyCSSFrontend().buildStyleTree(
            html: "<html><body>\(body)</body></html>",
            cssTexts: css,
            config: BrowserLayoutConfig(writingMode: writingMode),
            metrics: &metrics
        ).rootNode
    }

    @Test func acceptsCensusRubyShapes() throws {
        for body in [
            "<p><ruby>漢<rt>かん</rt></ruby></p>",
            "<p><ruby><span>漢字</span><rt>かんじ</rt></ruby></p>",
            "<p><ruby>漢<rt><span>かん</span></rt></ruby></p>",
            "<p><ruby>漢<rp>(</rp><rt>かん</rt><rp>)</rp></ruby></p>",
            "<p><ruby style='ruby-position:under'>漢<rt>かん</rt></ruby></p>",
            "<p><ruby style='-webkit-ruby-position:after'>漢<rt>かん</rt></ruby></p>",
            "<p><ruby style='ruby-position:under'><ruby style='ruby-position:over'>漢字<rt>かんじ</rt></ruby><rt>カンジ</rt></ruby></p>",
            "<p><ruby><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby> <rt>ママ</rt></ruby></p>",
            "<p><ruby>外<ruby>內<rt>n</rt></ruby><rt>w</rt></ruby></p>",
            "<p><ruby><span><ruby>來<rt>き</rt></ruby>た</span><rt>北</rt></ruby></p>",
            "<p><ruby><ruby>萬<rt>m</rt></ruby>更<ruby>椽<rt>m</rt></ruby><rt>w</rt></ruby></p>",
        ] {
            let root = try tree(body)
            #expect(HorizontalRubySupport.validate(root).isSupported)
        }
    }

    @Test func resolvesRubyComputedValuesThroughCascade() throws {
        let root = try tree(
            "<p><ruby class='r'>漢<rt>かん</rt></ruby></p>",
            css: ["ruby.r { ruby-align:center; ruby-position:over }"]
        )
        let ruby = try #require(HorizontalRubySupport.rubyNodes(in: root).first)
        #expect(ruby.style.rubyAlign == .center)
        #expect(ruby.style.rubyPosition == .over)
        let rt = try #require(ruby.children.compactMap(\.rubyElement).first { $0.tag == "rt" })
        #expect(abs(rt.style.fontSize - ruby.style.fontSize * 0.5) < 0.01)
    }

    @Test func rejectsRubyOutsidePhase4DSubset() throws {
        let rejected = [
            "<p><ruby>漢</ruby></p>",
            "<p><ruby>漢<rt>a</rt><rt>b</rt></ruby></p>",
            "<p><ruby>漢<rtc><rt>a</rt></rtc></ruby></p>",
            "<p><ruby><ruby>內<rt>n</rt>字<rt>z</rt></ruby><rt>w</rt></ruby></p>",
            "<p><ruby><ruby><ruby>內<rt>n</rt></ruby><rt>m</rt></ruby><rt>w</rt></ruby></p>",
            "<p><ruby><ruby>內<rt>n</rt></ruby><rt>w</rt><rt>x</rt></ruby></p>",
            "<p><ruby><ruby>內<rtc><rt>n</rt></rtc></ruby><rt>w</rt></ruby></p>",
            "<p><ruby><span style='display:block'>漢</span><rt>a</rt></ruby></p>",
            "<p><ruby>漢<rt><span style='display:block'>a</span></rt></ruby></p>",
        ]
        for body in rejected {
            let root = try tree(body)
            #expect(!HorizontalRubySupport.validate(root).isSupported)
        }
        let verticalRoot = try tree(
            "<p><ruby>漢<rt>a</rt></ruby></p>",
            writingMode: .verticalRTL
        )
        #expect(HorizontalRubySupport.validate(
            verticalRoot,
            writingMode: .verticalRTL
        ).isSupported)
    }

    @Test func rejectsUnsupportedRubyCSSValues() throws {
        for css in [
            "ruby { ruby-align:start }",
            "ruby { ruby-align:space-between }",
            "ruby { ruby-position:inter-character }",
            "ruby { ruby-position:alternate }",
            "ruby { -webkit-ruby-position:inter-character }",
            "ruby { ruby-merge:collapse }",
        ] {
            let root = try tree("<p><ruby>漢<rt>a</rt></ruby></p>", css: [css])
            #expect(!HorizontalRubySupport.validate(root).isSupported)
        }
    }
}

struct BrowserLayoutRubyUnitTests {
    private func pipeline(_ body: String, css: [String] = []) throws
        -> BrowserLayoutDocument.BrowserLayoutPipelineResult {
        let doc = BrowserLayoutDocument(
            html: "<html><body>\(body)</body></html>",
            cssTexts: css,
            config: BrowserLayoutConfig(renderWidth: 300, renderHeight: 400)
        )
        return try doc.makeLayout(containerSize: CGSize(width: 300, height: 400))
    }

    @Test func sourceTextContainsBaseButNotAnnotationOrRP() throws {
        let result = try pipeline("<p>甲<ruby>漢<rp>(</rp><rt>かん</rt><rp>)</rp></ruby>乙</p>")
        #expect(result.sourceText == "甲漢乙")
        let units = BrowserLayoutRubyTestProbe.rubyUnits(in: result.rootBox)
        let unit = try #require(units.only)
        #expect(unit.base.map(\.text).joined() == "漢")
        #expect(unit.annotation.text == "かん")
        #expect((result.sourceText as NSString).substring(with: unit.sourceRange) == "漢")
    }

    @Test func inlineDescendantBaseRetainsStyleNodeAndRange() throws {
        let result = try pipeline(
            "<p><a href='note.xhtml'><ruby><span class='b'>漢字</span><rt>かんじ</rt></ruby></a></p>",
            css: ["span.b { font-weight:700 }"]
        )
        let unit = try #require(BrowserLayoutRubyTestProbe.rubyUnits(in: result.rootBox).only)
        let piece = try #require(unit.base.only)
        #expect(piece.text == "漢字")
        #expect(piece.style.fontWeight == 700)
        #expect(piece.nodeID > 0)
        #expect(piece.linkTarget == "note.xhtml")
        #expect(unit.linkTarget == "note.xhtml")
    }

    @Test func rubyAnchorMapsToBaseStart() throws {
        let result = try pipeline("<p>前<ruby id='r'>漢<rt>かん</rt></ruby>後</p>")
        #expect(result.anchorOffsets["r"] == 1)
    }

    @Test func inlineAnnotationDescendantRetainsStylePieces() throws {
        let result = try pipeline(
            "<p><ruby>漢<rt>a<a href='note.xhtml'><span class='annotation'>b</span></a></rt></ruby></p>",
            css: ["span.annotation { font-weight:700 }"]
        )
        let box = try #require(BrowserLayoutRubyTestProbe.rubyBoxes(in: result.rootBox).only)
        #expect(box.annotation.pieces.map(\.text) == ["a", "b"])
        #expect(box.annotation.pieces[1].style.fontWeight == 700)
        #expect(box.annotation.pieces[0].nodeID != box.annotation.pieces[1].nodeID)
        #expect(box.annotation.pieces[1].linkTarget == "note.xhtml")
        #expect(box.annotation.pieces.allSatisfy { $0.sourceRange == box.unit.sourceRange })
        let pages = PageFragmentation.fragment(
            box: result.rootBox,
            pageSize: CGSize(width: 300, height: 400)
        )
        let linkedAnnotation = BrowserLayoutTestSupport.allTextFragments(pages).first {
            $0.renderedTextOverride == "b"
        }
        #expect(linkedAnnotation?.linkTarget == "note.xhtml")
    }
}

struct BrowserLayoutRubyMeasurementTests {
    private func pipeline(_ body: String, width: CGFloat = 300) throws
        -> BrowserLayoutDocument.BrowserLayoutPipelineResult {
        let doc = BrowserLayoutDocument(
            html: "<html><body><p style='margin:0'>\(body)</p></body></html>",
            cssTexts: [],
            config: BrowserLayoutConfig(renderWidth: width, renderHeight: 400)
        )
        return try doc.makeLayout(containerSize: CGSize(width: width, height: 400))
    }

    @Test func rubyAdvanceContainsWiderSideAndCentersBoth() throws {
        for body in [
            "<ruby>漢字<rt>a</rt></ruby>",
            "<ruby>字<rt>long annotation</rt></ruby>",
        ] {
            let result = try pipeline(body)
            let box = try #require(BrowserLayoutRubyTestProbe.rubyBoxes(in: result.rootBox).only)
            #expect(abs(box.advance - max(box.base.width, box.annotation.width)) < 0.01)
            #expect(abs(box.baseOffsetX - (box.advance - box.base.width) / 2) < 0.01)
            #expect(abs(box.annotationOffsetX - (box.advance - box.annotation.width) / 2) < 0.01)
        }
    }

    @Test func annotationIncreasesAscentAndStaysAboveBase() throws {
        let ruby = try pipeline("<ruby>漢<rt>かん</rt></ruby>")
        let plain = try pipeline("漢")
        let rubyLine = try #require(BrowserLayoutRubyTestProbe.lines(in: ruby.rootBox).only)
        let plainLine = try #require(BrowserLayoutRubyTestProbe.lines(in: plain.rootBox).only)
        let box = try #require(rubyLine.runs.compactMap(\.ruby).only)
        // The line box: its baseline lower, for the annotation over it.
        #expect(rubyLine.baseline > plainLine.baseline)
        #expect(box.annotationBaselineOffset + box.annotation.descent <= -box.base.ascent + 0.01)
        #expect(box.descent == max(box.base.descent, box.inlineBoxDescent))
    }

    /// An annotation under the base hangs from its content box: the line's descent grows by the
    /// annotation's height, its ascent stays the base's inline box's.
    @Test func underAnnotationHangsBelowBase() throws {
        let ruby = try pipeline("<ruby style='ruby-position:under'>漢<rt>かん</rt></ruby>")
        let plain = try pipeline("漢")
        let rubyLine = try #require(BrowserLayoutRubyTestProbe.lines(in: ruby.rootBox).only)
        let plainLine = try #require(BrowserLayoutRubyTestProbe.lines(in: plain.rootBox).only)
        let box = try #require(rubyLine.runs.compactMap(\.ruby).only)
        // The line box: its baseline where a plain line's is, the line taller below it.
        #expect(abs(rubyLine.baseline - plainLine.baseline) < 0.01)
        #expect(rubyLine.height - rubyLine.baseline > plainLine.height - plainLine.baseline)
        #expect(box.ascent == max(box.base.ascent, box.inlineBoxAscent))
        #expect(abs(box.annotationBaselineOffset - (box.base.descent + box.annotation.ascent)) < 0.01)
        let hanging = box.base.descent + box.annotation.ascent + box.annotation.descent
        #expect(abs(box.descent - max(hanging, box.inlineBoxDescent)) < 0.01)
    }

    /// A nested ruby's inner annotation sits next to the base, its outer one on its own side,
    /// beyond the inner one when they share it; the widest of the three sets the advance and all
    /// are centred.
    @Test(arguments: [("over", "under"), ("under", "over"), ("over", "over"), ("under", "under")])
    func nestedRubyStacksEachSideOutward(sides: (inner: String, outer: String)) throws {
        let result = try pipeline(
            "<ruby style='ruby-position:\(sides.outer)'><ruby style='ruby-position:\(sides.inner)'>漢字<rt>かんじ</rt></ruby>"
                + "<rt>ながいカンジ</rt></ruby>")
        #expect(result.sourceText == "漢字")
        let box = try #require(BrowserLayoutRubyTestProbe.rubyBoxes(in: result.rootBox).only)
        let placed = try #require(box.inner.only)
        let outer = box.annotation, inner = placed.line
        #expect(inner.pieces.map(\.text).joined() == "かんじ" && outer.pieces.map(\.text).joined() == "ながいカンジ")
        let base = box.base
        let innerHeight = inner.ascent + inner.descent, outerHeight = outer.ascent + outer.descent
        let innerOffset = sides.inner == "over" ? -base.ascent - inner.descent : base.descent + inner.ascent
        #expect(abs(placed.baselineOffset - innerOffset) < 0.01)
        let beyond = sides.inner == sides.outer ? innerHeight : 0
        let outerOffset = sides.outer == "over"
            ? -base.ascent - beyond - outer.descent : base.descent + beyond + outer.ascent
        #expect(abs(box.annotationBaselineOffset - outerOffset) < 0.01)
        // Each side holds the base's inline box, then the outer annotation beyond it.
        let ascent = max(base.ascent + (sides.inner == "over" ? innerHeight : 0), box.inlineBoxAscent)
            + (sides.outer == "over" ? outerHeight : 0)
        let descent = max(base.descent + (sides.inner == "under" ? innerHeight : 0), box.inlineBoxDescent)
            + (sides.outer == "under" ? outerHeight : 0)
        #expect(abs(box.ascent - ascent) < 0.01)
        #expect(abs(box.descent - descent) < 0.01)
        #expect(abs(box.advance - outer.width) < 0.01)
        #expect(abs(box.annotationOffsetX) < 0.01)
        #expect(abs(box.baseOffsetX - (box.advance - base.width) / 2) < 0.01)
        #expect(abs(placed.offsetX - (box.advance - inner.width) / 2) < 0.01)
    }

    /// The reading spoken for a base is the annotation over it; a left one is often a gloss.
    @Test func readingIsTheAnnotationOverTheBase() throws {
        func reading(_ body: String) throws -> String {
            try #require(BrowserLayoutRubyTestProbe.rubyUnits(in: try pipeline(body).rootBox).only).reading.text
        }
        #expect(try reading("<ruby style='ruby-position:under'><ruby style='ruby-position:over'>刺<rt>し</rt></ruby><rt>テフダ</rt></ruby>") == "し")
        #expect(try reading("<ruby style='ruby-position:over'><ruby style='ruby-position:under'>刺<rt>テフダ</rt></ruby><rt>し</rt></ruby>") == "し")
        #expect(try reading("<ruby><ruby>刺<rt>し</rt></ruby><rt>ママ</rt></ruby>") == "し")
        #expect(try reading("<ruby style='ruby-position:under'>刺<rt>テフダ</rt></ruby>") == "テフダ")
        #expect(try reading("<ruby>辞<ruby>義<rt>ママ</rt></ruby><rt>じぎ</rt></ruby>") == "じぎ")
    }

    @Test func lineBreakerNeverSlicesRubyBaseOrAnnotation() throws {
        let result = try pipeline("AAAA <ruby>漢字<rt>very-wide-annotation</rt></ruby> BBBB", width: 95)
        let rubyRuns = BrowserLayoutRubyTestProbe.lines(in: result.rootBox)
            .flatMap(\.runs).filter { $0.ruby != nil }
        let run = try #require(rubyRuns.only)
        #expect(run.sourceRange.length == 2)
        #expect((result.sourceText as NSString).substring(with: run.sourceRange) == "漢字")
        #expect(run.width == run.ruby?.advance)
    }
}

struct BrowserLayoutRubyFragmentTests {
    @Test func emitsIndependentBaseAndAnnotationGeometry() async throws {
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            "<html><body><p style='margin:0'>甲<ruby>漢<rt>かん</rt></ruby>乙</p></body></html>"
        )
        #expect(doc.lastSourceText == "甲漢乙")
        let rubyGroup = try #require(BrowserLayoutRubyTestProbe.rubyGroups(in: pages).only)
        let texts = BrowserLayoutRubyTestProbe.texts(in: rubyGroup)
        let base = try #require(texts.first { $0.renderedTextOverride == nil })
        let annotation = try #require(texts.first { $0.renderedTextOverride == "かん" })
        #expect(annotation.rect.maxY <= base.rect.minY + 0.01)
        #expect(annotation.sourceRange == base.sourceRange)
        #expect(annotation.sourceMapping == .wholeRange)

        let list = DisplayListBuilder.build(for: pages[0], sourceText: doc.lastSourceText)
        let rendered = list.items.compactMap { item -> String? in
            guard case .text(let text) = item else { return nil }
            return text.text
        }
        #expect(rendered.contains("漢"))
        #expect(rendered.contains("かん"))
        #expect(BrowserLayoutTestSupport.visibleText(pages, sourceText: doc.lastSourceText) == "甲漢乙")
    }

    /// Both of a nested ruby's annotations are drawn on their sides, for the base's whole range,
    /// and neither enters the text.
    @Test func nestedRubyEmitsBothAnnotations() async throws {
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            "<html><body><p style='margin:0'>甲<ruby style='ruby-position:under'><ruby style='ruby-position:over'>漢<rt>かん</rt></ruby>"
                + "<rt>カン</rt></ruby>乙</p></body></html>"
        )
        #expect(doc.lastSourceText == "甲漢乙")
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        let base = try #require(texts.first { $0.renderedTextOverride == nil && $0.sourceRange == NSRange(location: 1, length: 1) })
        let over = try #require(texts.first { $0.renderedTextOverride == "かん" })
        let under = try #require(texts.first { $0.renderedTextOverride == "カン" })
        #expect(over.rect.maxY <= base.rect.minY + 0.01)
        #expect(under.rect.minY >= base.rect.maxY - 0.01)
        #expect(over.sourceRange == base.sourceRange && under.sourceRange == base.sourceRange)
        #expect(BrowserLayoutTestSupport.visibleText(pages, sourceText: doc.lastSourceText) == "甲漢乙")
        let list = DisplayListBuilder.build(for: pages[0], sourceText: doc.lastSourceText)
        let rendered = list.items.compactMap { item -> String? in
            guard case .text(let text) = item else { return nil }
            return text.text
        }
        #expect(rendered.contains("かん") && rendered.contains("カン"))
    }

    @Test func rubyChildrenNeverSplitAcrossPages() async throws {
        let lead = String(repeating: "前文 ", count: 12)
        let html = "<html><body><p style='margin:0'>\(lead)<ruby>漢字<rt>かんじ</rt></ruby>後文</p></body></html>"
        let (pages, _) = try await BrowserLayoutTestSupport.layout(html, width: 120, height: 45)
        let groupsByPage = pages.enumerated().flatMap { pageIndex, page in
            BrowserLayoutRubyTestProbe.rubyGroups(in: [page]).map { (pageIndex, $0) }
        }
        let pair = try #require(groupsByPage.only)
        let texts = BrowserLayoutRubyTestProbe.texts(in: pair.1)
        #expect(texts.count >= 2)
        #expect(texts.allSatisfy { $0.rect.minY >= pages[pair.0].pageRect.minY })
        #expect(texts.allSatisfy { $0.rect.maxY <= pages[pair.0].pageRect.maxY + 0.01 })
    }
}


enum BrowserLayoutRubyTestProbe {
    static func rubyUnits(in root: BlockBox) -> [RubyInlineUnit] {
        var result: [RubyInlineUnit] = []
        func walk(_ box: BlockBox) {
            result.append(contentsOf: box.inlineRuns.compactMap(\.ruby))
            box.children.forEach(walk)
        }
        walk(root)
        return result
    }

    static func lines(in root: BlockBox) -> [LayoutLine] {
        var result: [LayoutLine] = []
        func walk(_ box: BlockBox) {
            result.append(contentsOf: box.lines)
            box.children.forEach(walk)
        }
        walk(root)
        return result
    }

    static func rubyBoxes(in root: BlockBox) -> [RubyBox] {
        lines(in: root).flatMap(\.runs).compactMap(\.ruby)
    }

    static func rubyGroups(in pages: [PageFragments]) -> [[Fragment]] {
        var result: [[Fragment]] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                guard case .group(let children) = fragment else { continue }
                let annotationCount = texts(in: children).filter {
                    $0.sourceMapping == .wholeRange
                }.count
                if annotationCount == 1 { result.append(children) }
                walk(children)
            }
        }
        pages.forEach { walk($0.fragments) }
        return result
    }

    static func texts(in fragments: [Fragment]) -> [TextFragment] {
        var result: [TextFragment] = []
        func walk(_ input: [Fragment]) {
            for fragment in input {
                switch fragment {
                case .text(let text): result.append(text)
                case .group(let children): walk(children)
                case .fill, .image: break
                }
            }
        }
        walk(fragments)
        return result
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}

private extension StyleTreeChild {
    var rubyElement: ComputedStyleNode? {
        guard case .element(let node) = self else { return nil }
        return node
    }
}
