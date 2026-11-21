import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import YueduCoreText

/// `calc()` of lengths and percentages on a property measured across the page. A book pins a
/// label over a progress bar with `left: 80px; width: calc(100% - 110px)`; any `calc()` used
/// to send its chapter to the host's fallback.
struct CalcLengthTests {
    @Test func aSumOfLengthsAndPercentagesParses() {
        var expected = CSSCalc()
        expected.percent = 1
        expected.px = -110
        #expect(CSSLengthResolver.parseCalc("calc(100% - 110px)") == .calc(expected))
        var mixed = CSSCalc()
        mixed.em = 2
        mixed.px = 10 + 12 * 96.0 / 72.0
        mixed.percent = -0.25
        #expect(CSSLengthResolver.parseCalc(" CALC(2em + 10px - 25% + 12pt) ") == .calc(mixed))
    }

    @Test(arguments: [
        "calc(100% * 2)", "calc(100% / 3)", "calc(100%-110px)", "calc(100% - (10px + 5px))",
        "calc(100% -)", "calc()", "calc(auto + 1px)", "min(100%, 300px)", "clamp(1px, 2vw, 3px)", "100%",
    ])
    func whatItDoesNotComputeIsNotGuessed(value: String) {
        #expect(CSSLengthResolver.parseCalc(value) == nil)
    }

    @Test func itResolvesAgainstTheSameBasesAsItsTerms() {
        let length = try! #require(CSSLengthResolver.parseCalc("calc(100% - 110px + 1em + 1rem)"))
        #expect(CSSLengthResolver.resolve(length, emBase: 12, remBase: 16, percentBase: 300) == CGFloat(218))
        // A viewport term with no viewport to measure is unresolved, like `vh` on its own.
        let viewport = try! #require(CSSLengthResolver.parseCalc("calc(50vw - 10px)"))
        #expect(CSSLengthResolver.resolve(viewport, emBase: 12, remBase: 16, percentBase: 300) == nil)
        #expect(CSSLengthResolver.resolve(viewport, emBase: 12, remBase: 16, percentBase: 300, viewportWidth: 400) == CGFloat(190))
    }

    @Test func aLengthStaysOneWordAndATag() {
        // Styles hold dozens of lengths and are copied by value deep in layout's recursion.
        #expect(MemoryLayout<CSSLength>.size == 9)
    }

    @Test func aBlockIsAsWideAsItsCalcSays() throws {
        let config = BrowserLayoutConfig(renderWidth: 350, renderHeight: 800, rootFontSize: 17,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        let css = """
        body { margin: 0 } .row { position: relative; padding: 0 30px 0 80px; height: 30px; }
        .bar { width: calc(100% - 110px); height: 14px; margin-left: calc(10px + 5%); border-left: 3px solid #000; }
        .label { position: absolute; left: 80px; top: 15px; width: calc(100% - 110px); height: 14px; border-left: 4px solid #000; }
        """
        let document = BrowserLayoutDocument(
            html: "<html><body><div class=\"row\"><div class=\"bar\"></div><div class=\"label\">进行中</div></div></body></html>",
            cssTexts: [css], config: config, imageLoader: { _ in nil })
        let root = try document.makeLayout(containerSize: CGSize(width: 350, height: 800)).rootBox
        func all(_ box: BlockBox) -> [BlockBox] { [box] + box.children.flatMap(all) }
        let bar = try #require(all(root).first { $0.borders.left == 3 })
        let label = try #require(all(root).first { $0.borders.left == 4 })
        // In flow: percentages of the row's 240pt content box.
        #expect(abs(bar.contentSize.width - (240 - 110)) < 0.01, "\(bar.contentSize)")
        #expect(abs(bar.margins.left - (10 + 12)) < 0.01, "\(bar.margins)")
        // Out of flow: percentages of the row's 350pt padding box, from its padding edge.
        #expect(abs(label.contentSize.width - (350 - 110)) < 0.01, "\(label.contentSize)")
        #expect(abs(label.frame.rawValue.minX - (-80 + 80)) < 0.01, "\(label.frame.rawValue)")
    }

    @Test func admissionTakesWhatLayoutComputes() {
        func scan(_ css: String, _ mode: ReaderWritingMode = .horizontal) -> [UnsupportedFeature] {
            BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body><div class=\"a\">x</div></body></html>",
                                                cssTexts: [css], writingMode: mode).unsupportedFeatures
        }
        #expect(scan(".a { width: calc(100% - 110px); margin-left: calc(1em + 2px) }").isEmpty)
        // Not a sum, or a property measured down the page.
        #expect(scan(".a { width: calc(100% / 3) }") == [.calcOrModernFunctions])
        #expect(scan(".a { height: calc(100% - 10px) }") == [.calcOrModernFunctions])
        #expect(scan(".a { margin: 0 calc(10% + 2px) }") == [.calcOrModernFunctions])
        #expect(scan(".a { width: min(100%, 300px) }") == [.calcOrModernFunctions])
        // In vertical text a width runs down the column.
        #expect(scan(".a { width: calc(100% - 110px) }", .verticalRTL).contains(.calcOrModernFunctions))
    }
}
