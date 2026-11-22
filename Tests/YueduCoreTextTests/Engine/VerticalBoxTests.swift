import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// Floats, inline-blocks and sizes in vertical text. Layout runs on the
/// canonical axes, so they are the ones horizontal text has, turned: these
/// used to send the chapter to the host's fallback. Positions were measured
/// against WKWebView on the app's fixture S020; here the relations are held.
///
/// `webKitReference` pages are 776 tall and 3000 wide in vertical text; type
/// is 17px, a Han character a 17px square.
struct VerticalBoxTests {

    private static func picture(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func layout(_ body: String, css: String) async throws -> (pages: [PageFragments], doc: BrowserLayoutDocument) {
        try await BrowserLayoutTestSupport.webKitReference(
            body, css: "body { margin: 0 } p { margin: 0; line-height: 17px } " + css, vertical: true,
            imageLoader: { _ in Self.picture(240, 160) })
    }

    private func scan(_ body: String, css: String) -> BrowserLayoutCapabilityResult {
        BrowserLayoutCapabilityScanner.scan(
            html: "<html><head></head><body>\(body)</body></html>",
            cssTexts: [css], writingMode: .verticalRTL)
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }

    @Test func theyAreAdmitted() {
        let css = ".f { float: left; height: 50%; } .ib { display: inline-block; height: 4em; } .m { min-width: 10em; max-height: 12em; }"
        let result = scan("<div class=\"m\"><img class=\"f\" src=\"a.png\"/><p>前<span class=\"ib\">中</span>後</p></div>", css: css)
        #expect(result.supported, "\(result.unsupportedFeatures)")
        // Across the page is the block axis: a limit or a percentage of it is still not resolved.
        #expect(scan("<div class=\"v\">字</div>", css: ".v { max-width: 10em; }").unsupportedFeatures == [.verticalWritingMode])
        #expect(scan("<div class=\"v\">字</div>", css: ".v { width: 50%; }").unsupportedFeatures == [.verticalWritingMode])
    }

    /// `float: left` is the top of the column; text runs below it, beside it across the page.
    @Test func aPictureFloatsToTheTopOfTheColumn() async throws {
        let text = String(repeating: "字", count: 60)
        let found = try await layout("<div><img class=\"f\" src=\"a.png\"/><p>\(text)</p></div><p class=\"c\">後</p>",
                                     css: ".f { float: left; height: 50%; margin-bottom: 17px; } .c { clear: both; }")
        let image = try #require(BrowserLayoutTestSupport.allImageFragments(found.pages).first).rect.rawValue
        // Half the column's length, its width in proportion: 388 down, 582 across.
        #expect(close(image.minY, 0) && close(image.height, 388) && close(image.width, 582), "\(image)")
        #expect(close(image.maxX, 3000))
        let texts = BrowserLayoutTestSupport.allTextFragments(found.pages).map(\.rect.rawValue)
        let beside = texts.dropLast()
        #expect(!beside.isEmpty && beside.allSatisfy { close($0.minY, 388 + 17) && $0.minX >= image.minX - 0.5 }, "\(texts)")
        // Cleared, what follows starts past the picture.
        #expect(try #require(texts.last).maxX <= image.minX + 0.5)
    }

    @Test func aFloatedBlockToTheRightIsTheBottomOfTheColumn() async throws {
        let found = try await layout("<div><div class=\"f\">浮</div><p>字字字</p></div>",
                                     css: ".f { float: right; height: 170px; }")
        let texts = BrowserLayoutTestSupport.allTextFragments(found.pages).map(\.rect.rawValue)
        #expect(texts.count == 2)
        #expect(close(texts[0].minY, 776 - 170), "the float: \(texts)")
        #expect(close(texts[1].minY, 0) && close(texts[1].maxX, texts[0].maxX), "the text beside it: \(texts)")
    }

    @Test func anInlineBlockSitsInTheColumn() async throws {
        let found = try await layout("<p>前<span class=\"ib\">中文</span>後</p><p>次</p>",
                                     css: ".ib { display: inline-block; height: 68px; }")
        let texts = BrowserLayoutTestSupport.allTextFragments(found.pages).map(\.rect.rawValue)
        #expect(texts.count == 4)
        // 前 at the top, the box's 68 after it, 後 after the box, all in one column.
        #expect(close(texts[0].minY, 0) && close(texts[1].minY, 17) && close(texts[2].minY, 17 + 68), "\(texts)")
        #expect(close(texts[0].midX, texts[2].midX))
        #expect(texts[3].maxX <= texts[0].minX + 0.5, "the next paragraph is the next column")
    }

    @Test func aPictureFillsAnInlineBlockOfItsOwnLength() async throws {
        let found = try await layout("<p>前<span class=\"ib\"><img src=\"a.png\"/></span>後</p>",
                                     css: ".ib { display: inline-block; height: 68px; } .ib img { height: 100%; }")
        let image = try #require(BrowserLayoutTestSupport.allImageFragments(found.pages).first).rect.rawValue
        #expect(close(image.height, 68) && close(image.width, 102) && close(image.minY, 17), "\(image)")
    }

    @Test func sizesLimitBothAxes() async throws {
        // `min-width` is the least a block takes across the page; `max-height` the longest its columns run.
        let found = try await layout("<div class=\"m\"><p>字</p></div><p>後</p>", css: ".m { min-width: 170px; }")
        let texts = BrowserLayoutTestSupport.allTextFragments(found.pages).map(\.rect.rawValue)
        #expect(close(texts[1].maxX, 3000 - 170), "\(texts)")
        let capped = try await layout("<div class=\"m\"><p>\(String(repeating: "字", count: 25))</p></div>", css: ".m { max-height: 170px; }")
        let columns = BrowserLayoutTestSupport.allTextFragments(capped.pages).map(\.rect.rawValue)
        #expect(columns.count == 3 && columns.allSatisfy { $0.maxY <= 170.5 }, "\(columns)")
    }

    /// Paged: columns fill a page from the right and the float's text stays on its pages.
    @Test func aFloatAndItsTextPaginate() async throws {
        let text = String(repeating: "字", count: 400)
        let html = "<html><body><div><div class=\"f\">浮動</div><p>\(text)</p></div></body></html>"
        let css = "body { margin: 0 } p { margin: 0; line-height: 20px; font-size: 20px } .f { float: left; height: 100px; font-size: 20px; line-height: 20px }"
        var layoutConfig = BrowserLayoutConfig(renderWidth: 200, renderHeight: 400, rootFontSize: 20,
                                               fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        layoutConfig.writingMode = .verticalRTL
        let doc = BrowserLayoutDocument(html: html, cssTexts: [css], config: layoutConfig, imageLoader: { _ in nil })
        let pages = try await doc.renderPages(containerSize: CGSize(width: 200, height: 400))
        #expect(pages.count > 1)
        var characters = 0
        for page in pages {
            let rects = BrowserLayoutTestSupport.allTextFragments([page])
            characters += rects.reduce(0) { $0 + $1.sourceRange.length }
            #expect(rects.allSatisfy { $0.rect.rawValue.minX >= -0.5 && $0.rect.rawValue.maxX <= 200.5
                && $0.rect.rawValue.minY >= -0.5 && $0.rect.rawValue.maxY <= 400.5 }, "page \(page.index)")
        }
        #expect(characters == 402)
    }
}

/// The `<html>` element's background is the page's (CSS Backgrounds §2.11.2);
/// `<body>`'s takes that place only when `<html>` has none.
struct RootBackgroundTests {
    private func background(_ css: String) async throws -> (page: UIColor?, fills: Int) {
        let layout = try await BrowserLayoutTestSupport.webKitReference("<p>字</p>", css: css)
        var fills = 0
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill: fills += 1
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        layout.pages.forEach { walk($0.fragments) }
        let root = try layout.doc.makeLayout(containerSize: CGSize(width: 366, height: 20_000)).rootBox
        return (BrowserLayoutDocument.bodyBackground(rootBox: root).color, fills)
    }

    @Test func theRootElementsBackgroundIsThePages() async throws {
        let plain = try await background("")
        #expect(plain.page == nil)
        let html = try await background("html { background-color: #fff4e7; }")
        // (The page's background is itself a fill on each page.)
        #expect(html.page != nil && html.fills == plain.fills + 1)
        let body = try await background("body { background-color: #fff4e7; }")
        #expect(body.page != nil && body.fills == html.fills)
        // Both: the page is `<html>`'s, and `<body>` paints its own box.
        let both = try await background("html { background-color: #fff4e7; } body { background-color: #ccc; }")
        #expect(both.page != nil && both.fills == html.fills + 1)
        #expect(both.page != (try await background("body { background-color: #ccc; }")).page)
    }
}
