import CoreText
import Testing
import UIKit
@testable import YueduCoreText
import YueduCoreTextTypography

/// Where list markers are drawn and how they change the lines they sit on, in
/// paged, scroll and viewport layout. Numbers name the S001c fixture case they
/// were measured on in the iOS 27.2 WKWebView
/// (`scripts/fidelity/fixtures/gaps/S001c-list-markers` in the App repository,
/// read with `scripts/fidelity/list_probe.sh`): PingFang SC 17px, line-height
/// 25.5px, an `ol`/`ul` padding of 40px, as here.
@Suite @MainActor
struct ListMarkerLayoutTests {

    private static let baseCSS = "body { margin: 0; line-height: 1.5 } p { margin: 0 } ol, ul { margin: 0 }"

    private static func html(_ body: String) -> String {
        "<html><head></head><body>\(body)</body></html>"
    }

    private static func config(width: CGFloat = 300, height: CGFloat = 2000) -> BrowserLayoutConfig {
        BrowserLayoutConfig(renderWidth: width, renderHeight: height, rootFontSize: 17,
                            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
    }

    private struct Layout {
        let pages: [PageFragments]
        let source: NSString

        var texts: [TextFragment] { BrowserLayoutTestSupport.allTextFragments(pages) }
        var markers: [TextFragment] { texts.filter(ListMarkerLayoutTests.isMarker) }
        var bullets: [FillFragment] { pages.flatMap { ListMarkerLayoutTests.fills($0.fragments) }.filter(\.followsTextColor) }

        /// The content fragment holding the first character of `string`.
        func text(_ string: String) throws -> TextFragment {
            let location = source.range(of: string).location
            try #require(location != NSNotFound, "\(string) is not in the chapter")
            return try #require(texts.first { $0.sourceRange.length > 0 && NSLocationInRange(location, $0.sourceRange) },
                                "no fragment draws \(string)")
        }

        /// The x where the content box of the `ol`/`ul` starts: a list item's
        /// border box start. Every layout here opens with a `參考` paragraph.
        func itemBorderStart(depth: CGFloat = 1) throws -> CGFloat {
            try text("參考").rect.rawValue.minX + 40 * depth
        }
    }

    private static func layout(
        _ body: String, css: String = "", width: CGFloat = 300, height: CGFloat = 2000,
        images: [String: UIImage] = [:], configure: (inout BrowserLayoutConfig) -> Void = { _ in }
    ) async throws -> Layout {
        var config = Self.config(width: width, height: height)
        configure(&config)
        let doc = BrowserLayoutDocument(html: Self.html(body), cssTexts: [Self.baseCSS + css], config: config,
                                        imageLoader: { images[$0] })
        let pages = try await doc.renderPages(containerSize: CGSize(width: width, height: height))
        return Layout(pages: pages, source: doc.lastSourceText as NSString)
    }

    /// A marker is generated text: drawn, with no characters of the source.
    nonisolated private static func isMarker(_ text: TextFragment) -> Bool {
        text.sourceRange.length == 0 && text.renderedTextOverride != nil
    }

    nonisolated private static func fills(_ fragments: [Fragment]) -> [FillFragment] {
        fragments.flatMap { fragment -> [FillFragment] in
            switch fragment {
            case .fill(let fill): return [fill]
            case .group(let children): return fills(children)
            default: return []
            }
        }
    }

    private static func displayMarkers(_ list: DisplayList) -> [DisplayTextItem] {
        list.items.compactMap { item in
            guard case .text(let text) = item, text.isListMarker else { return nil }
            return text
        }
    }

    // MARK: - Counters

    /// S001c 01-ol-text: every counter's ink ends 7.00 before the item's border
    /// box, on its first line's baseline, however long the item runs.
    @Test func counterEndsAtTheItemBorderOnItsFirstLineBaseline() async throws {
        let layout = try await Self.layout("<p>參考</p><ol><li>第一項。</li><li>第二項寫得比較長，長到在這個寬度上一定會折行，編號只在第一行。</li><li>第三項。</li></ol>")
        let border = try layout.itemBorderStart()
        #expect(layout.markers.map(\.renderedTextOverride) == ["1. ", "2. ", "3. "])
        for (marker, item) in zip(layout.markers, ["第一項", "第二項", "第三項"]) {
            let first = try layout.text(item)
            #expect(abs(marker.rect.rawValue.maxX - border) < 0.01, "\(item)")
            #expect(abs(marker.baselineY - first.baselineY) < 0.01, "\(item)")
            #expect(marker.sourceRange == NSRange(location: first.sourceRange.location, length: 0), "\(item)")
            #expect(marker.sourceMapping == .wholeRange)
            #expect(marker.linkTarget == nil)
            let ink = CTLineGetBoundsWithOptions(try #require(marker.ctLine), .useGlyphPathBounds)
            // One device pixel at 3× is the probe's resolution.
            #expect(abs(border - (marker.rect.rawValue.minX + ink.maxX) - 7) < 0.34, "\(item)")
        }
    }

    /// S001c 04-li-padding, 04-li-border, 05-center, 03-indent, 03-shift: none
    /// of these moves the marker off the border box start.
    @Test func paddingBorderAlignmentAndIndentLeaveTheMarkerAtTheBorder() async throws {
        let cases: [(body: String, css: String, contentInset: CGFloat?)] = [
            ("<ol class=x><li>項目。</li></ol>", ".x li { padding-left: 17px }", 17),
            ("<ol class=x><li>項目。</li></ol>", ".x li { border-left: 3px solid #888888 }", 3),
            ("<ol class=x><li>項目。</li></ol>", ".x li { text-align: center }", nil),
            ("<ol><li><p class=x>項目。</p></li></ol>", ".x { text-indent: 2em }", 34),
            ("<ol><li><p class=x>項目。</p></li></ol>", ".x { margin-left: 2em }", 34),
        ]
        for (body, css, contentInset) in cases {
            let layout = try await Self.layout("<p>參考</p>" + body, css: css)
            let border = try layout.itemBorderStart()
            let marker = try #require(layout.markers.first, "\(css)")
            #expect(abs(marker.rect.rawValue.maxX - border) < 0.01, "\(css)")
            let text = try layout.text("項目")
            #expect(abs(marker.baselineY - text.baselineY) < 0.01, "\(css)")
            if let contentInset {
                #expect(abs(text.rect.rawValue.minX - border - contentInset) < 0.01, "\(css)")
            }
        }
    }

    /// S001c 10-li-starts-with-list: an item that opens with a list shares its
    /// first line with the inner item, and both markers sit on it.
    @Test func nestedListOnTheFirstLineCarriesBothMarkers() async throws {
        let layout = try await Self.layout("<p>參考</p><ol><li><ol><li>內層。</li></ol></li><li>外層。</li></ol>")
        #expect(layout.markers.count == 3)
        let inner = try layout.text("內層")
        let firstLine = layout.markers.filter { abs($0.baselineY - inner.baselineY) < 0.01 }
            .sorted { $0.rect.rawValue.maxX < $1.rect.rawValue.maxX }
        try #require(firstLine.count == 2)
        #expect(abs(firstLine[0].rect.rawValue.maxX - (try layout.itemBorderStart(depth: 1))) < 0.01)
        #expect(abs(firstLine[1].rect.rawValue.maxX - (try layout.itemBorderStart(depth: 2))) < 0.01)
        #expect(firstLine.allSatisfy { $0.renderedTextOverride == "1. " })
    }

    // MARK: - Bullets

    /// S001c 01-ul-text, 11-circle, 11-square (17px: 19 out from the border,
    /// 9.5 above the baseline, side 6.83) and 08-ul-large (25.5px: 25 out).
    @Test func bulletsAreShapesSizedFromTheRoundedAscent() async throws {
        let layout = try await Self.layout(
            "<p>參考</p><ul><li>圓點。</li><li class=c>空心圓。</li><li class=s>方塊。</li><li class=big>大圓點。</li></ul>",
            css: "li.c { list-style-type: circle } li.s { list-style-type: square } li.big { font-size: 25.5px }")
        let border = try layout.itemBorderStart()
        #expect(layout.markers.isEmpty)
        try #require(layout.bullets.count == 4)
        for (bullet, item) in zip(layout.bullets, ["圓點", "空心圓", "方塊", "大圓點"]) {
            let text = try layout.text(item)
            let ascent = ceil(text.font.ascender)
            let side = (ascent * 2 / 3 + 1) / 2
            let shape = CGRect(x: border - (floor(ascent * 2 / 3) + 7), y: text.baselineY - ascent / 2, width: side, height: side)
            let rect = bullet.rect.rawValue
            switch item {
            case "空心圓":
                #expect(rect.equalTo(shape.insetBy(dx: -0.5, dy: -0.5)))
                #expect(bullet.color == .clear)
                #expect(bullet.borderTop.width == 1 && bullet.borderLeft.color == .black)
                #expect(bullet.cornerRadius == rect.width / 2)
            default:
                #expect(rect.equalTo(shape), "\(item)")
                #expect(bullet.color == .black)
                #expect(bullet.borderTop.width == 0)
                #expect(bullet.cornerRadius == (item == "方塊" ? 0 : side / 2))
            }
        }
        let disc = layout.bullets[0].rect.rawValue
        #expect(abs(disc.minX - (border - 19)) < 0.01 && abs(disc.width - 41.0 / 6) < 0.01)
        #expect(abs(disc.minY - (try layout.text("圓點").baselineY - 9.5)) < 0.01)
        #expect(abs(layout.bullets[3].rect.rawValue.minX - (border - 25)) < 0.01)
    }

    // MARK: - Line height

    private static func gapBefore(_ body: String, css: String) async throws -> CGFloat {
        let layout = try await Self.layout(body + "<p>後文</p>", css: css)
        return try layout.text("後文").rect.rawValue.minY
    }

    /// S001c 08-li-large and 08-ul-large: a 25.5px item around a 17px
    /// paragraph grows the first line by 12.75; 08-li-lh1 and every same-font
    /// item: by nothing.
    @Test func markerGrowsItsLineAsAnInlineBoxOfTheItemsFont() async throws {
        let large = ".large li { font-size: 25.5px } .large li p { font-size: 17px } .none { list-style-type: none }"
        for list in ["ol", "ul"] {
            let drawn = try await Self.gapBefore("<\(list) class=large><li><p>項目。</p></li></\(list)>", css: large)
            let none = try await Self.gapBefore("<\(list) class=\"large none\"><li><p>項目。</p></li></\(list)>", css: large)
            #expect(abs(drawn - none - 12.75) < 0.01, "\(list)")
        }
        for css in ["", "li { line-height: 1 }"] {
            let drawn = try await Self.gapBefore("<ol><li>項目。</li></ol>", css: css)
            let none = try await Self.gapBefore("<ol style=\"list-style-type: none\"><li>項目。</li></ol>", css: css)
            #expect(abs(drawn - none) < 0.001, "\(css)")
        }
    }

    /// S001c 07-empty, 07-empty-ul: an empty item is one item line tall and
    /// shows its marker; with no marker it has no height.
    @Test func anEmptyItemHoldsTheLineItsMarkerSitsOn() async throws {
        for list in ["ol", "ul"] {
            let drawn = try await Self.layout("<p>參考</p><\(list)><li></li></\(list)><p>後文</p>")
            let none = try await Self.layout("<p>參考</p><\(list) style=\"list-style-type: none\"><li></li></\(list)><p>後文</p>")
            let after = try drawn.text("後文")
            #expect(abs(after.rect.rawValue.minY - (try none.text("後文").rect.rawValue.minY) - 25.5) < 0.01, "\(list)")
            // Its baseline sits where a line of the item's own text would.
            let baseline = after.baselineY - 25.5
            if list == "ol" {
                let marker = try #require(drawn.markers.first)
                #expect(marker.renderedTextOverride == "1. ")
                #expect(abs(marker.baselineY - baseline) < 0.01)
                #expect(abs(marker.rect.rawValue.maxX - (try drawn.itemBorderStart())) < 0.01)
            } else {
                let bullet = try #require(drawn.bullets.first)
                #expect(abs(bullet.rect.rawValue.minY - (baseline - 9.5)) < 0.01)
            }
        }
    }

    /// S001c 07-block-image: an item that opens with a block image is the
    /// image's height, its marker on a line's baseline at the item's top.
    @Test func anItemOpeningWithABlockImageGetsNoExtraLine() async throws {
        let image = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 60, height: 60), color: .gray)
        let body = "<p>參考</p><ol%@><li><img src=\"plate.png\" style=\"display: block; width: 60px; height: 60px\"/></li></ol><p>後文</p>"
        let drawn = try await Self.layout(String(format: body, ""), images: ["plate.png": image])
        let none = try await Self.layout(String(format: body, " style=\"list-style-type: none\""), images: ["plate.png": image])
        let after = try drawn.text("後文").rect.rawValue.minY
        #expect(abs(after - (try none.text("後文").rect.rawValue.minY)) < 0.01)
        let marker = try #require(drawn.markers.first)
        // Where it would sit on a first line of text in the same item.
        let text = try await Self.layout("<p>參考</p><ol><li>文字。</li></ol>")
        let textMarker = try #require(text.markers.first)
        #expect(abs(marker.baselineY - textMarker.baselineY) < 0.01)
        #expect(marker.rect.rawValue.equalTo(textMarker.rect.rawValue))
    }

    // MARK: - Floats

    /// S001c 12-float-before: a float placed before the list pushes the item's
    /// first line and the marker goes with it.
    @Test func aFloatBeforeTheItemMovesTheMarkerWithItsLine() async throws {
        let layout = try await Self.layout(
            "<p>參考</p><div style=\"float: left; width: 60px; height: 100px\"></div><ol><li>第一項。</li></ol>")
        let text = try layout.text("第一項")
        let left = try layout.text("參考").rect.rawValue.minX
        #expect(abs(text.rect.rawValue.minX - (left + 60)) < 0.01)
        let marker = try #require(layout.markers.first)
        #expect(abs(marker.rect.rawValue.maxX - text.rect.rawValue.minX) < 0.01)
    }

    /// S001c 12-float-in-li: an item's own first float pushes its line but not
    /// its marker; the next item, whose line the same float still pushes, moves.
    @Test func anItemsOwnFloatLeavesItsMarkerAtTheBorder() async throws {
        let layout = try await Self.layout(
            "<p>參考</p><ol><li><div style=\"float: left; width: 60px; height: 40px\"></div>第一項。</li><li>第二項。</li></ol>")
        let border = try layout.itemBorderStart()
        let first = try layout.text("第一項")
        let second = try layout.text("第二項")
        #expect(abs(first.rect.rawValue.minX - (border + 60)) < 0.01)
        #expect(abs(second.rect.rawValue.minX - (border + 60)) < 0.01, "the float is 40 tall and reaches the second item")
        try #require(layout.markers.count == 2)
        #expect(abs(layout.markers[0].rect.rawValue.maxX - border) < 0.01)
        #expect(abs(layout.markers[1].rect.rawValue.maxX - second.rect.rawValue.minX) < 0.01)
    }

    // MARK: - Paths

    /// A marker is on its line's page and moves with it, however the list
    /// breaks, and when 底部對齊 spreads a page's lines apart.
    @Test(arguments: [false, true])
    func markersArePagedWithTheirLines(bottomJustify: Bool) async throws {
        let ordered = (1...30).map { "<li>第\($0)項寫得比較長，長到在這個寬度上一定會折行。</li>" }.joined()
        let bulleted = (1...30).map { "<li>圓點\($0)寫得比較長，長到在這個寬度上一定會折行。</li>" }.joined()
        let layout = try await Self.layout("<p>參考</p><ol>\(ordered)</ol><ul>\(bulleted)</ul>", height: 200) {
            $0.bottomJustify = bottomJustify
        }
        #expect(layout.pages.count > 6)
        var strings: [String] = []
        var bulletCount = 0
        for page in layout.pages {
            let texts = BrowserLayoutTestSupport.allTextFragments([page])
            for marker in texts.filter(Self.isMarker) {
                strings.append(marker.renderedTextOverride ?? "")
                #expect(texts.contains { $0.sourceRange.length > 0 && $0.sourceRange.location == marker.sourceRange.location
                    && abs($0.baselineY - marker.baselineY) < 0.01 }, "\(marker.renderedTextOverride ?? "") on page \(page.index)")
            }
            for bullet in Self.fills(page.fragments).filter(\.followsTextColor) {
                bulletCount += 1
                // 9.5 above the baseline of a line on the same page (PingFang 17px).
                #expect(texts.contains { $0.sourceRange.length > 0 && abs($0.baselineY - 9.5 - bullet.rect.rawValue.minY) < 0.01 },
                        "bullet at \(bullet.rect.rawValue.minY) on page \(page.index)")
            }
        }
        #expect(strings == (1...30).map { "\($0). " })
        #expect(bulletCount == 30)
        if bottomJustify {
            let plain = try await Self.layout("<p>參考</p><ol>\(ordered)</ol><ul>\(bulleted)</ul>", height: 200)
            #expect(plain.markers.map(\.baselineY) != layout.markers.map(\.baselineY), "底部對齊 moved no line here")
        }
    }

    private static let pathsBody = "<p>參考</p><ol><li>第一項。</li><li>第二項。</li></ol><ul><li>圓點。</li><li style=\"list-style-type: circle\">空心圓。</li></ul>"

    @Test func scrollModeDrawsTheSameMarkers() async throws {
        let paged = try await Self.layout(Self.pathsBody)
        let doc = BrowserLayoutDocument(html: Self.html(Self.pathsBody), cssTexts: [Self.baseCSS], config: Self.config(),
                                        imageLoader: nil)
        let scroll = BrowserScrollDocument.make(pipeline: try doc.makeLayout(containerSize: CGSize(width: 300, height: 2000)),
                                                contentWidth: 300, contentInsets: .zero)
        let markers = Self.displayMarkers(scroll.displayList)
        #expect(markers.map(\.renderedTextOverride) == paged.markers.map(\.renderedTextOverride))
        #expect(markers.map(\.rect.rawValue) == paged.markers.map(\.rect.rawValue))
        // A tile is a window onto the same items: the bullets keep their flag.
        let tile = scroll.items(in: CGRect(x: 0, y: 0, width: 300, height: scroll.contentHeight))
        let bullets = tile.items.compactMap { item -> DisplayFillItem? in
            guard case .fill(let fill) = item, fill.followsTextColor else { return nil }
            return fill
        }
        #expect(bullets.count == 2)
    }

    /// The viewport session shapes lines as they come into view; a marker
    /// rides on its line there, and comes back with it.
    @Test func viewportLayoutDrawsMarkersWithTheLinesItShapes() throws {
        let items = (1...200).map { "<li>第\($0)項。" + String(repeating: "很長的內容，", count: 12) + "</li>" }.joined()
        let html = Self.html("<ol>\(items)</ol>")
        let input = HTMLLayoutDocument(html: html, css: [Self.baseCSS], configuration: Self.config(width: 320, height: 600))
        let eager = try input.prepareContinuous(validateCapabilities: false).makeDocument()
        let session = try input.makeViewportSession()
        let first = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1200))
        let shown = Self.displayMarkers(first.displayList)
        #expect(!shown.isEmpty && shown.count < 200, "only the lines in view are shaped")
        #expect(eager.contentHeight > 12_000 + 1200)
        let far = try session.layout(in: CGRect(x: 0, y: 12_000, width: 320, height: 1200))
        #expect(!Self.displayMarkers(far.displayList).isEmpty)
        let back = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1200))
        #expect(Self.displayMarkers(back.displayList).map(\.rect.rawValue) == shown.map(\.rect.rawValue))
        let whole = Self.displayMarkers(try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1_000_000)).displayList)
        let eagerMarkers = Self.displayMarkers(eager.displayList)
        #expect(eagerMarkers.count == 200)
        #expect(whole.map(\.rect.rawValue) == eagerMarkers.map(\.rect.rawValue))
        #expect(whole.map(\.renderedTextOverride) == eagerMarkers.map(\.renderedTextOverride))
    }

    /// Lines out of view are estimated, not shaped. The estimate counts the
    /// height a marker adds to its line (08-li-large: 12.75 per item), or the
    /// chapter grows under the reader as those lines are shaped.
    @Test func viewportEstimateCountsTheHeightMarkersAdd() throws {
        let css = Self.baseCSS + " .large li { font-size: 25.5px } .large li p { font-size: 17px } .none { list-style-type: none }"
        let items = (1...200).map { "<li><p>第\($0)項。</p></li>" }.joined()
        func heights(_ classes: String) throws -> (estimated: CGFloat, shaped: CGFloat, shapedLines: Int) {
            let input = HTMLLayoutDocument(html: Self.html("<ol class=\"\(classes)\">\(items)</ol>"), css: [css],
                                           configuration: Self.config(width: 320, height: 600))
            let shaped = try input.prepareContinuous(validateCapabilities: false).makeDocument().contentHeight
            let session = try input.makeViewportSession()
            let estimated = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 600)).contentHeight
            return (estimated, shaped, session.shapedLineCount)
        }
        let drawn = try heights("large")
        let none = try heights("large none")
        #expect(drawn.shapedLines < 100, "most lines should still be estimated")
        #expect(abs(drawn.shaped - none.shaped - 200 * 12.75) < 0.5)
        #expect(abs((drawn.estimated - none.estimated) - (drawn.shaped - none.shaped)) < 0.5)
    }

    // MARK: - Paint

    /// A marker is drawn in its item's color, the color the item's text gets,
    /// down to the color baked into the counter's own line.
    @Test func markersTakeTheItemsTextColor() async throws {
        let grey = UIColor(white: 0.35, alpha: 1)
        let layout = try await Self.layout(
            "<p>參考</p><ol><li>第一項。</li></ol><ul><li>圓點。</li><li class=c>空心圓。</li></ul>",
            css: "li.c { list-style-type: circle }") { $0.textColor = grey }
        let text = try layout.text("第一項")
        #expect(text.color != .black)
        let marker = try #require(layout.markers.first)
        #expect(marker.color == text.color)
        let line = try #require(marker.ctLine)
        let run = try #require((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
        let attributes = CTRunGetAttributes(run) as NSDictionary
        #expect(attributes[NSAttributedString.Key.foregroundColor] as? UIColor == text.color)
        try #require(layout.bullets.count == 2)
        #expect(layout.bullets[0].color == text.color)
        #expect(layout.bullets[1].borderLeft.color == text.color)
    }

    /// Pixels, not rects: the drawer inks a counter's zero-length item, fills a
    /// disc and a square, and strokes a circle's ring inside its rect.
    @Test func drawnMarkersInkThePage() async throws {
        let layout = try await Self.layout(
            "<p>參考</p><ol><li>第一項。</li></ol><ul><li>圓點。</li><li class=c>空心圓。</li><li class=s>方塊。</li></ul>",
            css: "li.c { list-style-type: circle } li.s { list-style-type: square }")
        let list = DisplayListBuilder.build(for: layout.pages[0], sourceText: layout.source as String)
        let canvas = Canvas(list, size: CGSize(width: 300, height: 200))
        let counter = try #require(layout.markers.first).rect.rawValue
        #expect(canvas.inkedPixels(in: counter) > 20)
        try #require(layout.bullets.count == 3)
        let disc = layout.bullets[0].rect.rawValue
        let ring = layout.bullets[1].rect.rawValue
        let square = layout.bullets[2].rect.rawValue
        #expect(canvas.darkness(at: CGPoint(x: disc.midX, y: disc.midY)) > 0.9)
        #expect(canvas.darkness(at: CGPoint(x: square.midX, y: square.midY)) > 0.9)
        #expect(canvas.darkness(at: CGPoint(x: ring.midX, y: ring.midY)) < 0.1)
        // The 1pt ring runs from the rect's edge inward: the disc's own edge is
        // its middle.
        #expect(canvas.darkness(at: CGPoint(x: ring.minX + 0.5, y: ring.midY)) > 0.8)
        #expect(canvas.darkness(at: CGPoint(x: ring.minX - 0.5, y: ring.midY)) < 0.1)
    }

    /// A display list drawn at 3× on white, read back pixel by pixel.
    private struct Canvas {
        static let scale: CGFloat = 3
        private let pixels: [UInt8]
        private let width: Int
        private let height: Int

        init(_ list: DisplayList, size: CGSize) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = Self.scale
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                DisplayListDrawer.draw(list, in: context.cgContext)
            }
            let cgImage = image.cgImage!
            width = cgImage.width
            height = cgImage.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            data.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                                        bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            }
            pixels = data
        }

        /// 0 for white, 1 for black, at the pixel holding `point`.
        func darkness(at point: CGPoint) -> CGFloat {
            darkness(x: Int(floor(point.x * Self.scale)), y: Int(floor(point.y * Self.scale)))
        }

        func inkedPixels(in rect: CGRect) -> Int {
            var count = 0
            for y in Int(floor(rect.minY * Self.scale))..<Int(ceil(rect.maxY * Self.scale)) {
                for x in Int(floor(rect.minX * Self.scale))..<Int(ceil(rect.maxX * Self.scale)) where darkness(x: x, y: y) > 0.5 {
                    count += 1
                }
            }
            return count
        }

        /// The pixel-aligned box of every pixel in `rect` touched by ink, as
        /// the probe reads a marker from two screenshots' difference.
        func inkExtent(in rect: CGRect) -> CGRect? {
            var box: CGRect?
            for y in Int(floor(rect.minY * Self.scale))..<Int(ceil(rect.maxY * Self.scale)) {
                for x in Int(floor(rect.minX * Self.scale))..<Int(ceil(rect.maxX * Self.scale)) where darkness(x: x, y: y) > 0.05 {
                    let pixel = CGRect(x: CGFloat(x) / Self.scale, y: CGFloat(y) / Self.scale,
                                       width: 1 / Self.scale, height: 1 / Self.scale)
                    box = box.map { $0.union(pixel) } ?? pixel
                }
            }
            return box
        }

        private func darkness(x: Int, y: Int) -> CGFloat {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            let index = (y * width + x) * 4
            return 1 - (CGFloat(pixels[index]) + CGFloat(pixels[index + 1]) + CGFloat(pixels[index + 2])) / (3 * 255)
        }
    }

    /// A theme change that recolors text recolors markers drawn in the theme's
    /// color, a counter's text and a bullet's fill or ring alike, and leaves an
    /// authored color alone.
    @Test func themeRecolorReachesEveryMarker() async throws {
        let layout = try await Self.layout(
            "<p>參考</p><ol><li>第一項。</li></ol><ul><li>圓點。</li><li class=c>空心圓。</li><li class=red>紅色。</li></ul>",
            css: "li.c { list-style-type: circle } li.red { color: #ff0000 }")
        let list = DisplayListBuilder.build(for: layout.pages[0], sourceText: layout.source as String,
                                            themeTextColor: .white, oldThemeColor: .black)
        #expect(Self.displayMarkers(list).map(\.color) == [.white])
        let bullets = list.items.compactMap { item -> DisplayFillItem? in
            guard case .fill(let fill) = item, fill.followsTextColor else { return nil }
            return fill
        }
        try #require(bullets.count == 3)
        #expect(bullets[0].color == .white)
        #expect(bullets[1].color == .clear)
        #expect([bullets[1].borderTop, bullets[1].borderBottom, bullets[1].borderLeft, bullets[1].borderRight]
            .allSatisfy { $0.color == .white && $0.width == 1 })
        #expect(bullets[2].color != .white)
    }

    @Test func movingABulletKeepsItsThemeFlag() {
        let edge = BorderEdge.zero
        let fill = FillFragment(
            rect: PageLocalRect(rawValue: CGRect(x: 1, y: 2, width: 3, height: 3)),
            documentRect: DocumentRect(rawValue: CGRect(x: 1, y: 2, width: 3, height: 3)),
            color: .black, cornerRadius: 1.5, borderTop: edge, borderBottom: edge, borderLeft: edge, borderRight: edge,
            nodeID: 1, writingMode: .horizontal, followsTextColor: true)
        #expect(fill.with(rect: PageLocalRect(rawValue: CGRect(x: 1, y: 9, width: 3, height: 3))).followsTextColor)
    }

    /// Selection, hit testing and links read source text; a marker has none.
    @Test func selectionAndLinksPassMarkersBy() async throws {
        let layout = try await Self.layout("<p>參考</p><ol><li><a href=\"#note\">第一項</a>。</li></ol><p id=note>註。</p>")
        let marker = try #require(layout.markers.first)
        #expect(marker.linkTarget == nil)
        #expect(try layout.text("第一項").linkTarget != nil)
        let list = DisplayListBuilder.build(for: layout.pages[0], sourceText: layout.source as String)
        let point = CGPoint(x: marker.rect.rawValue.midX, y: marker.rect.rawValue.midY)
        #expect(BrowserTextGeometry.range(at: point, in: list, source: layout.source) == nil)
        let border = try layout.itemBorderStart()
        let rects = BrowserTextGeometry.rects(in: list, range: NSRange(location: 0, length: layout.source.length))
        #expect(!rects.isEmpty)
        #expect(!rects.contains { $0.minX < border - 0.01 && $0.maxY > marker.rect.rawValue.minY && $0.minY < marker.rect.rawValue.maxY })
    }

    // MARK: - Vertical writing

    /// The list indent is the UA's `padding-inline-start`, on the top edge in
    /// vertical-rl as in WebKit. Measured on a 390 × 776 page; these are wide
    /// enough for every case to stay on one page, so physical columns compare
    /// directly.
    private static func verticalLayout(_ body: String, css: String = "") async throws -> Layout {
        try await layout(body, css: css, width: 700, height: 500) { $0.writingMode = .verticalRTL }
    }

    /// The physical vertical-rl reading of `Layout`: a list item's border box
    /// starts at its top edge, 40 below the `參考` column's top.
    private static func itemTop(_ layout: Layout) throws -> CGFloat {
        try layout.text("參考").rect.rawValue.minY + 40
    }

    /// S001d 14-decimal, 14-cjk, 14-two-digit: a vertical counter ends at its
    /// item's top edge, on its first column's central line. Digits and ". " lie
    /// on their side, 「一」 stands and 「、」 takes its vertical form, as they do
    /// on the line.
    @Test func verticalCountersEndAtTheItemsTopOnTheColumnsCentralLine() async throws {
        let items = (1...10).map { "<li>第\($0)項。</li>" }.joined()
        let layout = try await Self.verticalLayout("<p>參考</p><ol>\(items)</ol><ol class=cjk><li>其一。</li></ol>",
                                                   css: ".cjk { list-style-type: cjk-ideographic }")
        let top = try Self.itemTop(layout)
        #expect(layout.markers.map(\.renderedTextOverride) == (1...10).map { "\($0). " } + ["一、"])
        for (marker, item) in zip(layout.markers, (1...10).map { "第\($0)項" } + ["其一"]) {
            let first = try layout.text(item)
            #expect(marker.writingMode == .verticalRTL, "\(item)")
            #expect(abs(marker.rect.rawValue.maxY - top) < 0.01, "\(item)")
            #expect(abs(marker.baselineY - first.baselineY) < 0.01, "\(item)")
            #expect(abs(marker.rect.rawValue.minX - first.rect.rawValue.minX) < 0.01
                    && abs(marker.rect.rawValue.width - first.rect.rawValue.width) < 0.01,
                    "\(item): the marker is on its line's column")
            #expect(marker.sourceRange == NSRange(location: first.sourceRange.location, length: 0), "\(item)")
            let line = try #require(marker.ctLine)
            let runs = try #require(CTLineGetGlyphRuns(line) as? [CTRun])
            let upright = runs.map { (CTRunGetAttributes($0) as NSDictionary)[kCTVerticalFormsAttributeName as String] as? Bool ?? false }
            #expect(upright.allSatisfy { $0 == (item == "其一") }, "\(item): \(upright)")
        }
    }

    /// S001d 14-li-lh1, 14-li-p-lh1, 14-li-large-lh1, 14-footnote-*, 14-decimal,
    /// 14-li-large, 14-li-large-tall: across a vertical line a marker takes the
    /// line's own font's rounded content area about the central line (25 at
    /// 17px, 37 at 25.5px, 23 at 15.3px), with no leading; the horizontal rule
    /// would widen none of the first five and widen 14-li-large.
    @Test func aVerticalMarkerWidensItsColumnToTheLinesContentArea() async throws {
        let cases: [(list: String, css: String, column: CGFloat, plain: CGFloat)] = [
            ("<li>項目。</li>", "", 25.5, 25.5),
            ("<li>項目。</li>", "li { line-height: 1 }", 25, 17),
            ("<li><p>項目。</p></li>", "li p { line-height: 1 }", 25, 17),
            ("<li>項目。</li>", "li { font-size: 25.5px; line-height: 1 }", 37, 25.5),
            ("<li>項目。</li>", "li { font-size: 15.3px; line-height: 1 }", 23, 15.3),
            ("<li>項目。</li>", "li { font-size: 15.3px; line-height: 1.2 }", 23, 18.36),
            ("<li><p>項目。</p></li>", "li { font-size: 25.5px } li p { font-size: 17px }", 25.5, 25.5),
            ("<li><p>項目。</p></li>", "li { font-size: 25.5px } li p { font-size: 17px; line-height: 2.5 }", 42.5, 42.5),
        ]
        for (list, css, column, plain) in cases {
            for none in [false, true] {
                let style = none ? " style=\"list-style-type: none\"" : ""
                let layout = try await Self.verticalLayout("<p>參考</p><ol\(style)>\(list)</ol>", css: css)
                let text = try layout.text("項目")
                let width = text.rect.rawValue.width
                #expect(abs(width - (none ? plain : column)) < 0.01, "\(css) none: \(none) → \(width)")
                // Widened evenly: the text stays on the column's central line.
                #expect(abs(text.rect.rawValue.midX - text.baselineY) < 0.01, "\(css) none: \(none)")
            }
        }
    }

    /// S001d 14-span-first-large, 14-span-later-large, 14-span-first-small:
    /// that room is the line's root inline box's (the item's 17px: 25), not its
    /// first box's nor its largest's. A 34px span leaves the column at 34, not
    /// 49; a 10.2px span at the start still widens it to 25, not 17. The marker
    /// stays on the column's central line.
    @Test func aVerticalMarkersRoomIsTheRootInlineBoxs() async throws {
        let css = "li { line-height: 1 } .big { font-size: 2em } .small { font-size: 0.6em }"
        let cases: [(item: String, probe: String, column: CGFloat)] = [
            ("<span class=big>大</span>字在行首。", "字在行首", 34),
            ("行首是正文，<span class=big>大</span>字在後面。", "行首是正文", 34),
            ("<span class=small>小</span>字在行首。", "字在行首", 25),
        ]
        for (item, probe, column) in cases {
            let layout = try await Self.verticalLayout("<p>參考</p><ol><li>\(item)</li></ol>", css: css)
            let text = try layout.text(probe)
            #expect(abs(text.rect.rawValue.width - column) < 0.01, "\(item): \(text.rect.rawValue.width)")
            let marker = try #require(layout.markers.first)
            #expect(abs(marker.baselineY - text.rect.rawValue.midX) < 0.01, "\(item)")
        }
    }

    /// S001d 14-empty, 14-empty-lh1, 14-empty-ul: an empty vertical item holds
    /// a column of its line-height or its marker's content area, whichever is
    /// wider (25.5; 25 at `line-height: 1`, not 17), its marker on the column's
    /// central line; with no marker it has no width.
    @Test func anEmptyVerticalItemHoldsTheColumnItsMarkerSitsOn() async throws {
        let cases: [(list: String, css: String, column: CGFloat)] = [
            ("ol", "", 25.5), ("ol", "li { line-height: 1 }", 25), ("ul", "", 25.5),
        ]
        for (list, css, column) in cases {
            let drawn = try await Self.verticalLayout("<p>參考</p><\(list)><li></li></\(list)><p>後文</p>", css: css)
            let none = try await Self.verticalLayout(
                "<p>參考</p><\(list) style=\"list-style-type: none\"><li></li></\(list)><p>後文</p>", css: css)
            // Columns run right to left: the item moves what follows it left.
            let after = try drawn.text("後文").rect.rawValue
            #expect(abs(try none.text("後文").rect.rawValue.maxX - after.maxX - column) < 0.01, "\(list) \(css)")
            let centre = after.maxX + column / 2
            let top = try Self.itemTop(drawn)
            if list == "ol" {
                let marker = try #require(drawn.markers.first)
                #expect(abs(marker.baselineY - centre) < 0.01, "\(css)")
                #expect(abs(marker.rect.rawValue.maxY - top) < 0.01, "\(css)")
                #expect(abs(marker.rect.rawValue.width - column) < 0.01, "\(css)")
            } else {
                // 17px: a content area of 25 about the central line, the
                // bullet's right edge A / 2 = 9.5 into it, 19 out from the top.
                let bullet = try #require(drawn.bullets.first).rect.rawValue
                #expect(abs(bullet.maxX - (centre + 12.5 - 9.5)) < 0.01)
                #expect(abs(bullet.minY - (top - 19)) < 0.01)
            }
        }
    }

    /// S001d 14-li-large, 14-li-large-tall, 14-cjk-large, 14-disc-large: a
    /// 25.5px marker on a 17px paragraph's column starts its content area
    /// (37 wide) where the 25 the line gives it starts, on the right, so its
    /// central line is 6 to the left of the column's; a bullet's right edge is
    /// A / 2 into that area. 14-disc: the same rule at the column's own size.
    @Test func aVerticalMarkerStartsItsContentAreaWhereItsRoomStarts() async throws {
        let large = "li { font-size: 25.5px } li p { font-size: 17px } .tall p { line-height: 2.5 }"
            + " .cjk { list-style-type: cjk-ideographic }"
        let layout = try await Self.verticalLayout(
            "<p>參考</p><ol><li><p>大號。</p></li></ol><ol class=tall><li><p>高行。</p></li></ol>"
                + "<ol class=cjk><li><p>中文。</p></li></ol><ul><li><p>圓點。</p></li></ul>"
                + "<ul style=\"font-size: 17px\"><li style=\"font-size: 17px\">小圓點。</li></ul>",
            css: large)
        let top = try Self.itemTop(layout)
        try #require(layout.markers.count == 3)
        for (marker, item) in zip(layout.markers, ["大號", "高行", "中文"]) {
            let text = try layout.text(item)
            #expect(abs(text.baselineY - marker.baselineY - 6) < 0.01, "\(item)")
            #expect(abs(marker.rect.rawValue.maxY - top) < 0.01, "\(item)")
        }
        try #require(layout.bullets.count == 2)
        for (bullet, item, size) in [(layout.bullets[0], "圓點", 25.5), (layout.bullets[1], "小圓點", 17)] as [(FillFragment, String, CGFloat)] {
            let text = try layout.text(item)
            let font = try #require(UIFont(name: "PingFangSC-Regular", size: size))
            let ascent = ceil(font.ascender)
            let side = (ascent * 2 / 3 + 1) / 2
            // The room's right edge: the line's 25 about its central line.
            let contentRight = text.baselineY + 25 / 2
            let rect = bullet.rect.rawValue
            #expect(abs(rect.maxX - (contentRight - ascent / 2)) < 0.01, "\(item)")
            #expect(abs(rect.minY - (top - (floor(ascent * 2 / 3) + 7))) < 0.01, "\(item)")
            #expect(abs(rect.width - side) < 0.01 && abs(rect.height - side) < 0.01, "\(item)")
            #expect(bullet.writingMode == .verticalRTL)
        }
        // 14-disc-large: 25 out from the top edge; 14-disc: 19.
        #expect(abs(layout.bullets[0].rect.rawValue.minY - (top - 25)) < 0.01)
        #expect(abs(layout.bullets[1].rect.rawValue.minY - (top - 19)) < 0.01)
    }

    /// Pixels: the drawer inks a vertical counter in its place, on its column
    /// and short of the item's top edge by about what WebKit leaves (S001d:
    /// decimal 6.67, cjk 6.33, disc 12.00, at 1/3pt), and fills a vertical disc.
    /// S001d is zh-Hant, whose 「、」 is centred in its cell; another language's
    /// sits at the cell's start and leaves 10.33.
    @Test func verticalMarkersInkTheirPlaces() async throws {
        let layout = try await Self.verticalLayout(
            "<p>參考</p><ol><li>第一項。</li></ol><ol class=cjk lang=\"zh-Hant\"><li>其一。</li></ol><ul><li>圓點。</li></ul>",
            css: ".cjk { list-style-type: cjk-ideographic }")
        try #require(layout.pages.count == 1)
        let top = try Self.itemTop(layout)
        let list = DisplayListBuilder.build(for: layout.pages[0], sourceText: layout.source as String)
        let canvas = Canvas(list, size: layout.pages[0].pageRect.rawValue.size)
        try #require(layout.markers.count == 2)
        for (marker, gap) in zip(layout.markers, [6.67, 6.33] as [CGFloat]) {
            let column = marker.rect.rawValue
            let ink = try #require(canvas.inkExtent(in: CGRect(x: column.minX, y: top - 40, width: column.width, height: 40)),
                                   "\(marker.renderedTextOverride ?? "")")
            #expect(abs(top - ink.maxY - gap) <= 0.5, "\(marker.renderedTextOverride ?? ""): \(top - ink.maxY)")
            #expect(ink.minX >= column.minX && ink.maxX <= column.maxX)
        }
        let disc = try #require(layout.bullets.first).rect.rawValue
        #expect(canvas.darkness(at: CGPoint(x: disc.midX, y: disc.midY)) > 0.9)
        let discInk = try #require(canvas.inkExtent(in: disc.insetBy(dx: -2, dy: -2)))
        #expect(abs(top - discInk.maxY - 12) <= 0.5, "\(top - discInk.maxY)")

        // A theme change redraws a counter from its line's runs: in the new
        // color, and still on its side or upright as it was shaped.
        let recolored = Self.displayMarkers(DisplayListBuilder.build(
            for: layout.pages[0], sourceText: layout.source as String, themeTextColor: .white, oldThemeColor: .black))
        try #require(recolored.count == 2)
        for item in recolored {
            #expect(item.color == .white)
            let runs = try #require(CTLineGetGlyphRuns(TextDrawingResources(item).line) as? [CTRun])
            let upright = runs.map { (CTRunGetAttributes($0) as NSDictionary)[kCTVerticalFormsAttributeName as String] as? Bool ?? false }
            #expect(upright.allSatisfy { $0 == (item.renderedTextOverride == "一、") }, "\(item.text): \(upright)")
        }
    }

    /// A vertical marker rides on its line through paging and continuous
    /// (scroll) layout alike, as the horizontal ones do.
    @Test func verticalMarkersArePagedAndScrolledWithTheirLines() async throws {
        let ordered = (1...20).map { "<li>第\($0)項寫得比較長，長到在這個高度上一定會折行。</li>" }.joined()
        let bulleted = (1...20).map { "<li>圓點\($0)寫得比較長，長到在這個高度上一定會折行。</li>" }.joined()
        let body = "<p>參考</p><ol>\(ordered)</ol><ul>\(bulleted)</ul>"
        let paged = try await Self.layout(body, width: 200, height: 300) { $0.writingMode = .verticalRTL }
        #expect(paged.pages.count > 4)
        var strings: [String] = []
        for page in paged.pages {
            let texts = BrowserLayoutTestSupport.allTextFragments([page])
            for marker in texts.filter(Self.isMarker) {
                strings.append(marker.renderedTextOverride ?? "")
                #expect(texts.contains { $0.sourceRange.length > 0 && $0.sourceRange.location == marker.sourceRange.location
                    && abs($0.baselineY - marker.baselineY) < 0.01 }, "\(marker.renderedTextOverride ?? "") on page \(page.index)")
            }
        }
        #expect(strings == (1...20).map { "\($0). " })
        #expect(paged.bullets.count == 20)

        var config = Self.config(width: 200, height: 300)
        config.writingMode = .verticalRTL
        let input = HTMLLayoutDocument(html: Self.html(body), css: [Self.baseCSS], configuration: config)
        #expect(input.capabilities().supported, "vertical lists are admitted")
        let scroll = try input.prepareContinuous().makeDocument()
        let texts = scroll.displayList.items.compactMap { item -> DisplayTextItem? in
            if case .text(let text) = item { return text }
            return nil
        }
        let markers = Self.displayMarkers(scroll.displayList)
        #expect(markers.map(\.renderedTextOverride) == (1...20).map { "\($0). " })
        for marker in markers {
            #expect(marker.writingMode == .verticalRTL)
            #expect(texts.contains { $0.sourceRange.length > 0 && $0.sourceRange.location == marker.sourceRange.location
                && abs($0.baselineY - marker.baselineY) < 0.01 }, "\(marker.renderedTextOverride ?? "")")
        }
        #expect(scroll.displayList.items.filter {
            if case .fill(let fill) = $0 { return fill.followsTextColor }
            return false
        }.count == 20)
    }

    /// The App lays a zh-Hant book out with its CJK typography (`.traditional`),
    /// which moves punctuation and picks fonts; the markers' ink still ends where
    /// WebKit's does (S001c 01-ol-text, 11-cjk; S001d 14-decimal, 14-cjk), in
    /// both orientations, at the place and width the plain layout gives them.
    @Test(arguments: [ReaderWritingMode.horizontal, .verticalRTL])
    func markersKeepTheirPlaceUnderTheBooksCJKTypography(mode: ReaderWritingMode) async throws {
        let body = "<p>參考</p><ol lang=\"zh-Hant\"><li>第一項。</li></ol><ol class=cjk lang=\"zh-Hant\"><li>其一。</li></ol>"
        let css = ".cjk { list-style-type: cjk-ideographic }"
        func layout(_ style: CJKTypographyStyle?) async throws -> Layout {
            try await Self.layout(body, css: css, width: 700, height: 500) {
                $0.writingMode = mode
                $0.cjkTypographyStyle = style
            }
        }
        let plain = try await layout(nil)
        let styled = try await layout(.traditional)
        try #require(styled.pages.count == 1 && styled.markers.count == 2)
        #expect(styled.markers.map(\.rect.rawValue) == plain.markers.map(\.rect.rawValue))
        #expect(styled.markers.map(\.baselineY) == plain.markers.map(\.baselineY))
        let list = DisplayListBuilder.build(for: styled.pages[0], sourceText: styled.source as String)
        let canvas = Canvas(list, size: styled.pages[0].pageRect.rawValue.size)
        let vertical = mode == .verticalRTL
        let border = vertical ? try Self.itemTop(styled) : try styled.itemBorderStart()
        let gaps: [CGFloat] = vertical ? [6.67, 6.33] : [7.00, 6.33]
        for (marker, gap) in zip(styled.markers, gaps) {
            let line = marker.rect.rawValue
            let region = vertical ? CGRect(x: line.minX, y: border - 40, width: line.width, height: 40)
                                  : CGRect(x: border - 40, y: line.minY, width: 40, height: line.height)
            let ink = try #require(canvas.inkExtent(in: region), "\(marker.renderedTextOverride ?? "")")
            let measured = border - (vertical ? ink.maxY : ink.maxX)
            #expect(abs(measured - gap) <= 0.5, "\(mode) \(marker.renderedTextOverride ?? ""): \(measured)")
        }
    }

    // MARK: - Not drawn yet

    /// Inside markers take room on the line (design §4), which nothing reserves
    /// yet. Admission sends such a chapter to the legacy engine
    /// (`ListMarkerAdmissionTests`); laid out here regardless, none is drawn.
    @Test func insideMarkersAreNotDrawnYet() async throws {
        let inside = try await Self.layout("<p>參考</p><ol><li>第一項。</li></ol><ul><li>圓點。</li></ul>",
                                           css: "ol, ul { list-style-position: inside }")
        #expect(inside.markers.isEmpty && inside.bullets.isEmpty)
    }

    @Test func aCounterStyleWithNoDefinitionDrawsDecimalAndSaysSo() async throws {
        final class Sink { var diagnostics: [CSSFrontendDiagnostic] = [] }
        let sink = Sink()
        let layout = try await Self.layout("<p>參考</p><ol class=x><li>一。</li><li>二。</li></ol>",
                                           css: ".x { list-style-type: hiragana }") {
            $0.onDiagnostic = { sink.diagnostics.append($0) }
        }
        #expect(layout.markers.map(\.renderedTextOverride) == ["1. ", "2. "])
        let reports = sink.diagnostics.filter { $0.property == "list-style-type" }
        #expect(!reports.isEmpty)
        #expect(reports.allSatisfy { $0.message.contains("hiragana") })
    }
}
