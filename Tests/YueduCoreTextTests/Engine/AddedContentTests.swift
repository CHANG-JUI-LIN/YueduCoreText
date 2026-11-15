import Testing
import UIKit
@testable import YueduCoreText

/// Pictures a client adds to a chapter (`BrowserAddedContent`): a comment badge at the end of a
/// paragraph, a card under one, cards after the chapter. They are drawn, can be tapped, and own
/// no character of the chapter, so every stored position means the same place with them and
/// without them; and a page of nothing but such pictures still has a position of its own.
@Suite("Pictures a client adds to a chapter")
@MainActor
struct AddedContentTests {
    private static let width: CGFloat = 300
    private static let height: CGFloat = 400
    private static let mark = BrowserAddedContent.attributeName

    private struct Laid {
        let pages: [PageFragments]
        let sourceText: String
        let pictureOffsets: BrowserPictureOffsets
    }

    private func layout(_ body: String, picture: CGSize = CGSize(width: 300, height: 120)) async throws -> Laid {
        let image = BrowserLayoutTestSupport.makeImage(size: picture, color: .gray)
        let config = BrowserLayoutConfig(
            renderWidth: Self.width, renderHeight: Self.height, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let doc = HTMLLayoutDocument(input: .currentCompatibility(html: "<html><body>\(body)</body></html>", cssTexts: []),
                                     configuration: config, imageLoader: { _ in image })
        let session = try doc.makePageSession()
        try await session.finish()
        return Laid(pages: session.completedPages, sourceText: session.sourceText, pictureOffsets: session.pictureOffsets)
    }

    private func badge(_ href: String = "comments://p") -> String {
        "<a href=\"\(href)\"><img src=\"badge\" \(Self.mark) style=\"width:1em;height:0.8em\"/></a>"
    }

    private func card(_ href: String = "comments://c", height: Int = 120) -> String {
        "<a href=\"\(href)\" style=\"display:block\"><img src=\"card\" \(Self.mark) style=\"display:block;width:100%;height:\(height)px\"/></a>"
    }

    private func added(on page: PageFragments) -> [ImageFragment] {
        BrowserLayoutTestSupport.allImageFragments([page]).filter(\.isAddedContent)
    }

    /// Every page is found again by its own position — its range's location, and for a page of
    /// nothing but added pictures the picture it starts with — and walking the positions
    /// forward and back passes every page once, as a page turn does.
    private func expectEveryPageHasItsOwnPosition(_ laid: Laid, sourceLocation: SourceLocation = #_sourceLocation) {
        let ranges = BrowserPageGeometry.buildPageRanges(laid.pages, sourceText: laid.sourceText)
        let starts = BrowserPageGeometry.buildPageAddedStarts(laid.pages, sourceText: laid.sourceText)
        func page(at index: Int) -> Int {
            BrowserPageGeometry.pageIndex(forCharOffset: ranges[index].location, addedIndex: starts[index], ranges: ranges,
                                          addedStarts: starts, sourceText: laid.sourceText)
        }
        for index in ranges.indices {
            #expect(page(at: index) == index, "page \(index) at \(ranges[index]) added \(String(describing: starts[index])) resolves to page \(page(at: index)); ranges \(ranges) starts \(starts)",
                    sourceLocation: sourceLocation)
        }
        // The page turn's walk: the page of a position, then the position of the page beside it.
        var forward = [0]
        while let last = forward.last, last + 1 < ranges.count, forward.count <= ranges.count {
            forward.append(page(at: page(at: last) + 1))
        }
        #expect(forward == Array(ranges.indices), "forward \(forward)", sourceLocation: sourceLocation)
        var backward = [ranges.count - 1]
        while let last = backward.last, last > 0, backward.count <= ranges.count {
            backward.append(page(at: page(at: last) - 1))
        }
        #expect(backward == Array(ranges.indices.reversed()), "backward \(backward)", sourceLocation: sourceLocation)
    }

    private static let chapter = """
    <h1>第三章&nbsp;風起</h1>
    <p>風，起了。<br/>他<ruby>推<rt>tuī</rt></ruby>開門 &amp; 走進長夜。</p>
    <p><img src="map"/>地圖之後還有一段。</p>
    <p>最後一段。</p>
    """

    @Test("the chapter's text, its offsets and its pictures' offsets are what they are without the added pictures")
    func sourceIsUntouched() async throws {
        let plain = try await layout(Self.chapter)
        let decorated = try await layout("""
        <h1>第三章&nbsp;風起</h1>
        <p>風，起了。<br/>他<ruby>推<rt>tuī</rt></ruby>開門 &amp; 走進長夜。\(badge())</p>\(card())
        <p><img src="map"/>地圖之後還有一段。\(badge())</p>
        <p>最後一段。</p>\(card())\(card())
        """)
        #expect(decorated.sourceText == plain.sourceText)
        #expect(decorated.pictureOffsets == plain.pictureOffsets, "an added picture is no picture of the book")
        #expect(plain.pictureOffsets.offsets.count == 1)
        let drawn = decorated.pages.flatMap(added)
        #expect(drawn.count == 5, "two badges and three cards are drawn: \(drawn.map(\.source))")
        #expect(drawn.allSatisfy { $0.sourceRange.length == 0 && $0.linkTarget != nil })
        #expect(plain.pages.flatMap(added).isEmpty, "a picture of the book is never taken for an added one")
    }

    @Test("a badge sits at the end of its paragraph's last line and takes no line of its own")
    func badgeEndsItsParagraph() async throws {
        let plain = try await layout("<p>風，起了。</p><p>他推開門。</p>")
        let decorated = try await layout("<p>風，起了。\(badge())</p><p>他推開門。</p>")
        let texts = BrowserLayoutTestSupport.allTextFragments(decorated.pages)
        let badge = try #require(decorated.pages.flatMap(added).first)
        let first = try #require(texts.first)
        #expect(badge.rect.rawValue.minX >= first.rect.rawValue.maxX - 0.5, "after the paragraph's last character")
        #expect(abs(badge.rect.rawValue.maxY - first.rect.rawValue.maxY) < first.rect.rawValue.height, "on its line")
        #expect(badge.sourceRange.location == ("風，起了。" as NSString).length, "before the next paragraph's first character")
        let plainTexts = BrowserLayoutTestSupport.allTextFragments(plain.pages)
        #expect(texts.map(\.sourceRange) == plainTexts.map(\.sourceRange))
    }

    @Test("a card alone on a page between two pages of text has a position of its own")
    func cardAloneBetweenText() async throws {
        // A page of text, a card as tall as a page, a page of text.
        let paragraph = String(repeating: "風起了。", count: 60)
        let laid = try await layout("<p>\(paragraph)</p>\(card(height: 380))<p>\(paragraph)</p>")
        let ranges = BrowserPageGeometry.buildPageRanges(laid.pages, sourceText: laid.sourceText)
        let starts = BrowserPageGeometry.buildPageAddedStarts(laid.pages, sourceText: laid.sourceText)
        let alone = try #require(starts.firstIndex { $0 != nil }, "no page of the card alone: ranges \(ranges)")
        #expect(starts[alone] == 0 && ranges[alone].length == 0)
        #expect(alone + 1 < ranges.count && ranges[alone + 1].location == ranges[alone].location,
                "the page after it starts at the same character: that is why it needs the card to be found by")
        #expect(BrowserPageGeometry.pageIndex(forCharOffset: ranges[alone].location, ranges: ranges, sourceText: laid.sourceText) == alone + 1,
                "the character alone is the text's page")
        expectEveryPageHasItsOwnPosition(laid)
    }

    @Test("cards after the chapter that take pages of their own each have a position")
    func trailingCardsOnTheirOwnPages() async throws {
        let paragraph = String(repeating: "風起了。", count: 60)
        let laid = try await layout("<p>\(paragraph)</p>\(card(height: 380))\(card(height: 380))\(card(height: 380))")
        let ranges = BrowserPageGeometry.buildPageRanges(laid.pages, sourceText: laid.sourceText)
        let starts = BrowserPageGeometry.buildPageAddedStarts(laid.pages, sourceText: laid.sourceText)
        let alone = starts.compactMap { $0 }
        #expect(alone.count >= 2, "the cards did not take pages of their own: ranges \(ranges) starts \(starts)")
        #expect(alone == alone.sorted() && Set(alone).count == alone.count, "each by the card it starts with: \(alone)")
        let end = (laid.sourceText as NSString).length
        #expect(BrowserPageGeometry.pageIndex(forCharOffset: end, ranges: ranges, sourceText: laid.sourceText) == ranges.count - 1,
                "the chapter's end is its last page")
        expectEveryPageHasItsOwnPosition(laid)
        // The cards gone (comments turned off): the same positions land on the chapter's text.
        let plain = try await layout("<p>\(paragraph)</p>")
        let plainRanges = BrowserPageGeometry.buildPageRanges(plain.pages, sourceText: plain.sourceText)
        let plainStarts = BrowserPageGeometry.buildPageAddedStarts(plain.pages, sourceText: plain.sourceText)
        #expect(plainStarts.allSatisfy { $0 == nil })
        #expect(BrowserPageGeometry.pageIndex(forCharOffset: end, addedIndex: 2, ranges: plainRanges, addedStarts: plainStarts,
                                              sourceText: plain.sourceText) == plainRanges.count - 1)
    }

    @Test("a page with text and added pictures is found by its text, as it is without them")
    func mixedPagesKeepTheirPositions() async throws {
        let plain = try await layout("<p>風，起了。</p><p>他推開門。</p>")
        let decorated = try await layout("<p>風，起了。\(badge())</p>\(card())<p>他推開門。\(badge())</p>\(card())")
        #expect(decorated.pages.count == 1 && plain.pages.count == 1)
        #expect(BrowserPageGeometry.buildPageRanges(decorated.pages, sourceText: decorated.sourceText)
                == BrowserPageGeometry.buildPageRanges(plain.pages, sourceText: plain.sourceText))
        #expect(BrowserPageGeometry.buildPageAddedStarts(decorated.pages, sourceText: decorated.sourceText) == [nil])
        expectEveryPageHasItsOwnPosition(decorated)
    }

    @Test("an added picture inside a link is tapped as its link")
    func addedPicturesAreTappable() async throws {
        let laid = try await layout("<p>風，起了。\(badge("comments://p/1"))</p>\(card("comments://c/1"))")
        let list = DisplayListBuilder.build(for: laid.pages[0], sourceText: laid.sourceText)
        let regions = LinkInteractionRegionSet.build(from: list, spineIndex: 0, anchors: [:])
        for picture in added(on: laid.pages[0]) {
            let centre = CGPoint(x: picture.rect.rawValue.midX, y: picture.rect.rawValue.midY)
            #expect(regions.hitTest(centre)?.href == picture.linkTarget, "\(picture.source) at \(centre)")
        }
        #expect(Set(added(on: laid.pages[0]).compactMap(\.linkTarget)) == ["comments://p/1", "comments://c/1"])
    }
}
