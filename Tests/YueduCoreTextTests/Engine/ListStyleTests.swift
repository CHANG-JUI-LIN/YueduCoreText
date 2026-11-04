import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// The style and numbering half of list markers: which elements are list items,
/// which marker style each one inherits, and the number each one counts as.
/// Expected values come from the iOS 27.2 WKWebView where a test names an S001c
/// fixture case (`scripts/fidelity/fixtures/gaps/S001c-list-markers` in the App
/// repository); nothing is drawn yet.
@Suite @MainActor
struct ListStyleTests {

    private static func tree(_ body: String, css: String = "") throws -> ComputedStyleNode {
        let document = try SwiftSoup.parse("<html><body>\(body)</body></html>")
        return ComputedStyleTreeBuilder(rules: CSSParser.parse(css: css), config: BrowserLayoutConfig())
            .buildTree(body: try #require(document.body()))
    }

    /// Every element node in tree order.
    private static func elements(_ node: ComputedStyleNode) -> [ComputedStyleNode] {
        node.children.flatMap { child -> [ComputedStyleNode] in
            guard case .element(let element) = child else { return [] }
            return [element] + elements(element)
        }
    }

    private static func node(_ id: String, in root: ComputedStyleNode) throws -> ComputedStyleNode {
        try #require(elements(root).first { $0.anchorID == id }, "no element #\(id)")
    }

    private static func items(_ root: ComputedStyleNode) -> [ComputedStyleNode] {
        elements(root).filter(\.style.isListItem)
    }

    private static func ordinals(_ body: String, css: String = "") throws -> [Int?] {
        items(try tree(body, css: css)).map(\.listItemOrdinal)
    }

    private static func type(_ name: String) -> CSSListStyleType { .counterStyle(name) }

    // MARK: - display: list-item

    @Test func liIsAListItemUntilAnotherDisplayReplacesIt() throws {
        let root = try Self.tree(
            "<ol><li id=a>a</li><li id=b class=block>b</li><li id=c class=ib>c</li><li id=d class=bogus>d</li></ol>",
            css: ".block { display: block } .ib { display: inline-block } .bogus { display: flow-root }"
        )
        #expect(try Self.node("a", in: root).style.isListItem)
        #expect(try !Self.node("b", in: root).style.isListItem)
        #expect(try !Self.node("c", in: root).style.isListItem)
        // An unparsed display value is dropped: the li keeps its UA list-item.
        #expect(try Self.node("d", in: root).style.isListItem)
        #expect(try Self.node("d", in: root).style.display == .block)
    }

    @Test func displayListItemMakesABlockListItemOfAnyElement() throws {
        let root = try Self.tree(
            "<p><span id=s class=item>s</span></p><div id=d class=item>d</div><ol id=o><li>x</li></ol>",
            css: ".item { display: list-item }"
        )
        let span = try Self.node("s", in: root)
        #expect(span.style.isListItem)
        #expect(span.style.display == .block)
        #expect(try Self.node("d", in: root).style.isListItem)
        // The flag is not inherited and a list container is not an item.
        #expect(try !Self.node("o", in: root).style.isListItem)
    }

    // MARK: - list-style-type defaults (WebKit html.css)

    /// S001c 10-nested-ul: disc, circle, square by depth; 10-ol-in-ul and
    /// 10-ul-in-ol: an `ol` stays decimal at any depth, a `ul` in an `ol` is circle.
    @Test func userAgentTypesFollowListNesting() throws {
        let root = try Self.tree("""
            <ul><li id=u1>1<ul><li id=u2>2<ul><li id=u3>3<ul><li id=u4>4</li></ul></li></ul></li></ul></li></ul>
            <ul><li>a<ol><li id=oInU>b</li></ol></li></ul>
            <ol><li id=o1>a<ul><li id=uInO>b</li></ul></li></ol>
            <menu><li id=m1>a<dir><li id=d2>b</li></dir></li></menu>
            <div><li id=orphan>c</li></div>
            """)
        #expect(try Self.node("u1", in: root).style.listStyleType == Self.type("disc"))
        #expect(try Self.node("u2", in: root).style.listStyleType == Self.type("circle"))
        #expect(try Self.node("u3", in: root).style.listStyleType == Self.type("square"))
        #expect(try Self.node("u4", in: root).style.listStyleType == Self.type("square"))
        #expect(try Self.node("oInU", in: root).style.listStyleType == Self.type("decimal"))
        #expect(try Self.node("o1", in: root).style.listStyleType == Self.type("decimal"))
        #expect(try Self.node("uInO", in: root).style.listStyleType == Self.type("circle"))
        #expect(try Self.node("m1", in: root).style.listStyleType == Self.type("disc"))
        #expect(try Self.node("d2", in: root).style.listStyleType == Self.type("circle"))
        // S001c 13-orphan-li: an li in no list keeps the initial disc.
        #expect(try Self.node("orphan", in: root).style.listStyleType == Self.type("disc"))
    }

    /// 三國演義's `ol { list-style-type: none }` reaches the items by
    /// inheritance, and a nested `ul` takes its own UA type again even though
    /// that type (disc at the top level) equals the initial value.
    @Test func authoredTypeInheritsAndANestedListResetsIt() throws {
        let root = try Self.tree(
            "<ol><li id=item>a<ul><li id=inner>b</li></ul></li></ol><div class=none><ul><li id=top>c</li></ul></div>",
            css: "ol { list-style-type: none } .none { list-style-type: none }"
        )
        #expect(try Self.node("item", in: root).style.listStyleType == CSSListStyleType.none)
        #expect(try Self.node("inner", in: root).style.listStyleType == Self.type("circle"))
        #expect(try Self.node("top", in: root).style.listStyleType == Self.type("disc"))
    }

    // MARK: - Longhands

    @Test func listStyleTypeKeepsAnyCounterStyleName() throws {
        let cases: [(css: String, expected: CSSListStyleType)] = [
            ("upper-roman", Self.type("upper-roman")),
            ("CJK-Ideographic", Self.type("cjk-ideographic")),
            ("none", .none),
            // An unknown name is valid and is drawn as decimal later, so it is kept.
            ("hebrew", Self.type("hebrew")),
            ("-moz-whatever", Self.type("-moz-whatever")),
            ("initial", Self.type("disc")),
            // Invalid: dropped, so the `li` rule's `square` survives.
            ("\"→\"", Self.type("square")),
            ("symbols(cyclic \"*\")", Self.type("square")),
            ("3d", Self.type("square")),
            ("default", Self.type("square")),
            ("disc circle", Self.type("square")),
        ]
        for (css, expected) in cases {
            let root = try Self.tree("<ol><li id=x>x</li></ol>", css: "li { list-style-type: square } #x { list-style-type: \(css) }")
            #expect(try Self.node("x", in: root).style.listStyleType == expected, "list-style-type: \(css)")
        }
    }

    @Test func cssWideKeywordsReadTheParent() throws {
        let root = try Self.tree(
            "<ol id=o><li id=i>x</li><li id=u>y</li></ol>",
            css: "#o { list-style: lower-alpha inside } #i { list-style-type: inherit; list-style-position: unset } #u { list-style-type: unset; list-style-position: initial }"
        )
        let inherited = try Self.node("i", in: root).style
        #expect(inherited.listStyleType == Self.type("lower-alpha"))
        #expect(inherited.listStylePosition == .inside)
        let unset = try Self.node("u", in: root).style
        #expect(unset.listStyleType == Self.type("lower-alpha"))
        #expect(unset.listStylePosition == .outside)
    }

    @Test func listStylePositionAcceptsOnlyItsTwoKeywords() throws {
        for (css, expected) in [("inside", CSSListStylePosition.inside), ("outside", .outside), ("center", .inside)] {
            let root = try Self.tree("<ul><li id=x>x</li></ul>", css: "li { list-style-position: inside } #x { list-style-position: \(css) }")
            #expect(try Self.node("x", in: root).style.listStylePosition == expected, "list-style-position: \(css)")
        }
    }

    // MARK: - Shorthand

    @Test func shorthandResetsWhatItLeavesOut() throws {
        let cases: [(css: String, type: CSSListStyleType, position: CSSListStylePosition)] = [
            ("inside", Self.type("disc"), .inside),
            ("decimal", Self.type("decimal"), .outside),
            ("outside upper-roman", Self.type("upper-roman"), .outside),
            ("none", .none, .outside),
            ("none inside", .none, .inside),
            // An image is not drawn; the type it leaves out resets to disc.
            ("url(\"marker one.png\")", Self.type("disc"), .outside),
            ("url(a.png) none", .none, .outside),
            ("none url(a.png) inside", .none, .inside),
            // `none` with the type already set goes to the image.
            ("square none", Self.type("square"), .outside),
            ("none none", .none, .outside),
            ("linear-gradient(red, blue) lower-alpha", Self.type("lower-alpha"), .outside),
        ]
        for (css, type, position) in cases {
            let root = try Self.tree("<ul><li id=x>x</li></ul>", css: "li { list-style: lower-greek inside } #x { list-style: \(css) }")
            let style = try Self.node("x", in: root).style
            #expect(style.listStyleType == type, "list-style: \(css)")
            #expect(style.listStylePosition == position, "list-style: \(css)")
        }
    }

    @Test func invalidShorthandIsDroppedWhole() throws {
        for css in ["decimal inside foo", "disc circle", "inside outside", "none none none",
                    "url(a.png) url(b.png)", "disc none url(a.png)", "inherit inside", "\"-\" inside"] {
            let root = try Self.tree("<ul><li id=x>x</li></ul>", css: "li { list-style: lower-greek inside } #x { list-style: \(css) }")
            let style = try Self.node("x", in: root).style
            #expect(style.listStyleType == Self.type("lower-greek"), "list-style: \(css)")
            #expect(style.listStylePosition == .inside, "list-style: \(css)")
        }
    }

    // MARK: - HTML type attribute

    @Test func typeAttributeMapsByElementAndCase() {
        func hint(_ tag: String, _ type: String) -> HTMLListStyleType? {
            let hints = HTMLPresentationalHintExtractor.extract(from: HTMLSemanticElement(tagName: tag, attributes: ["TYPE": type]))
            guard case .listStyleType(let value)? = hints.first?.value else { return nil }
            #expect(hints.count == 1 && hints[0].property == .listStyleType)
            return value
        }
        #expect(hint("ol", "1") == .decimal)
        #expect(hint("OL", "a") == .lowerAlpha)
        #expect(hint("ol", "A") == .upperAlpha)
        #expect(hint("ol", "i") == .lowerRoman)
        #expect(hint("ol", "I") == .upperRoman)
        #expect(hint("li", "A") == .upperAlpha)
        #expect(hint("ul", "Square") == .square)
        #expect(hint("ul", "CIRCLE") == .circle)
        #expect(hint("li", "disc") == .disc)
        #expect(hint("ul", "None") == HTMLListStyleType.none)
        // `ol` has no bullet keywords, `ul` no ordered ones; the value is never trimmed.
        #expect(hint("ol", "disc") == nil)
        #expect(hint("ul", "A") == nil)
        #expect(hint("ol", " a") == nil)
        #expect(hint("ol", "b") == nil)
        #expect(hint("div", "a") == nil)
        #expect(HTMLPresentationalHintExtractor.extract(from: HTMLSemanticElement(tagName: "ol", attributes: [:])).isEmpty)
    }

    /// S001c 06-type-A and 06-type-i. The hint sits between the UA and author
    /// CSS: it beats the UA `decimal`, an author rule beats it.
    @Test func typeAttributeEntersTheCascadeBelowAuthorCSS() throws {
        let root = try Self.tree(
            "<ol type=A><li id=a>a</li></ol><ol type=i><li id=i>i</li><li id=li type=a>a</li></ol><ol class=styled type=A><li id=s>s</li></ol><ul type=square><li id=q>q</li></ul>",
            css: ".styled { list-style-type: cjk-decimal }"
        )
        #expect(try Self.node("a", in: root).style.listStyleType == Self.type("upper-alpha"))
        #expect(try Self.node("i", in: root).style.listStyleType == Self.type("lower-roman"))
        #expect(try Self.node("li", in: root).style.listStyleType == Self.type("lower-alpha"))
        #expect(try Self.node("s", in: root).style.listStyleType == Self.type("cjk-decimal"))
        #expect(try Self.node("q", in: root).style.listStyleType == Self.type("square"))
    }

    // MARK: - Ordinals

    /// S001c 06-start, 06-reversed, 06-reversed-start, 06-value, 06-alpha-range, 06-roman-range.
    @Test func startReversedAndValueFollowTheMeasuredLists() throws {
        #expect(try Self.ordinals("<ol start=5><li>a<li>b</ol>") == [5, 6])
        #expect(try Self.ordinals("<ol reversed><li>a<li>b<li>c</ol>") == [3, 2, 1])
        #expect(try Self.ordinals("<ol reversed start=10><li>a<li>b</ol>") == [10, 9])
        #expect(try Self.ordinals("<ol><li>a<li value=7>b<li>c<li value=-2>d<li>e<li>f</ol>") == [1, 7, 8, -2, -1, 0])
        #expect(try Self.ordinals("<ol type=a start=0><li>a<li>b<li value=26>c<li>d</ol>") == [0, 1, 26, 27])
        #expect(try Self.ordinals("<ol type=I start=3998><li>a<li>b<li>c</ol>") == [3998, 3999, 4000])
    }

    /// S001c 13-li-block, 13-li-in-div, 13-div-list-item, 13-orphan-li.
    @Test func onlyListItemsCountAndTheyCountWhereverTheyAre() throws {
        #expect(try Self.ordinals("<ol><li>a<li class=block>b<li>c</ol>", css: ".block { display: block }") == [1, 2])
        #expect(try Self.ordinals("<ol><li>a</li><div><li>b</li></div><li>c</li></ol>") == [1, 2, 3])
        // Without an ol/ul/menu ancestor the parent element owns the items.
        #expect(try Self.ordinals("<div><div class=item>a</div><div class=item>b</div></div>",
                                  css: ".item { display: list-item }") == [1, 2])
        #expect(try Self.ordinals("<div><li>a</li></div>") == [1])
        // A hidden item is not in the tree and takes no number.
        #expect(try Self.ordinals("<ol><li>a<li class=gone>b<li hidden>c<li>d</ol>", css: ".gone { display: none }") == [1, 2])
    }

    /// S001c 10-li-starts-with-list: each list numbers its own items; the outer
    /// list resumes after the nested one.
    @Test func nestedListsNumberSeparately() throws {
        let root = try Self.tree("<ol><li id=outer1><ol><li id=inner1>a<li id=inner2>b</ol></li><li id=outer2>c</ol>")
        #expect(try Self.node("outer1", in: root).listItemOrdinal == 1)
        #expect(try Self.node("inner1", in: root).listItemOrdinal == 1)
        #expect(try Self.node("inner2", in: root).listItemOrdinal == 2)
        #expect(try Self.node("outer2", in: root).listItemOrdinal == 2)
    }

    @Test func aListThatIsAlsoAnItemCountsInTheListAroundIt() throws {
        let root = try Self.tree(
            "<ol><li id=a>a</li><ol id=nested class=item reversed><li id=n1>x<li id=n2>y</ol><li id=b>b</li></ol>",
            css: ".item { display: list-item }"
        )
        #expect(try Self.node("a", in: root).listItemOrdinal == 1)
        #expect(try Self.node("nested", in: root).listItemOrdinal == 2)
        #expect(try Self.node("b", in: root).listItemOrdinal == 3)
        #expect(try Self.node("n1", in: root).listItemOrdinal == 2)
        #expect(try Self.node("n2", in: root).listItemOrdinal == 1)
    }

    @Test func valueAppliesInAnyListButStartOnlyOnOl() throws {
        #expect(try Self.ordinals("<ul start=5><li>a<li value=9>b<li>c</ul>") == [1, 9, 10])
        // `value` belongs to li: a div list item ignores it.
        #expect(try Self.ordinals("<ol><li>a</li><div class=item value=9>b</div></ol>", css: ".item { display: list-item }") == [1, 2])
        // An unparseable start falls back as if absent.
        #expect(try Self.ordinals("<ol start=abc><li>a<li>b</ol>") == [1, 2])
        #expect(try Self.ordinals("<ol reversed start=x><li>a<li>b</ol>") == [2, 1])
        #expect(try Self.ordinals("<ol><li>a<li value=\" 4th\">b</ol>") == [1, 4])
    }

    /// The stages between the cascade and box construction rebuild nodes: the
    /// media pass rebuilds a video's ancestors, and a vertical chapter's
    /// `LogicalFlow.styleTree` rebuilds every node. The ordinal must come out of
    /// both, run in `makeLayout`'s order, for `BoxTreeBuilder` to read it.
    @Test func ordinalsSurviveTheStagesBeforeBoxConstruction() throws {
        for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
            let tree = try Self.tree("<ol reversed><li id=a><video src=\"clip.mp4\"></video>a</li><li id=b>b</li></ol>")
            let media = BrowserLayoutSemanticContent.prepareMedia(in: tree, renderWidth: 320)
            #expect(media.root !== tree, "the video should make the media pass rebuild its path")
            let root = LogicalFlow.styleTree(media.root, mode: mode)
            #expect(try Self.node("a", in: root).listItemOrdinal == 2, "mode=\(mode)")
            #expect(try Self.node("b", in: root).listItemOrdinal == 1, "mode=\(mode)")
        }
    }

    @Test func nonItemsHaveNoOrdinal() throws {
        let root = try Self.tree("<ol id=o><li id=i><p id=p>x</p></li></ol>")
        #expect(try Self.node("o", in: root).listItemOrdinal == nil)
        #expect(try Self.node("p", in: root).listItemOrdinal == nil)
        #expect(try Self.node("i", in: root).listItemOrdinal == 1)
    }

    @Test func integersParseByTheHTMLRules() {
        let cases: [(String, Int?)] = [
            ("7", 7), ("  -2", -2), ("+3", 3), ("-0", 0), ("5abc", 5), ("\t\n12 ", 12),
            ("", nil), ("abc", nil), ("-", nil), ("+-1", nil), (" ", nil),
            ("\u{3000}5", nil), ("５", nil), ("1e3", 1),
            ("2147483647", 2147483647), ("-2147483648", -2147483648),
            ("2147483648", nil), ("-2147483649", nil), ("99999999999999999999", nil),
        ]
        for (raw, expected) in cases {
            #expect(ListItemOrdinals.parseInteger(raw) == expected, "\"\(raw)\"")
        }
    }
}
