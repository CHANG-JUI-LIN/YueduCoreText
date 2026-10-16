import CoreGraphics
import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// Synthetic bold for faces without a native bold follows WebKit's model: a
/// marker carrying the horizontal offset (size/36), painted as a second
/// offset pass — never a uniform stroke, which also thickens horizontal
/// strokes and reads far heavier on CJK.
struct BrowserSyntheticBoldTests {

    private func textAttributes(family: String, fontWeight: Int, size: CGFloat) throws
        -> [NSAttributedString.Key: Any]
    {
        let font = try #require(UIFont(name: family, size: size))
        let resolver: ([String], Int, Bool, CGFloat) -> UIFont? = { families, _, _, size in
            families.contains(family) ? font.withSize(size) : nil
        }
        let style = ComputedStyle(
            fontSize: size, fontFamilies: [family], fontWeight: fontWeight,
            isItalic: false, color: .black, backgroundColor: nil
        )
        return InlineLayout.textAttributes(for: style, resolver: resolver)
    }

    @Test func boldFacelessFontGetsOffsetMarkerNotStroke() throws {
        // Zapfino ships a single regular face on iOS.
        let attrs = try textAttributes(family: "Zapfino", fontWeight: 700, size: 20)
        let offset = try #require((attrs[BrowserTextAttributes.syntheticBoldOffset] as? NSNumber)?.doubleValue)
        #expect(abs(offset - 20.0 / 36.0) < 0.001)
        #expect(attrs[.strokeWidth] == nil)
    }

    @Test func boldCapableFontGetsNoMarker() throws {
        let attrs = try textAttributes(family: "Times New Roman", fontWeight: 700, size: 20)
        #expect(attrs[BrowserTextAttributes.syntheticBoldOffset] == nil)
        #expect(attrs[.strokeWidth] == nil)
    }

    @Test func regularWeightGetsNoMarker() throws {
        let attrs = try textAttributes(family: "Zapfino", fontWeight: 400, size: 20)
        #expect(attrs[BrowserTextAttributes.syntheticBoldOffset] == nil)
        #expect(attrs[.strokeWidth] == nil)
    }

    @Test func offsetMarkerPaintsASecondPass() throws {
        let size: CGFloat = 40
        let font = try #require(UIFont(name: "Zapfino", size: size))
        func makeItem(marker: Bool) -> DisplayTextItem {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if marker {
                attributes[BrowserTextAttributes.syntheticBoldOffset] = size / 36 as NSNumber
            }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Bold", attributes: attributes))
            return DisplayTextItem(
                sourceRange: NSRange(location: 0, length: 4),
                nodeID: 0, linkTarget: nil, writingMode: .horizontal,
                rect: PageLocalRect(rawValue: CGRect(x: 0, y: 0, width: 200, height: 80)),
                baselineY: 60, font: font, color: .black, text: "Bold", ctLine: line
            )
        }
        func inkPixels(_ item: DisplayTextItem) -> Int {
            let context = CGContext(
                data: nil, width: 200, height: 80, bitsPerComponent: 8, bytesPerRow: 200,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )!
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 80))
            DisplayListDrawer.draw(DisplayList(items: [.text(item)]), in: context)
            let buffer = context.data!.bindMemory(to: UInt8.self, capacity: 200 * 80)
            var count = 0
            for index in 0..<(200 * 80) where buffer[index] < 128 { count += 1 }
            return count
        }
        #expect(inkPixels(makeItem(marker: true)) > inkPixels(makeItem(marker: false)))
    }
}
