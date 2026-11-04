import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// html.css's inline rules and the block margins around them, against a
/// WKWebView (iOS 27.2, S001 ua-all, horizontal and vertical-rl): `big`,
/// `small`, `sup` and `sub` size their text and their line; `cite`, `var`,
/// `dfn` and `address` are italic; `center` centres; `nobr` does not wrap;
/// `display: initial` and `unset` are inline; a closed `dialog` is not
/// drawn; a block's last child's margin passes out of its parent; CSS's
/// named colours are CSS's (list-marker design step 8f). Every expected
/// number is the web view's.
@Suite @MainActor
struct UserAgentInlineRuleTests {

    private static let css = """
        ul.m, ol.m { margin: 0; padding: 0; list-style: none; }
        .pe { padding-block-end: 1px; } .be { border-block-end: 1px solid black; }
        .neg { margin-block-end: -10px; } .fixed { height: 40px; } .m0 { margin: 0; }
        .as { vertical-align: super; font-size: 75%; } .sz { font-size: 0.7em; }
        .di { display: initial; } .du { display: unset; }
        .n-gray { color: gray; } .n-green { color: green; } .n-orange { color: orange; }
        .n-purple { color: purple; } .n-silver { color: silver; } .n-rebecca { color: rebeccapurple; }
        """

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    /// The probe's vertical chapter gives its fixed sizes physically, as
    /// `width` where the horizontal one has `height`.
    private static func layout(_ body: String, vertical: Bool) async throws -> Layout {
        let sizes = vertical
            ? ".fixed { width: 40px; } .cw { height: 100px; } .narrow { height: 200px; }"
            : ".fixed { height: 40px; } .cw { width: 100px; } .narrow { width: 200px; }"
        return try await BrowserLayoutTestSupport.webKitReference(body, css: css + sizes, vertical: vertical)
    }

    private static func fragment(_ text: String, after: String? = nil, in layout: Layout,
                                 sourceLocation: SourceLocation = #_sourceLocation) throws -> TextFragment {
        try #require(BrowserLayoutTestSupport.fragment(text, after: after, in: layout), "no fragment for \(text)",
                     sourceLocation: sourceLocation)
    }

    /// How far down (across, in vertical-rl) the line of `second` sits
    /// from the line of `first`.
    private static func advance(_ first: TextFragment, _ second: TextFragment, vertical: Bool) -> CGFloat {
        vertical ? first.baselineY - second.baselineY : second.baselineY - first.baselineY
    }

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    // MARK: - Block margins

    /// A last child's bottom margin passes out of a parent with no padding,
    /// border or height there, and collapses with what follows.
    @Test(arguments: [false, true])
    func lastChildMarginPassesOutOfItsParent(vertical: Bool) async throws {
        let cases: [(String, String, CGFloat)] = [
            ("<div><p>甲一段落。</p></div>", "<ol class=\"m\"><li>甲一之後。</li></ol>", 42.5),
            ("<div><div><p>甲二段落。</p></div></div>", "<ol class=\"m\"><li>甲二之後。</li></ol>", 42.5),
            ("<div class=\"pe\"><p>甲三段落。</p></div>", "<ol class=\"m\"><li>甲三之後。</li></ol>", 43.5),
            ("<div class=\"be\"><p>甲四段落。</p></div>", "<ol class=\"m\"><li>甲四之後。</li></ol>", 43.5),
            ("<ul><li><p>甲五段落。</p></li></ul>", "<ol class=\"m\"><li>甲五之後。</li></ol>", 42.5),
            ("<div class=\"neg\"><p>甲六段落。</p></div>", "<ol class=\"m\"><li>甲六之後。</li></ol>", 32.5),
            ("<div class=\"fixed\"><p>甲七段落。</p></div>", "<ol class=\"m\"><li>甲七之後。</li></ol>", 40),
            ("<div><p>甲八段落。</p></div>", "<p>甲八之後段落。</p>", 42.5),
            ("<div class=\"m0\"><div class=\"m0\"><p>甲九段落。</p></div><div></div></div>",
             "<ol class=\"m\"><li>甲九之後。</li></ol>", 42.5),
        ]
        for (first, second, expected) in cases {
            let layout = try await Self.layout("<p>起點。</p>" + first + second, vertical: vertical)
            let f = try Self.fragment(Self.firstText(first), in: layout)
            let s = try Self.fragment(Self.firstText(second), in: layout)
            #expect(Self.near(Self.advance(f, s, vertical: vertical), expected),
                    "\(first) → \(Self.advance(f, s, vertical: vertical)), expected \(expected)")
        }
    }

    /// The first run of text in `html`.
    private static func firstText(_ html: String) -> String {
        var text = "", inTag = false
        for character in html {
            if character == "<" { inTag = true; if !text.isEmpty { break } } else if character == ">" { inTag = false }
            else if !inTag { text.append(character) }
        }
        return text
    }

    // MARK: - big, small, sup, sub

    /// Each line's height (width, in vertical-rl) and the decorated run's
    /// size. WebKit sets an inline box's edges on 1/64 px, so the web view's
    /// line is up to 1/32 px from the engine's.
    @Test(arguments: [false, true])
    func sizesAndLines(vertical: Bool) async throws {
        let cases: [(String, String, CGFloat, CGFloat, CGFloat)] = [
            ("乙一<big>大字</big>乙一尾。", "大字", 20.4, 30.578, 30.578),
            ("乙二<small>小字</small>乙二尾。", "小字", 14.1667, 25.5, 25.5),
            ("乙三<sup>1</sup>乙三尾。", "1", 14.1667, 29.031, 30.031),
            ("乙四<sub>2</sub>乙四尾。", "2", 14.1667, 28.766, 27.766),
            ("乙六<sup>外<sup>內</sup></sup>乙六尾。", "內", 11.8056, 31.469, 33.969),
            ("乙七<span class=\"as\">釋</span>乙七尾。", "釋", 12.75, 26.969, 28.969),
            ("乙八<sup class=\"sz\">3</sup>乙八尾。", "3", 11.9, 25.828, 28.328),
        ]
        for (body, run, size, horizontalLine, verticalLine) in cases {
            let layout = try await Self.layout("<ol class=\"m\"><li>\(body)</li></ol>", vertical: vertical)
            let base = try Self.fragment(String(body.prefix(2)), in: layout)
            let decorated = try Self.fragment(run, after: String(body.prefix(2)), in: layout)
            #expect(Self.near(decorated.font.pointSize, size, 0.005), "\(body) size \(decorated.font.pointSize)")
            let line = vertical ? base.rect.rawValue.width : base.rect.rawValue.height
            let expected = vertical ? verticalLine : horizontalLine
            #expect(Self.near(line, expected, 1.0 / 32), "\(body) line \(line), expected \(expected)")
        }
    }

    /// First-glyph y of the run holding the fragment's text, in its CTLine
    /// (baseline 0, up positive).
    private static func glyphY(_ fragment: TextFragment) -> CGFloat? {
        guard case .linear(let shaped) = fragment.sourceMapping, let line = fragment.ctLine else { return nil }
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let range = CTRunGetStringRange(run)
            guard range.location <= shaped.location, shaped.location < range.location + range.length else { continue }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            return position.y
        }
        return nil
    }

    /// A `sup` rises a third of its parent's size and a pixel, a `sub` falls
    /// a fifth and a pixel, and a nested one adds its own to its parent's.
    @Test func superscriptShifts() async throws {
        let cases: [(String, String, CGFloat)] = [
            ("乙三<sup>1</sup>乙三尾。", "1", 6.672),
            ("乙四<sub>2</sub>乙四尾。", "2", -4.391),
            ("乙六<sup>外<sup>內</sup></sup>乙六尾。", "外", 6.656),
            ("乙六<sup>外<sup>內</sup></sup>乙六尾。", "內", 12.375),
            ("乙七<span class=\"as\">釋</span>乙七尾。", "釋", 6.656),
            ("乙八<sup class=\"sz\">3</sup>乙八尾。", "3", 6.672),
        ]
        for (body, run, expected) in cases {
            let layout = try await Self.layout("<ol class=\"m\"><li>\(body)</li></ol>", vertical: false)
            let base = try #require(Self.glyphY(try Self.fragment(String(body.prefix(2)), in: layout)))
            let shifted = try #require(Self.glyphY(try Self.fragment(run, after: String(body.prefix(2)), in: layout)))
            #expect(Self.near(shifted - base, expected, 0.05), "\(body) \(run) shift \(shifted - base)")
        }
    }

    // MARK: - Other html.css rules

    @Test func italicElements() throws {
        for tag in ["cite", "var", "dfn", "address"] {
            let document = try SwiftSoup.parse("<html><body><p><\(tag) id=\"x\">甲</\(tag)></p></body></html>")
            let tree = ComputedStyleTreeBuilder(rules: [], config: BrowserLayoutConfig())
                .buildTree(body: try #require(document.body()))
            func find(_ node: ComputedStyleNode) -> ComputedStyleNode? {
                if node.anchorID == "x" { return node }
                for child in node.children {
                    if case .element(let element) = child, let found = find(element) { return found }
                }
                return nil
            }
            #expect(try #require(find(tree)).style.isItalic, "\(tag)")
        }
    }

    @Test(arguments: [false, true])
    func centerCentresItsLinesAndBlocks(vertical: Bool) async throws {
        let layout = try await Self.layout("<center>丁四置中</center><center><div class=\"cw\">丁五塊</div></center>",
                                           vertical: vertical)
        func start(_ text: String) throws -> CGFloat {
            let rect = try Self.fragment(text, in: layout).rect.rawValue
            return vertical ? rect.minY : rect.minX
        }
        #expect(Self.near(try start("丁四"), vertical ? 354 : 149))
        #expect(Self.near(try start("丁五"), vertical ? 362.5 : 157.5))
    }

    @Test(arguments: [false, true])
    func nobrDoesNotWrap(vertical: Bool) async throws {
        let layout = try await Self.layout("<p class=\"narrow\">丁七<nobr>不換行的很長很長很長很長很長的文字</nobr>尾。</p>",
                                           vertical: vertical)
        let run = try Self.fragment("不換行", in: layout).rect.rawValue
        #expect(Self.near(vertical ? run.height : run.width, 289))
        let first = try Self.fragment("丁七", in: layout), last = try Self.fragment("尾。", in: layout)
        #expect(Self.near(Self.advance(first, last, vertical: vertical), 51))
    }

    @Test(arguments: [false, true])
    func initialAndUnsetDisplayAreInline(vertical: Bool) async throws {
        let layout = try await Self.layout("<div class=\"di\">庚一起始</div><div class=\"du\">庚二未設</div>", vertical: vertical)
        let a = try Self.fragment("庚一", in: layout), b = try Self.fragment("庚二", in: layout)
        #expect(a.baselineY == b.baselineY)
        #expect(Self.near(vertical ? b.rect.rawValue.minY : b.rect.rawValue.minX, 76))
    }

    @Test(arguments: [false, true])
    func closedDialogIsNotDrawn(vertical: Bool) async throws {
        let layout = try await Self.layout(
            "<ol class=\"m\"><li>庚三之後。</li></ol><dialog>庚四對話</dialog><ol class=\"m\"><li>庚五之後。</li></ol>",
            vertical: vertical)
        #expect(BrowserLayoutTestSupport.fragment("庚四", in: layout) == nil)
        let before = try Self.fragment("庚三", in: layout), after = try Self.fragment("庚五", in: layout)
        #expect(Self.near(Self.advance(before, after, vertical: vertical), 25.5))
    }

    @Test func namedColorsAreCSSColors() async throws {
        let layout = try await Self.layout("""
            <ol class="m"><li>癸一<span class="n-gray">灰</span><span class="n-green">綠</span><span class="n-orange">橙</span>\
            <span class="n-purple">紫</span><span class="n-silver">銀</span><span class="n-rebecca">紫二</span></li></ol>
            """, vertical: false)
        let expected: [(String, [Int])] = [
            ("灰", [128, 128, 128]), ("綠", [0, 128, 0]), ("橙", [255, 165, 0]),
            ("紫", [128, 0, 128]), ("銀", [192, 192, 192]), ("紫二", [102, 51, 153]),
        ]
        for (text, rgb) in expected {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            try Self.fragment(text, after: "癸一", in: layout).color.getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect([r, g, b].map { Int(($0 * 255).rounded()) } == rgb, "\(text)")
        }
    }

    /// A run after a line's first one starts where the one before it ends,
    /// in vertical-rl as horizontally (it once started 8.5 late there).
    @Test(arguments: [false, true])
    func inlineRunsFollowEachOther(vertical: Bool) async throws {
        let layout = try await Self.layout("<ol class=\"m\"><li>丙一<u>底線文字</u>丙一尾。</li></ol>", vertical: vertical)
        let run = try Self.fragment("底線", in: layout).rect.rawValue
        #expect(Self.near(vertical ? run.minY : run.minX, 42))
        let tail = try Self.fragment("丙一尾", in: layout).rect.rawValue
        #expect(Self.near(vertical ? tail.minY : tail.minX, 110))
    }
}
