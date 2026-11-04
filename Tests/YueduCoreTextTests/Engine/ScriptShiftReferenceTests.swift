import CoreText
import Testing
import UIKit
@testable import YueduCoreText

/// 上付き, 下付き, 訓点 and 割り注 as the Aozora converter writes them, against WebKit (WKWebView
/// iOS 26.5, the app's S013-scripts-and-kanbun and S013a-vertical-scripts-and-kanbun fixtures,
/// 2026-11-04). `vertical-align: super` raises a run by its parent's font size / 3 + 1 and `sub`
/// lowers it by / 5 + 1, whatever the run's own size (`VerticalAlignShift`); in vertical-rl up is
/// right, so 送り仮名 sit right of the column's central line and 返り点 left of it. Each run
/// advances down its line by its own size.
struct ScriptShiftReferenceTests {
    private static let css = """
        p { margin: 0; }
        .superscript { font-size: 0.8125rem; }
        .subscript { font-size: 0.8125rem; }
        .kaeriten { font-size: 0.5em; vertical-align: sub; }
        .okurigana { font-size: 0.5em; vertical-align: super; }
        .warichu { font-size: 0.5em; }
        """

    private static let body = """
        <p>起點段落。</p>\
        <p>甲x<sup class="superscript">2</sup>乙</p>\
        <p>甲x<sub class="subscript">2</sub>乙</p>\
        <p>甲<sup class="superscript">注</sup>乙</p>\
        <p>学<sup class="okurigana">ビテ</sup>而時習<sub class="kaeriten">レ</sub>之</p>\
        <p>不<sub class="kaeriten">二</sub>亦説<sub class="kaeriten">一</sub>乎</p>\
        <p>本文<span class="warichu">（注釈の文）</span>本文</p>\
        <p>基準基準</p>
        """

    /// Each paragraph's runs in order, by their first character: how far along the line each
    /// starts, and how far its baseline is shifted from the paragraph's, up or right. WebKit's
    /// numbers are in 64ths, so a third of 17 and 1 is 6.65625 or 6.671875 there.
    private static let rows: [[(text: String, along: CGFloat, shift: CGFloat)]] = [
        [("甲", 0, 0), ("2", 25.671875, 6.65625), ("乙", 33.84375, 0)],
        [("甲", 0, 0), ("2", 25.671875, -4.390625), ("乙", 33.84375, 0)],
        [("甲", 0, 0), ("注", 17, 6.65625), ("乙", 30.8125, 0)],
        [("学", 0, 0), ("ビ", 17, 6.671875), ("而", 34, 0), ("レ", 85, -4.390625), ("之", 93.5, 0)],
        [("不", 0, 0), ("二", 17, -4.390625), ("亦", 25.5, 0), ("一", 59.5, -4.390625), ("乎", 68, 0)],
        [("本", 0, 0), ("（", 34, 0), ("本", 85, 0)],
    ]

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    /// The character at `index` in the source: its line, its offset along the line, and the
    /// shift its run's baseline carries (up, or right in vertical-rl, is positive). Core Text
    /// turns a vertical line's runs by their own matrices, so its glyph positions are not the
    /// page's axes; `drawsTheColumns` shows where the shifts land.
    private static func character(at index: Int, in layout: Layout) throws -> (line: CTLine, along: CGFloat, shift: CGFloat) {
        let fragment = try #require(BrowserLayoutTestSupport.allTextFragments(layout.pages).first {
            $0.sourceRange.length > 0 && NSLocationInRange(index, $0.sourceRange)
        }, "no fragment at \(index)")
        guard case .linear(let shaped) = fragment.sourceMapping, let line = fragment.ctLine else {
            Issue.record("fragment at \(index) has no shaped line")
            throw CancellationError()
        }
        let target = shaped.location + index - fragment.sourceRange.location
        let along = CTLineGetOffsetForStringIndex(line, target, nil)
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let range = CTRunGetStringRange(run)
            guard range.location <= target, target < range.location + range.length else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let shift = (attributes[NSAttributedString.Key.baselineOffset] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            return (line, along, shift)
        }
        Issue.record("no run for source index \(index)")
        throw CancellationError()
    }

    @Test(arguments: [false, true])
    func scriptsShiftByTheirParentsSizeAndAdvanceByTheirOwn(vertical: Bool) async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference(Self.body, css: Self.css, vertical: vertical, lang: "ja")
        let source = layout.doc.lastSourceText as NSString
        var cursor = source.range(of: "起點段落。").location
        try #require(cursor != NSNotFound)
        for row in Self.rows {
            var start: (line: CTLine, along: CGFloat, shift: CGFloat)?
            for run in row {
                let found = source.range(of: run.text, range: NSRange(location: cursor, length: source.length - cursor))
                try #require(found.location != NSNotFound, "\(run.text)")
                cursor = NSMaxRange(found)
                let character = try Self.character(at: found.location, in: layout)
                let first = start ?? character
                start = first
                #expect(CFEqual(character.line, first.line), "\(run.text) is on another line")
                #expect(abs(character.along - first.along - run.along) <= 0.02,
                        "\(vertical ? "vertical" : "horizontal") \(run.text): along \(character.along - first.along), WebKit \(run.along)")
                // A sideways Latin run's baseline in vertical-rl also carries the offset that
                // centres it on the column, by its own size; `drawsTheColumns` shows its shift.
                guard !(vertical && run.text.allSatisfy(\.isASCII)) else { continue }
                #expect(abs(character.shift - first.shift - run.shift) <= 0.02,
                        "\(vertical ? "vertical" : "horizontal") \(run.text): shift \(character.shift - first.shift), WebKit \(run.shift)")
            }
        }
    }

    /// How far each paragraph's line sits from the one before, past a plain line: its baseline, or
    /// in vertical-rl its central line. WebKit 26.5 steps a plain 1.5 line 25 where 27.2 stepped
    /// 25.5, which the package follows, and rounds each box's leading its own way; the growth
    /// agrees within 0.75, the most a superscript's column differs by (4.28 here, 3.66 there).
    @Test(arguments: [false, true])
    func raisedAndLoweredRunsGrowTheirLines(vertical: Bool) async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference(Self.body, css: Self.css, vertical: vertical, lang: "ja")
        let source = layout.doc.lastSourceText as NSString
        var cursor = 0
        var positions: [CGFloat] = []
        for text in ["起點", "甲x", "甲x", "甲注", "学", "不", "本文", "基準"] {
            let found = source.range(of: text, range: NSRange(location: cursor, length: source.length - cursor))
            try #require(found.location != NSNotFound, "\(text)")
            cursor = NSMaxRange(found)
            let fragment = try #require(BrowserLayoutTestSupport.allTextFragments(layout.pages).first {
                $0.sourceRange.length > 0 && NSLocationInRange(found.location, $0.sourceRange)
            }, "\(text)")
            positions.append(fragment.baselineY)
        }
        let steps = zip(positions.dropFirst(), positions).map { vertical ? $1 - $0 : $0 - $1 }
        let plain = steps.last ?? 0
        let growth = steps.map { $0 - plain }
        print("SCRIPT_LINES \(vertical ? "vertical" : "horizontal") steps \(steps) growth \(growth)")
        // WebKit 26.5, from each row to the next: horizontal 27.656, 25, 31.047, 25, 26.391,
        // 26.391, 25; vertical 28.656, 25, 31.047, 25, 25, 25, 25.
        let webKit: [CGFloat] = vertical ? [3.656, 0, 6.047, 0, 0, 0, 0] : [2.656, 0, 6.047, 0, 1.391, 1.391, 0]
        for (index, (ours, theirs)) in zip(growth, webKit).enumerated() {
            #expect(abs(ours - theirs) <= 0.75, "\(vertical ? "vertical" : "horizontal") step \(index): growth \(ours), WebKit \(theirs)")
        }
    }

    /// The vertical page's right end, for the eye: each shift to the right or left of its
    /// column's central line. Written to `YUEDU_PROBE_OUT` (passed to the simulator as
    /// `TEST_RUNNER_YUEDU_PROBE_OUT`), or the temporary directory.
    @Test func drawsTheColumns() async throws {
        let layout = try await BrowserLayoutTestSupport.webKitReference(Self.body, css: Self.css, vertical: true, lang: "ja")
        let page = try #require(layout.pages.first)
        let list = DisplayListBuilder.build(for: page, sourceText: layout.doc.lastSourceText)
        let crop = CGRect(x: page.pageRect.rawValue.width - 240, y: 0, width: 240, height: 140)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        let image = UIGraphicsImageRenderer(size: crop.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: crop.size))
            context.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            list.draw(in: context.cgContext)
        }
        let folder = ProcessInfo.processInfo.environment["YUEDU_PROBE_OUT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let url = folder.appendingPathComponent("vertical-scripts.png")
        try #require(image.pngData()).write(to: url)
        print("VERTICAL_SCRIPTS \(url.path)")
    }
}
