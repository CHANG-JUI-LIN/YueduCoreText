import Testing
import UIKit
@testable import YueduCoreText
import YueduCoreTextTypography

/// Which fonts size a line, and where a centred line ends, against a WKWebView
/// (iOS 27.2, the app's S001h fixture): Han text in a font without Han is drawn
/// in its language's font, which WebKit treats as a fallback. At a fixed
/// line-height a fallback font does not grow the line; at `normal` it does,
/// with its own content area, and Han in the system font falls back through
/// the system's cascade, not the app's stand-in. Collapsible spaces at a line's
/// start and end take no part in placing it, also inside an inline element
/// next to a `<br>`, and a space right after another across an element's
/// boundary collapses. Every expected number is the web view's.
@Suite @MainActor
struct FallbackLineBoxTests {

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    private static let han = "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"

    private static let css = """
        .georgia { font-family: Georgia; }
        .sysui { font-family: -apple-system; }
        .helv { font-family: Helvetica; }
        .fixed { line-height: 25.5px; }
        .normal { line-height: normal; }
        .c { text-align: center; }
        """

    /// The baselines of the lines of `han`'s `occurrence`th copy in the source.
    private static func baselines(occurrence: Int, in layout: Layout) -> [CGFloat] {
        let source = layout.doc.lastSourceText as NSString
        var range = NSRange(location: 0, length: 0)
        for _ in 0...occurrence {
            let start = NSMaxRange(range)
            range = source.range(of: han, range: NSRange(location: start, length: source.length - start))
            if range.location == NSNotFound { return [] }
        }
        let lines = BrowserLayoutTestSupport.allTextFragments(layout.pages)
            .filter { $0.sourceRange.length > 0 && NSIntersectionRange($0.sourceRange, range).length > 0 }
            .map(\.baselineY)
        return Array(Set(lines.map { ($0 * 100).rounded() / 100 })).sorted()
    }

    /// Each paragraph's first baseline and its line pitch: Georgia, the system
    /// font and Helvetica at 25.5px keep PingFang's 25.5 (Georgia and the system
    /// font with their own baseline, 18.75 below the line's top); at `normal`,
    /// Georgia's lines take PingFang's 25 and the system font's its own 22.
    @Test(arguments: [
        ("georgia fixed", "georgia fixed", 78.25, 25.5),
        ("georgia normal", "georgia normal", 197.5, 25),
        ("system fixed", "sysui fixed", 314.25, 25.5),
        ("system normal", "sysui normal", 431.5, 22),
        ("helvetica fixed", "helv fixed", 538.75, 25.5),
        ("pingfang fixed", "fixed", 657.75, 25.5),
    ])
    func fallbackFontsSizeLinesOnlyAtNormal(name: String, classes: String, firstBaseline: CGFloat, pitch: CGFloat) async throws {
        _ = name
        let paragraphs = [
            ("georgia fixed"), ("georgia normal"), ("sysui fixed"), ("sysui normal"), ("helv fixed"), ("fixed"),
        ].map { "<p class=\"\($0)\">\(Self.han)</p>" }.joined()
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p>起點段落。</p>" + paragraphs, css: Self.css)
        let occurrence = try #require(["georgia fixed", "georgia normal", "sysui fixed", "sysui normal", "helv fixed", "fixed"]
            .firstIndex(of: classes))
        let lines = Self.baselines(occurrence: occurrence, in: layout)
        try #require(lines.count == 4, "\(name): \(lines)")
        #expect(abs(lines[0] - firstBaseline) <= 0.01, "\(name): first baseline \(lines[0])")
        for index in 1..<lines.count {
            #expect(abs(lines[index] - lines[index - 1] - pitch) <= 0.01, "\(name): \(lines)")
        }
    }

    /// The app's own default: no family, so the system font, with Han in the
    /// app's PingFang TC stand-in. Its lines are those of `-apple-system`: 25.5
    /// at line-height 1.5, 22 at `normal`, not the stand-in's.
    @Test(arguments: [(nil, 25.5), ("normal", 22)] as [(String?, CGFloat)])
    func theSystemFontWithAStandInKeepsItsLineHeight(lineHeight: String?, pitch: CGFloat) async throws {
        let css = lineHeight.map { "p { line-height: \($0); }" } ?? ""
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p>起點段落。</p><p>\(Self.han)</p>", css: css, rootFamilies: [], cjk: .traditional)
        let lines = Self.baselines(occurrence: 0, in: layout)
        try #require(lines.count == 4, "\(lines)")
        for index in 1..<lines.count {
            #expect(abs(lines[index] - lines[index - 1] - pitch) <= 0.01, "\(lines)")
        }
    }

    /// A `sup` at `line-height: normal` in a vertical line at 160%: its
    /// inline box is its own `normal` one, PingFang SC's 12 + 4 at 10.625px,
    /// about the central baseline and raised 6.67 toward the right. The
    /// column with it gains 1.06 on its right, not the 6.67 its block's
    /// line-height would give it. Measured, WKWebView iOS 27.2, the corpus's
    /// redchamber-vertical (spine 92, `sup.calibre12`, in PingFang SC): 28.26
    /// from the column before it, 27.2 to the one after.
    @Test func aSuperscriptAtNormalKeepsItsOwnBoxInAVerticalLine() async throws {
        let css = """
            p { line-height: 160%; }
            sup.c { font-size: 0.625em; line-height: normal; vertical-align: super; }
            """
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p>\(Self.han)<sup class=\"c\">〔一〕</sup>\(Self.han)</p>", css: css, vertical: true)
        let plain = try #require(BrowserLayoutTestSupport.fragment("這一年", in: layout))
        let marked = try #require(BrowserLayoutTestSupport.fragment("〔一〕", in: layout))
        let columns = BrowserLayoutTestSupport.allTextFragments(layout.pages)
            .filter { $0.sourceRange.length > 0 }
            .map { ($0.rect.rawValue.minX, $0.rect.rawValue.width) }
        #expect(abs(plain.rect.rawValue.width - 27.2) <= 1.0 / 32, "plain column \(plain.rect.rawValue.width)")
        let line = try #require(BrowserLayoutTestSupport.allTextFragments(layout.pages).first {
            $0.sourceRange.length > 0 && abs($0.rect.rawValue.midX - marked.rect.rawValue.midX) < 20
                && $0.font.pointSize > 16
        })
        #expect(abs(line.rect.rawValue.width - 28.26) <= 1.0 / 32, "sup column \(line.rect.rawValue.width); \(columns)")
    }

    /// A font's content area, its ascent and descent each rounded up: Times
    /// and Helvetica gain 15% of their height above, itself rounded up, and a
    /// Hiragino face keeps its own descent. Measured, WKWebView iOS 27.2 (the
    /// app's S001i fixture, `Hg` in a span at `normal`): every expected height
    /// is the span's box.
    @Test(arguments: [
        ("Helvetica", 8.5, 11), ("Helvetica", 14, 18), ("Helvetica", 15, 19), ("Helvetica", 16, 20),
        ("Times-Roman", 16, 19),
        ("HiraginoSans-W3", 8.5, 10), ("HiraginoSans-W3", 10, 11), ("HiraginoSans-W3", 12, 13),
        ("HiraginoSans-W3", 16, 17),
    ] as [(String, CGFloat, CGFloat)])
    func contentAreasRoundAsWebKitOnIOS(name: String, size: CGFloat, height: CGFloat) throws {
        let font = try #require(UIFont(name: name, size: size))
        let extent = InlineLayout.roundedContentExtent(font)
        #expect(extent.ascent + extent.descent == height, "\(name) \(size): \(extent)")
    }

    /// Latin and Han mixed in Georgia at 25.5px: three lines, 76.5 tall.
    @Test func mixedLatinAndHanKeepTheirLineHeight() async throws {
        let text = "Autumn 這一年的秋天 came at once 九月一日的早晨 crisp as an apple 小小的一家人 crossing the road 走向龐大的火車站"
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p>起點段落。</p><p class=\"georgia fixed\">\(text)</p>", css: Self.css)
        let fragments = BrowserLayoutTestSupport.allTextFragments(layout.pages)
            .filter { $0.sourceRange.length > 0 && $0.sourceRange.location >= 5 }
        let lines = Array(Set(fragments.map { ($0.baselineY * 100).rounded() / 100 })).sorted()
        try #require(lines.count == 3, "\(lines)")
        #expect(abs(lines[2] - lines[0] - 51) <= 0.01, "\(lines)")
    }

    /// A centred line's spaces at its start and end go before it is centred,
    /// also a space inside an element that ends just before the `<br>`: a 50px
    /// image alone on its line starts at 158; 甲乙 丙丁 at 146; 甲乙丙丁 at 149.
    @Test func lineEndSpacesInsideAnElementAreNotCentred() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 50, height: 50), color: .gray)
        let body = """
            <p class="c"><span>尾聲</span><br/> <span> <img alt="" src="mark.png" width="50" height="50"/> </span><br/>十九年後</p>\
            <p class="c">甲乙 <span>丙丁 </span><br/>戊</p>\
            <p class="c">庚辛壬癸 <br/>子</p>
            """
        let layout = try await BrowserLayoutTestSupport.webKitReference(body, css: Self.css, imageLoader: { _ in image })
        let picture = try #require(BrowserLayoutTestSupport.allImageFragments(layout.pages).first)
        #expect(abs(picture.rect.rawValue.minX - 158) <= 0.01, "image at \(picture.rect.rawValue.minX)")
        let first = try #require(BrowserLayoutTestSupport.fragment("甲乙", in: layout))
        #expect(abs(first.rect.rawValue.minX - 146) <= 0.25, "甲乙 at \(first.rect.rawValue.minX)")
        let second = try #require(BrowserLayoutTestSupport.fragment("庚辛", in: layout))
        #expect(abs(second.rect.rawValue.minX - 149) <= 0.25, "庚辛 at \(second.rect.rawValue.minX)")
    }

    /// A line after a `<br>` starts at the line's start, not a space in; a space
    /// right after another, across an element's boundary, takes no room; a
    /// right-aligned line ends at its last character, not its trailing space.
    @Test func lineStartAndDoubledSpacesTakeNoRoom() async throws {
        let body = """
            <p>甲乙<br/> <span>丙丁</span></p>\
            <p>子丑 <span> <span>寅卯</span></span></p>\
            <p style="text-align: right">辰巳午未 <br/>申</p>
            """
        let layout = try await BrowserLayoutTestSupport.webKitReference(body, css: Self.css)
        let afterBreak = try #require(BrowserLayoutTestSupport.fragment("丙丁", in: layout))
        #expect(abs(afterBreak.rect.rawValue.minX - 8) <= 0.01, "丙丁 at \(afterBreak.rect.rawValue.minX)")
        let doubled = try #require(BrowserLayoutTestSupport.fragment("寅卯", in: layout))
        #expect(abs(doubled.rect.rawValue.minX - 47.661) <= 0.01, "寅卯 at \(doubled.rect.rawValue.minX)")
        let right = try #require(BrowserLayoutTestSupport.fragment("辰巳", in: layout))
        #expect(abs(right.rect.rawValue.minX - 290) <= 0.01, "辰巳 at \(right.rect.rawValue.minX)")
    }
}
