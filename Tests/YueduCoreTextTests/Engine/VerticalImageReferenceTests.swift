import Testing
import UIKit
@testable import YueduCoreText

/// Images in vertical writing against WebKit (WKWebView iOS 26.5, the app's fixture
/// S005a-vertical-image-positions, 2026-11-04). An image stands upright at its own size, its
/// height along the column. An inline one is centred on its column's central line and widens
/// the column to hold it; a block one is as wide as it is, and `text-align` centres it down
/// the column. WebKit on iOS 26.5 sets a plain 1.5 column 25 wide where 27.2 sets 25.5
/// (`RubyPositionReferenceTests`), so these pin where images sit against the text beside them,
/// not absolute positions.
struct VerticalImageReferenceTests {
    private static let sizes: [String: CGSize] = [
        "mark.png": CGSize(width: 17, height: 17), "wide.png": CGSize(width: 40, height: 10),
        "tall.png": CGSize(width: 10, height: 40), "plate-small.png": CGSize(width: 60, height: 60),
        "plate.png": CGSize(width: 240, height: 160), "huge.png": CGSize(width: 60, height: 1000),
    ]

    private static let css = """
        p { margin: 0; }
        div.figure { margin: 1em 0; text-align: center; }
        img.block { display: block; }
        """

    private static let body = """
        <p>起點段落。</p>\
        <p>一二<img src="mark.png"/>三四</p>\
        <p>五六<img src="wide.png"/>七八</p>\
        <p>九十<img src="tall.png"/>百千</p>\
        <p>東西<img src="plate-small.png"/>南北</p>\
        <p>春夏<img src="plate.png" width="48"/>秋冬</p>\
        <p>甲乙丙丁戊己庚辛壬癸<br/>子丑寅<img src="plate-small.png"/>卯辰巳<br/>天地玄黃宇宙洪荒日月</p>\
        <p>基準基準</p>\
        <div class="figure"><img src="plate.png"/></div>\
        <p>圖後基準</p>\
        <img class="block" src="plate-small.png"/>\
        <p>塊後基準</p>\
        <div class="figure"><img src="huge.png"/></div>\
        <p>末尾基準</p>
        """

    /// Each inline image, by the text before it: the size it is drawn at.
    private static let inline: [(before: String, size: CGSize)] = [
        ("一二", CGSize(width: 17, height: 17)), ("五六", CGSize(width: 40, height: 10)),
        ("九十", CGSize(width: 10, height: 40)), ("東西", CGSize(width: 60, height: 60)),
        // `width="48"` is across the column; the height keeps the 240×160 ratio.
        ("春夏", CGSize(width: 48, height: 32)), ("子丑寅", CGSize(width: 60, height: 60)),
    ]

    /// How far each line's central line is left of the one before: half of each column, a
    /// column as wide as its widest box. WebKit 26.5, its 25 columns: 25, 32, 33, 42, 54, 37,
    /// 42, 43, 25, 265, 85 between rounded centres.
    private static let strut: CGFloat = 25.5
    private static let steps: [(text: String, step: CGFloat)] = [
        ("一二", strut), ("五六", strut / 2 + 20), ("九十", 20 + strut / 2), ("東西", strut / 2 + 30),
        ("春夏", 30 + 24), ("甲乙丙", 24 + strut / 2), ("子丑寅", strut / 2 + 30), ("天地玄", 30 + strut / 2),
        ("基準基準", strut), ("圖後基準", strut / 2 + 240 + strut / 2), ("塊後基準", strut / 2 + 60 + strut / 2),
    ]

    private typealias Layout = (pages: [PageFragments], doc: BrowserLayoutDocument)

    private static func layout() async throws -> Layout {
        try await BrowserLayoutTestSupport.webKitReference(body, css: css, vertical: true, imageLoader: { source in
            sizes[source].map { image(size: $0) }
        })
    }

    private static func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func text(_ text: String, in layout: Layout) throws -> TextFragment {
        try #require(BrowserLayoutTestSupport.fragment(text, in: layout), "\(text) not laid out")
    }

    /// The first image after `text`.
    private static func image(after text: String, in layout: Layout) throws -> ImageFragment {
        let source = layout.doc.lastSourceText as NSString
        let found = source.range(of: text)
        try #require(found.location != NSNotFound, "\(text)")
        return try #require(BrowserLayoutTestSupport.allImageFragments(layout.pages)
            .filter { $0.sourceRange.location >= NSMaxRange(found) }
            .min { $0.sourceRange.location < $1.sourceRange.location }, "no image after \(text)")
    }

    @Test func inlineImagesAreUprightAndCentredOnTheirColumn() async throws {
        let layout = try await Self.layout()
        let columnStart = try Self.text("起點", in: layout).rect.rawValue.minY
        for row in Self.inline {
            let before = try Self.text(row.before, in: layout)
            let image = try Self.image(after: row.before, in: layout)
            let rect = image.rect.rawValue
            #expect(abs(rect.width - row.size.width) <= 0.01 && abs(rect.height - row.size.height) <= 0.01,
                    "\(row.before): \(rect.size), WebKit \(row.size)")
            #expect(abs(rect.midX - before.baselineY) <= 0.01,
                    "\(row.before): centre \(rect.midX), the column's \(before.baselineY)")
            // After the text before it, and as long down the column as it is tall.
            let advance = CGFloat((row.before as NSString).length) * 17
            #expect(abs(rect.minY - columnStart - advance) <= 0.01, "\(row.before): starts \(rect.minY - columnStart)")
        }
        // The text after an image goes on from its end.
        let after = try Self.text("七八", in: layout)
        let wide = try Self.image(after: "五六", in: layout)
        #expect(abs(after.rect.rawValue.minY - wide.rect.rawValue.maxY) <= 0.01,
                "\(after.rect.rawValue.minY), the image ends at \(wide.rect.rawValue.maxY)")
    }

    /// The page's right end, for the eye: written to `YUEDU_PROBE_OUT` (passed to the
    /// simulator as `TEST_RUNNER_YUEDU_PROBE_OUT`), or the temporary directory.
    @Test func drawsThePage() async throws {
        let layout = try await Self.layout()
        let page = try #require(layout.pages.first)
        let list = DisplayListBuilder.build(for: page, sourceText: layout.doc.lastSourceText)
        let crop = CGRect(x: page.pageRect.rawValue.width - 820, y: 0, width: 820, height: page.pageRect.rawValue.height)
        let image = UIGraphicsImageRenderer(size: crop.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: crop.size))
            context.cgContext.translateBy(x: -crop.minX, y: 0)
            list.draw(in: context.cgContext)
        }
        let folder = ProcessInfo.processInfo.environment["YUEDU_PROBE_OUT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let url = folder.appendingPathComponent("vertical-images.png")
        try #require(image.pngData()).write(to: url)
        print("VERTICAL_IMAGES \(url.path)")
    }

    @Test func aColumnWidensToItsWidestBox() async throws {
        let layout = try await Self.layout()
        var previous = try Self.text("起點", in: layout).baselineY
        for row in Self.steps {
            let centre = try Self.text(row.text, in: layout).baselineY
            #expect(abs(previous - centre - row.step) <= 0.01, "\(row.text): \(previous - centre), expected \(row.step)")
            previous = centre
        }
    }

    @Test func blockImagesTakeTheirWidthAcrossTheColumns() async throws {
        let layout = try await Self.layout()
        let columnStart = try Self.text("起點", in: layout).rect.rawValue.minY
        let middle = try Self.text("基準基準", in: layout).baselineY

        // In `div.figure`: 1em in from either end of the column, centred down the rest of it.
        let figure = try Self.image(after: "基準基準", in: layout).rect.rawValue
        #expect(figure.size == CGSize(width: 240, height: 160), "\(figure.size)")
        #expect(abs(figure.minY - columnStart - (17 + (760 - 34 - 160) / 2)) <= 0.01, "\(figure.minY - columnStart)")
        #expect(abs(figure.midX - (middle - Self.strut / 2 - 120)) <= 0.01, "\(figure.midX)")

        // `display: block`: at the column's start.
        let afterFigure = try Self.text("圖後基準", in: layout).baselineY
        let block = try Self.image(after: "圖後基準", in: layout).rect.rawValue
        #expect(block.size == CGSize(width: 60, height: 60), "\(block.size)")
        #expect(abs(block.minY - columnStart) <= 0.01, "\(block.minY - columnStart)")
        #expect(abs(block.midX - (afterFigure - Self.strut / 2 - 30)) <= 0.01, "\(block.midX)")
    }

    /// WebKit lets a 1000-long image run past its 726 column. Here it scales to the column,
    /// as an image wider than its line does horizontally.
    @Test func anImageLongerThanItsColumnScalesToIt() async throws {
        let layout = try await Self.layout()
        let columnStart = try Self.text("起點", in: layout).rect.rawValue.minY
        let huge = try Self.image(after: "塊後基準", in: layout).rect.rawValue
        #expect(abs(huge.height - 726) <= 0.01 && abs(huge.width - 60 * 726 / 1000) <= 0.01, "\(huge.size)")
        #expect(abs(huge.minY - columnStart - 17) <= 0.01, "\(huge.minY - columnStart)")
    }

    /// Still outside vertical scope: an image as a ruby's base, a floated one, an inline-block
    /// that is not an image, and other replaced elements.
    @Test(arguments: [
        ("<p><ruby><img src=\"mark.png\"/><rt>よみ</rt></ruby></p>", ""),
        ("<p>甲<img class=\"f\" src=\"mark.png\"/>乙</p>", "img.f { float: right; }"),
        ("<p>甲<span class=\"i\">丙</span>乙</p>", "span.i { display: inline-block; }"),
        ("<p>甲<svg width=\"10\" height=\"10\"></svg>乙</p>", ""),
    ])
    func whatStillFallsBack(html: String, css: String) {
        let features = BrowserLayoutCapabilityScanner.scan(
            html: "<html><head></head><body>\(html)</body></html>", cssTexts: [css], writingMode: .verticalRTL
        ).unsupportedFeatures
        #expect(features.contains(.verticalWritingMode), "\(html): \(features)")
    }

    @Test func imagesInlineAndAsBlocksAreInVerticalScope() {
        let result = BrowserLayoutCapabilityScanner.scan(
            html: "<html><head></head><body>\(Self.body)</body></html>", cssTexts: [Self.css], writingMode: .verticalRTL)
        #expect(result.supported, "\(result.unsupportedFeatures)")
    }
}
