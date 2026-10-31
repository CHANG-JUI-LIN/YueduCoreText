import CoreGraphics
import Foundation
import Testing
@testable import YueduCoreText

/// FloatContext-level projection semantics: each container queries and places
/// floats in its own inline range of the shared context axis.
struct BrowserFloatContextProjectionTests {

    @Test func intervalProjectionKeepsOutOfRangeFloatsSilent() {
        let fc = FloatContext(containerWidth: 390)
        fc.placeFloat(
            side: .left,
            marginBoxSize: CGSize(width: 50, height: 100),
            margins: .zero,
            startY: 0,
            inlineRange: 0 ..< 100
        )
        // Container [290,390]: no x overlap with the float's margin box [0,50].
        let outside = fc.availableInterval(y: 10, height: 20, inlineRange: 290 ..< 390)
        #expect(outside.lineX == 0)
        #expect(outside.lineWidth == 100)
        // Container [30,130]: the float's right edge bites 20pt into it.
        let overlapping = fc.availableInterval(y: 10, height: 20, inlineRange: 30 ..< 130)
        #expect(overlapping.lineX == 20)
        #expect(overlapping.lineWidth == 80)
        // Below the float every container gets its full width back.
        let below = fc.availableInterval(y: 120, height: 20, inlineRange: 30 ..< 130)
        #expect(below.lineX == 0)
        #expect(below.lineWidth == 100)
    }

    @Test func rightFloatPlacementStaysInsideNarrowRange() {
        let fc = FloatContext(containerWidth: 390)
        let placed = fc.placeFloat(
            side: .right,
            marginBoxSize: CGSize(width: 80, height: 40),
            margins: .zero,
            startY: 0,
            inlineRange: 95 ..< 295
        )
        // Local coordinates: the right edge kisses 200, so minX = 120.
        #expect(placed.borderBox.minX == 120)
        // The recorded exclusion uses FloatContext coordinates (95 + 120).
        #expect(fc.activeFloats.first?.borderBox.minX == 215)
        // A following right float in the same range marches left from it.
        let second = fc.placeFloat(
            side: .right,
            marginBoxSize: CGSize(width: 80, height: 40),
            margins: .zero,
            startY: 0,
            inlineRange: 95 ..< 295
        )
        #expect(second.borderBox.minX == 40)
    }
}
