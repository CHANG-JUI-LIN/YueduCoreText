import Testing
import UIKit
@testable import YueduCoreText

/// Since 0.11 a picture takes one U+FFFC of the chapter's source text, the character every
/// position, highlight and page range counts. Before, it had a place but no extent: a page of
/// pictures followed directly by text shared that text's position.
@Suite("Pictures in the source text")
@MainActor
struct PictureSourceTextTests {
    private static let picture = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 100, height: 60), color: .gray)

    private static func pipeline(_ body: String, css: [String] = [], loads: Bool = true) throws
        -> BrowserLayoutDocument.BrowserLayoutPipelineResult {
        let config = BrowserLayoutConfig(
            renderWidth: 300, renderHeight: 400, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let document = BrowserLayoutDocument(html: "<html><body>\(body)</body></html>", cssTexts: css,
                                             config: config, imageLoader: { _ in loads ? Self.picture : nil })
        return try document.makeLayout(containerSize: CGSize(width: 300, height: 400))
    }

    private static func pictureRuns(_ box: BlockBox) -> [InlineRun] {
        box.inlineRuns.filter { $0.atomic != nil } + box.children.flatMap(pictureRuns)
    }

    private static func blockPictures(_ box: BlockBox) -> [BlockBox] {
        (box.imageAttachment == nil ? [] : [box]) + box.children.flatMap(blockPictures)
    }

    @Test("each picture takes one U+FFFC where it stands", arguments: [
        ("<p>前<img src='a.png'/>后</p>", "前\u{FFFC}后", [1]),
        ("<p>前文</p>\n<div><img src='a.png' style='width:100%'/></div>\n<p>图注</p>", "前文\u{FFFC}图注", [2]),
        ("<p>前文</p><img src='a.png' style='display:block'/><p>图注</p>", "前文\u{FFFC}图注", [2]),
        ("<p><img src='a.png' style='float:left'/>图注</p>", "\u{FFFC}图注", [0]),
        ("<p>前</p><svg><image href='a.png'/></svg><p>后</p>", "前\u{FFFC}后", [1]),
        ("<p>甲<img src='a.png'/><img src='b.png'/>乙</p>", "甲\u{FFFC}\u{FFFC}乙", [1, 2]),
    ])
    func pictureTakesOneCharacter(body: String, expected: String, pictures: [Int]) throws {
        let result = try Self.pipeline(body)
        #expect(result.sourceText == expected)
        #expect(result.pictureOffsets == pictures)
        let ranges = Self.pictureRuns(result.rootBox).map(\.sourceRange)
            + Self.blockPictures(result.rootBox).map(\.imageSourceRange)
        #expect(Set(ranges.map(\.location)) == Set(pictures))
        #expect(ranges.allSatisfy { $0.length == 1 }, "\(ranges)")
    }

    /// An image that fails to load must not move the offsets after it: a reading position
    /// saved while it loaded has to mean the same text when it does not.
    @Test("a picture that does not load keeps its character")
    func unloadedPictureKeepsItsCharacter() throws {
        let body = "<p>前<img src='a.png'/>中</p><img src='b.png' style='display:block'/><p>后</p>"
        let loaded = try Self.pipeline(body)
        let missing = try Self.pipeline(body, loads: false)
        #expect(missing.sourceText == loaded.sourceText)
        #expect(missing.pictureOffsets == loaded.pictureOffsets)
        #expect(loaded.pictureOffsets == [1, 3])
    }

    @Test("a CSS background is paint, not a picture of the text")
    func backgroundTakesNoCharacter() throws {
        let result = try Self.pipeline("<div class='bg'>字</div>",
                                       css: [".bg { background-image: url(bg.png); height: 50px; }"])
        #expect(result.sourceText == "字")
        #expect(result.pictureOffsets.isEmpty)
    }

    @Test("an id on a picture targets the picture's character")
    func anchorOnPictureTargetsItsCharacter() throws {
        let result = try Self.pipeline("<p>前文</p><img id='fig' src='a.png' style='display:block'/><p>图注</p>")
        #expect(result.anchorOffsets["fig"] == 2)
    }

    /// Paragraph ranges serve text selection, which never selects a picture's character.
    @Test("paragraph ranges hold text only")
    func paragraphRangesHoldTextOnly() throws {
        let result = try Self.pipeline("<p><img src='a.png'/>前文</p><div><img src='b.png'/></div><p>图注</p>")
        #expect(result.sourceText == "\u{FFFC}前文\u{FFFC}图注")
        #expect(BrowserLayoutSemanticContent.paragraphRanges(in: result.rootBox)
            == [NSRange(location: 1, length: 2), NSRange(location: 4, length: 2)])
    }

    /// Scroll mode reads the same offsets: the picture's character is where the picture is
    /// drawn, and the text after it is not.
    @Test("scroll mode places a picture's character on the picture")
    func scrollModePlacesPictureCharacter() throws {
        let result = try Self.pipeline("<p>前文</p><div><img src='a.png' style='width:100%'/></div><p>图注</p>")
        let document = BrowserScrollDocument.make(pipeline: result, contentWidth: 300, contentInsets: .zero)
        let image = try #require(document.displayList.items.compactMap { item -> DisplayImageItem? in
            if case .image(let image) = item, !image.isBackgroundPaint { return image }
            return nil
        }.first)
        #expect(image.sourceRange == NSRange(location: 2, length: 1))
        #expect(document.documentY(forCharOffset: 2) == image.rect.minY)
        #expect(document.documentY(forCharOffset: 3) >= image.rect.maxY)
        #expect(document.charOffset(atDocumentY: image.rect.midY) == 2)
    }

    /// A highlight that runs across a block picture now holds the picture's character. It
    /// still marks text only: the illustration between its two halves stays unpainted.
    @Test("a highlight across a block picture paints the text, not the picture")
    func highlightAcrossBlockPictureSkipsPicture() throws {
        let result = try Self.pipeline("<p>前文</p><div><img src='a.png' style='width:100%'/></div><p>图注</p>")
        let document = BrowserScrollDocument.make(pipeline: result, contentWidth: 300, contentInsets: .zero)
        let image = try #require(document.displayList.items.compactMap { item -> DisplayImageItem? in
            if case .image(let image) = item, !image.isBackgroundPaint { return image }
            return nil
        }.first)
        let rects = document.displayList.selectionRects(for: NSRange(location: 1, length: 3))
        #expect(rects.count == 2)
        #expect(rects.allSatisfy { !$0.intersects(image.rect.rawValue.insetBy(dx: 1, dy: 1)) }, "\(rects)")
    }
}
