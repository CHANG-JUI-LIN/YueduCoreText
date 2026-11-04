import Testing
import UIKit
@testable import YueduCoreText

/// `text-emphasis` against a WKWebView (iOS 27.2, the app's S001i and S001j
/// fixtures, device pixel ratio 3): which characters take a mark, how much a
/// line grows to hold them, and where they are drawn, in both writing modes.
/// Every expected number is the web view's, except where a test says so.
@Suite @MainActor
struct TextEmphasisTests {

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)
    private typealias Row = (name: String, html: String, text: String)

    private static let css = """
        .fs { -webkit-text-emphasis-style: filled sesame; text-emphasis-style: filled sesame; }
        .os { -webkit-text-emphasis-style: open sesame; text-emphasis-style: open sesame; }
        .fd { -webkit-text-emphasis-style: filled dot; text-emphasis-style: filled dot; }
        .od { -webkit-text-emphasis-style: open dot; text-emphasis-style: open dot; }
        .fc { -webkit-text-emphasis-style: filled circle; text-emphasis-style: filled circle; }
        .oc { -webkit-text-emphasis-style: open circle; text-emphasis-style: open circle; }
        .fdc { -webkit-text-emphasis-style: filled double-circle; text-emphasis-style: filled double-circle; }
        .odc { -webkit-text-emphasis-style: open double-circle; text-emphasis-style: open double-circle; }
        .ft { -webkit-text-emphasis-style: filled triangle; text-emphasis-style: filled triangle; }
        .ot { -webkit-text-emphasis-style: open triangle; text-emphasis-style: open triangle; }
        .str { -webkit-text-emphasis-style: "×"; text-emphasis-style: "×"; }
        .sesame_dot { font-style: normal; -webkit-text-emphasis-style: filled sesame; text-emphasis-style: filled sesame; }
        .under { -webkit-text-emphasis-position: under left; text-emphasis-position: under left; }
        .normal { line-height: normal; }
        .big { font-size: 2em; }
        .over { -webkit-text-emphasis-position: over right; text-emphasis-position: over right; }
        .left { -webkit-text-emphasis-position: over left; text-emphasis-position: over left; }
        """

    private static let rows: [Row] = [
        ("p0", "<p>起點段落。</p>", "起點段落。"),
        ("fs-p", "<p>甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("os-p", "<p>甲<span class=\"os\">傍點</span>乙</p>", "甲傍點乙"),
        ("fd-p", "<p>甲<span class=\"fd\">傍點</span>乙</p>", "甲傍點乙"),
        ("od-p", "<p>甲<span class=\"od\">傍點</span>乙</p>", "甲傍點乙"),
        ("fc-p", "<p>甲<span class=\"fc\">傍點</span>乙</p>", "甲傍點乙"),
        ("oc-p", "<p>甲<span class=\"oc\">傍點</span>乙</p>", "甲傍點乙"),
        ("fdc-p", "<p>甲<span class=\"fdc\">傍點</span>乙</p>", "甲傍點乙"),
        ("odc-p", "<p>甲<span class=\"odc\">傍點</span>乙</p>", "甲傍點乙"),
        ("ft-p", "<p>甲<span class=\"ft\">傍點</span>乙</p>", "甲傍點乙"),
        ("ot-p", "<p>甲<span class=\"ot\">傍點</span>乙</p>", "甲傍點乙"),
        ("str-p", "<p>甲<span class=\"str\">傍點</span>乙</p>", "甲傍點乙"),
        ("per-p", "<p>甲<span class=\"fs\">一二三四</span>乙</p>", "甲一二三四乙"),
        ("skip-p", "<p>甲<span class=\"fs\">一，二　三。</span>乙</p>", "甲一，二　三。乙"),
        ("latin-p", "<p>甲<span class=\"fs\">ab cd</span>乙</p>", "甲ab cd乙"),
        ("under-p", "<p>甲<span class=\"fs under\">傍點</span>乙</p>", "甲傍點乙"),
        ("ruby-p", "<p>甲<span class=\"fs\"><ruby>漢<rt>かん</rt></ruby>字</span>乙</p>", "甲漢字乙"),
        ("big-p", "<p>甲<span class=\"fs big\">大字</span>乙</p>", "甲大字乙"),
        ("sesame-dot-p", "<p>甲<em class=\"sesame_dot\">傍點</em>乙</p>", "甲傍點乙"),
        ("lines-plain", "<p>這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站</p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"),
        ("lines-em", "<p><span class=\"fs\">這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站</span></p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"),
        ("lines-under", "<p><span class=\"fs under\">這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站</span></p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"),
        ("lines-mid", "<p>這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在<span class=\"fs\">車聲中輕</span>快地穿過馬路走向龐大的被燻黑的火車站</p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"),
        ("normal-plain", "<p class=\"normal\">這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站</p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"),
        ("normal-em", "<p class=\"normal\"><span class=\"fs\">這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站</span></p>", "這一年的秋天似乎一下子就到了九月一日的早晨像蘋果一樣脆生生金爛爛的小小的一家人在車聲中輕快地穿過馬路走向龐大的被燻黑的火車站"),
        ("over-p", "<p>甲<span class=\"fs over\">傍點</span>乙</p>", "甲傍點乙"),
        ("left-p", "<p>甲<span class=\"fs left\">傍點</span>乙</p>", "甲傍點乙"),
        ("ja-p", "<p lang=\"ja\">甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("en-p", "<p lang=\"en\">甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("hans-p", "<p lang=\"zh-Hans\">甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("mid-skip-p", "<p>甲<span class=\"fs\">一「二」三</span>乙</p>", "甲一「二」三乙"),
        ("ko-p", "<p lang=\"ko\">甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("mn-p", "<p lang=\"mn\">甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("nolang-p", "<p lang=\"\">甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("pc-comma-p", "<p>甲<span class=\"fs\">，</span>乙</p>", "甲，乙"),
        ("pc-ideocomma-p", "<p>甲<span class=\"fs\">、</span>乙</p>", "甲、乙"),
        ("pc-period-p", "<p>甲<span class=\"fs\">。</span>乙</p>", "甲。乙"),
        ("pc-open-p", "<p>甲<span class=\"fs\">「</span>乙</p>", "甲「乙"),
        ("pc-close-p", "<p>甲<span class=\"fs\">」</span>乙</p>", "甲」乙"),
        ("pc-excl-p", "<p>甲<span class=\"fs\">！</span>乙</p>", "甲！乙"),
        ("pc-dot-p", "<p>甲<span class=\"fs\">・</span>乙</p>", "甲・乙"),
        ("pc-ellipsis-p", "<p>甲<span class=\"fs\">…</span>乙</p>", "甲…乙"),
        ("pc-dash-p", "<p>甲<span class=\"fs\">—</span>乙</p>", "甲—乙"),
        ("pc-digit-p", "<p>甲<span class=\"fs\">1</span>乙</p>", "甲1乙"),
        ("pc-fullA-p", "<p>甲<span class=\"fs\">Ａ</span>乙</p>", "甲Ａ乙"),
        ("pc-choon-p", "<p>甲<span class=\"fs\">ー</span>乙</p>", "甲ー乙"),
        ("pc-kurikaeshi-p", "<p>甲<span class=\"fs\">々</span>乙</p>", "甲々乙"),
        ("pc-zero-p", "<p>甲<span class=\"fs\">〇</span>乙</p>", "甲〇乙"),
        ("pc-asciiperiod-p", "<p>甲<span class=\"fs\">.</span>乙</p>", "甲.乙"),
        ("pc-asciiexcl-p", "<p>甲<span class=\"fs\">!</span>乙</p>", "甲!乙"),
        ("pc-kome-p", "<p>甲<span class=\"fs\">※</span>乙</p>", "甲※乙"),
        ("pc-nbsp-p", "<p>甲<span class=\"fs\"> </span>乙</p>", "甲 乙"),
        ("pc-ideospace-p", "<p>甲<span class=\"fs\">　</span>乙</p>", "甲　乙"),
        ("pc-hash-p", "<p>甲<span class=\"fs\">#</span>乙</p>", "甲#乙"),
        ("pc-plus-p", "<p>甲<span class=\"fs\">＋</span>乙</p>", "甲＋乙"),
        ("helv16-p", "<p class=\"normal\">甲<span style=\"font-family: 'Helvetica'; font-size: 16px\">Hg</span>乙</p>", "甲Hg乙"),
        ("helv14-p", "<p class=\"normal\">甲<span style=\"font-family: 'Helvetica'; font-size: 14px\">Hg</span>乙</p>", "甲Hg乙"),
        ("helv15-p", "<p class=\"normal\">甲<span style=\"font-family: 'Helvetica'; font-size: 15px\">Hg</span>乙</p>", "甲Hg乙"),
        ("helv8-p", "<p class=\"normal\">甲<span style=\"font-family: 'Helvetica'; font-size: 8.5px\">Hg</span>乙</p>", "甲Hg乙"),
        ("times16-p", "<p class=\"normal\">甲<span style=\"font-family: 'Times'; font-size: 16px\">Hg</span>乙</p>", "甲Hg乙"),
        ("hira8-p", "<p class=\"normal\">甲<span style=\"font-family: 'Hiragino Sans'; font-size: 8.5px\">Hg</span>乙</p>", "甲Hg乙"),
        ("hira10-p", "<p class=\"normal\">甲<span style=\"font-family: 'Hiragino Sans'; font-size: 10px\">Hg</span>乙</p>", "甲Hg乙"),
        ("hira12-p", "<p class=\"normal\">甲<span style=\"font-family: 'Hiragino Sans'; font-size: 12px\">Hg</span>乙</p>", "甲Hg乙"),
        ("hira16-p", "<p class=\"normal\">甲<span style=\"font-family: 'Hiragino Sans'; font-size: 16px\">Hg</span>乙</p>", "甲Hg乙"),
        ("after", "<p>之後。</p>", "之後。"),
    ]

    /// The S001j fixture: the rows up to `mid-skip-p`, then `after`.
    private static let verticalRows = Array(rows.prefix { $0.name != "ko-p" }) + rows.filter { $0.name == "after" }

    private static func layout(_ rows: [Row], vertical: Bool) async throws -> Layout {
        try await BrowserLayoutTestSupport.webKitReference(rows.map(\.html).joined(), css: css, vertical: vertical)
    }

    /// Each row's first line's baseline (its y, or in vertical-rl its x),
    /// found by the row's text in source order.
    private static func baselines(_ rows: [Row], in layout: Layout) -> [String: CGFloat] {
        let source = layout.doc.lastSourceText as NSString
        let fragments = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
        var cursor = 0
        var result: [String: CGFloat] = [:]
        for row in rows {
            let found = source.range(of: row.text, range: NSRange(location: cursor, length: source.length - cursor))
            guard found.location != NSNotFound else { continue }
            cursor = NSMaxRange(found)
            if let first = fragments.first(where: { NSLocationInRange(found.location, $0.sourceRange) }) {
                result[row.name] = first.baselineY
            }
        }
        return result
    }

    // MARK: Parsing

    @Test func parsesStylesPositionsAndTheShorthand() {
        #expect(TextEmphasisValue.style("filled sesame") == .some(.shape(filled: true, shape: .sesame)))
        #expect(TextEmphasisValue.style("open") == .some(.shape(filled: false, shape: nil)))
        #expect(TextEmphasisValue.style("triangle") == .some(.shape(filled: true, shape: .triangle)))
        #expect(TextEmphasisValue.style("\"×\"") == .some(.string("×")))
        #expect(TextEmphasisValue.style("none") == .some(nil))
        #expect(TextEmphasisValue.style("filled open") == nil)
        #expect(TextEmphasisValue.position("under left") == TextEmphasisPosition(over: false, right: false))
        #expect(TextEmphasisValue.position("over") == TextEmphasisPosition(over: true, right: true))
        #expect(TextEmphasisValue.position("auto") == TextEmphasisPosition())
        #expect(TextEmphasisValue.position("left") == nil)
        let red = UIColor.red
        let parsed = TextEmphasisValue.shorthand(["open", "dot", "red"], color: { $0 == "red" ? .some(red) : nil })
        #expect(parsed?.style == .shape(filled: false, shape: .dot) && parsed?.color == red)
        #expect(TextEmphasisStyle.shape(filled: true, shape: nil).mark(vertical: false) == "\u{25CF}")
        #expect(TextEmphasisStyle.shape(filled: true, shape: nil).mark(vertical: true) == "\u{FE45}")
    }

    @Test func theAutoPositionFollowsTheLanguage() {
        let auto = TextEmphasisPosition()
        #expect(auto.isOver(language: "ja") && auto.isOver(language: "ko-KR"))
        #expect(!auto.isOver(language: "zh-Hant") && !auto.isOver(language: "zh-Hans")
            && !auto.isOver(language: "en") && !auto.isOver(language: "mn") && !auto.isOver(language: nil))
    }

    /// Measured on single characters with marks: punctuation, separators and
    /// spaces take none; letters, digits, the listed symbols and CJK marks
    /// such as ー 々 〇 take one.
    @Test func charactersThatTakeAMark() {
        for character in ["，", "、", "。", "「", "」", "！", "・", "…", "—", ".", "!", "※", "\u{00A0}", "\u{3000}", " "] {
            #expect(!TextEmphasisCharacters.receivesMark(character.unicodeScalars.first!), "\(character)")
        }
        for character in ["#", "1", "Ａ", "ー", "々", "〇", "＋", "a", "傍", "%", "@", "§", "¶"] {
            #expect(TextEmphasisCharacters.receivesMark(character.unicodeScalars.first!), "\(character)")
        }
    }

    // MARK: Line boxes

    /// Every row's first baseline, from the first row's: a line with marks is
    /// 35.25 tall in sesame (Hiragino's 10 below a 25 content box), 36.25 in
    /// dot or ×; at `normal` 35; a 34px run's 68. The ruby row is left out:
    /// its ruby, not its marks, sets its line (it is checked below).
    @Test func linesGrowToHoldTheirMarks() async throws {
        let rows = Self.rows.filter { $0.name != "ruby-p" }
        let layout = try await Self.layout(rows, vertical: false)
        let found = Self.baselines(rows, in: layout)
        let origin = try #require(found["p0"])
        for (name, expected) in Self.horizontalBaselines {
            let got = try #require(found[name], "\(name) not found")
            #expect(abs(got - origin - expected) <= 0.01, "\(name): \(got - origin), WebKit \(expected)")
        }
    }

    /// The same in vertical-rl, the column growing toward its marks. One
    /// deliberate difference: WebKit draws a vertical `filled circle` at the
    /// text's full size (its column 46.25, every other mark's at half), which
    /// the engine does not copy; its column is 36.25, so its baseline and the
    /// rows after it sit 10 further right.
    @Test func columnsGrowToHoldTheirMarks() async throws {
        let rows = Self.verticalRows.filter { $0.name != "ruby-p" }
        let layout = try await Self.layout(rows, vertical: true)
        let found = Self.baselines(rows, in: layout)
        let origin = try #require(found["p0"])
        for (name, expected) in Self.verticalBaselines {
            let got = try #require(found[name], "\(name) not found")
            #expect(abs(got - origin - expected) <= 0.01, "\(name): \(got - origin), WebKit \(expected)")
        }
    }

    // MARK: Where the marks are drawn

    /// The ink in `region` (page coordinates) of the page's text drawn at 3x:
    /// the box of the pixels at least 8 levels from white, as the probe reads it.
    /// `marked` draws only the text that carries marks, leaving out a ruby's
    /// annotation, which in vertical-rl shares its column with the marks; the
    /// probe isolates them by making `text-emphasis-color` transparent.
    private static func ink(of layout: Layout, in region: CGRect, marked: Bool = false) -> CGRect? {
        let list = DisplayListBuilder.build(for: layout.pages[0], sourceText: layout.doc.lastSourceText)
        let items = list.items.filter { item in
            guard case .text(let text) = item, !marked || text.textEmphasis != nil else { return false }
            return text.rect.rawValue.insetBy(dx: -40, dy: -40).intersects(region)
        }
        let scale: CGFloat = 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: region.size, format: format).image { context in
            UIColor.white.setFill()
            // A point past the region: its size need not be whole pixels, and
            // the opaque image's last row would read as ink.
            context.fill(CGRect(origin: .zero, size: region.size).insetBy(dx: -1, dy: -1))
            context.cgContext.translateBy(x: -region.minX, y: -region.minY)
            DisplayListDrawer.draw(DisplayList(items: items), in: context.cgContext)
        }
        let cgImage = image.cgImage!
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i] <= 247 || pixels[i + 1] <= 247 || pixels[i + 2] <= 247 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: region.minX + CGFloat(minX) / scale, y: region.minY + CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// The probe's mark ink: horizontally x and width as drawn, y from the
    /// row's baseline; vertically x from the row's baseline, y and height as
    /// drawn. Within two device pixels: WebKit sets the text's baseline on a
    /// device pixel first.
    @Test(arguments: [false, true])
    func marksAreDrawnWhereWebKitDrawsThem(vertical: Bool) async throws {
        let rows = (vertical ? Self.verticalRows : Self.rows).filter { $0.name != "ruby-p" }
        let layout = try await Self.layout(rows, vertical: vertical)
        let found = Self.baselines(rows, in: layout)
        for (name, x, y, width, height) in vertical ? Self.verticalInk : Self.horizontalInk {
            let baseline = try #require(found[name + "-p"], "\(name) not found")
            let expected = vertical
                ? CGRect(x: baseline + x, y: y, width: width, height: height)
                : CGRect(x: x, y: baseline + y, width: width, height: height)
            let got = try #require(Self.ink(of: layout, in: expected.insetBy(dx: -3, dy: -3)), "\(name): no ink")
            let tolerance: CGFloat = 0.67
            #expect(abs(got.minX - expected.minX) <= tolerance && abs(got.maxX - expected.maxX) <= tolerance
                && abs(got.minY - expected.minY) <= tolerance && abs(got.maxY - expected.maxY) <= tolerance,
                "\(name): \(got) WebKit \(expected)")
        }
    }

    /// No mark where the text takes none: punctuation and spaces alone leave
    /// the band under them blank.
    @Test func punctuationAloneDrawsNoMark() async throws {
        let rows = Self.rows.filter { $0.name.hasPrefix("pc-") || $0.name == "p0" }
        let layout = try await Self.layout(rows, vertical: false)
        let found = Self.baselines(rows, in: layout)
        for name in ["pc-comma", "pc-ideocomma", "pc-period", "pc-open", "pc-close", "pc-excl", "pc-dot",
                     "pc-ellipsis", "pc-dash", "pc-asciiperiod", "pc-asciiexcl", "pc-kome", "pc-nbsp", "pc-ideospace"] {
            let baseline = try #require(found[name + "-p"], "\(name) not found")
            let band = CGRect(x: 25, y: baseline + 6.5, width: 17, height: 10)
            #expect(Self.ink(of: layout, in: band) == nil, "\(name) drew a mark")
        }
    }

    /// A ruby takes its side: horizontally the zh default puts the marks under
    /// and the ruby over, so both base characters are marked (ink 31 to 53);
    /// in vertical-rl both are on the right, so only 字 is (ink y 48 to 53.33).
    @Test(arguments: [false, true])
    func aRubyTakesItsSideFromTheMarks(vertical: Bool) async throws {
        let rows = Self.rows.filter { $0.name == "p0" || $0.name == "ruby-p" }
        let layout = try await Self.layout(rows, vertical: vertical)
        let base = try #require(BrowserLayoutTestSupport.fragment("漢", in: layout))
        let character = try #require(BrowserLayoutTestSupport.fragment("字", in: layout))
        let baseline = character.baselineY
        if vertical {
            let band = CGRect(x: baseline + 13, y: base.rect.rawValue.minY - 2, width: 12,
                              height: character.rect.rawValue.maxY - base.rect.rawValue.minY + 4)
            let got = try #require(Self.ink(of: layout, in: band, marked: true), "no mark")
            #expect(abs(got.minY - 48) <= 0.67 && abs(got.maxY - 53.33) <= 0.67, "\(got)")
        } else {
            let band = CGRect(x: 25, y: baseline + 5, width: 34, height: 12)
            let got = try #require(Self.ink(of: layout, in: band), "no mark")
            #expect(abs(got.minX - 31) <= 0.67 && abs(got.maxX - 53) <= 0.67, "\(got)")
        }
    }

    // MARK: Elements and italic text

    private static let elementRows: [Row] = [
        ("p0", "<p>起點段落。</p>", "起點段落。"),
        ("a-p", "<p>甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("b-p", "<p>甲<em class=\"sesame_dot\">傍點</em>乙</p>", "甲傍點乙"),
        ("c-p", "<p>甲<span class=\"sesame_dot\">傍點</span>乙</p>", "甲傍點乙"),
        ("d-p", "<p>甲<em class=\"fs\">傍點</em>乙</p>", "甲傍點乙"),
        ("e-p", "<p>甲<span class=\"fs ni\">傍點</span>乙</p>", "甲傍點乙"),
        ("f-p", "<p>甲<span class=\"fs it\">傍點</span>乙</p>", "甲傍點乙"),
        ("g-p", "<p>甲<i class=\"fs\">傍點</i>乙</p>", "甲傍點乙"),
        ("h-p", "<p>甲<b class=\"fs\">傍點</b>乙</p>", "甲傍點乙"),
        ("i-p", "<p>甲<em class=\"fs ni\">傍點</em>乙</p>", "甲傍點乙"),
        ("j-p", "<p>甲<strong class=\"fs\">傍點</strong>乙</p>", "甲傍點乙"),
        ("after", "<p>之後。</p>", "之後。"),
    ]

    /// The probe's mark ink, y from each row's baseline.
    private static let elementInk: [(String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        ("a", 30.667, 7.917, 22.333, 5.333),
        ("b", 30.667, 8.0, 22.333, 5.333),
        ("c", 30.667, 8.083, 22.333, 5.333),
        ("d", 31.667, 8.167, 22, 5.333),
        ("e", 30.667, 7.917, 22.333, 5.333),
        ("f", 31.667, 8.0, 22, 5.333),
        ("g", 31.667, 8.083, 22, 5.333),
        ("h", 30.667, 8.167, 22.333, 5.333),
        ("i", 30.667, 7.917, 22.333, 5.333),
        ("j", 30.667, 8.0, 22.333, 5.333),
    ]

    /// Aozora's `<em class="sesame_dot">` and every element draw their marks
    /// as a `span` does; on italic text, centred on the slanted glyphs' ink,
    /// a point right. Measured, the app's S001k fixture.
    @Test func elementsAndItalicTextDrawTheirMarks() async throws {
        let css = Self.css + ".ni { font-style: normal; } .it { font-style: italic; }"
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            Self.elementRows.map(\.html).joined(), css: css)
        let found = Self.baselines(Self.elementRows, in: layout)
        for (name, x, y, width, height) in Self.elementInk {
            let baseline = try #require(found[name + "-p"], "\(name) not found")
            let expected = CGRect(x: x, y: baseline + y, width: width, height: height)
            let got = try #require(Self.ink(of: layout, in: expected.insetBy(dx: -3, dy: -3)), "\(name): no ink")
            #expect(abs(got.minX - expected.minX) <= 0.67 && abs(got.maxX - expected.maxX) <= 0.67
                && abs(got.minY - expected.minY) <= 0.67 && abs(got.maxY - expected.maxY) <= 0.67,
                "\(name): \(got) WebKit \(expected)")
        }
    }

    // MARK: 縦中横 cells

    private static let cellRows: [Row] = [
        ("p0", "<p>起點段落。</p>", "起點段落。"),
        ("a-p", "<p>甲<span class=\"fs\">傍點</span>乙</p>", "甲傍點乙"),
        ("b-p", "<p>甲<span class=\"fs\"><span class=\"tcy\">12</span>字</span>乙</p>", "甲12字乙"),
        ("c-p", "<p>甲<span class=\"fs\">字<span class=\"tcy\">12</span></span>乙</p>", "甲字12乙"),
        ("d-p", "<p>甲<span class=\"fs\"><span class=\"tcy\">!?</span>字</span>乙</p>", "甲!?字乙"),
        ("e-p", "<p>甲<span class=\"fd\"><span class=\"tcy\">123</span>字</span>乙</p>", "甲123字乙"),
        ("after", "<p>之後。</p>", "之後。"),
    ]

    /// Each row's baseline from `a-p`'s, and its marks' ink as in `verticalInk`.
    private static let cellExpectations: [(String, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        ("a", 0, 15, 31, 5.333, 22.333),
        ("b", -52.25, 14.917, 31, 5.333, 22.333),
        ("c", -104.5, 14.833, 31, 5.333, 22.333),
        ("d", -156.75, 14.75, 31, 5.333, 22.333),
        ("e", -210, 17, 32, 2.333, 19),
    ]

    /// A 縦中横 cell takes one mark, on its column's centre line and centred
    /// on its em square, punctuation too, and its column grows as any marked
    /// column does. Measured, the app's S001l fixture: `12`, `!?` and `123`
    /// each one mark where `傍點` takes theirs; columns 35.25 wide, 36.25 in dot.
    @Test func aCombinedCellTakesOneMark() async throws {
        let css = Self.css + ".tcy { -webkit-text-combine: horizontal; text-combine-upright: all; }"
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            Self.cellRows.map(\.html).joined(), css: css, vertical: true)
        let found = Self.baselines(Self.cellRows, in: layout)
        let origin = try #require(found["a-p"])
        for (name, column, x, y, width, height) in Self.cellExpectations {
            let baseline = try #require(found[name + "-p"], "\(name) not found")
            #expect(abs(baseline - origin - column) <= 0.01, "\(name): \(baseline - origin), WebKit \(column)")
            let expected = CGRect(x: baseline + x, y: y, width: width, height: height)
            let got = try #require(Self.ink(of: layout, in: expected.insetBy(dx: -3, dy: -3), marked: true),
                                   "\(name): no ink")
            #expect(abs(got.minX - expected.minX) <= 0.67 && abs(got.maxX - expected.maxX) <= 0.67
                && abs(got.minY - expected.minY) <= 0.67 && abs(got.maxY - expected.maxY) <= 0.67,
                "\(name): \(got) WebKit \(expected)")
        }
    }

    // MARK: Contract and theme

    /// Marks add no source text and own none.
    @Test func marksLeaveTheSourceTextAlone() async throws {
        let marked = try await BrowserLayoutTestSupport.webKitReference(
            "<p>甲<span class=\"fs\">傍點，一二</span>乙</p>", css: Self.css)
        let plain = try await BrowserLayoutTestSupport.webKitReference("<p>甲<span>傍點，一二</span>乙</p>")
        #expect(marked.doc.lastSourceText == plain.doc.lastSourceText)
        #expect(BrowserLayoutTestSupport.visibleText(marked.pages, sourceText: marked.doc.lastSourceText)
            == BrowserLayoutTestSupport.visibleText(plain.pages, sourceText: plain.doc.lastSourceText))
    }

    /// A mark in `currentColor` follows a theme change with its text, as a
    /// decoration does; one in a colour of its own keeps it.
    @Test func marksInTheTextColourFollowTheTheme() async throws {
        let css = Self.css + ".red { -webkit-text-emphasis-color: red; text-emphasis-color: red; }"
        let layout = try await BrowserLayoutTestSupport.webKitReference(
            "<p>甲<span class=\"fs\">傍點</span><span class=\"fs red\">二三</span>乙</p>", css: css)
        let list = DisplayListBuilder.build(for: layout.pages[0], sourceText: layout.doc.lastSourceText,
                                            themeTextColor: .white, oldThemeColor: .black)
        let marked = list.items.compactMap { item -> DisplayTextItem? in
            if case .text(let text) = item, text.textEmphasis != nil { return text }
            return nil
        }
        try #require(marked.count == 2, "\(marked.count) marked items")
        #expect(marked[0].textEmphasis?.color == .white && marked[0].color == .white)
        #expect(marked[1].textEmphasis?.color == .red)
    }

    /// WebKit's first baselines from the first row's, the ruby row left out
    /// (the rows after it moved back by its 65).
    private static let horizontalBaselines: [(String, CGFloat)] = [
        ("p0", 0.0),
        ("fs-p", 42.5),
        ("os-p", 94.75),
        ("fd-p", 147.0),
        ("od-p", 200.25),
        ("fc-p", 252.5),
        ("oc-p", 305.75),
        ("fdc-p", 358.0),
        ("odc-p", 410.25),
        ("ft-p", 462.5),
        ("ot-p", 514.75),
        ("str-p", 567.0),
        ("per-p", 620.25),
        ("skip-p", 672.5),
        ("latin-p", 724.75),
        ("under-p", 777.0),
        ("big-p", 848.0),
        ("sesame-dot-p", 914.25),
        ("lines-plain", 966.5),
        ("lines-em", 1085.5),
        ("lines-under", 1243.5),
        ("lines-mid", 1401.5),
        ("normal-plain", 1530.0),
        ("normal-em", 1647.0),
        ("over-p", 1814.0),
        ("left-p", 1866.25),
        ("ja-p", 1918.5),
        ("en-p", 1961.0),
        ("hans-p", 2013.25),
        ("mid-skip-p", 2065.5),
        ("ko-p", 2127.5),
        ("mn-p", 2170.0),
        ("nolang-p", 2222.25),
        ("pc-comma-p", 2274.5),
        ("pc-ideocomma-p", 2326.75),
        ("pc-period-p", 2379.0),
        ("pc-open-p", 2431.25),
        ("pc-close-p", 2483.5),
        ("pc-excl-p", 2535.75),
        ("pc-dot-p", 2588.0),
        ("pc-ellipsis-p", 2640.25),
        ("pc-dash-p", 2692.5),
        ("pc-digit-p", 2744.75),
        ("pc-fullA-p", 2797.0),
        ("pc-choon-p", 2849.25),
        ("pc-kurikaeshi-p", 2901.5),
        ("pc-zero-p", 2953.75),
        ("pc-asciiperiod-p", 3006.0),
        ("pc-asciiexcl-p", 3058.25),
        ("pc-kome-p", 3110.5),
        ("pc-nbsp-p", 3162.75),
        ("pc-ideospace-p", 3215.0),
        ("pc-hash-p", 3267.25),
        ("pc-plus-p", 3319.5),
        ("helv16-p", 3371.5),
        ("helv14-p", 3413.5),
        ("helv15-p", 3455.5),
        ("helv8-p", 3497.5),
        ("times16-p", 3539.5),
        ("hira8-p", 3581.5),
        ("hira10-p", 3623.5),
        ("hira12-p", 3665.5),
        ("hira16-p", 3707.5),
        ("after", 3749.75),
    ]

    /// The same in vertical-rl, the ruby row's 55.25 taken out, and `fc-p` and
    /// the rows after it 10 to the right of WebKit's (see `columnsGrowToHoldTheirMarks`).
    private static let verticalBaselines: [(String, CGFloat)] = [
        ("p0", 0.0),
        ("fs-p", -52.25),
        ("os-p", -104.5),
        ("fd-p", -157.75),
        ("od-p", -210.0),
        ("fc-p", -263.25),
        ("oc-p", -315.5),
        ("fdc-p", -367.75),
        ("odc-p", -420.0),
        ("ft-p", -472.25),
        ("ot-p", -524.5),
        ("str-p", -577.75),
        ("per-p", -630.0),
        ("skip-p", -682.25),
        ("latin-p", -734.5),
        ("under-p", -777.0),
        ("big-p", -859.0),
        ("sesame-dot-p", -924.0),
        ("lines-plain", -966.5),
        ("lines-em", -1044.25),
        ("lines-under", -1122.0),
        ("lines-mid", -1219.25),
        ("normal-plain", -1287.0),
        ("normal-em", -1364.0),
        ("over-p", -1451.0),
        ("left-p", -1493.5),
        ("ja-p", -1555.5),
        ("en-p", -1607.75),
        ("hans-p", -1660.0),
        ("mid-skip-p", -1712.25),
        ("after", -1754.75),
    ]

    /// The probe's mark ink (`fc` left out in vertical-rl, see above), with
    /// two exceptions horizontally. `sesame-dot` is measured alone (the app's
    /// S001i fixture reads no marks on that one row, in two runs, where the
    /// same `<em class="sesame_dot">` anywhere else in a fixture draws its
    /// marks as a `span` does: a probe artefact, not WebKit's behaviour).
    /// `ft` is left out: WebKit's filled triangle there is a device pixel
    /// smaller each way and up to 1 higher than Hiragino's ▲, which it draws
    /// in vertical-rl and as the open triangle's size, and no installed face
    /// with a 10-tall box has that ink; the engine draws Hiragino's.
    private static let horizontalInk: [(String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        ("fs", 30.667, 7.917, 22.333, 5.333),
        ("os", 30, 7.667, 23.333, 6),
        ("fd", 32, 11.083, 19.333, 2),
        ("od", 31.333, 9.167, 21, 3.667),
        ("fc", 31.333, 10.583, 21, 4),
        ("oc", 29.333, 7, 25, 7.667),
        ("fdc", 29.333, 7.083, 25, 7.667),
        ("odc", 29.333, 7.167, 25, 7.667),
        ("ot", 29.333, 7, 25, 7),
        ("str", 31, 10.75, 21.667, 4.333),
        ("per", 30.667, 8.167, 56.333, 5.333),
        ("skip", 30.667, 7.917, 73.333, 5.333),
        ("latin", 27, 8, 40, 5.333),
        ("under", 30.667, 8.083, 22.333, 5.333),
        ("big", 36.667, 15.417, 44.333, 10.333),
        ("sesame-dot", 30.667, 7.917, 22.333, 5.333),
        ("over", 30.667, -26.917, 22.333, 5.333),
        ("left", 30.667, -26.833, 22.333, 5.333),
        ("ja", 30.667, -27.083, 22.333, 5.333),
        ("en", 30.667, 8.083, 22.333, 5.333),
        ("hans", 30.667, 8.167, 22.333, 5.333),
        ("mid-skip", 30.667, 7.917, 73.333, 5.333),
        ("ko", 30.667, -27.083, 22.333, 5.333),
        ("mn", 30.667, 8.083, 22.333, 5.333),
        ("nolang", 30.667, 8.167, 22.333, 5.333),
        ("pc-digit", 25, 8, 5.333, 5.333),
        ("pc-fullA", 30.667, 8.083, 5.333, 5.333),
        ("pc-choon", 30.667, 8.167, 5.333, 5.333),
        ("pc-kurikaeshi", 29.667, 7.917, 5.333, 5.333),
        ("pc-zero", 30.667, 8, 5.333, 5.333),
        ("pc-hash", 27.333, 8.167, 5.333, 5.333),
        ("pc-plus", 30.667, 7.917, 5.333, 5.333),
    ]
    private static let verticalInk: [(String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        ("fs", 15, 31, 5.333, 22.333),
        ("os", 14.25, 30.667, 6, 23),
        ("fd", 16.833, 32, 2.333, 19),
        ("od", 15.417, 32, 3.667, 20.667),
        ("oc", 13.583, 30, 7.667, 24.667),
        ("fdc", 13.5, 30, 7.667, 24.667),
        ("odc", 13.417, 30, 7.667, 24.667),
        ("ft", 13.667, 30, 8, 24),
        ("ot", 13.583, 30, 8, 24),
        ("str", 15.833, 31.667, 4.333, 21.333),
        ("per", 14.75, 31, 5.333, 56.333),
        ("skip", 15, 31, 5.333, 73.333),
        ("latin", 14.917, 27, 5.333, 40),
        ("under", -20.25, 31, 5.333, 22.333),
        ("big", 28.333, 37, 10.333, 44.333),
        ("sesame-dot", 15, 31, 5.333, 22.333),
        ("over", 15, 31, 5.333, 22.333),
        ("left", -20.167, 31, 5.333, 22.333),
        ("ja", 14.833, 31, 5.333, 22.333),
        ("en", 14.75, 31, 5.333, 22.333),
        ("hans", 15, 31, 5.333, 22.333),
        ("mid-skip", 14.917, 31, 5.333, 73.333),
    ]
}
