import Testing
import UIKit
@testable import YueduCoreText

/// A page background is sized, placed and repeated as CSS Backgrounds 3 §3
/// says, wherever it is painted. Every path used to draw it as `cover`
/// whatever the book declared: a 1024×57 ornament strip declared
/// `background-size: contain; background-repeat: repeat-y` was scaled about
/// fifteen times to fill the page's height.
@MainActor
struct BackgroundImageGeometryTests {

    private static let page = CGSize(width: 390, height: 844)
    private static let strip = CGSize(width: 1024, height: 57)

    private static func image(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// The root background the engine computes for `<body>` under `css`.
    private static func background(_ css: String, body: String = "<body>") throws -> BrowserLayoutDocument.RootBackground {
        let config = BrowserLayoutConfig(
            renderWidth: page.width, renderHeight: page.height, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        let doc = BrowserLayoutDocument(html: "<html>\(body)<p>text</p></body></html>", cssTexts: [css],
                                        config: config, imageLoader: { _ in nil })
        return BrowserLayoutDocument.bodyBackground(rootBox: try doc.makeLayout(containerSize: page).rootBox)
    }

    private static func tiling(_ css: String, image: CGSize, body: String = "<body>") throws -> BackgroundTiling {
        try #require(try background(css, body: body).tiling(for: image, canvas: page, rootFontSize: 17))
    }

    // MARK: - Size

    @Test func containFitsTheImageInsideThePage() throws {
        let tiling = try Self.tiling("body { background-image: url(a.png); background-size: contain }", image: Self.strip)
        #expect(tiling.tile.width == 390)
        #expect(abs(tiling.tile.height - 390 * 57 / 1024) < 0.001)
    }

    @Test func coverFillsThePageAndCentresTheOverflow() throws {
        let tiling = try Self.tiling(
            "body { background-image: url(a.png); background-size: cover; background-position: center }",
            image: CGSize(width: 1000, height: 1000))
        #expect(abs(tiling.tile.width - 844) < 0.001 && abs(tiling.tile.height - 844) < 0.001)
        // The overflowing axis is cropped evenly on both sides.
        #expect(abs(tiling.tile.minX - (390 - 844) / 2) < 0.001)
        #expect(abs(tiling.tile.minY) < 0.001)
    }

    @Test func noSizeKeepsTheImagesOwnSize() throws {
        let tiling = try Self.tiling("body { background-image: url(a.png) }", image: CGSize(width: 64, height: 48))
        #expect(tiling.tile == CGRect(x: 0, y: 0, width: 64, height: 48))
        #expect(tiling.repeatsX && tiling.repeatsY)
    }

    @Test func explicitSizesResolveAgainstThePageAndKeepProportions() throws {
        let image = CGSize(width: 200, height: 100)
        #expect(try Self.tiling("body { background-image: url(a.png); background-size: 100% 100% }", image: image).tile.size == Self.page)
        #expect(try Self.tiling("body { background-image: url(a.png); background-size: 100% auto }", image: image).tile.size
                == CGSize(width: 390, height: 195))
        #expect(try Self.tiling("body { background-image: url(a.png); background-size: 170px }", image: image).tile.size
                == CGSize(width: 170, height: 85))
        #expect(try Self.tiling("body { background-image: url(a.png); background-size: auto 2em; font-size: 20px }", image: image).tile.size
                == CGSize(width: 80, height: 40))
    }

    // MARK: - Position

    @Test func oneKeywordCentresTheOtherAxis() throws {
        let css = "body { background-image: url(a.png); background-size: contain; background-repeat: no-repeat; background-position: left }"
        let tiling = try Self.tiling(css, image: Self.strip)
        #expect(tiling.tile.minX == 0)
        #expect(abs(tiling.tile.midY - 422) < 0.001)
    }

    @Test func keywordsNameTheirAxisInEitherOrder() throws {
        let image = CGSize(width: 90, height: 44)
        for position in ["bottom center", "center bottom"] {
            let tile = try Self.tiling("body { background: url(a.png) no-repeat; background-position: \(position) }", image: image).tile
            #expect(tile.midX == 195, "\(position)")
            #expect(tile.maxY == 844, "\(position)")
        }
        let corner = try Self.tiling("body { background: url(a.png) no-repeat; background-position: top right }", image: image).tile
        #expect(corner.maxX == 390)
        #expect(corner.minY == 0)
    }

    @Test func percentagesAndEdgeOffsets() throws {
        let image = CGSize(width: 90, height: 44)
        let percent = try Self.tiling("body { background: url(a.png) no-repeat; background-position: 90% 14% }", image: image).tile
        #expect(abs(percent.minX - 0.9 * 300) < 0.001)
        #expect(abs(percent.minY - 0.14 * 800) < 0.001)
        let offset = try Self.tiling("body { background: url(a.png) no-repeat; background-position: right 10px bottom 20px }", image: image).tile
        #expect(offset.maxX == 380)
        #expect(offset.maxY == 824)
    }

    // MARK: - Repeat

    @Test func repeatYStacksTilesDownThePageOnly() throws {
        let css = "body { background-image: url(a.png); background-repeat: repeat-y; background-position: left; background-size: contain }"
        let tiling = try Self.tiling(css, image: Self.strip)
        #expect(!tiling.repeatsX && tiling.repeatsY)
        let tiles = tiling.tiles()
        let height = 390.0 * 57 / 1024
        // Every tile spans the page's width; together they cover its height.
        #expect(tiles.allSatisfy { $0.minX == 0 && $0.width == 390 })
        #expect(tiles.count == Int((844 / height).rounded(.up)) || tiles.count == Int((844 / height).rounded(.up)) + 1)
        #expect(try #require(tiles.first).minY <= 0)
        #expect(try #require(tiles.last).maxY >= 844)
        for (above, below) in zip(tiles, tiles.dropFirst()) { #expect(abs(below.minY - above.maxY) < 0.001) }
    }

    @Test func tilesAreLimitedToTheRectAskedFor() throws {
        let tiling = BackgroundTiling(tile: CGRect(x: 5, y: 5, width: 10, height: 10), repeatsX: true, repeatsY: true,
                                      clip: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(tiling.tiles().count == 11 * 11)
        let window = tiling.tiles(in: CGRect(x: 20, y: 40, width: 20, height: 10))
        #expect(window.count == 3 * 2)
        #expect(window.allSatisfy { $0.intersects(CGRect(x: 20, y: 40, width: 20, height: 10)) })
        let single = BackgroundTiling(tile: CGRect(x: 5, y: 5, width: 10, height: 10), repeatsX: false, repeatsY: false,
                                      clip: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(single.tiles() == [CGRect(x: 5, y: 5, width: 10, height: 10)])
        #expect(single.tiles(in: CGRect(x: 50, y: 50, width: 10, height: 10)).isEmpty)
    }

    // MARK: - Cascade

    /// `background-size` above `background-image` in the same rule used to be
    /// dropped, because the size had no image to attach to yet.
    @Test func longhandsApplyInAnyOrder() throws {
        let css = """
        body { background-size: cover; background-repeat: no-repeat; background-attachment: fixed;
               background-position: bottom center; background-image: url(a.jpg) }
        """
        let image = try #require(try Self.background(css).image)
        #expect(image.source == "a.jpg")
        #expect(image.size == .cover)
        #expect(!image.repeatsX && !image.repeatsY)
        #expect(image.attachment == .fixed)
        #expect(image.positionX == .percent(0.5))
        #expect(image.positionY == .percent(1))
    }

    @Test func shorthandSetsEveryLonghandAndLaterLonghandsWin() throws {
        let css = "body { background-size: contain; background: #fff url(a.jpg) no-repeat center; background-position: top center; background-size: cover }"
        let image = try #require(try Self.background(css).image)
        #expect(image.size == .cover)
        #expect(!image.repeatsX && !image.repeatsY)
        #expect(image.positionX == .percent(0.5))
        #expect(image.positionY == .percent(0))
        // What the shorthand leaves out returns to its initial value.
        let reset = try #require(try Self.background("body { background-size: contain; background: url(a.jpg) }").image)
        #expect(reset.size == .auto)
        #expect(reset.repeatsX && reset.repeatsY)
        let sized = try #require(try Self.background("body { background: url(a.jpg) center / 50% auto repeat-x fixed }").image)
        #expect(sized.size == .explicit(width: .percent(0.5), height: .auto))
        #expect(sized.repeatsX && !sized.repeatsY)
        #expect(sized.attachment == .fixed)
    }

    @Test func noneRemovesTheImage() throws {
        #expect(try Self.background("body { background-image: url(a.jpg) } body { background-image: none }").image == nil)
        #expect(try Self.background("body { background-image: url(a.jpg) } body { background: none }").image == nil)
    }

    // MARK: - Paint

    @Test func pagedLayoutPaintsTheTilingOnEveryPage() async throws {
        let css = "body { background-image: url(strip.png); background-repeat: repeat-y; background-position: left; background-size: contain }"
        let config = BrowserLayoutConfig(
            renderWidth: Self.page.width, renderHeight: Self.page.height, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        let strip = Self.image(Self.strip)
        let doc = BrowserLayoutDocument(html: "<html><body><p>text</p></body></html>", cssTexts: [css], config: config,
                                        imageLoader: { $0 == "strip.png" ? strip : nil })
        let pages = try await doc.renderPages(containerSize: Self.page)
        let list = DisplayListBuilder.build(for: try #require(pages.first), sourceText: doc.lastSourceText)
        let backgrounds = list.items.compactMap { item -> DisplayImageItem? in
            if case .image(let image) = item, image.isBackgroundPaint { return image }
            return nil
        }
        let item = try #require(backgrounds.first)
        #expect(backgrounds.count == 1)
        let tiling = try #require(item.tiling)
        #expect(tiling.clip == CGRect(origin: .zero, size: Self.page))
        #expect(item.rect.rawValue == tiling.tile)
        #expect(abs(tiling.tile.height - 390 * 57 / 1024) < 0.001)

        // Drawn: ink down the whole page, in strips no taller than a tile.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let drawn = UIGraphicsImageRenderer(size: Self.page, format: format).image { context in
            DisplayListDrawer.draw(DisplayList(items: [.image(item)]), in: context.cgContext)
        }
        let bitmap = try #require(drawn.cgImage)
        let data = try #require(bitmap.dataProvider?.data as Data?)
        func alpha(x: Int, y: Int) -> UInt8 { data[y * bitmap.bytesPerRow + x * 4 + 3] }
        for y in [2, 300, 600, 840] { #expect(alpha(x: 195, y: y) > 0, "no background painted at y=\(y)") }
    }
}
