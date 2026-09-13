import Testing
import UIKit
import YueduCoreText
import Consumer

@MainActor
struct ConsumerTests {
    @Test func englishAuthorStylesDrawWithStableSourceGeometry() async throws {
        let text = "Extraordinary imagination illuminates extraordinary possibilities."
        let html = "<html lang='en'><body><p id='start'><a href='#start'>\(text)</a></p></body></html>"
        let css = ["body {margin:0;font-family:Georgia;font-size:20px} p {margin:0;line-height:24px;text-indent:12pt;text-align:justify;hyphens:auto} p:first-letter {font-size:200%;color:red}"]
        let config = BrowserLayoutConfig(renderWidth:180,renderHeight:120,rootFontSize:20)
        let doc = HTMLLayoutDocument(html:html,css:css,configuration:config)
        #expect(doc.capabilities().supported)
        let session = try doc.makePageSession(); try await session.finish()
        #expect(session.sourceText == text)
        let flow = try doc.prepareContinuous().makeDocument()
        #expect(flow.sourceText == text)
        let first = try #require(session.completedPages.first)
        let list = DisplayListBuilder.build(for:first,sourceText:session.sourceText)
        let initialRect = try #require(list.selectionRects(for:NSRange(location:0,length:1)).first)
        #expect(initialRect.minX == 16)
        #expect(list.sourceRange(at:CGPoint(x:initialRect.midX,y:initialRect.midY),sourceText:text)?.location == 0)
        #expect(list.items.contains { if case .text(let t) = $0 { return t.linkTarget == "#start" }; return false })
        let bitmap = try #require(CGContext(data:nil,width:180,height:120,bitsPerComponent:8,bytesPerRow:720,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        list.draw(in:bitmap)
        let rendered = try #require(bitmap.makeImage())
        let data = try #require(rendered.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(stride(from:0,to:CFDataGetLength(data),by:4).contains { bytes[$0] > 150 && bytes[$0+1] < 50 && bytes[$0+2] < 50 })
        let reformatted = HTMLLayoutDocument(html:html,css:css,configuration:BrowserLayoutConfig(renderWidth:240,renderHeight:120,rootFontSize:20))
        let changed = try reformatted.prepareContinuous().makeDocument()
        #expect(changed.sourceText == flow.sourceText)
        #expect(changed.contentSize != flow.contentSize)
    }

    @Test func compiledExampleDrawsAndReturnsLinks() async throws {
        let result = try await renderExample()
        #expect(result.text == "Hello 世界 🌕")
        #expect(result.image.width == 320)
        #expect(result.image.height == 480)
        #expect(result.links.count > 0)
        #expect(result.links.allSatisfy { $0.href == "#intro" })
        let bytes = try #require(result.image.dataProvider?.data)
        let pixels = try #require(CFDataGetBytePtr(bytes))
        // The authored border must be at the top of the exported image.
        func bluePixelCount(rows: Range<Int>) -> Int {
            rows.reduce(0) { total, y in
                total + (0..<result.image.width).filter { x in
                    let offset = y * result.image.bytesPerRow + x * 4
                    return pixels[offset] < 40 && pixels[offset + 1] < 40
                        && pixels[offset + 2] > 200 && pixels[offset + 3] > 200
                }.count
            }
        }
        #expect(bluePixelCount(rows: 0..<60) > 300)
        #expect(bluePixelCount(rows: 420..<480) == 0)
    }

    @Test func paginationContinuousResourcesAndUTF16Geometry() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 15), format: format).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 20, height: 15))
        }
        let text = String(repeating: "原生排版世界 🌕 abc ", count: 50)
        let html = "<html><body><p id='start'><a href='#start'>\(text)</a></p><img src='art.png'/></body></html>"
        let css = ["body { margin:0; } p { margin:0; border:1px solid blue; background:#eeeeee; } img { width:20px; height:15px; }"]
        let config = BrowserLayoutConfig(renderWidth: 220, renderHeight: 140, rootFontSize: 17)
        let doc = HTMLLayoutDocument(html: html, css: css, baseURL: URL(string: "https://fixture.invalid/book/"),
                                    configuration: config, images: ["https://fixture.invalid/book/art.png": image])
        let session = try doc.makePageSession(generation: 7)
        let first = try #require(try await session.layoutNextPage())
        #expect(!session.isFinished)
        #expect(session.completedPages.count == 1)
        try await session.finish()
        #expect(session.completedPages.count > 2)
        #expect(session.generation == 7)
        #expect(session.anchorOffsets["start"] == 0)
        let ranges = BrowserPageGeometry.buildPageRanges(session.completedPages, sourceText: session.sourceText)
        #expect(ranges.first?.location == 0)
        #expect(ranges.filter { $0.length > 0 }.last.map(NSMaxRange) == (session.sourceText as NSString).length - 1)
        // The collapsed final space stays in sourceText but is trimmed from the shaped last line.
        #expect((session.sourceText as NSString).substring(from: (session.sourceText as NSString).length - 1) == " ")
        let list = DisplayListBuilder.build(for: first, sourceText: session.sourceText)
        let rect = try #require(list.selectionRects(for: NSRange(location: 0, length: 2)).first)
        #expect(rect.width > 0)
        let hit = try #require(list.sourceRange(at: CGPoint(x: rect.midX, y: rect.midY), sourceText: session.sourceText))
        #expect(hit.location < 2)
        let continuous = try doc.prepareContinuous().makeDocument()
        #expect(continuous.sourceText == session.sourceText)
        #expect(continuous.contentHeight > 140)
        #expect(continuous.contentSize == CGSize(width: 220, height: continuous.contentHeight))
        #expect(continuous.displayList.items.contains { if case .image(let item) = $0 { return item.image != nil && item.rect.width == 20 }; return false })
        let exampleFlow = try makeContinuousExample(image: image)
        #expect(exampleFlow.sourceText == "Hello 世界")
        #expect(exampleFlow.contentSize.width == 320)
        #expect(exampleFlow.displayList.items.contains {
            if case .image(let item) = $0 { return item.rect.width == 120 && item.image != nil }
            return false
        })
        let viewportBitmap = try #require(CGContext(data: nil, width: 320, height: 480,
            bitsPerComponent: 8, bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        viewportBitmap.translateBy(x: 0, y: 480)
        viewportBitmap.scaleBy(x: 1, y: -1)
        drawFirstViewport(of: exampleFlow, in: viewportBitmap)
        #expect(viewportBitmap.makeImage() != nil)
        let bitmap = try #require(CGContext(data: nil, width: 220,
            height: Int(ceil(continuous.contentHeight)), bitsPerComponent: 8, bytesPerRow: 220 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        continuous.displayList.draw(in: bitmap)
        let painted = try #require(bitmap.makeImage())
        let data = try #require(painted.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let pixelOffsets = stride(from: 0, to: CFDataGetLength(data), by: 4)
        // The bitmap must contain the supplied red image, authored blue border and gray background.
        #expect(pixelOffsets.contains { bytes[$0] > 200 && bytes[$0 + 1] < 40 && bytes[$0 + 2] < 40 && bytes[$0 + 3] > 200 })
        #expect(pixelOffsets.contains { bytes[$0] < 40 && bytes[$0 + 1] < 40 && bytes[$0 + 2] > 200 && bytes[$0 + 3] > 200 })
        #expect(pixelOffsets.contains { bytes[$0] == 238 && bytes[$0 + 1] == 238 && bytes[$0 + 2] == 238 && bytes[$0 + 3] == 255 })
        let largeFont = HTMLLayoutDocument(html: html, css: css,
            configuration: BrowserLayoutConfig(renderWidth: 140, renderHeight: 140, rootFontSize: 25), images: ["art.png": image])
        let reflow = try largeFont.makePageSession(); try await reflow.finish()
        #expect(reflow.sourceText == session.sourceText)
        #expect(reflow.completedPages.count > session.completedPages.count)
    }

    @Test func missingImageReportsItsResource() throws {
        do {
            _ = try HTMLLayoutDocument(html: "<p>text</p><img src='missing.png'/>").makePageSession()
            Issue.record("Missing image silently accepted")
        } catch HTMLLayoutError.resourceFailure(let source) { #expect(source == "missing.png") }
    }

    @Test func unsupportedIsDistinctFromEmptySuccess() throws {
        let doc = HTMLLayoutDocument(html: "<table><tr><td>Unsupported</td></tr></table>")
        do { _ = try doc.makePageSession(); Issue.record("Unsupported table accepted") }
        catch HTMLLayoutError.unsupported(let reasons) { #expect(reasons.contains(.table)) }
    }
    @Test func cancellationAndResourceFailuresAreObservable() async throws {
        var document: HTMLLayoutDocument? = HTMLLayoutDocument(html: "<p>owned document</p>")
        var session: BrowserLayoutSession? = try document?.makePageSession(generation: 8)
        weak var weakSession = session
        session?.cancel()
        do { _ = try await session?.layoutNextPage(); Issue.record("Cancelled session emitted a page") }
        catch HTMLLayoutError.cancelled { }
        session = nil; document = nil
        #expect(weakSession == nil)
        let input = CSSFrontendInput(html: "<p>text</p>", stylesheets: [
            AuthorStylesheet(source: .linked(href: "missing.css"), text: "", sourceOrder: 0,
                currentCompatibilityOrder: 0, currentCompatibilityOnly: false,
                media: nil, isAlternate: false, loadFailed: true)
        ])
        do {
            _ = try HTMLLayoutDocument(input: input, configuration: .init()).makePageSession()
            Issue.record("Missing stylesheet became an empty success")
        } catch HTMLLayoutError.resourceFailure(let source) { #expect(source == "missing.css") }
    }
}

extension ConsumerTests {
    @Test func verticalPublicAPIAndRubyGeometry() async throws {
        let result = try await makeVerticalExample()
        #expect(result.text == "山路を登りながら考えた。かなカナ ABC 123 か\u{3099}𠮷🌕")
        let first = try #require(result.pages.first)
        #expect(first.pageRect.rawValue.size == CGSize(width: 224, height: 344))
        let list = DisplayListBuilder.build(for: first, sourceText: result.text)
        let annotation = try #require(list.items.compactMap { item -> DisplayTextItem? in
            if case .text(let t) = item, t.text == "やまみち" { return t }; return nil
        }.first)
        #expect(annotation.writingMode == .verticalRTL)
        #expect(annotation.font.pointSize == 12)
        #expect(annotation.sourceRange == NSRange(location: 0, length: 2))
        #expect(list.sourceRange(at: CGPoint(x: annotation.rect.rawValue.midX, y: annotation.rect.rawValue.midY), sourceText: result.text) == annotation.sourceRange)
        let baseRects = list.selectionRects(for: NSRange(location: 0, length: 1))
        #expect(baseRects.contains { $0.maxX <= annotation.rect.minX + 0.01 })
        #expect(BrowserPageGeometry.rects(pages: result.pages, sourceText: result.text,
            range: NSRange(location: 0, length: 1)).first?.rects == baseRects)
        #expect(result.flow.contentHeight == 344)
        #expect(result.flow.documentPoint(forCharOffset: 0) != nil)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let bitmap = UIGraphicsImageRenderer(size: first.pageRect.rawValue.size, format: format).image {
            UIColor.white.setFill(); $0.fill(first.pageRect.rawValue); list.draw(in: $0.cgContext)
        }
        let cg = try #require(bitmap.cgImage)
        let data = try #require(cg.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(stride(from: 0, to: CFDataGetLength(data), by: 4).filter {
            bytes[$0] < 100 && bytes[$0 + 1] < 100 && bytes[$0 + 2] < 100
        }.count > 100)
        let vertical = BrowserLayoutConfig(writingMode: .verticalRTL)
        for html in ["<p style='float:right;width:30px'>浮動</p>",
                     "<p style='writing-mode:vertical-lr'>未支援</p>",
                     "<p style='text-combine-upright:all'>12</p>"] {
            do { _ = try HTMLLayoutDocument(html: html, configuration: vertical).makePageSession(); Issue.record("Unsupported vertical subset accepted") }
            catch HTMLLayoutError.unsupported(let reasons) { #expect(reasons.contains(.verticalWritingMode)) }
        }
    }
}
