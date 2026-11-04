import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// The UA declarations that go through the cascade (WebKit html.css, read out
/// of the iOS 27.2 runtime, `UserAgentStyle.declarations`): `p`, `pre`, the
/// headings and `dl` are spaced at their block ends, `blockquote` and `figure`
/// are also inset 40px at both inline ends, `hr` is centred, `dd` and list
/// containers are indented 40px at their inline start, and lists and `dl`s
/// have no block margins inside another list or a `dl`. Logical, so in
/// vertical-rl paragraphs are spaced between columns and a list is indented
/// from the top. Heading sizes are relative to the parent's. In S001c an
/// unstyled `ol` starts 1em after a paragraph; in S001d a vertical item starts
/// 40px below the body's top (list-marker design steps 8 and 8b).
@Suite @MainActor
struct UserAgentDeclarationTests {

    private static func tree(_ body: String, css: String = "",
                             writingMode: ReaderWritingMode = .horizontal) throws -> ComputedStyleNode {
        let document = try SwiftSoup.parse("<html><body>\(body)</body></html>")
        var config = BrowserLayoutConfig()
        config.writingMode = writingMode
        return ComputedStyleTreeBuilder(rules: CSSParser.parse(css: css), config: config)
            .buildTree(body: try #require(document.body()))
    }

    private static func elements(_ node: ComputedStyleNode) -> [ComputedStyleNode] {
        node.children.flatMap { child -> [ComputedStyleNode] in
            guard case .element(let element) = child else { return [] }
            return [element] + elements(element)
        }
    }

    /// Margins, then paddings, each top, right, bottom, left.
    private struct Box: Equatable, CustomStringConvertible {
        let margins: [CSSLength]
        let paddings: [CSSLength]
        var description: String { "margins \(margins) paddings \(paddings)" }
    }

    private static func style(_ body: String, css: String = "",
                              writingMode: ReaderWritingMode = .horizontal) throws -> ComputedStyle {
        try #require(elements(try tree(body, css: css, writingMode: writingMode)).first { $0.anchorID == "x" },
                     "no element #x").style
    }

    private static func box(_ body: String, css: String = "",
                            writingMode: ReaderWritingMode = .horizontal) throws -> Box {
        let s = try style(body, css: css, writingMode: writingMode)
        return Box(margins: [s.marginTop, s.marginRight, s.marginBottom, s.marginLeft],
                   paddings: [s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft])
    }

    private static let zero = CSSLength.px(0)
    private static let noPadding = [zero, zero, zero, zero]

    /// A box with `block` margins at both block ends and `inline` at both
    /// inline ends; vertical-rl's block axis runs right to left.
    private static func margins(block: CSSLength, inline: CSSLength = zero, _ mode: ReaderWritingMode) -> [CSSLength] {
        switch mode {
        case .horizontal: [block, inline, block, inline]
        case .verticalRTL: [inline, block, inline, block]
        }
    }

    private static func listBox(margin: CSSLength, _ mode: ReaderWritingMode) -> Box {
        switch mode {
        case .horizontal: Box(margins: margins(block: margin, mode), paddings: [zero, zero, zero, .px(40)])
        case .verticalRTL: Box(margins: margins(block: margin, mode), paddings: [.px(40), zero, zero, zero])
        }
    }

    @Test(arguments: ReaderWritingMode.allCases)
    func paragraphsAndHeadingsAreSpacedAtTheirBlockEnds(mode: ReaderWritingMode) throws {
        let cases: [(tag: String, em: CGFloat)] = [
            ("p", 1), ("h1", 0.67), ("h2", 0.83), ("h3", 1), ("h4", 1.33), ("h5", 1.67), ("h6", 2.33),
        ]
        for (tag, em) in cases {
            #expect(try Self.box("<\(tag) id=\"x\">甲</\(tag)>", writingMode: mode)
                    == Box(margins: Self.margins(block: .em(em), mode), paddings: Self.noPadding), "\(tag)")
        }
    }

    /// Vertical-rl: inline-start is the top, block-start the right.
    @Test(arguments: ReaderWritingMode.allCases)
    func aBlockquoteIsInsetAtBothInlineEnds(mode: ReaderWritingMode) throws {
        let expected: [CSSLength] = switch mode {
        case .horizontal: [.em(1), .px(40), .em(1), .px(40)]
        case .verticalRTL: [.px(40), .em(1), .px(40), .em(1)]
        }
        #expect(try Self.box("<blockquote id=\"x\">甲</blockquote>", writingMode: mode)
                == Box(margins: expected, paddings: Self.noPadding))
    }

    @Test(arguments: ReaderWritingMode.allCases)
    func preFigureHrAndDdHaveTheirOwnMargins(mode: ReaderWritingMode) throws {
        #expect(try Self.box("<pre id=\"x\">甲</pre>", writingMode: mode)
                == Box(margins: Self.margins(block: .em(1), mode), paddings: Self.noPadding))
        #expect(try Self.box("<figure id=\"x\">甲</figure>", writingMode: mode)
                == Box(margins: Self.margins(block: .em(1), inline: .px(40), mode), paddings: Self.noPadding))
        #expect(try Self.box("<hr id=\"x\"/>", writingMode: mode)
                == Box(margins: Self.margins(block: .em(0.5), inline: .auto, mode), paddings: Self.noPadding))
        let ddMargins: [CSSLength] = switch mode {
        case .horizontal: [Self.zero, Self.zero, Self.zero, .px(40)]
        case .verticalRTL: [.px(40), Self.zero, Self.zero, Self.zero]
        }
        #expect(try Self.box("<dl><dt>甲</dt><dd id=\"x\">乙</dd></dl>", writingMode: mode)
                == Box(margins: ddMargins, paddings: Self.noPadding))
        #expect(try Self.box("<dl id=\"x\"><dt>甲</dt></dl>", writingMode: mode)
                == Box(margins: Self.margins(block: .em(1), mode), paddings: Self.noPadding))
    }

    /// `:heading(n)` sizes are relative to the parent's, so a heading follows
    /// the reader's font size; `h4` has none and inherits.
    @Test func headingSizesAreRelativeToTheParent() throws {
        let cases: [(tag: String, size: CGFloat)] = [
            ("h1", 40), ("h2", 30), ("h3", 23.4), ("h4", 20), ("h5", 16.6), ("h6", 13.4),
        ]
        for (tag, size) in cases {
            let style = try Self.style("<\(tag) id=\"x\">甲</\(tag)>", css: "body { font-size: 20px }")
            #expect(abs(style.fontSize - size) < 0.001, "\(tag) \(style.fontSize)")
            #expect(style.fontWeight == 700, "\(tag)")
        }
        let nested = try Self.style("<div style=\"font-size: 10px\"><h1 id=\"x\">甲</h1></div>",
                                    css: "body { font-size: 20px }")
        #expect(nested.fontSize == 20)
        let authored = try Self.style("<h1 id=\"x\">甲</h1>", css: "body { font-size: 20px } h1 { font-size: 1.2em }")
        #expect(abs(authored.fontSize - 24) < 0.001)
    }

    @Test(arguments: ReaderWritingMode.allCases)
    func aListIsIndentedAtItsInlineStartAndSpacedAtItsBlockEnds(mode: ReaderWritingMode) throws {
        for tag in ["ul", "ol", "menu", "dir"] {
            #expect(try Self.box("<\(tag) id=\"x\"><li>甲</li></\(tag)>", writingMode: mode)
                    == Self.listBox(margin: .em(1), mode), "\(tag)")
        }
    }

    /// `:is(dir, dl, menu, ol, ul) :is(dir, dl, menu, ol, ul) { margin-block: 0 }`:
    /// any depth, and a `dl` counts though it draws no markers.
    @Test(arguments: ReaderWritingMode.allCases)
    func aListInsideAListOrADlHasNoBlockMargins(mode: ReaderWritingMode) throws {
        let nested = [
            "<ul><li><ol id=\"x\"><li>甲</li></ol></li></ul>",
            "<ol><li><div><p>甲</p><ul id=\"x\"><li>乙</li></ul></div></li></ol>",
            "<dl><dd><ul id=\"x\"><li>甲</li></ul></dd></dl>",
            "<menu><li><dir id=\"x\"><li>甲</li></dir></li></menu>",
        ]
        for body in nested {
            #expect(try Self.box(body, writingMode: mode) == Self.listBox(margin: Self.zero, mode), "\(body)")
        }
        let outside = [
            "<div><blockquote><ol id=\"x\"><li>甲</li></ol></blockquote></div>",
            // A list item outside any list is not a list container.
            "<li><ul id=\"x\"><li>甲</li></ul></li>",
        ]
        for body in outside {
            #expect(try Self.box(body, writingMode: mode) == Self.listBox(margin: .em(1), mode), "\(body)")
        }
        // The same rule takes a `dl`'s block margins inside a list or a `dl`.
        for body in ["<ul><li><dl id=\"x\"><dt>甲</dt></dl></li></ul>", "<dl><dd><dl id=\"x\"><dt>甲</dt></dl></dd></dl>"] {
            #expect(try Self.box(body, writingMode: mode)
                    == Box(margins: Self.noPadding, paddings: Self.noPadding), "\(body)")
        }
    }

    /// The UA is the lowest origin: an author's physical or logical
    /// declaration of the same side replaces it, and the other sides stay.
    @Test func authorDeclarationsWin() throws {
        let list = "<ol id=\"x\"><li>甲</li></ol>"
        for mode in ReaderWritingMode.allCases {
            #expect(try Self.box(list, css: "ol { margin: 0; padding-inline-start: 0 }", writingMode: mode)
                    == Box(margins: Self.noPadding, paddings: Self.noPadding), "\(mode)")
            #expect(try Self.box("<p id=\"x\">甲</p>", css: "p { margin: 0 }", writingMode: mode)
                    == Box(margins: Self.noPadding, paddings: Self.noPadding), "\(mode)")
        }
        #expect(try Self.box(list, css: "ol { padding-left: 2em }")
                == Box(margins: [.em(1), Self.zero, .em(1), Self.zero], paddings: [Self.zero, Self.zero, Self.zero, .em(2)]))
        // In vertical-rl the left is the block end: the indent stays on top.
        #expect(try Self.box(list, css: "ol { padding-left: 2em }", writingMode: .verticalRTL)
                == Box(margins: [Self.zero, .em(1), Self.zero, .em(1)], paddings: [.px(40), Self.zero, Self.zero, .em(2)]))
        let quote = "<blockquote id=\"x\">甲</blockquote>"
        #expect(try Self.box(quote, css: "blockquote { margin-left: 0 }")
                == Box(margins: [.em(1), .px(40), .em(1), Self.zero], paddings: Self.noPadding))
        #expect(try Self.box(quote, css: "blockquote { margin-left: 0 }", writingMode: .verticalRTL)
                == Box(margins: [.px(40), .em(1), .px(40), Self.zero], paddings: Self.noPadding))
    }

    /// Laid out: two unstyled paragraphs are one collapsed 1em apart along the
    /// block axis, and start flush at the inline start. Vertical-rl used to
    /// inset every paragraph 1em from the top and bottom and run the columns
    /// together.
    @Test(arguments: ReaderWritingMode.allCases)
    func adjacentParagraphMarginsCollapseAlongTheBlockAxis(mode: ReaderWritingMode) async throws {
        var config = BrowserLayoutConfig(renderWidth: 300, renderHeight: 600, rootFontSize: 17,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        config.writingMode = mode
        let doc = BrowserLayoutDocument(html: "<html><head></head><body><p>甲。</p><p>乙。</p></body></html>",
                                        cssTexts: ["body { margin: 0; line-height: 1.5 }"], config: config)
        let pages = try await doc.renderPages(containerSize: CGSize(width: 300, height: 600))
        let source = doc.lastSourceText as NSString
        let texts = BrowserLayoutTestSupport.allTextFragments(pages).filter { $0.sourceRange.length > 0 }
        func fragment(_ text: String) throws -> TextFragment {
            let location = source.range(of: text).location
            return try #require(texts.first { NSLocationInRange(location, $0.sourceRange) }, "\(text)")
        }
        let first = try fragment("甲"), second = try fragment("乙")
        // Vertical-rl: the baseline is the column's x, right to left.
        let step = mode == .horizontal ? second.baselineY - first.baselineY : first.baselineY - second.baselineY
        #expect(abs(step - (25.5 + 17)) < 0.01, "\(step)")
        let inlineStart = mode == .horizontal ? first.rect.rawValue.minX : first.rect.rawValue.minY
        #expect(abs(inlineStart) < 0.01, "\(inlineStart)")
    }
}
