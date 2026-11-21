import Testing
import UIKit
@testable import YueduCoreText

/// Continuous layout of vertical text scrolls sideways: a picture is never wider than the
/// screen it scrolls across. ナミヤ雑貨店の奇蹟's 1442×2048 cover was fitted to the column's
/// height alone and came out 550pt across a 440pt screen.
struct ContinuousPictureFitTests {
    private static let cover = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 1442, height: 2048), color: .gray)
    private static let screen = CGSize(width: 440, height: 780)

    private static func pictures(_ body: String, mode: ReaderWritingMode) throws -> [CGSize] {
        var config = BrowserLayoutConfig(
            renderWidth: screen.width, renderHeight: screen.height, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        config.writingMode = mode
        let document = BrowserLayoutDocument(html: "<html><body>\(body)</body></html>", cssTexts: [],
                                             config: config, imageLoader: { _ in cover })
        let pipeline = try document.makeLayout(containerSize: screen)
        func sizes(_ box: BlockBox) -> [CGSize] {
            (box.imageAttachment.map { [$0.usedSize] } ?? [])
                + box.inlineRuns.compactMap { $0.atomic?.usedSize }
                + box.children.flatMap(sizes)
        }
        return sizes(pipeline.rootBox)
    }

    @Test(arguments: [
        #"<div><svg width="100%" height="100%" viewBox="0 0 1442 2048"><image width="1442" height="2048" xlink:href="cover.jpg"/></svg></div>"#,
        #"<p><img src="cover.jpg"/></p>"#,
        #"<img style="display: block" src="cover.jpg"/>"#,
    ])
    func aPortraitPictureFitsTheScreenInVerticalText(body: String) throws {
        let sizes = try Self.pictures(body, mode: .verticalRTL)
        let size = try #require(sizes.first, "no picture laid out")
        // Layout axes: `height` runs across the columns, the way the chapter scrolls.
        #expect(abs(size.height - Self.screen.width) <= 0.01, "\(size)")
        #expect(abs(size.width / size.height - 2048.0 / 1442.0) <= 0.001, "\(size)")
    }

    @Test func horizontalTextKeepsATallPictureWhole() throws {
        // A column as wide as the screen: a picture three screens tall stays that tall and
        // scrolls down.
        let strip = #"<p><img src="cover.jpg" style="width: 400px; height: 2400px"/></p>"#
        let size = try #require(try Self.pictures(strip, mode: .horizontal).first)
        #expect(size == CGSize(width: 400, height: 2400), "\(size)")
    }
}
