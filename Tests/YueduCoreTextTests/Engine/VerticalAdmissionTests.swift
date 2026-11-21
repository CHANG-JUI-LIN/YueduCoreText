import Testing
import UIKit
@testable import YueduCoreText

/// What a vertical chapter is admitted with. Two rules used to send whole books
/// to the host's fallback engine:
/// - the template most Japanese publishers build on writes `html { writing-mode:
///   horizontal-tb }` and overrides it with `.vrtl` on the same `<html>`; any
///   matched horizontal declaration rejected the chapter, whoever won;
/// - an inline mark sized `width: 1em` was rejected because only px widths were
///   in scope.
struct VerticalAdmissionTests {
    private static let template = """
        html, .hltr { -webkit-writing-mode: horizontal-tb; -epub-writing-mode: horizontal-tb; }
        .vrtl { -webkit-writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }
        .vltr { -webkit-writing-mode: vertical-lr; -epub-writing-mode: vertical-lr; }
        """

    private static func scan(_ html: String, css: String = template) -> BrowserLayoutCapabilityResult {
        BrowserLayoutCapabilityScanner.scan(html: html, cssTexts: [css], writingMode: .verticalRTL)
    }

    @Test func anOverriddenHorizontalDeclarationDoesNotReject() throws {
        let html = "<html class=\"vrtl\"><head></head><body><p>縦書きの本文。</p></body></html>"
        let result = Self.scan(html)
        #expect(result.supported, "\(result.unsupportedFeatures)")
        let document = try BrowserChapterDocument(input: .currentCompatibility(html: html, cssTexts: [Self.template]))
        #expect(document.principalWritingMode == .verticalRTL)
    }

    @Test func aHorizontalBlockInsideAVerticalChapterStillFallsBack() {
        let html = "<html class=\"vrtl\"><head></head><body><p>縦。</p><div class=\"hltr\"><p>横組みの注記。</p></div></body></html>"
        #expect(Self.scan(html).unsupportedFeatures == [.verticalWritingMode])
        let inline = "<html class=\"vrtl\"><head></head><body><p style=\"writing-mode: horizontal-tb\">横。</p></body></html>"
        #expect(Self.scan(inline).unsupportedFeatures == [.verticalWritingMode])
    }

    @Test func aChapterLaidOutVerticallyAgainstItsOwnDeclarationFallsBack() {
        // No `.vrtl`: the document says horizontal and the host asks for vertical.
        let html = "<html><head></head><body><p>本文。</p></body></html>"
        #expect(Self.scan(html).unsupportedFeatures == [.verticalWritingMode])
    }

    @Test func aModeTheEngineDoesNotLayOutFallsBack() {
        let html = "<html class=\"vrtl\"><head></head><body><div class=\"vltr\"><p>左から右へ。</p></div></body></html>"
        #expect(Self.scan(html).unsupportedFeatures == [.verticalWritingMode])
    }

    @Test(arguments: ["1em", "0.5rem", "12pt", "17px"])
    func aLengthWidthIsInScope(_ width: String) {
        let html = "<html><head></head><body><p>甲<img src=\"mark.png\"/>乙</p></body></html>"
        let result = Self.scan(html, css: "img { width: \(width); }")
        #expect(result.supported, "\(width): \(result.unsupportedFeatures)")
    }

    @Test(arguments: ["50%", "10vw"])
    func aWidthThatDependsOnTheContainerStillFallsBack(_ width: String) {
        let html = "<html><head></head><body><p>甲<img src=\"mark.png\"/>乙</p></body></html>"
        #expect(Self.scan(html, css: "img { width: \(width); }").unsupportedFeatures == [.verticalWritingMode])
    }

    /// The cover page of the same template: an svg holding one picture.
    @Test func anSVGThatOnlyWrapsAPictureIsInScope() {
        let cover = """
            <html><head></head><body><div class="main">
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 1442 2048">
            <image width="1442" height="2048" xlink:href="cover.jpg"/></svg></div></body></html>
            """
        let result = Self.scan(cover, css: "html, body { margin: 0; padding: 0; font-size: 0; } svg { margin: 0; padding: 0; }")
        #expect(result.supported, "\(result.unsupportedFeatures)")
        // Real vector content is not a picture.
        let drawing = "<html><head></head><body><svg width=\"10\" height=\"10\"><circle r=\"4\"/></svg></body></html>"
        #expect(Self.scan(drawing, css: "").unsupportedFeatures.contains(.verticalWritingMode))
    }

    @MainActor
    @Test func anEmWideMarkIsDrawnOneEmAcrossItsColumn() async throws {
        var config = BrowserLayoutConfig(renderWidth: 300, renderHeight: 400, rootFontSize: 20,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        config.writingMode = .verticalRTL
        let mark = UIGraphicsImageRenderer(size: CGSize(width: 34, height: 34)).image { _ in }
        let doc = BrowserLayoutDocument(html: "<html><body><p>甲<img src=\"mark.png\"/>乙</p></body></html>",
                                        cssTexts: ["img { width: 1em; }"], config: config,
                                        imageLoader: { $0 == "mark.png" ? mark : nil })
        let pages = try await doc.renderPages(containerSize: CGSize(width: 300, height: 400))
        let list = DisplayListBuilder.build(for: try #require(pages.first), sourceText: doc.lastSourceText)
        let image = try #require(list.items.compactMap { item -> DisplayImageItem? in
            if case .image(let image) = item { return image }
            return nil
        }.first)
        #expect(abs(image.rect.rawValue.width - 20) < 0.01)
        #expect(abs(image.rect.rawValue.height - 20) < 0.01)
    }
}
