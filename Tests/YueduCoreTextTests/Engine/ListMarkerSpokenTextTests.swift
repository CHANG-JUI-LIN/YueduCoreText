import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// What VoiceOver reads for a page (list-marker design §14, decision 1): the
/// page's source text, each paragraph on a line of its own, each counter read
/// where its item starts, bullets silent, and the source text and page ranges
/// unchanged.
@Suite @MainActor
struct ListMarkerSpokenTextTests {

    private static let css = "body { margin: 0; line-height: 1.5 } p { margin: 0 } ol, ul { margin: 0 }"

    private struct Chapter {
        let source: String
        let ranges: [NSRange]
        let lists: [DisplayList]
        let paragraphs: [NSRange]

        func pageText(_ page: Int) -> String { (source as NSString).substring(with: ranges[page]) }
        func spoken(_ page: Int) -> String { spoken(lists[page], page: page) }
        func spoken(_ list: DisplayList, page: Int) -> String {
            list.spokenText(pageText: pageText(page), pageRange: ranges[page], paragraphRanges: paragraphs)
        }
        var spokenPages: [String] { lists.indices.map(spoken) }
    }

    /// Lines are 25.5 tall, so a height of 60 holds two of them.
    private static func chapter(
        _ body: String, height: CGFloat = 2000, writingMode: ReaderWritingMode = .horizontal,
        images: [String: UIImage] = [:]
    ) async throws -> Chapter {
        var config = BrowserLayoutConfig(renderWidth: 300, renderHeight: height, rootFontSize: 17,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        config.writingMode = writingMode
        let doc = BrowserLayoutDocument(html: "<html><head></head><body>\(body)</body></html>", cssTexts: [Self.css],
                                        config: config, imageLoader: { images[$0] })
        let pages = try await doc.renderPages(containerSize: CGSize(width: 300, height: height))
        let source = doc.lastSourceText
        let pipeline = try doc.makeLayout(containerSize: CGSize(width: 300, height: height))
        try #require(pipeline.sourceText == source)
        return Chapter(source: source, ranges: BrowserPageGeometry.buildPageRanges(pages, sourceText: source),
                       lists: pages.map { DisplayListBuilder.build(for: $0, sourceText: source) },
                       paragraphs: BrowserLayoutSemanticContent.paragraphRanges(in: pipeline.rootBox))
    }

    @Test func orderedNumbersAreReadWhereTheirItemsStart() async throws {
        let body = "<p>Fruit:</p><ol%@><li>Apple</li><li>Banana</li></ol>"
        let numbered = try await Self.chapter(String(format: body, ""))
        let plain = try await Self.chapter(String(format: body, " style=\"list-style-type: none\""))
        #expect(numbered.spokenPages == ["Fruit:\n1. Apple\n2. Banana"])
        // Speech only: the offsets every other reader of the page uses stay put.
        #expect(numbered.source == plain.source)
        #expect(numbered.ranges == plain.ranges)
        #expect(plain.spokenPages == ["Fruit:\nApple\nBanana"])
    }

    /// The source runs blocks together; speech puts each paragraph on a line.
    @Test func eachParagraphIsReadOnALineOfItsOwn() async throws {
        let chapter = try await Self.chapter("\n  <h2>第一章 序幕</h2>\n  <p>Fruit:</p>\n  <p>那天<b>下雨</b>。<br/>次行</p>\n")
        #expect(chapter.pageText(0) == "第一章 序幕Fruit:那天下雨。\n次行")
        #expect(chapter.spokenPages == ["第一章 序幕\nFruit:\n那天下雨。\n次行"])
    }

    /// Every counter style is read as drawn, less its suffix's trailing space.
    @Test func everyCounterStyleIsReadWithoutItsTrailingSpace() async throws {
        let cases: [(type: String, first: String, second: String)] = [
            ("decimal", "1.", "2."),
            ("lower-alpha", "a.", "b."),
            ("upper-roman", "I.", "II."),
            ("cjk-decimal", "一、", "二、"),
            ("trad-chinese-informal", "一、", "二、"),
            ("simp-chinese-informal", "一、", "二、"),
        ]
        for (type, first, second) in cases {
            let chapter = try await Self.chapter("<ol style=\"list-style-type: \(type)\"><li>甲。</li><li>乙。</li></ol>")
            #expect(chapter.spokenPages == ["\(first) 甲。\n\(second) 乙。"], "\(type)")
        }
    }

    @Test func bulletsSayNothing() async throws {
        for type in ["disc", "circle", "square", "none"] {
            let chapter = try await Self.chapter("<ul style=\"list-style-type: \(type)\"><li>甲。</li><li>乙。</li></ul>")
            #expect(chapter.spokenPages == ["甲。\n乙。"], "\(type)")
        }
    }

    /// Items that start at one place are read outermost first; an empty item
    /// starts where the next text does.
    @Test func itemsStartingTogetherAreReadOutermostFirst() async throws {
        let nested = try await Self.chapter("<ol start=\"3\"><li><ol><li>甲。</li></ol></li><li>乙。</li></ol>")
        #expect(nested.spokenPages == ["3. \n1. 甲。\n4. 乙。"])
        let empty = try await Self.chapter("<ol><li>甲。</li><li></li><li>丙。</li></ol>")
        #expect(empty.spokenPages == ["1. 甲。\n2. \n3. 丙。"])
    }

    /// An item continued from an earlier page is not numbered again, nor
    /// broken off from what came before.
    @Test func anItemIsNumberedOnlyOnThePageItStartsOn() async throws {
        let long = String(repeating: "長", count: 45)
        let chapter = try await Self.chapter("<ol><li>\(long)</li></ol>", height: 60)
        try #require(chapter.lists.count >= 2)
        #expect(chapter.spoken(0) == "1. " + chapter.pageText(0))
        for page in 1..<chapter.lists.count {
            #expect(chapter.spoken(page) == chapter.pageText(page))
        }
    }

    /// A scroll tile also draws its neighbours' edge lines. A number is read
    /// only by the tile its item's text starts in, never twice.
    @Test func aNumberDrawnInANeighboursEdgeIsNotRead() async throws {
        let line = String(repeating: "甲", count: 15)
        let chapter = try await Self.chapter("<ol><li>\(line)\(line)</li><li>乙。</li></ol>", height: 60)
        try #require(chapter.lists.count == 2)
        // The second item starts exactly where the first page ends.
        try #require(chapter.ranges[1].location == NSMaxRange(chapter.ranges[0]))
        let bleeding = DisplayList(items: chapter.lists[0].items + chapter.lists[1].items)
        #expect(chapter.spoken(bleeding, page: 0) == chapter.spoken(0))
        #expect(chapter.spoken(bleeding, page: 1) == chapter.spoken(1))
        #expect(chapter.spokenPages == ["1. \(line)\(line)", "2. 乙。"])
    }

    /// Ruby text is not a marker; a picture's U+FFFC says nothing.
    @Test func rubyAndPicturesAreNotRead() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 20, height: 20), color: .gray)
        let chapter = try await Self.chapter(
            "<p><ruby>漢<rt>かん</rt></ruby>字<img src=\"p.png\" style=\"width: 20px; height: 20px\"/>。</p>",
            images: ["p.png": image])
        #expect(chapter.pageText(0).contains("\u{FFFC}"))
        #expect(!chapter.lists[0].items.contains { if case .text(let text) = $0 { text.isListMarker } else { false } })
        #expect(chapter.spokenPages == ["漢字。"])
    }

    /// An item that opens with a picture is numbered at the picture, and its
    /// paragraph starts after it: the number gets a line of its own. Joining
    /// the two across the picture would also join a picture-only item's number
    /// to the next paragraph, which is not the item's.
    @Test func aPictureFirstItemReadsItsNumberOnALineOfItsOwn() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 20, height: 20), color: .gray)
        let inline = try await Self.chapter(
            "<ol><li><img src=\"p.png\" style=\"width: 20px; height: 20px\"/>前文</li></ol>", images: ["p.png": image])
        #expect(inline.spokenPages == ["1. \n前文"])
        let block = try await Self.chapter(
            "<ol><li><img src=\"p.png\" style=\"display: block; width: 20px; height: 20px\"/></li></ol><p>後文</p>",
            images: ["p.png": image])
        #expect(block.spokenPages == ["1. \n後文"])
    }

    @Test func verticalListsReadTheSame() async throws {
        let body = "<p>參考。</p><ol><li>甲。</li><li>乙。</li></ol><ol style=\"list-style-type: cjk-decimal\"><li>丙。</li></ol>"
        let horizontal = try await Self.chapter(body)
        let vertical = try await Self.chapter(body, writingMode: .verticalRTL)
        #expect(horizontal.spokenPages == ["參考。\n1. 甲。\n2. 乙。\n一、 丙。"])
        #expect(vertical.spokenPages == horizontal.spokenPages)
    }
}
