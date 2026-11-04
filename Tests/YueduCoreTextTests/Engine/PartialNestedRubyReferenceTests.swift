import Testing
import UIKit
@testable import YueduCoreText

/// A ruby whose base holds rubies beside other text, as the Aozora converter writes a note on part
/// of a word with ruby, against WebKit (WKWebView iOS 26.5, the app's S001o-partial-nested-ruby and
/// S001p-vertical-partial-nested-ruby fixtures, 2026-11-04). Each inner ruby takes the room of its
/// base or its annotation, whichever is longer, its base centred in it, and the outer base runs on
/// past it; the outer annotation spans the whole base, beyond the inner annotations on a side it
/// shares with them, and grows the lines as a ruby inside a ruby does (`RubyPositionReferenceTests`).
struct PartialNestedRubyReferenceTests {
    typealias Row = (name: String, html: String, text: String)

    private static let css = """
        .under, ruby.left { -webkit-ruby-position: after; ruby-position: under; }
        .over { -webkit-ruby-position: before; ruby-position: over; }
        """

    private static let rows: [Row] = [
        ("p0", "<p>起點段落。</p>", "起點段落。"),
        ("pre", "<p>甲<ruby><ruby>制<rt>（ママ）</rt></ruby>肘<rt>ちゅう</rt></ruby>乙</p>", "甲制肘乙"),
        ("post", "<p>甲<ruby>辞<ruby>義<rt>ママ</rt></ruby><rt>じぎ</rt></ruby>乙</p>", "甲辞義乙"),
        ("mid", "<p>甲<ruby>目的<ruby>欸<rt>（疑）</rt></ruby>已<rt>のみ</rt></ruby>乙</p>", "甲目的欸已乙"),
        ("lo", "<p>甲<ruby class=\"left\">天の配<ruby class=\"over\">剤<rt>ザイ</rt></ruby><rt>いかにもむずかしいハイザイね</rt></ruby>乙</p>", "甲天の配剤乙"),
        ("ol", "<p>甲<ruby>其<ruby class=\"left\">駁雑<rt>トリマゼ</rt></ruby><rt>そのはくざつ</rt></ruby>乙</p>", "甲其駁雑乙"),
        ("span", "<p>甲<ruby class=\"left\"><span><ruby class=\"over\">来<rt>き</rt></ruby>た</span><rt>北</rt></ruby>乙</p>", "甲来た乙"),
        ("wi", "<p>甲<ruby><ruby>小高坂<rt>（高知城西）</rt></ruby>辺<rt>ヘン</rt></ruby>乙</p>", "甲小高坂辺乙"),
        ("two", "<p>甲<ruby><ruby>万<rt>（ママ）</rt></ruby>更<ruby>椽<rt>（ママ）</rt></ruby><rt>ざらえん</rt></ruby>乙</p>", "甲万更椽乙"),
        ("after", "<p>基準基準</p>", "基準基準"),
        ("n1", "<p>甲乙丙<ruby><ruby>制<rt>（ママ）</rt></ruby>肘<rt>ちゅう</rt></ruby>丁戊己庚辛<br/>甲乙丙丁戊己庚辛壬癸<br/>甲乙丙丁戊己庚辛壬癸</p>",
         "甲乙丙制肘丁戊己庚辛\n甲乙丙丁戊己庚辛壬癸\n甲乙丙丁戊己庚辛壬癸"),
        ("n2", "<p>甲乙丙丁戊己庚辛壬癸<br/>甲乙丙<ruby><ruby>制<rt>（ママ）</rt></ruby>肘<rt>ちゅう</rt></ruby>丁戊己庚辛<br/>甲乙丙丁戊己庚辛壬癸</p>",
         "甲乙丙丁戊己庚辛壬癸\n甲乙丙制肘丁戊己庚辛\n甲乙丙丁戊己庚辛壬癸"),
        ("b1", "<p>甲乙丙<ruby class=\"left\">天の配<ruby class=\"over\">剤<rt>ザイ</rt></ruby><rt>ハイザイ</rt></ruby>丁戊己庚辛<br/>甲乙丙丁戊己庚辛壬癸<br/>甲乙丙丁戊己庚辛壬癸</p>",
         "甲乙丙天の配剤丁戊己庚辛\n甲乙丙丁戊己庚辛壬癸\n甲乙丙丁戊己庚辛壬癸"),
        ("b2", "<p>甲乙丙丁戊己庚辛壬癸<br/>甲乙丙<ruby class=\"left\">天の配<ruby class=\"over\">剤<rt>ザイ</rt></ruby><rt>ハイザイ</rt></ruby>丁戊己庚辛<br/>甲乙丙丁戊己庚辛壬癸</p>",
         "甲乙丙丁戊己庚辛壬癸\n甲乙丙天の配剤丁戊己庚辛\n甲乙丙丁戊己庚辛壬癸"),
        ("last", "<p>基準基準</p>", "基準基準"),
    ]

    /// Each ruby's room along its line, from the end of the 甲 before it to the start of the 乙
    /// after it: WebKit's ruby box. `lo`'s is its outer annotation, 14 kana: 119 in WebKit, here
    /// 118.15 (118.065 down a column), because the package sets kana annotations in Hiragino Sans,
    /// whose kerning narrows ハイ and ザイ, for any ruby (a finding of its own, not this shape's).
    private static let advances: [(row: String, horizontal: CGFloat, vertical: CGFloat)] = [
        ("pre", 51, 51), ("post", 34, 34), ("mid", 76.5, 76.5), ("lo", 118.15, 118.065), ("ol", 51, 51),
        ("span", 34, 34), ("wi", 68, 68), ("two", 85, 85),
    ]

    /// Where each inner base, and each annotation, is centred along the line from the ruby's start,
    /// and each annotation's baseline from its base's toward the under side (down, or left in
    /// vertical-rl): over 22 up and under 16 down, 19 either side in vertical-rl; 13 further beyond
    /// an inner annotation on the same side. Nil: not checked along the line (see below).
    private static let placements: [(row: String, text: String, along: CGFloat?, horizontal: CGFloat?, vertical: CGFloat?)] = [
        ("pre", "制", 17, nil, nil), ("pre", "（ママ）", 17, -22, -19), ("pre", "ちゅう", 25.5, -35, -32),
        ("post", "義", 25.5, nil, nil), ("post", "ママ", 25.5, -22, -19), ("post", "じぎ", 17, -35, -32),
        ("mid", "欸", 46.75, nil, nil), ("mid", "（疑）", 46.75, -22, -19), ("mid", "のみ", 38.25, -35, -32),
        ("lo", "ザイ", nil, -22, -19), ("lo", "いかにもむずかしいハイザイね", nil, 16, 19),
        ("ol", "駁雑", 34, nil, nil), ("ol", "トリマゼ", 34, 16, 19), ("ol", "そのはくざつ", 25.5, -22, -19),
        ("span", "来", 8.5, nil, nil), ("span", "き", 8.5, -22, -19), ("span", "北", 17, 16, 19),
        ("wi", "小高坂", 25.5, nil, nil), ("wi", "（高知城西）", 25.5, -22, -19), ("wi", "ヘン", 34, -35, -32),
        // WebKit lets the first （ママ） overhang 更 by half its font size, so 更 and the second
        // inner ruby start 4.25 earlier there (63.75): the overhang Phase 2d recorded, not done here.
        ("two", "万", 17, nil, nil), ("two", "椽", 68, nil, nil), ("two", "ざらえん", 42.5, -35, -32),
    ]

    /// How much further each row's first line sits from the row before's last one than two plain
    /// lines would: what its rubies add over it, and under the row before. WebKit 26.5 steps a
    /// plain 1.5 line 25 where 27.2 stepped 25.5, which the package follows; the growth agrees
    /// within 0.5 (`RubyPositionReferenceTests` pins it to the quarter on 27.2).
    private static let rowGrowth: [(row: String, growth: CGFloat)] = [
        ("pre", 26), ("post", 26), ("mid", 26), ("lo", 13), ("ol", 26), ("span", 26), ("wi", 39), ("two", 26),
        ("after", 0),
    ]

    /// Each later line's growth over a plain line within its paragraph: a ruby on a later line
    /// takes CSS Ruby's leading, the outer annotation counting the inner one too.
    private static let lineGrowth: [(row: String, growth: [CGFloat])] = [
        ("n1", [0, 0]), ("n2", [26, 0]), ("b1", [13, 0]), ("b2", [13, 26]),
    ]

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    private static func layout(vertical: Bool) async throws -> Layout {
        try await BrowserLayoutTestSupport.webKitReference(rows.map(\.html).joined(), css: css, vertical: vertical, lang: "ja")
    }

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

    private static func texts(_ layout: Layout) -> [TextFragment] {
        BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
    }

    /// The base text fragment holding the source offset.
    private static func base(at offset: Int, in texts: [TextFragment]) -> TextFragment? {
        texts.first { $0.renderedTextOverride == nil && NSLocationInRange(offset, $0.sourceRange) }
    }

    private static func span(_ rect: CGRect, vertical: Bool) -> (start: CGFloat, end: CGFloat) {
        vertical ? (rect.minY, rect.maxY) : (rect.minX, rect.maxX)
    }

    /// The ruby's start along the line: the end of the 甲 before it.
    private static func rubyStart(_ row: String, ranges: [String: NSRange], texts: [TextFragment], vertical: Bool) throws -> CGFloat {
        let range = try #require(ranges[row], "\(row) not laid out")
        let before = try #require(base(at: range.location, in: texts), "\(row) 甲")
        let rect = before.rect.rawValue
        // A plain run's fragment may hold more than its first character: 甲 is 17 long.
        return span(rect, vertical: vertical).start + 17
    }

    @Test(arguments: [false, true])
    func eachRubyTakesTheRoomOfItsBaseAndInnerRubies(vertical: Bool) async throws {
        let layout = try await Self.layout(vertical: vertical)
        let ranges = Self.ranges(in: layout), texts = Self.texts(layout)
        let source = layout.doc.lastSourceText as NSString
        for entry in Self.advances {
            let row = entry.row, advance = vertical ? entry.vertical : entry.horizontal
            let range = try #require(ranges[row])
            let start = try Self.rubyStart(row, ranges: ranges, texts: texts, vertical: vertical)
            let after = source.range(of: "乙", range: NSRange(location: range.location + 1, length: range.length - 1))
            let next = try #require(Self.base(at: after.location, in: texts), "\(row) 乙")
            let nextStart = Self.span(next.rect.rawValue, vertical: vertical).start
            #expect(abs(nextStart - start - advance) <= 0.01,
                    "\(vertical ? "vertical" : "horizontal") \(row): \(nextStart - start), WebKit \(advance)")
        }
    }

    @Test(arguments: [false, true])
    func innerAndOuterAnnotationsSitWhereWebKitSetsThem(vertical: Bool) async throws {
        let layout = try await Self.layout(vertical: vertical)
        let ranges = Self.ranges(in: layout), texts = Self.texts(layout)
        let source = layout.doc.lastSourceText as NSString
        let mode = vertical ? "vertical" : "horizontal"
        for placement in Self.placements {
            let range = try #require(ranges[placement.row])
            let start = try Self.rubyStart(placement.row, ranges: ranges, texts: texts, vertical: vertical)
            let isAnnotation = placement.horizontal != nil
            let fragments: [TextFragment]
            if isAnnotation {
                fragments = texts.filter {
                    $0.renderedTextOverride == placement.text && NSIntersectionRange($0.sourceRange, range).length > 0
                }
            } else {
                let found = source.range(of: placement.text, range: range)
                fragments = texts.filter {
                    $0.renderedTextOverride == nil && NSIntersectionRange($0.sourceRange, found).length > 0
                }
            }
            let first = try #require(fragments.first, "\(placement.row) \(placement.text) not drawn")
            if let along = placement.along {
                let extent = fragments.map { Self.span($0.rect.rawValue, vertical: vertical) }
                let centre = ((extent.map(\.start).min() ?? 0) + (extent.map(\.end).max() ?? 0)) / 2
                #expect(abs(centre - start - along) <= 0.01,
                        "\(mode) \(placement.row) \(placement.text): centred at \(centre - start), WebKit \(along)")
            }
            guard let expected = vertical ? placement.vertical : placement.horizontal else { continue }
            let base = try #require(Self.base(at: range.location + 1, in: texts))
            let offset = vertical ? base.baselineY - first.baselineY : first.baselineY - base.baselineY
            #expect(abs(offset - expected) <= 0.01, "\(mode) \(placement.row) \(placement.text): \(offset), WebKit \(expected)")
        }
    }

    @Test(arguments: [false, true])
    func linesGrowAsWebKitGrowsThem(vertical: Bool) async throws {
        let layout = try await Self.layout(vertical: vertical)
        let ranges = Self.ranges(in: layout), texts = Self.texts(layout)
        let source = layout.doc.lastSourceText as NSString
        let mode = vertical ? "vertical" : "horizontal"
        // Along the block axis: down, or left in vertical-rl.
        func position(at offset: Int) throws -> CGFloat {
            let fragment = try #require(Self.base(at: offset, in: texts), "nothing at \(offset)")
            return vertical ? -fragment.baselineY : fragment.baselineY
        }
        /// Each line's first character: after each line break in the row.
        func lineStarts(_ row: String) throws -> [Int] {
            let range = try #require(ranges[row])
            var starts = [range.location]
            var cursor = range.location
            while true {
                let found = source.range(of: "\n", range: NSRange(location: cursor, length: NSMaxRange(range) - cursor))
                guard found.location != NSNotFound else { break }
                starts.append(NSMaxRange(found))
                cursor = NSMaxRange(found)
            }
            return starts
        }
        let names = Self.rows.map(\.name)
        func step(into row: String) throws -> CGFloat {
            let previous = names[try #require(names.firstIndex(of: row)) - 1]
            return try position(at: lineStarts(row)[0]) - position(at: try #require(lineStarts(previous).last))
        }
        let plainRow = try step(into: "after")
        for (row, growth) in Self.rowGrowth {
            let got = try step(into: row) - plainRow
            #expect(abs(got - growth) <= 0.5, "\(mode) \(row): grows \(got), WebKit \(growth)")
        }
        // A plain 1.5 line of 17px text, as the package sets it (WebKit 27.2).
        let plainLine: CGFloat = 25.5
        for (row, expected) in Self.lineGrowth {
            let starts = try lineStarts(row)
            try #require(starts.count == expected.count + 1, "\(row) has \(starts.count) lines")
            for (index, growth) in expected.enumerated() {
                let got = try position(at: starts[index + 1]) - position(at: starts[index]) - plainLine
                #expect(abs(got - growth) <= 0.5, "\(mode) \(row) line \(index + 2): grows \(got), WebKit \(growth)")
            }
        }
    }
}
