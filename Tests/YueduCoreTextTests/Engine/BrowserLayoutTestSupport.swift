import Testing
import UIKit
@testable import YueduCoreText
import YueduCoreTextTypography

/// Shared helpers for the browser-layout test suites.
enum BrowserLayoutTestSupport {

    /// Runs the full pipeline and returns pages + the document (for sourceText/anchors/metrics).
    static func layout(
        _ html: String,
        cssTexts: [String] = [],
        width: CGFloat = 300,
        height: CGFloat = 400,
        rootFontSize: CGFloat = 17,
        imageLoader: ((String) -> UIImage?)? = nil,
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)? = nil
    ) async throws -> (pages: [PageFragments], doc: BrowserLayoutDocument) {
        var config = BrowserLayoutConfig(
            renderWidth: width, renderHeight: height, rootFontSize: rootFontSize,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        config.fontResolver = fontResolver
        let doc = BrowserLayoutDocument(
            html: html, cssTexts: cssTexts, config: config, imageLoader: imageLoader
        )
        let pages = try await doc.renderPages(containerSize: CGSize(width: width, height: height))
        return (pages, doc)
    }

    /// The reference document WebKit was measured with (S001: 17px PingFang
    /// SC at line-height 1.5, an 8px body margin, `lang="zh-Hant"`) holding
    /// `body`: 366 wide, or a 776 tall vertical-rl page.
    /// `rootFamilies` replaces the reader's font: `[]` is the app's own default,
    /// the system font, with CJK text in its language's font. `cjk` is the
    /// app's CJK typography, which draws Han in a stand-in font.
    static func webKitReference(
        _ body: String, css: String = "", vertical: Bool = false, lang: String? = "zh-Hant",
        rootFamilies: [String] = ["PingFangSC-Regular"], cjk: CJKTypographyStyle? = nil,
        imageLoader: (@Sendable (String) -> UIImage?)? = nil
    ) async throws -> (pages: [PageFragments], doc: BrowserLayoutDocument) {
        let family = rootFamilies.isEmpty ? "" : "font-family:\"PingFang SC\""
        let reference = "html{font-size:17px;line-height:1.5;text-align:justify;\(family)}"
        let width: CGFloat = vertical ? 3000 : 366
        let height: CGFloat = vertical ? 776 : 20_000
        var config = BrowserLayoutConfig(renderWidth: width, renderHeight: height, rootFontSize: 17,
                                         fontFamilies: rootFamilies, textColor: .black, backgroundColor: .white)
        config.writingMode = vertical ? .verticalRTL : .horizontal
        config.cjkTypographyStyle = cjk
        let html = "<html\(lang.map { " lang=\"\($0)\"" } ?? "")><body>\(body)</body></html>"
        let doc = BrowserLayoutDocument(html: html, cssTexts: [reference, css], config: config, imageLoader: imageLoader)
        let pages = try await doc.renderPages(containerSize: CGSize(width: width, height: height))
        return (pages, doc)
    }

    /// The text fragment holding the first character of `text`'s first
    /// occurrence after the first `from` in the source.
    static func fragment(_ text: String, after from: String? = nil, in layout: (pages: [PageFragments], doc: BrowserLayoutDocument)) -> TextFragment? {
        let source = layout.doc.lastSourceText as NSString
        let anchor = from.map { source.range(of: $0) } ?? NSRange(location: 0, length: 0)
        guard anchor.location != NSNotFound else { return nil }
        let start = anchor.location + anchor.length
        let found = source.range(of: text, range: NSRange(location: start, length: source.length - start))
        guard found.location != NSNotFound else { return nil }
        return allTextFragments(layout.pages).first {
            $0.sourceRange.length > 0 && NSLocationInRange(found.location, $0.sourceRange)
        }
    }

    /// All text fragments across all pages, flattened in document order.
    static func allTextFragments(_ pages: [PageFragments]) -> [TextFragment] {
        var result: [TextFragment] = []
        for page in pages {
            collectText(page.fragments, into: &result)
        }
        return result
    }

    private static func collectText(_ fragments: [Fragment], into out: inout [TextFragment]) {
        for fragment in fragments {
            switch fragment {
            case .text(let t): out.append(t)
            case .group(let children): collectText(children, into: &out)
            default: break
            }
        }
    }

    static func allImageFragments(_ pages: [PageFragments]) -> [ImageFragment] {
        var result: [ImageFragment] = []
        for page in pages {
            collectImages(page.fragments, into: &result)
        }
        return result
    }

    private static func collectImages(_ fragments: [Fragment], into out: inout [ImageFragment]) {
        for fragment in fragments {
            switch fragment {
            case .image(let i): out.append(i)
            case .group(let children): collectImages(children, into: &out)
            default: break
            }
        }
    }

    /// Concatenates fragment source slices in order; the parity check target.
    static func visibleText(_ pages: [PageFragments], sourceText: String) -> String {
        var out = ""
        let ns = sourceText as NSString
        for fragment in allTextFragments(pages) {
            guard case .linear = fragment.sourceMapping else { continue }
            guard fragment.sourceRange.length > 0,
                  fragment.sourceRange.location >= 0,
                  fragment.sourceRange.location + fragment.sourceRange.length <= ns.length else { continue }
            out += ns.substring(with: fragment.sourceRange)
        }
        return out
    }

    /// True when every fragment range is non-overlapping and in increasing order
    /// (no loss/duplication/reordering across the whole layout).
    static func rangesAreOrdered(_ pages: [PageFragments]) -> Bool {
        var cursor = -1
        for fragment in allTextFragments(pages) {
            guard case .linear = fragment.sourceMapping else { continue }
            let range = fragment.sourceRange
            guard range.length > 0 else { continue }
            guard range.location >= cursor else { return false }
            cursor = range.location + range.length
        }
        return true
    }

    /// Generates a solid-color image in memory (no files, no network).
    static func makeImage(size: CGSize, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
