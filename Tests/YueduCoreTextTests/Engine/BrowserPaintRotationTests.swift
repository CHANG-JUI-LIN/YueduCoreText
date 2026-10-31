import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// CSS `transform: rotate()` is paint-only: layout keeps the untransformed
/// boxes while fragments carry a `PaintTransform` about their owning box's
/// border-box center, in page coordinates.
struct BrowserPaintRotationTests {

    private func makeLayout(
        _ html: String, width: CGFloat = 390
    ) async throws -> [PageFragments] {
        let config = BrowserLayoutConfig(
            renderWidth: width, renderHeight: 800, rootFontSize: 16,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
        let doc = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: nil)
        return try await doc.renderPages(containerSize: CGSize(width: width, height: 800))
    }

    private func texts(_ pages: [PageFragments]) -> [TextFragment] {
        BrowserLayoutTestSupport.allTextFragments(pages)
    }

    private func fills(_ pages: [PageFragments]) -> [FillFragment] {
        var result: [FillFragment] = []
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .fill(let f): result.append(f)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        for page in pages { walk(page.fragments) }
        return result
    }

    /// The linear part is the rotation matrix, and the box center is a fixed
    /// point of the full transform.
    private func expectRotation(
        _ transform: PaintTransform?,
        degrees: CGFloat,
        fixedPoint: CGPoint,
        source: SourceLocation = #_sourceLocation
    ) throws {
        let m = try #require(transform, sourceLocation: source).matrix
        let rad = degrees * .pi / 180
        #expect(abs(m.a - cos(rad)) < 0.01, sourceLocation: source)
        #expect(abs(m.b - sin(rad)) < 0.01, sourceLocation: source)
        #expect(abs(m.c + sin(rad)) < 0.01, sourceLocation: source)
        #expect(abs(m.d - cos(rad)) < 0.01, sourceLocation: source)
        let mapped = fixedPoint.applying(m)
        #expect(abs(mapped.x - fixedPoint.x) < 0.5, sourceLocation: source)
        #expect(abs(mapped.y - fixedPoint.y) < 0.5, sourceLocation: source)
    }

    @Test func rotatedLetterCellCarriesPaintTransform() async throws {
        let pages = try await makeLayout("""
            <html><body style="margin: 0;">
            <div style="margin-top: 100px;"><p style="width: 1em; height: 16px; margin: 0; transform: rotate(90deg);">i</p></div>
            </body></html>
            """)
        let fragment = try #require(texts(pages).first)
        // The 1em square sits at (0,100); the rotation pivots its center.
        try expectRotation(fragment.paintTransform, degrees: 90, fixedPoint: CGPoint(x: 8, y: 108))
        // Layout itself is untouched: the line box stays put.
        #expect(fragment.rect.minY < 108)
    }

    @Test func blockRotationAppliesToDescendantTextAndFill() async throws {
        let pages = try await makeLayout("""
            <html><body style="margin: 0;">
            <div style="width: 200px; height: 40px; margin: 100px 0 0 50px; background: #eee; transform: rotate(-5deg);"><p style="margin: 0;">标题文字</p></div>
            </body></html>
            """)
        let text = try #require(texts(pages).first)
        // Border box (50,100,200,40) → center (150,120).
        try expectRotation(text.paintTransform, degrees: -5, fixedPoint: CGPoint(x: 150, y: 120))
        let fill = try #require(fills(pages).first { $0.rect.width == 200 })
        try expectRotation(fill.paintTransform, degrees: -5, fixedPoint: CGPoint(x: 150, y: 120))
    }

    @Test func nestedTransformsCompose() async throws {
        let pages = try await makeLayout("""
            <html><body style="margin: 0;">
            <div style="transform: rotate(10deg);"><div style="transform: rotate(20deg);"><p style="margin: 0;">x</p></div></div>
            <div style="transform: rotate(30deg);"><div><p style="margin: 0;">y</p></div></div>
            </body></html>
            """)
        let ordered = texts(pages).sorted { $0.sourceRange.location < $1.sourceRange.location }
        #expect(ordered.count == 2)
        // Nested rotations compose: the linear part is 10° + 20°.
        let composed = try #require(ordered[0].paintTransform).matrix
        #expect(abs(composed.b - sin(.pi / 6)) < 0.01)
        #expect(abs(composed.a - cos(.pi / 6)) < 0.01)
        // Without its own transform the inner box inherits the ancestor's.
        #expect(abs((try #require(ordered[1].paintTransform).matrix).b - sin(.pi / 6)) < 0.01)
    }

    @Test func turnAndRadUnitsConvertToDegrees() async throws {
        let pages = try await makeLayout("""
            <html><body style="margin: 0;">
            <div style="transform: rotate(0.25turn);"><p style="margin: 0;">a</p></div>
            <div style="transform: rotate(3.141592653589793rad);"><p style="margin: 0;">b</p></div>
            <div style="transform: rotate(90deg) scale(2);"><p style="margin: 0;">c</p></div>
            </body></html>
            """)
        let ordered = texts(pages).sorted { $0.sourceRange.location < $1.sourceRange.location }
        #expect(ordered.count == 3)
        #expect(abs((try #require(ordered[0].paintTransform).matrix).b - 1) < 0.01)
        #expect(abs((try #require(ordered[1].paintTransform).matrix).a + 1) < 0.01)
        // Lists beyond a bare rotate() compute to none rather than half-apply.
        #expect(ordered[2].paintTransform == nil)
    }

    @Test func untransformedContentHasNoPaintTransform() async throws {
        let pages = try await makeLayout("""
            <html><body style="margin: 0;">
            <p style="margin: 0;">plain</p>
            </body></html>
            """)
        #expect(texts(pages).allSatisfy { $0.paintTransform == nil })
    }

    @Test func anonymousBlockUnderRotatedParentRotatesOnce() async throws {
        // "lead" sits beside a block sibling, so it is wrapped in an anonymous
        // block. The wrapper turns with its parent and must not add its own turn.
        let pages = try await makeLayout("""
            <html><body style="margin: 0;">
            <div style="width: 200px; margin-top: 100px; transform: rotate(10deg);">lead<p style="margin: 0;">para</p></div>
            </body></html>
            """)
        let ordered = texts(pages).sorted { $0.sourceRange.location < $1.sourceRange.location }
        #expect(ordered.count == 2)
        let rad = 10 * CGFloat.pi / 180
        for fragment in ordered {
            let m = try #require(fragment.paintTransform).matrix
            #expect(abs(m.a - cos(rad)) < 0.01)
            #expect(abs(m.b - sin(rad)) < 0.01)
        }
    }
}
