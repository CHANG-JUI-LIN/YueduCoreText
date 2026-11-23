import Testing
import UIKit
@testable import YueduCoreText

/// Title pages lower their title with a percentage margin, which resolves against the page's
/// width. On an iPhone held sideways (760×300) `margin-top: 40%` and up is more than a page,
/// and the first page held nothing but the background: 157 chapters of six books in the
/// 2026-11-23 census, every one of them the page before a 卷 or 章 title. That page also
/// reported the chapter's end as its position, so the next page's start found it.
@Suite("Margins before a chapter's first content")
@MainActor
struct LeadingMarginPaginationTests {
    private static let sideways = CGSize(width: 760, height: 300)

    private func layout(_ body: String, css: [String] = ["body { margin: 0; }"],
                        page: CGSize = sideways, writingMode: ReaderWritingMode = .horizontal,
                        picture: CGSize = CGSize(width: 1080, height: 600)) async throws
        -> (pages: [PageFragments], sourceText: String) {
        let image = BrowserLayoutTestSupport.makeImage(size: picture, color: .gray)
        let config = BrowserLayoutConfig(
            renderWidth: page.width, renderHeight: page.height, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white,
            writingMode: writingMode
        )
        let doc = HTMLLayoutDocument(input: .currentCompatibility(html: "<html><body>\(body)</body></html>", cssTexts: css),
                                     configuration: config, imageLoader: { _ in image })
        let session = try doc.makePageSession()
        try await session.finish()
        return (session.completedPages, session.sourceText)
    }

    private func hasInk(_ page: PageFragments) -> Bool {
        !BrowserLayoutTestSupport.allTextFragments([page]).isEmpty
            || BrowserLayoutTestSupport.allImageFragments([page]).contains { !$0.isBackgroundPaint }
    }

    /// The boxes the chapter paints on a page: its fills, without the page background.
    private func boxes(on page: PageFragments) -> [FillFragment] {
        var result: [FillFragment] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill(let fill) where !fill.isBackgroundPaint: result.append(fill)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        walk(page.fragments)
        return result
    }

    /// Every page has something on it, and its position finds it again: what a page turn,
    /// a restore and the reader's progress all resolve through.
    private func expectEveryPageReadable(_ pages: [PageFragments], sourceText: String,
                                         sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!pages.isEmpty, sourceLocation: sourceLocation)
        for (index, page) in pages.enumerated() {
            #expect(hasInk(page), "page \(index) of \(pages.count) has nothing on it", sourceLocation: sourceLocation)
        }
        let ranges = BrowserPageGeometry.buildPageRanges(pages, sourceText: sourceText)
        for (index, range) in ranges.enumerated() where range.length > 0 {
            let resolved = BrowserPageGeometry.pageIndex(forCharOffset: range.location, ranges: ranges,
                                                         sourceText: sourceText)
            #expect(resolved == index, "page \(index) at \(range) resolves to page \(resolved); ranges \(ranges)",
                    sourceLocation: sourceLocation)
        }
    }

    /// book-d53a7692: `h1.chapter { margin-top: 50% }`, 380pt on a 300pt page.
    @Test("a title lowered by more than a page starts the first page")
    func titleLoweredByMoreThanAPage() async throws {
        let (pages, sourceText) = try await layout(
            "<h1 style='margin-top: 50%'>第一章</h1><p>正文第一段。</p>")
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
        let title = try #require(BrowserLayoutTestSupport.allTextFragments(Array(pages.prefix(1))).first)
        #expect(title.rect.minY < 1, "the title sits \(title.rect.minY)pt down")
    }

    /// redchamber, book-772d4bf7: the margin is on a bordered box around the title, so the
    /// first thing to leave the page is the box, not a line.
    @Test("a box lowered by more than a page starts the first page")
    func boxLoweredByMoreThanAPage() async throws {
        let (pages, sourceText) = try await layout(
            "<div style='margin: 60% 0 0; border: 4px solid #333; padding: 3px'><h1 style='margin: 0'>第一章</h1></div>")
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
        let box = try #require(pages.first.flatMap { boxes(on: $0).first })
        #expect(box.rect.minY < 1, "the box starts \(box.rect.minY)pt down")
    }

    /// orv: the margin leaves room for the box's top edge but not for its first line, so the
    /// first page held a 2pt strip of the box and nothing else.
    @Test("a box whose first line does not fit under its margin starts the first page whole")
    func boxWhoseFirstLineMissesThePage() async throws {
        let (pages, sourceText) = try await layout(
            "<div style='margin-top: 37%; border: 1px solid #333; padding: 7px'><p style='margin: 0'>一个新的世界正在诞生。</p></div>")
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
        let box = try #require(pages.first.flatMap { boxes(on: $0).first })
        #expect(box.rect.minY < 1, "the box starts \(box.rect.minY)pt down")
        #expect(box.fragmentPosition == .single, "the box is cut: \(box.fragmentPosition)")
    }

    /// book-0be89331: a video poster under `margin: 100% auto 0`.
    @Test("a picture lowered by more than a page starts the first page")
    func pictureLoweredByMoreThanAPage() async throws {
        let (pages, sourceText) = try await layout(
            "<div style='margin: 100% auto 0'><img src='poster.webp' style='width: 100%'/></div>")
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
    }

    /// book-8fbb4b7b's end page: the body has room above its content (here a padding, there
    /// a margin the missing logo left on an empty box), so the heading's margin is its own
    /// and not the root's.
    @Test("a margin of the first content's own box is dropped as well")
    func marginNotFoldedIntoTheRoot() async throws {
        let (pages, sourceText) = try await layout(
            "<h2 style='margin-top: 45%'>THE BEGINNING</h2><p>Let the conversation begin.</p>",
            css: ["body { margin: 0; padding-top: 1px; }"])
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
    }

    /// Vertical writing: the block axis runs right to left and a percentage margin resolves
    /// against the inline size, the page's height, so a portrait page is the short one.
    @Test("a vertical title lowered by more than a page starts the first page")
    func verticalTitleLoweredByMoreThanAPage() async throws {
        let (pages, sourceText) = try await layout(
            "<h1 style='margin-right: 50%'>第一章</h1><p>正文第一段。</p>",
            css: ["html { writing-mode: vertical-rl; } body { margin: 0; }"],
            page: CGSize(width: 330, height: 760), writingMode: .verticalRTL)
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
    }

    // MARK: - What stays as it was

    /// A title page on a page tall enough for it keeps its margin.
    @Test("a margin that leaves room for the content is kept")
    func marginThatFitsIsKept() async throws {
        let (pages, sourceText) = try await layout(
            "<h1 style='margin-top: 20%'>第一章</h1><p>正文第一段。</p>")
        #expect(pages.count == 1)
        expectEveryPageReadable(pages, sourceText: sourceText)
        let title = try #require(BrowserLayoutTestSupport.allTextFragments(pages).first)
        #expect(abs(title.rect.minY - 152) < 1, "the title sits \(title.rect.minY)pt down, not under its 152pt margin")
    }

    /// A box taller than the page painted with a background leaves the first page with
    /// nothing but paint, and dropping the margin above it would not change that: the page
    /// is left as it was, margin and all.
    @Test("a painted box that fills the first page keeps the margin above it")
    func paintedBoxKeepsItsMargin() async throws {
        let (pages, _) = try await layout(
            "<div style='height: 400px; background: #ccc'></div><p>After the box.</p>",
            css: ["body { margin: 8px; }"])
        #expect(pages.count == 2)
        let box = try #require(pages.first.flatMap { boxes(on: $0).first })
        #expect(abs(box.rect.minY - 8) < 1, "the box starts \(box.rect.minY)pt down, not under the 8pt body margin")
    }
}
