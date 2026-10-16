import Testing
import UIKit
@testable import YueduCoreText

/// `vertical-align: super/sub` shifts the inline run's baseline (CSS 2.1
/// §10.8.1: a UA-defined amount). Fragments are line-box granular, so the
/// shift is asserted on the glyph origins inside the shared CTLine — the
/// shifted run's glyphs move by the offset while siblings stay at zero.
struct BrowserVerticalAlignTests {

    private static func fragments(
        _ html: String
    ) async throws -> [String: TextFragment] {
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            html, cssTexts: [], width: 300, height: 800, rootFontSize: 10)
        let ns = doc.lastSourceText as NSString
        var byText: [String: TextFragment] = [:]
        for f in BrowserLayoutTestSupport.allTextFragments(pages).sorted(by: {
            $0.sourceRange.location < $1.sourceRange.location
        }) {
            guard case .linear = f.sourceMapping, f.sourceRange.length > 0,
                f.sourceRange.location + f.sourceRange.length <= ns.length
            else { continue }
            byText[ns.substring(with: f.sourceRange)] = f
        }
        return byText
    }

    /// First-glyph y of the run covering the fragment's shaped range, in
    /// CTLine coordinates (baseline = 0, up is positive).
    private static func glyphY(_ fragment: TextFragment) -> CGFloat? {
        guard case .linear(let shaped) = fragment.sourceMapping,
            let ctLine = fragment.ctLine
        else { return nil }
        for run in CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? [] {
            let range = CTRunGetStringRange(run)
            guard range.location <= shaped.location, shaped.location < range.location + range.length
            else { continue }
            var positions = [CGPoint](repeating: .zero, count: 1)
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &positions)
            return positions.first?.y
        }
        return nil
    }

    @Test func superscriptRaisesRunAboveSharedBaseline() async throws {
        let byText = try await Self.fragments("""
            <body style="margin:0"><p style="margin:0;line-height:1em;font-size:20px">世<span style="vertical-align:super;font-size:0.5em">獻</span>界</p>
            </body>
            """)
        let big = try #require(byText["世"], "base fragment missing")
        let sup = try #require(byText["獻"], "sup fragment missing")
        // +⅓em at 10px ≈ +3.3 above the sibling's zero baseline.
        #expect((try #require(Self.glyphY(sup))) - (try #require(Self.glyphY(big))) > 2)
    }

    @Test func subscriptLowersRunBelowSharedBaseline() async throws {
        let byText = try await Self.fragments("""
            <body style="margin:0"><p style="margin:0;line-height:1em;font-size:40px">世<span style="vertical-align:sub;font-size:0.5em">獻</span>界</p>
            </body>
            """)
        let big = try #require(byText["世"], "base fragment missing")
        let sub = try #require(byText["獻"], "sub fragment missing")
        // -⅕em at 20px = -4 below the sibling's zero baseline.
        #expect((try #require(Self.glyphY(big))) - (try #require(Self.glyphY(sub))) > 2)
    }

    @Test func superscriptGrowsLineBoxAbove() async throws {
        // A same-size superscript must extend the line box above the strut,
        // so the next line moves down (CSS 2.1 §10.8.1).
        let plain = try await Self.fragments("""
            <body style="margin:0"><p style="margin:0;line-height:1em;font-size:20px">世獻<br/>界</p>
            </body>
            """)
        let raised = try await Self.fragments("""
            <body style="margin:0"><p style="margin:0;line-height:1em;font-size:20px">世<span style="vertical-align:super">獻</span><br/>界</p>
            </body>
            """)
        let plainNext = try #require(plain["界"], "plain next-line fragment missing")
        let raisedNext = try #require(raised["界"], "raised next-line fragment missing")
        #expect(raisedNext.rect.rawValue.minY - plainNext.rect.rawValue.minY > 4)
    }
}
