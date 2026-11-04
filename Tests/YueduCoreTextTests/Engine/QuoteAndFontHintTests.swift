import Testing
import UIKit
@testable import YueduCoreText

/// `q`'s generated quotation marks, `<font>`'s attributes, the generic font
/// families and WebKit's line metrics, against a WKWebView (iOS 27.2, S001
/// ua-all and ua-q, horizontal and vertical-rl; list-marker design step
/// 8f). Every expected number is the web view's, but one: `<font size>`
/// scales from the reader's root size where WebKit's `medium` is a fixed
/// 16px, so its sizes here are WebKit's times 17/16 (maintainer, 2026-11-04).
@Suite @MainActor
struct QuoteAndFontHintTests {

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    private static func fragment(_ text: String, after: String? = nil, in layout: Layout,
                                 sourceLocation: SourceLocation = #_sourceLocation) throws -> TextFragment {
        try #require(BrowserLayoutTestSupport.fragment(text, after: after, in: layout), "no fragment for \(text)",
                     sourceLocation: sourceLocation)
    }

    // MARK: - q

    @Test func quotePairsByLanguage() {
        func outer(_ language: String?) -> String {
            let pairs = QuoteMarks.pairs(forLanguage: language)
            return pairs.prefix(2).map { $0.open + $0.close }.joined(separator: " ")
        }
        #expect(outer("zh-Hant") == "「」 『』")
        #expect(outer("ja") == "「」 『』")
        #expect(outer("zh-CN") == "“” ‘’")
        #expect(outer("zh-TW") == "“” ‘’")
        #expect(outer("zh-HK") == "“” ‘’")
        #expect(outer("ko") == "“” ‘’")
        #expect(outer("en") == "“” ‘’")
        #expect(outer(nil) == "\"\" ''")
        #expect(outer("und") == "\"\" ''")
        // Past the last level, the last repeats.
        let pairs = QuoteMarks.pairs(forLanguage: "en")
        #expect(QuoteMarks.pair(pairs, depth: 5) == pairs.last)
    }

    /// Where the quoted text starts and the closing mark ends, in each
    /// direction; the marks are drawn, not source text.
    @Test(arguments: [false, true])
    func quotesTakeTheirRoom(vertical: Bool) async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference("""
            <p lang="zh-CN">戊一<q>简体引号</q>戊一尾。</p>
            <p lang="zh-CN">戊二<q>外层<q>内层</q>外层</q>戊二尾。</p>
            <p>戊三<q>繁體引號</q>戊三尾。</p>
            <p lang="en">戊四<q>quote</q>戊四尾。</p>
            <p lang="ja">戊五<q>日本引用</q>戊五尾。</p>
            """, vertical: vertical)
        func start(_ text: String) throws -> CGFloat {
            let rect = try Self.fragment(text, in: layout).rect.rawValue
            return vertical ? rect.minY : rect.minX
        }
        // WebKit sets them on 1/64 px: “ is 9.132 wide, its text at 51.125.
        #expect(Self.near(try start("简体"), 51.125))
        #expect(Self.near(try start("内层"), 90.906))
        #expect(Self.near(try start("繁體"), 59))
        #expect(Self.near(try start("quote"), 51.125))
        #expect(Self.near(try start("日本"), 59))
        #expect(Self.near(try start("戊一尾"), 42 + 86.265))

        let generated = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.renderedTextOverride != nil }
        #expect(generated.map { $0.renderedTextOverride ?? "" }.joined()
                == "“”“‘’”「」“”「」")
        #expect(generated.allSatisfy { $0.sourceRange.length == 0 })
        #expect(!layout.doc.lastSourceText.contains("“"))
        #expect(!layout.doc.lastSourceText.contains("「"))
    }

    // MARK: - font

    @Test func legacyFontSizes() {
        let cases: [(String, HTMLFontSizeKeyword?)] = [
            ("1", .xSmall), ("2", .small), ("3", .medium), ("4", .large), ("5", .xLarge), ("6", .xxLarge),
            ("7", .xxxLarge), ("+1", .large), ("-1", .small), ("+5", .xxxLarge), ("0", .xSmall), ("-9", .xSmall),
            (" 4px", .large), ("x", nil), ("", nil), ("+", nil),
        ]
        for (raw, keyword) in cases {
            #expect(HTMLFontSizeKeyword.parse(legacyFontSize: raw) == keyword, "\(raw)")
        }
    }

    @Test func legacyColors() {
        #expect(CSSNamedColors.parseLegacy("red") == CSSRGB(255, 0, 0))
        #expect(CSSNamedColors.parseLegacy("#00f") == CSSRGB(0, 0, 255))
        #expect(CSSNamedColors.parseLegacy("00ff00") == CSSRGB(0, 255, 0))
        #expect(CSSNamedColors.parseLegacy("chucknorris") == CSSRGB(192, 0, 0))
        #expect(CSSNamedColors.parseLegacy("") == nil)
        #expect(CSSNamedColors.parseLegacy("transparent") == nil)
    }

    @Test(arguments: [false, true])
    func fontAttributes(vertical: Bool) async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference("""
            <p>己一<font size="1">一</font><font size="2">二</font><font size="3">三</font><font size="4">四</font>\
            <font size="5">五</font><font size="6">六</font><font size="7">七</font><font size="+1">加</font>\
            <font size="-1">減</font><font size="+5">超</font><font size="0">零</font>尾。</p>
            <p>己二<font color="red">紅</font><font color="#00f">藍</font><font color="00ff00">綠</font>\
            <font color="chucknorris">怪</font><font face="Menlo">Mono</font><font face="NoSuchFont, Courier">Cour</font>尾。</p>
            """, vertical: vertical)
        // WebKit: 10, 13, 16, 18, 24, 32, 48, 18, 13, 48, 10.
        let sizes: [(String, CGFloat)] = [("一", 10), ("二", 13), ("三", 16), ("四", 18), ("五", 24), ("六", 32),
                                          ("七", 48), ("加", 18), ("減", 13), ("超", 48), ("零", 10)]
        for (text, webKit) in sizes {
            let size = try Self.fragment(text, after: "己一", in: layout).font.pointSize
            #expect(Self.near(size, webKit * 17 / 16, 0.001), "\(text) \(size)")
        }
        let colors: [(String, [Int])] = [("紅", [255, 0, 0]), ("藍", [0, 0, 255]), ("綠", [0, 255, 0]), ("怪", [192, 0, 0])]
        for (text, rgb) in colors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            try Self.fragment(text, after: "己二", in: layout).color.getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect([r, g, b].map { Int(($0 * 255).rounded()) } == rgb, "\(text)")
        }
        #expect(try Self.fragment("Mono", in: layout).font.fontName == "Menlo-Regular")
        #expect(try Self.fragment("Cour", in: layout).font.fontName == "Courier")
        // Menlo's 40.94 and Courier's 40.81, as measured.
        let mono = try Self.fragment("Mono", in: layout).rect.rawValue
        #expect(Self.near(vertical ? mono.height : mono.width, 40.939, 0.002))
    }

    // MARK: - Generic families and metrics

    @Test func genericFamilies() {
        func name(_ family: String, _ language: String?) -> String? {
            GenericFontFamily.font(named: family, language: language, size: 17)?.fontName
        }
        #expect(name("serif", nil) == "TimesNewRomanPSMT")
        #expect(name("sans-serif", nil) == "Helvetica")
        #expect(name("cursive", nil) == "SnellRoundhand")
        #expect(name("fantasy", nil) == "Papyrus")
        #expect(name("monospace", nil) == "Courier")
        #expect(name("serif", "zh-Hant") == "PingFangTC-Regular")
        #expect(name("sans-serif", "zh-CN") == "PingFangSC-Regular")
        #expect(name("serif", "zh-HK") == "PingFangHK-Regular")
        #expect(name("monospace", "zh-Hant") == "Menlo-Regular")
        #expect(name("serif", "ja") == "HiraMinProN-W3")
        #expect(name("sans-serif", "ja") == "HiraginoSans-W4")
        #expect(name("cursive", "ko") == "AppleSDGothicNeo-Regular")
        #expect(name("fantasy", "en") == "Zapfino")
        #expect(name("fantasy", "ru") == "SnellRoundhand")
        #expect(name("system-ui", "zh-Hant") == UIFont.systemFont(ofSize: 17).fontName)
        #expect(name("Georgia", nil) == nil)
    }

    /// A 17px span in each face on a 17px PingFang line at 1.5: WebKit
    /// rounds each box's ascent and descent up, Times and Helvetica gaining
    /// 15% above.
    @Test func lineHeightsFollowWebKitMetrics() async throws {
        let cases: [(String, CGFloat)] = [
            ("Menlo-Regular", 26.5), ("system-ui", 26), ("HiraMinProN-W3", 26), ("TimesNewRomanPSMT", 26),
            ("AppleSDGothicNeo-Regular", 27), ("SnellRoundhand", 27), ("Zapfino", 29), ("Helvetica", 25.5),
        ]
        for (face, expected) in cases {
            let layout = try await BrowserLayoutTestSupport.webKitReference(
                "<p>甲<span style=\"font-family: \(face)\">Hamburgefonstiv</span></p>")
            let line = try Self.fragment("甲", in: layout).rect.rawValue.height
            #expect(Self.near(line, expected), "\(face) \(line)")
        }
    }
}
