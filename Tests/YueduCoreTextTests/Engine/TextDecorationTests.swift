import CoreText
import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// CSS text decorations as WebKit on iOS 27.2 draws them (list-marker design
/// step 8f). The expected rects are a WKWebView's ink at device pixel ratio 3
/// (S001 ua-all, 17px PingFang): each case supplies the baseline the web view
/// set its line on, so the device-pixel snapping is the same as there.
@Suite @MainActor
struct TextDecorationTests {

    private static let reference = "html{font-size:17px;line-height:1.5;text-align:justify;font-family:\"PingFang SC\"}"

    // MARK: - Parsing and propagation

    private static func tree(_ body: String, css: String = "") throws -> ComputedStyleNode {
        let document = try SwiftSoup.parse("<html><body>\(body)</body></html>")
        return ComputedStyleTreeBuilder(rules: CSSParser.parse(css: css), config: BrowserLayoutConfig())
            .buildTree(body: try #require(document.body()))
    }

    private static func style(_ body: String, css: String = "", id: String = "x") throws -> ComputedStyle {
        func find(_ node: ComputedStyleNode) -> ComputedStyleNode? {
            if node.anchorID == id { return node }
            for child in node.children {
                if case .element(let element) = child, let found = find(element) { return found }
            }
            return nil
        }
        return try #require(find(try tree(body, css: css)), "no element #\(id)").style
    }

    private static func rgba(_ color: UIColor?) -> [CGFloat] {
        var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 255).rounded() }
    }

    private static let red: [CGFloat] = [255, 0, 0, 255]

    @Test func lineValuesParse() {
        #expect(TextDecorationValue.lines("none") == [])
        #expect(TextDecorationValue.lines("underline line-through") == [.underline, .lineThrough])
        #expect(TextDecorationValue.lines("underline underline") == nil)
        #expect(TextDecorationValue.lines("sideways") == nil)
        #expect(TextDecorationValue.underlinePosition("under right") == TextUnderlinePosition(under: true, right: true))
        #expect(TextDecorationValue.underlinePosition("left right") == nil)
    }

    @Test func shorthandResetsWhatItLeavesOut() throws {
        let s = try Self.style(#"<p><span id="x" style="text-decoration-style: wavy; text-decoration: overline red">a</span></p>"#)
        #expect(s.textDecorationLine == .overline)
        #expect(s.textDecorationStyle == .solid)
        #expect(Self.rgba(s.textDecorationColor) == Self.red)
        let t = try Self.style(#"<p><span id="x" style="text-decoration: dotted underline 3px">a</span></p>"#)
        #expect(t.textDecorationLine == .underline)
        #expect(t.textDecorationStyle == .dotted)
        #expect(t.textDecorationThickness == .length(.px(3)))
        #expect(t.textDecorationColor == nil)
        // Two styles: invalid, so the declaration before it stands.
        let u = try Self.style(#"<p><u id="x" style="text-decoration: dotted dashed">a</u></p>"#)
        #expect(u.textDecorationLine == .underline)
    }

    @Test func userAgentDecorations() throws {
        for (tag, line) in [("u", TextDecorationLines.underline), ("ins", .underline),
                            ("s", .lineThrough), ("strike", .lineThrough), ("del", .lineThrough)] {
            #expect(try Self.style("<p><\(tag) id=\"x\">a</\(tag)></p>").textDecorationLine == line, "\(tag)")
        }
    }

    /// A descendant's `none` takes nothing away; an inline-block or a float
    /// takes none of its ancestors' decorations; a block takes them onto its
    /// root inline box.
    @Test func propagation() throws {
        let none = try Self.style(#"<p><u>a<span id="x" style="text-decoration: none">b</span></u></p>"#)
        #expect(none.textDecorationsInEffect.map(\.lines) == [.underline])
        #expect(none.textDecorationsInEffect.first?.anchor != nil)

        let atomic = try Self.style(#"<p><u>a<span id="x" style="display: inline-block">b</span></u></p>"#)
        #expect(atomic.textDecorationsInEffect.isEmpty)
        let float = try Self.style(#"<p><u>a<span id="x" style="float: left">b</span></u></p>"#)
        #expect(float.textDecorationsInEffect.isEmpty)

        let block = try Self.style(#"<div style="text-decoration: underline"><p id="x">a</p></div>"#)
        #expect(block.textDecorationsInEffect.map(\.lines) == [.underline])
        #expect(block.textDecorationsInEffect.first?.anchor == nil)

        let red = try Self.style(#"<p><u id="x" style="color: red">a</u></p>"#)
        #expect(Self.rgba(red.textDecorationsInEffect.first?.color) == Self.red)
    }

    // MARK: - Placement, measured

    private struct Drawn {
        let line: TextDecorationPaint.Line
        let rect: CGRect
        let segments: [TextDecorationPainter.Segment]
        let color: UIColor
    }

    /// Lays out `body` and returns every decoration line with its rect in
    /// page coordinates, the text set on `baseline` (its y, or in vertical-rl
    /// its x), as a 3x flipped device would draw it.
    private static func drawn(_ body: String, css: String = "", vertical: Bool = false,
                              baseline: CGFloat) async throws -> [Drawn] {
        let width: CGFloat = vertical ? 600 : 366
        let height: CGFloat = vertical ? 776 : 600
        var config = BrowserLayoutConfig(renderWidth: width, renderHeight: height, rootFontSize: 17,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        config.writingMode = vertical ? .verticalRTL : .horizontal
        let doc = BrowserLayoutDocument(html: "<html lang=\"zh-Hant\"><body>\(body)</body></html>",
                                        cssTexts: [reference, css], config: config)
        let pages = try await doc.renderPages(containerSize: CGSize(width: width, height: height))
        let device = CGAffineTransform(a: 3, b: 0, c: 0, d: -3, tx: 0, ty: 3000)
        var result: [Drawn] = []
        for page in pages {
            for case .text(let item) in DisplayListBuilder.build(for: page, sourceText: doc.lastSourceText).items
            where !item.textDecorations.isEmpty {
                let toPage = vertical
                    ? CGAffineTransform(rotationAngle: .pi / 2).concatenating(CGAffineTransform(translationX: baseline, y: item.rect.minY))
                    : CGAffineTransform(translationX: item.rect.minX, y: baseline)
                let resources = TextDrawingResources(item)
                for paint in item.textDecorations {
                    let rect = TextDecorationPainter.rect(for: paint, length: vertical ? item.rect.height : item.rect.width,
                                                          toDevice: toPage.concatenating(device))
                    var segments = [TextDecorationPainter.Segment(begin: 0, end: rect.width)]
                    if paint.skipsInk {
                        let crossings = TextDecorationPainter.glyphCrossings(line: resources.line, string: resources.attributed,
                                                                             band: rect.minY...rect.maxY)
                            .map { TextDecorationPainter.Segment(begin: $0.begin - rect.minX, end: $0.end - rect.minX) }
                        if !crossings.isEmpty {
                            segments = TextDecorationPainter.difference(segments[0], crossings,
                                                                        dilation: min(rect.height, paint.inkDilationLimit))
                        }
                    }
                    result.append(Drawn(line: paint.line, rect: rect.applying(toPage), segments: segments, color: paint.color))
                }
            }
        }
        return result
    }

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.002) -> Bool { abs(a - b) < tolerance }

    /// Each case's block-axis edge and thickness; in vertical-rl the left edge.
    private static func edges(_ drawn: [Drawn], vertical: Bool) -> [[CGFloat]] {
        drawn.map { vertical ? [$0.rect.minX, $0.rect.width] : [$0.rect.minY, $0.rect.height] }
    }

    private static func expectEdges(_ drawn: [Drawn], _ expected: [[CGFloat]], vertical: Bool,
                                    sourceLocation: SourceLocation = #_sourceLocation) {
        let got = edges(drawn, vertical: vertical)
        #expect(got.count == expected.count
                && zip(got, expected).allSatisfy { near($0[0], $1[0]) && near($0[1], $1[1]) },
                "got \(got), expected \(expected)", sourceLocation: sourceLocation)
    }

    @Test func horizontalPlacementMatchesWebKit() async throws {
        let cases: [(String, CGFloat, [[CGFloat]])] = [
            ("丙一<u>底線文字</u>丙一尾。", 1072.1875, [[1073.333, 1.333]]),
            ("丙二<ins>插入文字</ins>丙二尾。", 1097.6875, [[1098.667, 1.333]]),
            ("丙三<s>刪除文字</s>丙三尾。", 1123.1875, [[1117.0, 1.333]]),
            ("丙四<del>刪去文字</del>丙四尾。", 1148.6875, [[1142.667, 1.333]]),
            ("丙五<span style=\"text-decoration: overline\">上線文字</span>丙五尾。", 1174.1875, [[1155.333, 1.333]]),
            ("丙六<span style=\"text-decoration: underline line-through\">雙線文字</span>丙六尾。", 1199.6875,
             [[1200.667, 1.333], [1193.667, 1.333]]),
            // 30px: 2 thick, the gap still 1.
            ("丙十一<u style=\"font-size: 30px\">大底</u>丙十一尾。", 1360.4375, [[1361.333, 2.0]]),
        ]
        for (body, baseline, expected) in cases {
            Self.expectEdges(try await Self.drawn("<p>\(body)</p>", baseline: baseline), expected, vertical: false)
        }
        // Every run of the underlined box is underlined where the box sets
        // it, the 30px child's and the `none` child's too.
        let mixed = try await Self.drawn("<p>丙七<u>小字<span style=\"font-size: 30px\">大</span>小字</u>丙七尾。</p>",
                                         baseline: 1238.9375)
        Self.expectEdges(mixed, Array(repeating: [1240.0, 1.333], count: 3), vertical: false)
        #expect(Self.near(mixed.map(\.rect.width).reduce(0, +), 98))
        let none = try await Self.drawn("<p>丙八<u>外層<span style=\"text-decoration: none\">內層</span>外層</u>丙八尾。</p>",
                                        baseline: 1270.1875)
        Self.expectEdges(none, Array(repeating: [1271.333, 1.333], count: 3), vertical: false)
    }

    @Test func verticalPlacementMatchesWebKit() async throws {
        // The probe's ink for the overline is a half-weight 0.667 there; its
        // left edge is the one compared.
        let cases: [(String, CGFloat, [[CGFloat]])] = [
            ("丙一<u>底線文字</u>丙一尾。", -682.6875, [[-697.667, 1.333]]),
            ("丙二<ins>插入文字</ins>丙二尾。", -708.1875, [[-723.0, 1.333]]),
            ("丙三<s>刪除文字</s>丙三尾。", -733.6875, [[-735.333, 1.333]]),
            ("丙四<del>刪去文字</del>丙四尾。", -759.1875, [[-760.667, 1.333]]),
            ("丙五<span style=\"text-decoration: overline\">上線文字</span>丙五尾。", -784.6875, [[-772.667, 1.333]]),
            ("丙六<span style=\"text-decoration: underline line-through\">雙線文字</span>丙六尾。", -810.1875,
             [[-825.0, 1.333], [-811.667, 1.333]]),
            ("丙八<u>外層<span style=\"text-decoration: none\">內層</span>外層</u>丙八尾。", -880.6875,
             Array(repeating: [-895.667, 1.333], count: 3)),
            ("丙十一<u style=\"font-size: 30px\">大底</u>丙十一尾。", -966.9375, [[-991.333, 2.0]]),
        ]
        for (body, baseline, expected) in cases {
            Self.expectEdges(try await Self.drawn("<p>\(body)</p>", vertical: true, baseline: baseline),
                             expected, vertical: true)
        }
        // Under the 30px child's content box, which reaches further left.
        let mixed = try await Self.drawn("<p>丙七<u>小字<span style=\"font-size: 30px\">大</span>小字</u>丙七尾。</p>",
                                         vertical: true, baseline: -845.4375)
        Self.expectEdges(mixed, Array(repeating: [-869.333, 1.333], count: 3), vertical: true)
    }

    /// Latin descenders break the underline; ideographs, here and in every
    /// case above, are drawn through. Vertical text never skips ink.
    @Test func skipInk() async throws {
        let latin = try await Self.drawn("<p>丙九<u>Ugjpq</u>丙九尾。</p>", baseline: 1295.6875)
        let only = try #require(latin.first)
        #expect(Self.near(only.rect.minY, 1296.667))
        // WebKit's ink, read off the coverage of each piece's antialiased end
        // pixel: 0–12.10 and 30.50–42.90.
        let pieces = only.segments.map { [$0.begin, $0.end] }
        #expect(pieces.count == 2 && Self.near(pieces[0][0], 0) && Self.near(pieces[0][1], 12.10, 0.02)
                && Self.near(pieces[1][0], 30.50, 0.01) && Self.near(pieces[1][1], 42.90, 0.01), "\(pieces)")

        let cjk = try await Self.drawn("<p>丙一<u>底線文字</u>丙一尾。</p>", baseline: 1072.1875)
        #expect(cjk.first?.segments == [TextDecorationPainter.Segment(begin: 0, end: 68)])

        let none = try await Self.drawn("<p>丙九<u style=\"text-decoration-skip-ink: none\">Ugjpq</u>尾。</p>", baseline: 1295.6875)
        #expect(none.first?.segments.count == 1)
        let vertical = try await Self.drawn("<p>丙九<u>Ugjpq</u>丙九尾。</p>", vertical: true, baseline: -906.1875)
        #expect(vertical.first?.segments.count == 1)
        #expect(vertical.first.map { Self.near($0.rect.minX, -921.0) } == true)
    }

    @Test func colorIsTheOriginatingBoxes() async throws {
        let drawn = try await Self.drawn("<p>丙十<u style=\"color: red\">紅<span style=\"color: blue\">底</span>線</u>尾。</p>",
                                         baseline: 100)
        #expect(drawn.count == 3)
        #expect(drawn.allSatisfy { Self.rgba($0.color) == Self.red })
    }

    // MARK: - Painter geometry

    @Test func differenceDropsDilatedCrossingsAndShortPieces() {
        typealias Segment = TextDecorationPainter.Segment
        let whole = Segment(begin: 0, end: 100)
        #expect(TextDecorationPainter.difference(whole, [Segment(begin: 40, end: 50)], dilation: 2)
                == [Segment(begin: 0, end: 38), Segment(begin: 52, end: 100)])
        // A piece no longer than the dilation goes.
        #expect(TextDecorationPainter.difference(whole, [Segment(begin: 3, end: 10), Segment(begin: 90, end: 99)], dilation: 2)
                == [Segment(begin: 12, end: 88)])
        #expect(TextDecorationPainter.difference(whole, [Segment(begin: -5, end: 120)], dilation: 1).isEmpty)
    }

    @Test func dashesDotsAndDoubleLines() {
        typealias Segment = TextDecorationPainter.Segment
        let dashed = TextDecorationPainter.rects(origin: CGPoint(x: 10, y: 5), thickness: 1,
                                                 segments: [Segment(begin: 0, end: 10)], style: .dashed)
        #expect(dashed.map(\.minX) == [10, 14, 18])
        #expect(dashed.map(\.width) == [2, 2, 2])
        let dotted = TextDecorationPainter.rects(origin: .zero, thickness: 2, segments: [Segment(begin: 0, end: 7)], style: .dotted)
        #expect(dotted.map(\.minX) == [0, 4])
        #expect(dotted.map(\.width) == [2, 2])
        let double = TextDecorationPainter.rects(origin: CGPoint(x: 0, y: 5), thickness: 1,
                                                 segments: [Segment(begin: 0, end: 30)], style: .double)
        #expect(double.map(\.minY) == [5, 7])
    }

    /// A thickness is rounded up to device pixels; an underline starts at the
    /// nearest pixel, a line-through at the next one away from the text.
    @Test func snapping() {
        let device = CGAffineTransform(a: 3, b: 0, c: 0, d: -3, tx: 0, ty: 300)
        func paint(_ line: TextDecorationPaint.Line, _ position: CGFloat, thickness: CGFloat = 17.0 / 16) -> TextDecorationPaint {
            TextDecorationPaint(line: line, color: .black, style: .solid, position: position, thickness: thickness,
                                autoThickness: 17.0 / 16, waveAmplitude: 0, waveStep: 0, skipsInk: false, inkDilationLimit: 0)
        }
        let at = CGAffineTransform(translationX: 0, y: 50.1875).concatenating(device)
        let underline = TextDecorationPainter.rect(for: paint(.underline, 1), length: 10, toDevice: at)
        #expect(Self.near(underline.height, 4.0 / 3))
        #expect(Self.near(underline.minY + 50.1875, 51.333))
        let through = TextDecorationPainter.rect(for: paint(.lineThrough, -19.0 / 3), length: 10, toDevice: at)
        // 50.1875 − 6.333 = 43.854, device 168.4375, floored to 168.
        #expect(Self.near(through.minY + 50.1875, 44))
        let thin = TextDecorationPainter.rect(for: paint(.underline, 1, thickness: 0.1), length: 10, toDevice: at)
        #expect(Self.near(thin.height, 0.5))
    }
}
