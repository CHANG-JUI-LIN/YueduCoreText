import Testing
import UIKit
@testable import YueduCoreText

/// Ruby annotation sides against WebKit (WKWebView iOS 27.2, the app's S001m-ruby-positions and
/// S001n-vertical-ruby-positions fixtures, 2026-11-04): over and under a base, the nested rubies
/// Aozora's readings on both sides are written as, and the lines they grow.
struct RubyPositionReferenceTests {
    typealias Row = (name: String, html: String, text: String)

    private static let css = """
        .under, ruby.left { -webkit-ruby-position: after; ruby-position: under; }
        .over { -webkit-ruby-position: before; ruby-position: over; }
        .normal { line-height: normal; }
        """

    private static let rows: [Row] = [
        ("p0", "<p>起點段落。</p>", "起點段落。"),
        ("over-p", "<p>甲<ruby>漢字<rt>かんじ</rt></ruby>乙</p>", "甲漢字乙"),
        ("under-p", "<p>甲<ruby class=\"under\">漢字<rt>かんじ</rt></ruby>乙</p>", "甲漢字乙"),
        ("left-p", "<p>甲<ruby class=\"left\">漢字<rt>かんじ</rt></ruby>乙</p>", "甲漢字乙"),
        ("nested-p", "<p>甲<ruby class=\"left\"><ruby>漢字<rt>かんじ</rt></ruby><rt>カンジ</rt></ruby>乙</p>", "甲漢字乙"),
        ("wide-p", "<p>甲<ruby class=\"under\">字<rt>ながいよみがな</rt></ruby>乙</p>", "甲字乙"),
        ("rl-p", "<p>甲<ruby class=\"left\"><ruby class=\"over\">漢字<rt>かんじ</rt></ruby><rt>カンジ</rt></ruby>乙</p>", "甲漢字乙"),
        ("lr-p", "<p>甲<ruby class=\"over\"><ruby class=\"left\">漢字<rt>カンジ</rt></ruby><rt>かんじ</rt></ruby>乙</p>", "甲漢字乙"),
        ("rr-p", "<p>甲<ruby class=\"over\"><ruby class=\"over\">漢字<rt>かんじ</rt></ruby><rt>ママ</rt></ruby>乙</p>", "甲漢字乙"),
        ("rl-wide-p", "<p>甲<ruby class=\"left\"><ruby class=\"over\">字<rt>ながいよみ</rt></ruby><rt>ナガイヨミガナ</rt></ruby>乙</p>", "甲字乙"),
        ("rl-narrow-p", "<p>甲<ruby class=\"left\"><ruby class=\"over\">漢字熟語<rt>かん</rt></ruby><rt>ゴ</rt></ruby>乙</p>", "甲漢字熟語乙"),
        ("after-p", "<p>基準基準</p>", "基準基準"),
        ("multi-p", "<p>這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生<ruby class=\"under\">金爛爛<rt>きんらんらん</rt></ruby>的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人</p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人"),
        ("normal-p", "<p class=\"normal\">甲<ruby class=\"under\">漢字<rt>かんじ</rt></ruby>乙</p>", "甲漢字乙"),
        ("rl-normal-p", "<p class=\"normal\">甲<ruby class=\"left\"><ruby class=\"over\">漢字<rt>かんじ</rt></ruby><rt>カンジ</rt></ruby>乙</p>", "甲漢字乙"),
        ("last", "<p>基準基準</p>", "基準基準"),
    ] + lineRows + [("end", "<p>基準基準</p>", "基準基準")]

    /// Three lines broken by `br`, a ruby under, over or on both sides on the first, second or
    /// third (`u1`...`b3`), or under on all three (`ua`): where a ruby's room depends on its line.
    private static let lineRows: [Row] = {
        let rubies = [
            ("u", "<ruby class=\"under\">漢字<rt>かんじ</rt></ruby>"),
            ("o", "<ruby>漢字<rt>かんじ</rt></ruby>"),
            ("b", "<ruby class=\"left\"><ruby class=\"over\">漢字<rt>かんじ</rt></ruby><rt>カンジ</rt></ruby>"),
        ]
        func row(_ name: String, rubyOn lines: Set<Int>, _ ruby: String) -> Row {
            let html = (0..<3).map { lines.contains($0) ? "甲乙丙\(ruby)丁戊己庚辛" : "甲乙丙丁戊己庚辛壬癸" }
            let text = (0..<3).map { lines.contains($0) ? "甲乙丙漢字丁戊己庚辛" : "甲乙丙丁戊己庚辛壬癸" }
            return (name, "<p>" + html.joined(separator: "<br/>") + "</p>", text.joined(separator: "\n"))
        }
        return rubies.flatMap { side, ruby in (0..<3).map { row("\(side)\($0 + 1)", rubyOn: [$0], ruby) } }
            + [row("ua", rubyOn: [0, 1, 2], rubies[0].1)]
    }()

    /// Each row's first baseline from the first row's: its y, or in vertical-rl its x (so the
    /// columns run negative). The two agree until the long row, which wraps differently.
    private static let horizontalBaselines: [(String, CGFloat)] = [
        ("over-p", 55.25), ("under-p", 97.75), ("left-p", 153.0), ("nested-p", 208.25), ("wide-p", 276.5),
        ("rl-p", 344.5), ("lr-p", 413.0), ("rr-p", 494.0), ("rl-wide-p", 549.25), ("rl-narrow-p", 617.5),
        ("after-p", 673.0), ("multi-p", 715.5), ("normal-p", 897.75), ("rl-normal-p", 965.75), ("last", 1021.0),
    ]
    private static let verticalBaselines: [(String, CGFloat)] = [
        ("over-p", -55.25), ("under-p", -97.75), ("left-p", -153.0), ("nested-p", -208.25), ("wide-p", -276.5),
        ("rl-p", -344.5), ("lr-p", -413.0), ("rr-p", -494.0), ("rl-wide-p", -549.25), ("rl-narrow-p", -617.5),
        ("after-p", -673.0), ("multi-p", -715.5), ("normal-p", -821.5), ("rl-normal-p", -889.5), ("last", -944.75),
    ]

    /// Each line's baseline in `lineRows` from the first row's, as in `horizontalBaselines` and
    /// `verticalBaselines`. A ruby on a block's first line grows it as on a line of its own; on a
    /// later line by CSS Ruby's rule: 0.25 less on its side, or with a reading on each side 0.25 less
    /// over and 12.5 more under.
    private static let lineBaselines: [(row: String, line: Int, horizontal: CGFloat, vertical: CGFloat)] = [
        ("u1", 0, 1063.5, -987.25), ("u1", 1, 1101.75, -1025.5), ("u1", 2, 1127.25, -1051),
        ("u2", 0, 1169.75, -1093.5), ("u2", 1, 1195.25, -1119), ("u2", 2, 1233.25, -1157),
        ("u3", 0, 1275.75, -1199.5), ("u3", 1, 1301.25, -1225), ("u3", 2, 1326.75, -1250.5),
        ("o1", 0, 1394.5, -1318.25), ("o1", 1, 1420, -1343.75), ("o1", 2, 1445.5, -1369.25),
        ("o2", 0, 1488, -1411.75), ("o2", 1, 1526, -1449.75), ("o2", 2, 1551.5, -1475.25),
        ("o3", 0, 1594, -1517.75), ("o3", 1, 1619.5, -1543.25), ("o3", 2, 1657.5, -1581.25),
        ("b1", 0, 1712.75, -1636.5), ("b1", 1, 1751.25, -1675), ("b1", 2, 1776.75, -1700.5),
        ("b2", 0, 1819.25, -1743), ("b2", 1, 1857.25, -1781), ("b2", 2, 1908.25, -1832),
        ("b3", 0, 1950.75, -1874.5), ("b3", 1, 1976.25, -1900), ("b3", 2, 2014.25, -1938),
        ("ua", 0, 2082.25, -2006), ("ua", 1, 2120.5, -2044.25), ("ua", 2, 2158.5, -2082.25),
        ("end", 0, 2213.5, -2137.25),
    ]

    /// Each annotation's baseline from its base's, toward the under side: down, or left in
    /// vertical-rl, where a line's baseline is its centre. Horizontally over is 22 up, under 16
    /// down; vertically 19 either side. A second annotation on a side goes 13 further.
    private static let annotations: [(row: String, text: String, horizontal: CGFloat, vertical: CGFloat)] = [
        ("over-p", "かんじ", -22, -19), ("under-p", "かんじ", 16, 19), ("left-p", "かんじ", 16, 19),
        ("nested-p", "かんじ", 16, 19), ("nested-p", "カンジ", 29, 32), ("wide-p", "ながいよみがな", 16, 19),
        ("rl-p", "かんじ", -22, -19), ("rl-p", "カンジ", 16, 19),
        ("lr-p", "カンジ", 16, 19), ("lr-p", "かんじ", -22, -19),
        ("rr-p", "かんじ", -22, -19), ("rr-p", "ママ", -35, -32),
        ("rl-wide-p", "ながいよみ", -22, -19), ("rl-wide-p", "ナガイヨミガナ", 16, 19),
        ("rl-narrow-p", "かん", -22, -19), ("rl-narrow-p", "ゴ", 16, 19),
        ("multi-p", "きんらんらん", 16, 19), ("normal-p", "かんじ", 16, 19),
        ("rl-normal-p", "かんじ", -22, -19), ("rl-normal-p", "カンジ", 16, 19),
    ]

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    private static func layout(vertical: Bool) async throws -> Layout {
        try await BrowserLayoutTestSupport.webKitReference(rows.map(\.html).joined(), css: css, vertical: vertical)
    }

    /// Each row's source range, found in source order.
    private static func ranges(in layout: Layout) -> [String: NSRange] {
        let source = layout.doc.lastSourceText as NSString
        var cursor = 0
        var result: [String: NSRange] = [:]
        for row in rows {
            let found = source.range(of: row.text, range: NSRange(location: cursor, length: source.length - cursor))
            guard found.location != NSNotFound else { continue }
            cursor = NSMaxRange(found)
            result[row.name] = found
        }
        return result
    }

    @Test(arguments: [false, true])
    func rowsGrowAsWebKitGrowsThem(vertical: Bool) async throws {
        let layout = try await Self.layout(vertical: vertical)
        #expect(layout.doc.lastSourceText.contains("甲漢字乙"))
        let ranges = Self.ranges(in: layout)
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
        func baseline(_ row: String) -> CGFloat? {
            guard let range = ranges[row] else { return nil }
            return texts.first { $0.renderedTextOverride == nil && NSLocationInRange(range.location, $0.sourceRange) }?.baselineY
        }
        let origin = try #require(baseline("p0"))
        for (name, expected) in vertical ? Self.verticalBaselines : Self.horizontalBaselines {
            let got = try #require(baseline(name), "\(name) not found")
            #expect(abs(got - origin - expected) <= 0.01, "\(name): \(got - origin), WebKit \(expected)")
        }
    }

    @Test(arguments: [false, true])
    func everyLineSitsWhereWebKitSetsIt(vertical: Bool) async throws {
        let layout = try await Self.layout(vertical: vertical)
        let ranges = Self.ranges(in: layout)
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
        func baseline(at offset: Int) -> CGFloat? {
            texts.first { $0.renderedTextOverride == nil && NSLocationInRange(offset, $0.sourceRange) }?.baselineY
        }
        let first = try #require(ranges["p0"])
        let origin = try #require(baseline(at: first.location))
        for line in Self.lineBaselines {
            // Each line is ten characters and its line break.
            let row = try #require(ranges[line.row], "\(line.row) not found")
            let start = row.location + line.line * 11
            let got = try #require(baseline(at: start), "\(line.row) line \(line.line) not found")
            let expected = vertical ? line.vertical : line.horizontal
            #expect(abs(got - origin - expected) <= 0.01,
                    "\(line.row) line \(line.line): \(got - origin), WebKit \(expected)")
        }
    }

    @Test(arguments: [false, true])
    func annotationsSitWhereWebKitSetsThem(vertical: Bool) async throws {
        let layout = try await Self.layout(vertical: vertical)
        let ranges = Self.ranges(in: layout)
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
        for annotation in Self.annotations {
            let range = try #require(ranges[annotation.row])
            let found = try #require(texts.first {
                $0.renderedTextOverride == annotation.text && NSIntersectionRange($0.sourceRange, range).length > 0
            }, "\(annotation.row) \(annotation.text) not drawn")
            let base = try #require(texts.first {
                $0.renderedTextOverride == nil && NSIntersectionRange($0.sourceRange, found.sourceRange).length > 0
            })
            // Toward the under side: down, or left (x falling) in vertical-rl.
            let offset = vertical ? base.baselineY - found.baselineY : found.baselineY - base.baselineY
            let expected = vertical ? annotation.vertical : annotation.horizontal
            #expect(abs(offset - expected) <= 0.01, "\(annotation.row) \(annotation.text): \(offset), WebKit \(expected)")
        }
    }
}
