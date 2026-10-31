import CoreText
import Testing
import UIKit
@testable import YueduCoreText

/// `display: inline-block` (CSS 2.1 §9.2.2): a block container of its own,
/// shrunk to fit its content (§10.3.9) and placed on its line as one atomic
/// box that sits on the baseline of its last line (§10.8.1). The engine used to
/// lay it out as an ordinary inline box, so a chat bubble lost its background
/// and spread across the whole column.
@MainActor
struct BrowserInlineBlockTests {

    private struct Layout {
        let pages: [PageFragments]
        /// Trimmed text of each text fragment → its page and fragment.
        let texts: [String: (page: Int, fragment: TextFragment)]
        let fills: [(page: Int, fill: FillFragment)]
        let doc: BrowserLayoutDocument

        func text(_ word: String) throws -> TextFragment { try #require(texts[word]).fragment }
        func page(of word: String) throws -> Int { try #require(texts[word]).page }
    }

    private static func fills(_ fragments: [Fragment], page: Int, into out: inout [(page: Int, fill: FillFragment)]) {
        for fragment in fragments {
            switch fragment {
            case .fill(let fill): out.append((page, fill))
            case .group(let children): fills(children, page: page, into: &out)
            default: break
            }
        }
    }

    private static func config(
        width: CGFloat, height: CGFloat, bottomJustify: Bool = false,
        writingMode: ReaderWritingMode = .horizontal,
        textTransform: ((NSMutableAttributedString) -> Void)? = nil
    ) -> BrowserLayoutConfig {
        BrowserLayoutConfig(
            renderWidth: width, renderHeight: height, rootFontSize: 10,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white,
            textTransform: textTransform, writingMode: writingMode, bottomJustify: bottomJustify
        )
    }

    private static func html(_ body: String) -> String {
        "<html><body style=\"margin:0;font-size:10px;line-height:1\">\(body)</body></html>"
    }

    private static func layout(
        _ body: String, width: CGFloat = 300, height: CGFloat = 800, bottomJustify: Bool = false,
        textTransform: ((NSMutableAttributedString) -> Void)? = nil
    ) async throws -> Layout {
        let doc = BrowserLayoutDocument(
            html: html(body), cssTexts: [],
            config: config(width: width, height: height, bottomJustify: bottomJustify, textTransform: textTransform)
        )
        let pages = try await doc.renderPages(containerSize: CGSize(width: width, height: height))
        let source = doc.lastSourceText as NSString
        var texts: [String: (page: Int, fragment: TextFragment)] = [:]
        var fills: [(page: Int, fill: FillFragment)] = []
        for (index, page) in pages.enumerated() {
            for fragment in BrowserLayoutTestSupport.allTextFragments([page]) {
                guard case .linear = fragment.sourceMapping, fragment.sourceRange.length > 0,
                      NSMaxRange(fragment.sourceRange) <= source.length else { continue }
                let word = source.substring(with: fragment.sourceRange).trimmingCharacters(in: .whitespacesAndNewlines)
                texts[word] = (index, fragment)
            }
            Self.fills(page.fragments, page: index, into: &fills)
        }
        return Layout(pages: pages, texts: texts, fills: fills, doc: doc)
    }

    private static let bubble = "display:inline-block;background-color:#ccc"

    // MARK: - Box

    /// The chat bubble: one box around the message, as wide as the message.
    @Test func bubbleShrinksToItsTextAndPaintsOneBox() async throws {
        let result = try await Self.layout("""
            <div><div style="\(Self.bubble);padding:5px;border:1px solid #000">
            <p style="margin:0">Hi there</p>
            </div></div>
            """)
        #expect(result.fills.count == 1)
        let box = try #require(result.fills.first).fill.rect.rawValue
        let text = try result.text("Hi there").rect.rawValue
        #expect(abs(box.minX) < 0.01)
        #expect(abs(box.width - (text.width + 12)) < 0.5)
        #expect(abs(box.height - (text.height + 12)) < 0.5)
        #expect(abs(text.minX - (box.minX + 6)) < 0.01)
        #expect(abs(text.minY - (box.minY + 6)) < 0.01)
    }

    /// A long message wraps inside the room its line gives it. The width the
    /// box may take is the containing block's: here 80% of the column, which
    /// is also what its percentage padding resolves against.
    @Test func longMessageWrapsWithinItsContainingBlock() async throws {
        let message = String(repeating: "words in a long message ", count: 8)
        let result = try await Self.layout("""
            <div style="margin-right:20%"><div style="\(Self.bubble);padding:2%">
            <p style="margin:0">\(message)</p>
            </div></div>
            """)
        #expect(result.fills.count == 1)
        let box = try #require(result.fills.first).fill.rect.rawValue
        #expect(box.maxX <= 240 + 0.01)
        let lines = Set(result.texts.values.map { ($0.fragment.rect.minY * 100).rounded() })
        #expect(lines.count > 1)
        for entry in result.texts.values {
            #expect(abs(entry.fragment.rect.minX - (box.minX + 4.8)) < 0.01)
        }
    }

    /// An empty inline-block is its padding box, standing on the baseline.
    @Test func emptyBoxStandsOnTheBaseline() async throws {
        let result = try await Self.layout("<div>a<span style=\"\(Self.bubble);padding:5px\"></span>b</div>")
        #expect(result.fills.count == 1)
        let box = try #require(result.fills.first).fill.rect.rawValue
        let a = try result.text("a")
        let b = try result.text("b")
        #expect(abs(box.width - 10) < 0.01)
        #expect(abs(box.height - 10) < 0.01)
        #expect(abs(box.maxY - a.baselineY) < 0.01)
        #expect(abs(box.minX - a.rect.maxX) < 0.01)
        #expect(abs(b.rect.minX - box.maxX) < 0.01)
    }

    @Test func nestedBoxSitsInsideItsParent() async throws {
        let result = try await Self.layout("""
            <div><span style="\(Self.bubble);padding:3px">a <span style="display:inline-block;\
            background-color:#999;padding:2px">b</span></span></div>
            """)
        #expect(result.fills.count == 2)
        let outer = try #require(result.fills.first).fill.rect.rawValue
        let inner = try #require(result.fills.last).fill.rect.rawValue
        #expect(outer.contains(inner))
        let b = try result.text("b").rect.rawValue
        #expect(abs(b.minX - (inner.minX + 2)) < 0.01)
        #expect(abs(b.minY - (inner.minY + 2)) < 0.01)
    }

    // MARK: - On the line

    /// Its last line's baseline is the baseline of the line it sits on.
    @Test func sitsOnTheBaselineOfItsLastLine() async throws {
        let result = try await Self.layout(
            "<div>A <span style=\"display:inline-block;width:20px\">one two</span> B</div>")
        let a = try result.text("A")
        let one = try result.text("one")
        let two = try result.text("two")
        let b = try result.text("B")
        #expect(one.baselineY < two.baselineY - 1)
        #expect(abs(a.baselineY - two.baselineY) < 0.01)
        #expect(abs(b.baselineY - two.baselineY) < 0.01)
    }

    /// One box never breaks across lines: when it does not fit what is left of
    /// a line, all of it starts the next.
    @Test func movesWholeToTheNextLine() async throws {
        let result = try await Self.layout(
            "<div style=\"width:100px\">x <span style=\"display:inline-block;width:95px\">bb cc</span></div>")
        let x = try result.text("x")
        let content = try result.text("bb cc")
        #expect(content.rect.minY >= x.rect.maxY - 0.01)
    }

    @Test func textAfterItSharesItsLine() async throws {
        let result = try await Self.layout(
            "<div>x <span style=\"display:inline-block;width:40px\">bb</span> y</div>")
        let x = try result.text("x")
        let bb = try result.text("bb")
        let y = try result.text("y")
        #expect(abs(y.baselineY - bb.baselineY) < 0.01)
        #expect(abs(bb.rect.minX - x.rect.maxX) < 0.01)
        #expect(y.rect.minX >= bb.rect.minX + 40 - 0.01)
    }

    // MARK: - Pages

    private static let pageLines = (0..<18).map { "<p style=\"margin:0\">line\($0)</p>" }.joined()
    private static let threeLineBubble = """
        <div style="\(bubble);padding:5px"><p style="margin:0">b1</p>\
        <p style="margin:0">b2</p><p id="target" style="margin:0">b3</p></div>
        """

    /// A box that fits a page is never cut: one that would cross the page end
    /// moves to the next page, with everything after it.
    @Test func pageEndMovesTheWholeBox() async throws {
        let result = try await Self.layout(
            Self.pageLines + Self.threeLineBubble + "<p style=\"margin:0\">after</p>", height: 200)
        #expect(try result.page(of: "line17") == 0)
        for word in ["b1", "b2", "b3", "after"] {
            #expect(try result.page(of: word) == 1)
        }
        let box = try #require(result.fills.first)
        #expect(box.page == 1)
        #expect(abs(box.fill.rect.minY) < 0.01)
        #expect(abs(try result.text("b1").rect.minY - 5) < 0.01)
    }

    /// A box taller than a page cannot move whole; its lines break across
    /// pages like a block's, so none is cut off.
    @Test func boxTallerThanAPageBreaksBetweenItsLines() async throws {
        let lines = (0..<30).map { "<p style=\"margin:0\">poem\($0)</p>" }.joined()
        let result = try await Self.layout("<div style=\"\(Self.bubble)\">\(lines)</div>", height: 200)
        #expect(result.pages.count == 2)
        #expect(try result.page(of: "poem19") == 0)
        #expect(try result.page(of: "poem20") == 1)
        #expect(result.fills.map(\.page) == [0, 1])
    }

    /// An offset inside the box resolves to the page the box landed on.
    @Test func offsetInsideTheBoxFindsItsPage() async throws {
        let result = try await Self.layout(Self.pageLines + Self.threeLineBubble, height: 200)
        let offset = try #require(result.doc.lastAnchorOffsets["target"])
        let source = result.doc.lastSourceText
        let ranges = result.pages.map { page -> NSRange in
            let texts = BrowserLayoutTestSupport.allTextFragments([page]).map(\.sourceRange).filter { $0.length > 0 }
            let start = texts.map(\.location).min() ?? 0
            return NSRange(location: start, length: (texts.map(NSMaxRange).max() ?? start) - start)
        }
        #expect(BrowserPageGeometry.pageIndex(forCharOffset: offset, ranges: ranges, sourceText: source) == 1)
    }

    /// 底部對齊 spreads a page's line gaps; the box and its lines are one line
    /// of the page, so they move together and the box still holds its text.
    @Test func bottomJustifyMovesTheBoxAsOneLine() async throws {
        let body = "<p style=\"margin:0\">top</p>" + Self.threeLineBubble
            + (0..<30).map { "<p style=\"margin:0\">tail\($0)</p>" }.joined()
        let natural = try await Self.layout(body, height: 205)
        let justified = try await Self.layout(body, height: 205, bottomJustify: true)
        let moved = try justified.text("b1").rect.minY - natural.text("b1").rect.minY
        #expect(moved > 0.01)
        for word in ["b2", "b3"] {
            #expect(abs(try justified.text(word).rect.minY - natural.text(word).rect.minY - moved) < 0.01)
        }
        let naturalBox = try #require(natural.fills.first).fill.rect.rawValue
        let justifiedBox = try #require(justified.fills.first).fill.rect.rawValue
        #expect(abs(justifiedBox.minY - naturalBox.minY - moved) < 0.01)
        #expect(abs(justifiedBox.height - naturalBox.height) < 0.01)
    }

    /// A bubble that no longer fits ends the page like a text line does, so
    /// 底部對齊 spreads the page it leaves behind.
    @Test func bottomJustifyStretchesThePageABoxLeaves() async throws {
        let body = (0..<20).map { "<p style=\"margin:0\">line\($0)</p>" }.joined()
            + "<div style=\"\(Self.bubble)\"><p style=\"margin:0\">bubble</p></div>"
        let natural = try await Self.layout(body, height: 205)
        let justified = try await Self.layout(body, height: 205, bottomJustify: true)
        #expect(try justified.page(of: "line19") == 0)
        #expect(try justified.page(of: "bubble") == 1)
        #expect(abs(try justified.text("line0").rect.minY - natural.text("line0").rect.minY) < 0.01)
        #expect(try justified.text("line19").rect.minY - natural.text("line19").rect.minY > 0.01)
    }

    /// A box taller than a page moves with its line under 底部對齊, but the
    /// slice that runs on to the next page still ends on the content bottom.
    @Test func bottomJustifyKeepsATallBoxOnThePage() async throws {
        let lines = (0..<30).map { "<p style=\"margin:0\">poem\($0)</p>" }.joined()
        let body = "<p style=\"margin:0\">top</p><div style=\"\(Self.bubble)\">\(lines)</div>"
        let natural = try await Self.layout(body, height: 205)
        let justified = try await Self.layout(body, height: 205, bottomJustify: true)
        let moved = try justified.text("poem0").rect.minY - natural.text("poem0").rect.minY
        #expect(moved > 0.01)
        let naturalSlice = try #require(natural.fills.first { $0.page == 0 }).fill.rect.rawValue
        let justifiedSlice = try #require(justified.fills.first { $0.page == 0 }).fill.rect.rawValue
        #expect(abs(justifiedSlice.minY - naturalSlice.minY - moved) < 0.01)
        #expect(abs(justifiedSlice.maxY - 205) < 0.01)
    }

    // MARK: - Other consumers

    /// Reader text rules see the box's text like any other.
    @Test func readerRulesReachTheText() async throws {
        let result = try await Self.layout(
            "<div>a <span style=\"display:inline-block\">inside</span></div>",
            textTransform: { text in
                let range = (text.string as NSString).range(of: "inside")
                if range.location != NSNotFound { text.addAttribute(.foregroundColor, value: UIColor.red, range: range) }
            })
        let line = try #require(try result.text("inside").ctLine)
        let colors = (CTLineGetGlyphRuns(line) as! [CTRun]).compactMap {
            (CTRunGetAttributes($0) as NSDictionary)[NSAttributedString.Key.foregroundColor] as? UIColor
        }
        #expect(colors.contains(.red))
    }

    /// Vertical writing has no inline-block layout yet: the chapter is refused,
    /// not drawn wrong.
    @Test func verticalChapterIsRefused() async throws {
        let doc = BrowserLayoutDocument(
            html: Self.html("<p>a<span style=\"display:inline-block\">b</span></p>"), cssTexts: [],
            config: Self.config(width: 300, height: 400, writingMode: .verticalRTL)
        )
        await #expect(throws: HTMLLayoutError.self) {
            _ = try await doc.renderPages(containerSize: CGSize(width: 300, height: 400))
        }
    }

    // MARK: - Viewport (scroll mode)

    private static func viewportHTML() -> String {
        html("<div><div style=\"\(bubble);padding:4px\"><p id=\"msg\" style=\"margin:0\">message</p></div></div>"
            + (0..<300).map { "<p>\($0) " + String(repeating: "filler text ", count: 20) + "</p>" }.joined())
    }

    private static func messageRect(_ document: BrowserScrollDocument) -> CGRect? {
        let source = document.sourceText as NSString
        for item in document.displayList.items {
            guard case .text(let text) = item, text.sourceRange.length > 0,
                  NSMaxRange(text.sourceRange) <= source.length,
                  source.substring(with: text.sourceRange) == "message" else { continue }
            return text.rect.rawValue
        }
        return nil
    }

    /// Scroll mode demands lines as they come into view and drops them as they
    /// leave. The box's text comes back with its line.
    @Test func scrollingAwayAndBackRedrawsTheBoxText() throws {
        let config = BrowserLayoutConfig(renderWidth: 320, renderHeight: 600, rootFontSize: 10)
        let session = try HTMLLayoutDocument(html: Self.viewportHTML(), configuration: config).makeViewportSession()
        let first = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1200))
        let rect = try #require(Self.messageRect(first))
        let far = try session.layout(in: CGRect(x: 0, y: 30_000, width: 320, height: 1200))
        #expect(Self.messageRect(far) == nil)
        let back = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1200))
        #expect(Self.messageRect(back) == rect)
        let offset = try #require(session.anchorOffsets["msg"])
        #expect(abs(session.documentY(for: offset) - (rect.minY - 4)) < 0.01)
    }

    private static func inlineBlocks(in box: BlockBox) -> [BlockBox] {
        box.inlineBlockBoxes + box.children.flatMap(inlineBlocks)
    }

    private static func hasLines(_ box: BlockBox) -> Bool {
        !box.lines.isEmpty || box.children.contains(where: hasLines)
    }

    /// A geometry pass costs the paragraphs it shapes. An inline-block far
    /// below the demanded region is laid out only once its line is shaped;
    /// laying out every box on every pass made scrolling a chapter of chat
    /// bubbles cost in proportion to all of them.
    @Test func boxBelowTheViewportIsLaidOutOnlyWithItsLine() throws {
        let config = BrowserLayoutConfig(renderWidth: 320, renderHeight: 600, rootFontSize: 10)
        let html = Self.html((0..<300).map { "<p>\($0) " + String(repeating: "filler text ", count: 20) + "</p>" }.joined()
            + "<div><div style=\"\(Self.bubble)\"><p id=\"far\" style=\"margin:0\">far</p></div></div>")
        let session = try HTMLLayoutDocument(html: html, configuration: config).makeViewportSession()
        try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1200))
        let unit = try #require(Self.inlineBlocks(in: session.pipeline.rootBox).first)
        #expect(!Self.hasLines(unit))
        let offset = try #require(session.anchorOffsets["far"])
        try session.layout(in: CGRect(x: 0, y: session.documentY(for: offset), width: 320, height: 1200),
                           anchorOffset: offset)
        #expect(Self.hasLines(unit))
    }

    @Test func scrollModeMatchesEagerLayout() throws {
        let config = BrowserLayoutConfig(renderWidth: 320, renderHeight: 600, rootFontSize: 10)
        let input = HTMLLayoutDocument(html: Self.viewportHTML(), configuration: config)
        let eager = try input.prepareContinuous(validateCapabilities: false).makeDocument()
        let demanded = try input.makeViewportSession().layout(in: CGRect(x: 0, y: 0, width: 320, height: 100_000))
        #expect(Self.messageRect(demanded) == Self.messageRect(eager))
        #expect(Self.messageRect(eager) != nil)
    }
}
