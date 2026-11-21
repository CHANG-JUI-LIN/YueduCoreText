import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// `display: flex` around text: one flex item, as wide as the text, placed by
/// `justify-content`. Any flex container used to send its chapter to the
/// host's fallback; books use this one to centre a heading or a label.
struct FlexSingleItemTests {

    private let reset = "body { margin: 0; padding: 0; line-height: 1; } h3, p, div { margin: 0; font-size: 20px; font-weight: normal; }"

    private func texts(_ body: String, css: String, width: CGFloat = 400) async throws -> [TextFragment] {
        let pages = try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [reset + css],
                                                              width: width, height: 800).0
        return BrowserLayoutTestSupport.allTextFragments(pages)
    }

    private func scan(_ body: String, css: String) -> BrowserLayoutCapabilityResult {
        BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body>\(body)</body></html>", cssTexts: [css])
    }

    @Test(arguments: [("center", 0.5), ("flex-end", 1.0), ("flex-start", 0.0), ("space-between", 0.0), ("space-around", 0.5)])
    func theItemIsPlacedAlongTheLine(_ justify: String, _ fraction: CGFloat) async throws {
        let found = try await texts("<h3 class=\"f\">標題</h3>", css: ".f { display: flex; justify-content: \(justify); }")
        let text = try #require(found.first)
        #expect(found.count == 1)
        #expect(abs(text.rect.rawValue.minX - (400 - text.rect.rawValue.width) * fraction) < 0.5, "\(justify): \(text.rect.rawValue)")
    }

    /// The item's text keeps the container's own alignment: a centred item that
    /// wraps is as wide as the container, and its lines are set as `text-align` says.
    @Test func theTextInsideTheItemKeepsTheContainersAlignment() async throws {
        let long = String(repeating: "一行放不下的長標題", count: 6)
        let found = try await texts("<h3 class=\"f\">\(long)</h3>", css: ".f { display: flex; justify-content: center; text-align: left; }")
        #expect(found.count > 1)
        #expect(found.allSatisfy { abs($0.rect.rawValue.minX) < 0.5 }, "wrapped lines start at the left edge")
    }

    @Test func aColumnCentresTheItemByAlignItems() async throws {
        let centred = try await texts("<div class=\"f\">標籤</div>", css: ".f { display: flex; flex-direction: column; align-items: center; }")
        let text = try #require(centred.first)
        #expect(abs(text.rect.rawValue.midX - 200) < 0.5)
        // The default stretches the item across the container: an ordinary block.
        let stretched = try await texts("<div class=\"f\">標籤</div>", css: ".f { display: flex; flex-direction: column; }")
        #expect(abs(try #require(stretched.first).rect.rawValue.minX) < 0.5)
    }

    @Test func anInlineFlexContainerSitsOnTheLine() async throws {
        let found = try await texts("<p>前<span class=\"f\">中</span>後</p>", css: ".f { display: inline-flex; align-items: center; justify-content: center; width: 60px; }")
        #expect(found.count == 3)
        let before = found[0].rect.rawValue, inner = found[1].rect.rawValue, after = found[2].rect.rawValue
        #expect(abs(before.minY - after.minY) < 0.5)
        // Centred in its 60px box, which starts where 前 ends.
        #expect(abs(inner.midX - (before.maxX + 30)) < 0.5)
        #expect(abs(after.minX - (before.maxX + 60)) < 0.5)
    }

    @Test func aTextOnlyContainerIsAdmitted() {
        let css = "h3 { display: flex; align-items: flex-start; justify-content: center; flex-wrap: wrap; gap: 4px; }"
        let result = scan("<h3>第一章</h3>", css: css)
        #expect(result.supported, "\(result.unsupportedFeatures)")
    }

    @Test func whatFlexStillFallsBack() {
        // More than one item to place.
        #expect(scan("<div class=\"f\"><span>A</span><span>B</span></div>", css: ".f { display: flex; }").unsupportedFeatures == [.flexGrid])
        #expect(scan("<div class=\"f\"><div>block</div></div>", css: ".f { display: flex; justify-content: center; }").unsupportedFeatures == [.flexGrid])
        #expect(scan("<div class=\"f\">A</div>", css: ".f { display: flex; flex-direction: row-reverse; }").unsupportedFeatures == [.flexGrid])
        #expect(scan("<div class=\"g\">A</div>", css: ".g { display: grid; }").unsupportedFeatures.contains(.unknownBlockDisplay))
        #expect(scan("<div class=\"g\">A</div>", css: ".g { grid-template-columns: 1fr 1fr; }").unsupportedFeatures == [.flexGrid])
    }
}

/// An `<svg>` with nothing inside it — a cover whose picture was removed —
/// used to report `unsupportedSVG`. It draws nothing and keeps its box.
struct EmptySVGTests {
    private func fills(_ pages: [PageFragments]) -> [FillFragment] {
        var result: [FillFragment] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill(let fill): result.append(fill)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        for page in pages { walk(page.fragments) }
        return result
    }

    @Test func anEmptySVGIsAdmittedAndAVectorOneIsNot() {
        let empty = "<html><head></head><body><div><svg width=\"100%\" height=\"100%\" viewBox=\"0 0 563 751\"></svg></div></body></html>"
        #expect(BrowserLayoutCapabilityScanner.scan(html: empty, cssTexts: []).supported)
        let vector = "<html><head></head><body><svg width=\"10\" height=\"10\"><circle r=\"4\"/></svg></body></html>"
        #expect(BrowserLayoutCapabilityScanner.scan(html: vector, cssTexts: []).unsupportedFeatures == [.unsupportedSVG])
    }

    /// As WebKit sizes it: the line's width, and a height in the viewBox's proportion.
    @Test func itKeepsTheBoxItsSizeAndViewBoxGiveIt() async throws {
        let css = "body { margin: 0; line-height: 1; } p { margin: 0; } svg { background: #ddd; }"
        let body = "<p>before</p><div><svg width=\"100%\" height=\"100%\" viewBox=\"0 0 200 100\"></svg></div><p>after</p>"
        let pages = try await BrowserLayoutTestSupport.layout("<html><body>\(body)</body></html>", cssTexts: [css], width: 400, height: 2000).0
        let box = try #require(fills(pages).first { $0.color != .clear })
        #expect(abs(box.rect.rawValue.width - 400) < 0.5)
        #expect(abs(box.rect.rawValue.height - 200) < 0.5)
        let texts = BrowserLayoutTestSupport.allTextFragments(pages)
        #expect(texts.count == 2)
        #expect(texts[1].rect.rawValue.minY >= box.rect.rawValue.maxY - 0.5, "what follows starts under the box")
    }
}
