import Testing
import UIKit
import CoreText
@testable import YueduCoreText

@Suite @MainActor
struct VerticalLayoutTests {

}

extension VerticalLayoutTests {
    @Test func pagedAndContinuousRuby() async throws {
        var config = BrowserLayoutConfig()
        config.writingMode = .verticalRTL
        config.renderWidth = 180; config.renderHeight = 280
        config.rootFontSize = 24
        config.fontFamilies = ["HiraginoSans-W3"]
        let html = "<p id='start'>山路かなカナ、。ーABC123か\u{3099}𠮷" +
            "<a href='#start'><ruby><rb>山<span>路</span></rb><rp>(</rp><rt>やまみち</rt><rp>)</rp></ruby></a>" +
            "<ruby>東<rt>とう</rt>京<rt>きょう</rt></ruby>" + String(repeating: "春の山路を登りながら考えた。", count: 25) + "</p>"
        let document = HTMLLayoutDocument(html: html, css: ["p{margin:0;line-height:1.75;text-indent:1em} rt{font-size:50%;color:red}"], configuration: config)
        #expect(document.capabilities().supported)
        let session = try document.makePageSession()
        try await session.finish()
        #expect(session.completedPages.count > 1)
        #expect(!session.sourceText.contains("やまみち"))
        #expect(session.sourceText.contains("山路東京"))
        #expect(session.anchorOffsets["start"] == 0)
        let first = try #require(session.completedPages.first)
        let list = DisplayListBuilder.build(for: first, sourceText: session.sourceText)
        let items = list.items.compactMap { if case .text(let t) = $0 { return t }; return nil }
        #expect(items.allSatisfy { $0.writingMode == .verticalRTL })
        let annotation = try #require(items.first { $0.text == "やまみち" })
        let base = try #require(items.first { $0.sourceRange.location == annotation.sourceRange.location && $0.renderedTextOverride == nil })
        #expect(annotation.rect.minX >= base.rect.maxX - 0.01)
        #expect(abs(annotation.font.pointSize - 12) < 0.01)
        let selection = list.selectionRects(for: NSRange(location: 0, length: 1))
        let r = try #require(selection.first)
        #expect(list.sourceRange(at: CGPoint(x: r.midX, y: r.midY), sourceText: session.sourceText) == NSRange(location: 0, length: 1))
        let image = UIGraphicsImageRenderer(size: first.pageRect.rawValue.size).image { c in UIColor.white.setFill(); c.fill(first.pageRect.rawValue); list.draw(in: c.cgContext) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vertical-layout.png")
        try image.pngData()!.write(to: url); print("VERTICAL_LAYOUT \(url.path)")
        let continuous = try document.prepareContinuous().makeDocument()
        #expect(continuous.contentWidth > config.renderWidth)
        #expect(continuous.contentHeight == config.renderHeight)
        #expect(continuous.sourceText == session.sourceText)
        let full = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 280)).image {
            UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 240, height: 280))
            continuous.items(in: CGRect(x: continuous.contentWidth - 240, y: 0, width: 240, height: 280)).draw(in: $0.cgContext)
        }
        try full.pngData()!.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("vertical-continuous.png"))
    }
}

extension VerticalLayoutTests {
    @Test func glyphRasterMatchesNativeFrame() async throws {
        let source = "山路かなカナ、。ーABC123か\u{3099}𠮷🌕"
        let font = try #require(UIFont(name: "HiraginoSans-W3", size: 24))
        let size = CGSize(width: 180, height: 600)
        let config = BrowserLayoutConfig(renderWidth: size.width, renderHeight: size.height,
            rootFontSize: 24, fontFamilies: [font.fontName], writingMode: .verticalRTL)
        let doc = HTMLLayoutDocument(html: "<p>\(source)</p>", css: ["body,p{margin:0}"], configuration: config)
        let session = try doc.makePageSession(); try await session.finish()
        #expect(session.completedPages.count == 1)
        let list = DisplayListBuilder.build(for: try #require(session.completedPages.first), sourceText: session.sourceText)
        let item = try #require(list.items.compactMap { if case .text(let t) = $0 { return t }; return nil }.first)
        let native = NSAttributedString(string: source, attributes: [.font:font,
            kCTVerticalFormsAttributeName as NSAttributedString.Key:true])
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(native),
            CFRange(location:0,length:0), CGPath(rect:CGRect(origin:.zero,size:size),transform:nil),
            [kCTFrameProgressionAttributeName:CTFrameProgression.rightToLeft.rawValue] as CFDictionary)
        var origin = CGPoint.zero
        CTFrameGetLineOrigins(frame, CFRange(location:0,length:1), &origin)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func raster(_ draw: (CGContext) -> Void) throws -> Data {
            let image = UIGraphicsImageRenderer(size:size,format:format).image {
                UIColor.white.setFill(); $0.fill(CGRect(origin:.zero,size:size)); draw($0.cgContext)
            }
            return try #require(image.cgImage?.dataProvider?.data) as Data
        }
        let actual = try raster { list.draw(in:$0) }
        let expected = try raster { c in
            c.translateBy(x: item.baselineY - origin.x,
                          y: item.rect.minY - (size.height - origin.y))
            c.translateBy(x:0,y:size.height); c.scaleBy(x:1,y:-1); CTFrameDraw(frame,c)
        }
        #expect(actual == expected, "Native vertical glyph forms, orientation and combining clusters must match CTFrameDraw exactly")
    }

    @Test func sharedRubyStylesRangesAndReflow() async throws {
        for mode: ReaderWritingMode in [.horizontal, .verticalRTL] {
            for factor in [CGFloat(0.5), 0.75] {
                let html = "<p><ruby id='r'><span style='color:blue'>山</span><em>路</em><rt><span style='color:red'>やま</span><span style='color:#008000'>みち</span></rt></ruby><ruby>東<rt>とう</rt>京<rt>きょう</rt></ruby>" + String(repeating:"春の山を登る。",count:30) + "</p>"
                func session(width:CGFloat, height:CGFloat, fontSize:CGFloat) async throws -> BrowserLayoutSession {
                    let doc = HTMLLayoutDocument(html:html, css:["p{margin:0;line-height:1.75}rt{font-size:\(factor * 100)%}"],
                        configuration:BrowserLayoutConfig(renderWidth:width, renderHeight:height,rootFontSize:fontSize,
                            fontFamilies:["HiraginoSans-W3"],writingMode:mode))
                    let session = try doc.makePageSession(); try await session.finish(); return session
                }
                let normal = try await session(width:180,height:240,fontSize:24)
                let large = try await session(width:180,height:240,fontSize:32)
                #expect(large.completedPages.count > normal.completedPages.count)
                #expect(normal.sourceText == large.sourceText)
                #expect(normal.sourceText.hasPrefix("山路東京"))
                let ranges = BrowserPageGeometry.buildPageRanges(normal.completedPages,sourceText:normal.sourceText)
                #expect(ranges.first?.location == 0)
                #expect(ranges.last.map(NSMaxRange) == (normal.sourceText as NSString).length)
                for pair in zip(ranges,ranges.dropFirst()) { #expect(NSMaxRange(pair.0) == pair.1.location) }
                let list = DisplayListBuilder.build(for:try #require(normal.completedPages.first),sourceText:normal.sourceText)
                let annotations = list.items.compactMap { item -> DisplayTextItem? in
                    if case .text(let t) = item, t.renderedTextOverride != nil { return t }; return nil
                }
                #expect(annotations.map(\.text) == ["やま","みち","とう","きょう"])
                #expect(annotations.map(\.sourceRange) == [NSRange(location:0,length:2), NSRange(location:0,length:2), NSRange(location:2,length:1), NSRange(location:3,length:1)])
                for a in annotations { #expect(abs(a.font.pointSize - 24 * factor) < 0.001) }
                #expect(annotations[0].attributedText.attribute(.foregroundColor,at:0,effectiveRange:nil) as? UIColor == UIColor.red)
                #expect(annotations[1].attributedText.attribute(.foregroundColor,at:0,effectiveRange:nil) as? UIColor == UIColor(red:0,green:128/255,blue:0,alpha:1))
                #expect(normal.anchorOffsets["r"] == 0)
                normal.cancel()
                do { _ = try await normal.layoutNextPage(); Issue.record("Cancelled session emitted a page") }
                catch HTMLLayoutError.cancelled { }
            }
        }
    }
}

extension VerticalLayoutTests {
    @Test func physicalInsetsClustersAndContinuousTiles() async throws {
        let source = String(repeating: "山路かなか\u{3099}𠮷🌕ABC。", count: 15)
        let config = BrowserLayoutConfig(renderWidth: 180, renderHeight: 280, rootFontSize: 24,
            fontFamilies:["HiraginoSans-W3"], contentInsets:UIEdgeInsets(top:11,left:13,bottom:17,right:19),
            writingMode:.verticalRTL)
        let doc = HTMLLayoutDocument(html:"<p>\(source)</p>", css:["body{margin:0;padding:6px 8px 10px 12px;border:2px solid blue;max-height:220px}p{margin:0;text-indent:12px;line-height:1.75}"], configuration:config)
        let session = try doc.makePageSession(); try await session.finish()
        let first = try #require(session.completedPages.first)
        let list = DisplayListBuilder.build(for:first,sourceText:session.sourceText)
        let firstRect = try #require(list.selectionRects(for:NSRange(location:0,length:1)).first)
        #expect(abs(firstRect.minY - 31) < 0.01) // inset + border + top padding + indent
        let ns = session.sourceText as NSString
        let range = try #require(BrowserPageGeometry.buildPageRanges([first],sourceText:session.sourceText).first)
        var offset = range.location
        while offset < NSMaxRange(range) {
            let cluster = ns.rangeOfComposedCharacterSequence(at:offset)
            for rect in list.selectionRects(for:cluster) {
                #expect(list.sourceRange(at:CGPoint(x:rect.midX,y:rect.midY),sourceText:session.sourceText) == cluster)
            }
            offset = NSMaxRange(cluster)
        }
        let flow = try doc.prepareContinuous().makeDocument()
        let tile = CGRect(x:flow.contentWidth - 150,y:5,width:140,height:270)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func raster(_ paint:(CGContext)->Void) throws -> Data {
            let bitmap = UIGraphicsImageRenderer(size:tile.size,format:format).image {
                UIColor.white.setFill(); $0.fill(CGRect(origin:.zero,size:tile.size)); paint($0.cgContext)
            }
            return try #require(bitmap.cgImage?.dataProvider?.data) as Data
        }
        let actual = try raster { flow.items(in:tile).draw(in:$0) }
        let expected = try raster { $0.translateBy(x:-tile.minX,y:-tile.minY); flow.displayList.draw(in:$0) }
        #expect(actual == expected)
        let batch = try await BrowserLayoutDocument(html:"<p>\(source)</p>", cssTexts:["body{margin:0;padding:6px 8px 10px 12px;border:2px solid blue;max-height:220px}p{margin:0;text-indent:12px;line-height:1.75}"],config:config).renderPages(containerSize:CGSize(width:212,height:308))
        #expect(BrowserPageGeometry.buildPageRanges(batch,sourceText:session.sourceText) == BrowserPageGeometry.buildPageRanges(session.completedPages,sourceText:session.sourceText))
        #expect(BrowserLayoutTestSupport.allTextFragments(batch).map(\.rect) == BrowserLayoutTestSupport.allTextFragments(session.completedPages).map(\.rect))
    }
}
