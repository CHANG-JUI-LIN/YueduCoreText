import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// WebKit's `hr` and monospace UA rules (html.css, iOS 27.2 runtime; list-marker
/// design step 8d). Measured in Safari on iOS 27.2: a horizontal `hr` is a 2px
/// border box spanning the line, its top and left painted rgb(44,44,44) and its
/// bottom and right rgb(212,212,212); a vertical-rl `hr` is a 2px column, dark
/// on its physical left. `pre` and `code` are Menlo at the inherited size: ten
/// "M"s at 17px are 102.35 wide.
@Suite @MainActor
struct HorizontalRuleAndMonospaceTests {

    private static func style(_ body: String, css: String = "",
                              writingMode: ReaderWritingMode = .horizontal) throws -> ComputedStyle {
        let document = try SwiftSoup.parse("<html><body>\(body)</body></html>")
        var config = BrowserLayoutConfig()
        config.writingMode = writingMode
        let root = ComputedStyleTreeBuilder(rules: CSSParser.parse(css: css), config: config)
            .buildTree(body: try #require(document.body()))
        func find(_ node: ComputedStyleNode) -> ComputedStyleNode? {
            if node.anchorID == "x" { return node }
            for child in node.children {
                if case .element(let element) = child, let found = find(element) { return found }
            }
            return nil
        }
        return try #require(find(root), "no element #x").style
    }

    private static func widths(_ s: ComputedStyle) -> [CGFloat] {
        [s.borderTopWidth, s.borderRightWidth, s.borderBottomWidth, s.borderLeftWidth]
    }

    private static func layout(_ body: String, css: String = "", mode: ReaderWritingMode,
                               size: CGSize = CGSize(width: 300, height: 300)) async throws
        -> (pages: [PageFragments], source: NSString) {
        var config = BrowserLayoutConfig(renderWidth: size.width, renderHeight: size.height, rootFontSize: 17,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        config.writingMode = mode
        let doc = BrowserLayoutDocument(html: "<html><head></head><body>\(body)</body></html>",
                                        cssTexts: ["body { margin: 0; line-height: 1.5 } " + css], config: config)
        let pages = try await doc.renderPages(containerSize: size)
        return (pages, doc.lastSourceText as NSString)
    }

    /// The baselines of the runs holding "甲" and "乙".
    private static func baselines(_ layout: (pages: [PageFragments], source: NSString)) throws -> (CGFloat, CGFloat) {
        let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
        func baseline(_ text: String) throws -> CGFloat {
            let location = layout.source.range(of: text).location
            return try #require(texts.first { NSLocationInRange(location, $0.sourceRange) }, "\(text)").baselineY
        }
        return (try baseline("甲"), try baseline("乙"))
    }

    private static func fills(_ pages: [PageFragments]) -> [DisplayFillItem] {
        DisplayListBuilder.build(for: pages[0]).items.compactMap {
            if case .fill(let fill) = $0 { return fill }
            return nil
        }
    }

    // MARK: - hr

    @Test(arguments: ReaderWritingMode.allCases)
    func anHrIsAOnePixelInsetGrayBorderWithAnAutoWidth(mode: ReaderWritingMode) throws {
        let s = try Self.style("<hr id=\"x\"/>", writingMode: mode)
        #expect(Self.widths(s) == [1, 1, 1, 1])
        #expect([s.borderTopStyle, s.borderRightStyle, s.borderBottomStyle, s.borderLeftStyle]
                == [.inset, .inset, .inset, .inset])
        // `currentColor` on every side, and the colour is html.css's gray.
        #expect([s.borderTopColor, s.borderRightColor, s.borderBottomColor, s.borderLeftColor].allSatisfy { $0 == nil })
        #expect(Self.rgb(try #require(s.color)) == [128, 128, 128, 255])
        // html.css gives hr no width: the line's, not a percentage, which
        // vertical-rl admission turns away.
        #expect(s.width == .auto)
    }

    /// A side styled `none` has a computed width of 0, so the common resets
    /// drop the UA's 1px rather than keep an invisible border taking room.
    @Test func aBorderStyledNoneTakesNoRoom() throws {
        #expect(Self.widths(try Self.style("<hr id=\"x\"/>", css: "hr { border: none }")) == [0, 0, 0, 0])
        #expect(Self.widths(try Self.style("<hr id=\"x\"/>", css: "hr { border: 0 }")) == [0, 0, 0, 0])
        #expect(Self.widths(try Self.style("<hr id=\"x\"/>", css: "hr { border-style: hidden }")) == [0, 0, 0, 0])
        let topOnly = try Self.style("<hr id=\"x\"/>", css: "hr { border: none; border-top: 1px solid #ccc }")
        #expect(Self.widths(topOnly) == [1, 0, 0, 0])
        #expect(topOnly.borderTopStyle == .solid)
        // An author border on any element.
        #expect(Self.widths(try Self.style("<div id=\"x\">甲</div>", css: "div { border: 3px none }")) == [0, 0, 0, 0])
    }

    @Test func aHorizontalHrSpansTheLineTwoPixelsTall() async throws {
        let layout = try await Self.layout("<p>甲。</p><hr/><p>乙。</p>", mode: .horizontal)
        let rule = try #require(Self.fills(layout.pages).first { $0.hasVisibleBorder })
        #expect(rule.rect.rawValue.width == 300)
        #expect(rule.rect.rawValue.height == 2)
        #expect(rule.borderTop.style == .inset && rule.borderBottom.style == .inset)
        // Its 0.5em margins collapse into the paragraphs' 1em: one line box
        // (25.5) and 17 on each side lie between the two baselines and the hr.
        let (first, second) = try Self.baselines(layout)
        let around = (rule.rect.rawValue.minY - first) + (second - rule.rect.rawValue.maxY)
        #expect(abs(around - (25.5 + 17 + 17)) < 0.01, "\(around)")
    }

    @Test func aVerticalChapterWithAnHrIsAdmittedAndTheHrIsAColumn() async throws {
        let body = "<p>甲。</p><hr/><p>乙。</p>"
        #expect(BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body>\(body)</body></html>",
                                                    cssTexts: [""], writingMode: .verticalRTL).unsupportedFeatures.isEmpty)
        let layout = try await Self.layout(body, mode: .verticalRTL)
        let rule = try #require(Self.fills(layout.pages).first { $0.hasVisibleBorder })
        #expect(rule.rect.rawValue.width == 2)
        #expect(rule.rect.rawValue.height == 300)
        // The same collapsed margins as horizontal, right to left.
        let (first, second) = try Self.baselines(layout)
        let around = (first - rule.rect.rawValue.maxX) + (rule.rect.rawValue.minX - second)
        #expect(abs(around - (25.5 + 17 + 17)) < 0.01, "\(around)")
    }

    /// An authored percentage width is still one vertical-rl does not take.
    @Test func aPercentageWidthHrStillSendsAVerticalChapterToTheLegacyEngine() {
        let features = BrowserLayoutCapabilityScanner.scan(
            html: "<html><head></head><body><p>甲。</p><hr/></body></html>",
            cssTexts: ["hr { width: 50% }"], writingMode: .verticalRTL).unsupportedFeatures
        #expect(features == [.verticalWritingMode])
    }

    // MARK: - inset and outset colours

    private static func rgb(_ color: UIColor) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Int(($0 * 255).rounded()) }
    }

    private static func edge(_ white: CGFloat, _ style: BorderStyle) -> BorderEdge {
        BorderEdge(width: 1, color: UIColor(white: white / 255, alpha: 1), style: style)
    }

    @Test func insetDarkensTopAndLeftAndLightensBottomAndRight() {
        let gray = Self.edge(128, .inset)
        #expect(Self.rgb(gray.paintedBevel(topOrLeft: true).color) == [44, 44, 44, 255])
        #expect(Self.rgb(gray.paintedBevel(topOrLeft: false).color) == [212, 212, 212, 255])
        #expect(gray.paintedBevel(topOrLeft: true).style == .solid)
        let outset = Self.edge(128, .outset)
        #expect(Self.rgb(outset.paintedBevel(topOrLeft: true).color) == [212, 212, 212, 255])
        #expect(Self.rgb(outset.paintedBevel(topOrLeft: false).color) == [44, 44, 44, 255])
        // At or below rgb(32,32,32) nothing darkens; black lightens to 84.
        #expect(Self.rgb(Self.edge(0, .inset).paintedBevel(topOrLeft: true).color) == [0, 0, 0, 255])
        #expect(Self.rgb(Self.edge(32, .inset).paintedBevel(topOrLeft: true).color) == [32, 32, 32, 255])
        #expect(Self.rgb(Self.edge(0, .inset).paintedBevel(topOrLeft: false).color) == [84, 84, 84, 255])
        // At or above rgb(235,235,235) nothing lightens; white darkens to 171.
        #expect(Self.rgb(Self.edge(235, .inset).paintedBevel(topOrLeft: false).color) == [235, 235, 235, 255])
        #expect(Self.rgb(Self.edge(255, .inset).paintedBevel(topOrLeft: false).color) == [255, 255, 255, 255])
        #expect(Self.rgb(Self.edge(255, .inset).paintedBevel(topOrLeft: true).color) == [171, 171, 171, 255])
        // Hue is kept: every channel scales by the same factor.
        let red = BorderEdge(width: 1, color: UIColor(red: 1, green: 0, blue: 0, alpha: 0.5), style: .inset)
        #expect(Self.rgb(red.paintedBevel(topOrLeft: true).color) == [171, 0, 0, 128])
        // Other styles are untouched.
        let dotted = Self.edge(128, .dotted)
        #expect(dotted.paintedBevel(topOrLeft: true) == dotted)
    }

    /// The colours go by physical side in both writing modes, as WebKit paints
    /// them.
    @Test(arguments: ReaderWritingMode.allCases)
    func anHrPaintsItsDarkAndLightSidesWhereWebKitDoes(mode: ReaderWritingMode) async throws {
        let size = CGSize(width: 60, height: 60)
        let layout = try await Self.layout("<hr/><p>甲。</p>", css: "hr { margin: 0 }", mode: mode, size: size)
        let canvas = Canvas(DisplayListBuilder.build(for: layout.pages[0]), size: size)
        switch mode {
        case .horizontal:
            // Rows 0–1 and 1–2 from the top.
            #expect(canvas.gray(at: CGPoint(x: 30, y: 0.5)).isNear(44), "\(canvas.gray(at: CGPoint(x: 30, y: 0.5)))")
            #expect(canvas.gray(at: CGPoint(x: 30, y: 1.5)).isNear(212), "\(canvas.gray(at: CGPoint(x: 30, y: 1.5)))")
            #expect(canvas.gray(at: CGPoint(x: 30, y: 2.5)).isNear(255))
        case .verticalRTL:
            // The column at the right edge: dark on its physical left.
            #expect(canvas.gray(at: CGPoint(x: 58.5, y: 30)).isNear(44), "\(canvas.gray(at: CGPoint(x: 58.5, y: 30)))")
            #expect(canvas.gray(at: CGPoint(x: 59.5, y: 30)).isNear(212), "\(canvas.gray(at: CGPoint(x: 59.5, y: 30)))")
            #expect(canvas.gray(at: CGPoint(x: 57.5, y: 30)).isNear(255))
        }
    }

    /// A display list drawn at 3× on white, read back as gray levels.
    private struct Canvas {
        static let scale: CGFloat = 3
        private let pixels: [UInt8]
        private let width: Int

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
            var data = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
            data.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                                        bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            }
            pixels = data
        }

        /// The red channel at the device pixel holding `point`.
        func gray(at point: CGPoint) -> Int {
            let x = Int(floor(point.x * Self.scale)), y = Int(floor(point.y * Self.scale))
            return Int(pixels[(y * width + x) * 4])
        }
    }

    // MARK: - monospace

    @Test func preAndTheCodeElementsAreMonospace() throws {
        for tag in ["pre", "xmp", "plaintext", "listing", "tt", "code", "kbd", "samp"] {
            #expect(try Self.style("<\(tag) id=\"x\">M</\(tag)>").fontFamilies == ["monospace"], "\(tag)")
        }
        for tag in ["tt", "kbd", "samp"] {
            #expect(try Self.style("<p><\(tag) id=\"x\">M</\(tag)></p>").display == .inline, "\(tag)")
        }
        #expect(try Self.style("<pre id=\"x\">M</pre>", css: "pre { font-family: serif }").fontFamilies == ["serif"])
        // Inherited, not reset, by what is inside.
        #expect(try Self.style("<pre><span id=\"x\">M</span></pre>").fontFamilies == ["monospace"])
    }

    /// In a document with a language, as the measured one (zh-Hant) has; with
    /// none, WebKit's own setting, Courier (`GenericFontFamilyTests`).
    @Test func monospaceIsMenloAtTheInheritedSize() async throws {
        #expect(InlineLayout.installedFont(family: "monospace", size: 17, language: "zh-Hant")?.fontName == "Menlo-Regular")
        #expect(InlineLayout.installedFont(family: "MONOSPACE", size: 17, language: "zh-Hant")?.fontName == "Menlo-Regular")
        #expect(InlineLayout.installedFont(family: "Georgia", size: 17, language: "zh-Hant")?.fontName == "Georgia")
        let cases: [(body: String, css: String)] = [
            ("<pre lang=\"zh-Hant\">MMMMMMMMMM</pre>", ""),
            ("<p lang=\"zh-Hant\"><code>MMMMMMMMMM</code></p>", ""),
            ("<p lang=\"zh-Hant\"><kbd>MMMMMMMMMM</kbd></p>", ""),
            // A family not installed falls through to the generic one after it.
            ("<p lang=\"zh-Hant\" class=\"c\">MMMMMMMMMM</p>", ".c { font-family: Consolas, monospace }"),
        ]
        for (body, css) in cases {
            let layout = try await Self.layout(body, css: css, mode: .horizontal)
            let texts = BrowserLayoutTestSupport.allTextFragments(layout.pages).filter { $0.sourceRange.length > 0 }
            let run = try #require(texts.first, "\(body)")
            #expect(run.font.fontName == "Menlo-Regular", "\(body) \(run.font.fontName)")
            #expect(run.font.pointSize == 17)
            #expect(abs(run.rect.rawValue.width - 102.35) < 0.01, "\(body) \(run.rect.rawValue.width)")
        }
    }
}

private extension Int {
    func isNear(_ value: Int) -> Bool { abs(self - value) <= 1 }
}
