import Testing
import UIKit
@testable import YueduCoreText

/// 剑来's full-page maps: one picture per chapter, 8pt down under the body margin, and a
/// gallery chapter of pictures separated by white space. Each map was preceded by a blank
/// page, and every picture page reported the chapter's end as its position, so a page turn
/// resolved to the wrong page.
@Suite("Pages of pictures")
@MainActor
struct ImagePagePaginationTests {
    private static let width: CGFloat = 300
    private static let height: CGFloat = 400

    private func layout(_ body: String, css: [String] = [], picture: CGSize) async throws
        -> (pages: [PageFragments], sourceText: String) {
        let image = BrowserLayoutTestSupport.makeImage(size: picture, color: .gray)
        let config = BrowserLayoutConfig(
            renderWidth: Self.width, renderHeight: Self.height, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let doc = HTMLLayoutDocument(input: .currentCompatibility(html: "<html><body>\(body)</body></html>", cssTexts: css),
                                     configuration: config, imageLoader: { _ in image })
        let session = try doc.makePageSession()
        try await session.finish()
        return (session.completedPages, session.sourceText)
    }

    private func pictures(on page: PageFragments) -> [ImageFragment] {
        BrowserLayoutTestSupport.allImageFragments([page]).filter { !$0.isBackgroundPaint }
    }

    private func hasInk(_ page: PageFragments) -> Bool {
        !pictures(on: page).isEmpty || !BrowserLayoutTestSupport.allTextFragments([page]).isEmpty
    }

    /// Every page has a position of its own, and that position finds the page again —
    /// what a page turn, a restore and the reader's progress all resolve through.
    private func expectPositionsRoundTrip(_ pages: [PageFragments], sourceText: String,
                                          sourceLocation: SourceLocation = #_sourceLocation) {
        let ranges = BrowserPageGeometry.buildPageRanges(pages, sourceText: sourceText)
        for (index, range) in ranges.enumerated() {
            let resolved = BrowserPageGeometry.pageIndex(forCharOffset: range.location, ranges: ranges,
                                                         sourceText: sourceText)
            #expect(resolved == index, "page \(index) at \(range) resolves to page \(resolved); ranges \(ranges)",
                    sourceLocation: sourceLocation)
        }
    }

    /// 1080×2400 drawn 100% wide is 631pt — taller than the page, scaled to fit; 1080×1506
    /// is 396pt — fits a page, but not under the margin. Either way it used to move to the
    /// next page and leave the first one blank.
    @Test("a picture under the body margin draws on the first page, not after a blank one",
          arguments: [CGSize(width: 1080, height: 2400), CGSize(width: 1080, height: 1506)])
    func pictureUnderBodyMarginHasNoBlankPage(picture: CGSize) async throws {
        let (pages, sourceText) = try await layout(
            "\n  <img src='../Images/DT1.webp' style='width:100%'/>\n", css: ["body { margin: 8px; }"],
            picture: picture)
        #expect(pages.count == 1, "\(pages.count) pages; picture pages \(pages.map { pictures(on: $0).count })")
        #expect(pages.allSatisfy(hasInk))
        let drawn = try #require(pages.first.flatMap { pictures(on: $0).first })
        #expect(drawn.rect.rawValue.maxY <= Self.height + 0.5, "the picture runs off the page: \(drawn.rect)")
        expectPositionsRoundTrip(pages, sourceText: sourceText)
    }

    @Test("a gallery of page-tall pictures takes a page each, none of them blank")
    func galleryOfTallPicturesHasNoBlankPage() async throws {
        let body = (0..<3).map { _ in "<img src='map.webp' style='width:100%'/>" }.joined(separator: "\n")
        let (pages, sourceText) = try await layout(body, css: ["body { margin: 8px; }"],
                                                   picture: CGSize(width: 1080, height: 2400))
        #expect(pages.count == 3, "\(pages.count) pages; picture pages \(pages.map { pictures(on: $0).count })")
        #expect(pages.allSatisfy(hasInk))
        expectPositionsRoundTrip(pages, sourceText: sourceText)
    }

    /// 剑来's 后记 chapter as the book has it: a title, then a gallery whose cells each hold
    /// one picture. The pictures fill the pages after the title with no text beside them,
    /// and every one of those pages reported the chapter's end as its position.
    @Test("a gallery's picture pages each have their own position")
    func galleryPicturePagesHaveTheirOwnPositions() async throws {
        let cells = (1...7).map {
            "<div class='duokan-image-gallery-cell'><img alt='' src='../Images/S\($0).webp'/>\n    </div>"
        }.joined(separator: "\n    ")
        let css = """
            p.appendix-title { text-align: center; text-indent: 0; margin: 1.5em 0; }
            div.duokan-image-gallery-cell img { margin: 0; width: 100%; }
            """
        let (pages, sourceText) = try await layout(
            "<h2 style='display:none'>剑来</h2>\n<p class='appendix-title'>剑来</p>\n"
                + "<div class='duokan-image-gallery'>\n    \(cells)\n  </div>",
            css: [css], picture: CGSize(width: 1080, height: 1082))
        try #require(pages.count > 2)
        #expect(pages.allSatisfy(hasInk))
        expectPositionsRoundTrip(pages, sourceText: sourceText)
    }

    /// An illustration page between two paragraphs, the way illustrated light novels lay
    /// them out. The white space between the blocks collapses away; before 0.11 a picture
    /// had a place but no extent, so its place was the next paragraph's first character and
    /// its page shared that page's position. Each picture now takes one U+FFFC.
    @Test("an illustration page between paragraphs has a position of its own", arguments: [
        "<p>前文</p>\n<div><img src='a.webp' style='width:100%'/></div>\n<p>图注</p>",
        "<p>前文</p><div><img src='a.webp' style='width:100%'/></div><div><img src='b.webp' style='width:100%'/></div><p>图注</p>",
        "<p>前文</p>\n<img src='a.webp' style='display:block; width:100%'/>\n<p>图注</p>",
    ])
    func illustrationPageBetweenParagraphs(body: String) async throws {
        let (pages, sourceText) = try await layout(body, picture: CGSize(width: 1080, height: 1440))
        try #require(pages.count > 2)
        #expect(pages.allSatisfy(hasInk))
        expectPositionsRoundTrip(pages, sourceText: sourceText)
    }

    @Test("block pictures between paragraphs keep the place they have in the text")
    func blockPicturePositionsRoundTrip() async throws {
        let body = (0..<4).map {
            "<p>第\($0)段</p><img src='p.webp' style='display:block; width:100%'/>"
        }.joined() + "<p>完</p>"
        let (pages, sourceText) = try await layout(body, picture: CGSize(width: 1080, height: 1300))
        try #require(pages.count > 2)
        expectPositionsRoundTrip(pages, sourceText: sourceText)
        // A block picture's place is where it stands in the text, never the chapter's start.
        for page in pages.dropFirst() {
            for picture in self.pictures(on: page) {
                #expect(picture.sourceRange.location > 0, "a block picture on page \(page.index) sits at offset 0")
            }
        }
    }
}
