import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("CJK typography: punctuation positions")
struct CJKPunctuationTests {
    private static let size: CGFloat = 20

    private func font(_ name: String) throws -> UIFont {
        try #require(UIFont(name: name, size: Self.size))
    }

    /// Where the middle character of a three-character string ends up when the line is
    /// drawn as the engines draw it, in ems from the point midway between its two
    /// neighbours' ink: the frame of `PunctuationPlacement.Position`, with the string's
    /// own offsets and kerns applied. Ink is assigned to squares by where they were
    /// before any kern, as the neighbours do not move.
    private func drawnPosition(of text: NSAttributedString, vertical: Bool) -> PunctuationPlacement.Position? {
        let shaped = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: shaped.length)
        shaped.addAttribute(.foregroundColor, value: UIColor.black.cgColor, range: whole)
        if vertical {
            shaped.addAttribute(NSAttributedString.Key(kCTVerticalFormsAttributeName as String), value: true, range: whole)
        }
        let line = CTLineCreateWithAttributedString(shaped)
        let unkerned = NSMutableAttributedString(attributedString: shaped)
        unkerned.removeAttribute(.kern, range: whole)
        let squares = CTLineCreateWithAttributedString(unkerned)
        let edges = (0...3).map { CTLineGetOffsetForStringIndex(squares, $0, nil) }
        let em = Self.size
        let scale: CGFloat = 4
        let alongSpan = Int((edges[3] + em) * scale), acrossSpan = Int(em * 2.5 * scale)
        let width = vertical ? acrossSpan : alongSpan, height = vertical ? alongSpan : acrossSpan
        var pixels = [UInt8](repeating: 0, count: width * height)
        let origin = CGPoint(x: vertical ? em * 1.25 : em / 2, y: vertical ? CGFloat(height) / scale - em / 2 : em)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: origin.x, y: origin.y)
            if vertical { context.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) }
            context.textPosition = .zero
            CTLineDraw(line, context)
        }
        func ink(along range: ClosedRange<CGFloat>) -> CGRect? {
            var box = CGRect.null
            for row in 0..<height {
                for column in 0..<width where pixels[row * width + column] < 128 {
                    let point = CGPoint(x: (CGFloat(column) + 0.5) / scale, y: (CGFloat(height - row) - 0.5) / scale)
                    let along = vertical ? origin.y - point.y : point.x - origin.x
                    if range.contains(along) { box = box.union(CGRect(origin: point, size: .zero)) }
                }
            }
            return box.isNull ? nil : box
        }
        guard let before = ink(along: edges[0]...edges[1]), let mark = ink(along: edges[1]...edges[2]),
              let after = ink(along: edges[2]...edges[3]) else { return nil }
        let centre = CGPoint(x: (before.midX + after.midX) / 2, y: (before.midY + after.midY) / 2)
        if vertical {
            return .init(along: (centre.y - mark.midY) / em, across: (mark.midX - centre.x) / em)
        }
        return .init(along: (mark.midX - centre.x) / em, across: (centre.y - mark.midY) / em)
    }

    private func isCentred(_ p: PunctuationPlacement.Position?) -> Bool {
        guard let p else { return false }
        return abs(p.along) <= 0.08 && abs(p.across) <= 0.08
    }

    /// Lower left in horizontal text, upper right in vertical text: across positive
    /// (below, or right), along negative (earlier).
    private func isCornered(_ p: PunctuationPlacement.Position?) -> Bool {
        guard let p else { return false }
        return p.along <= -0.15 && p.across >= 0.15
    }

    @Test("Each style's system font sets 。 where CLREQ and JLREQ do")
    func referencePositions() throws {
        for vertical in [true, false] {
            let tc = PunctuationPlacement.position(of: "。", in: try font("PingFangTC-Regular") as CTFont, language: "zh-Hant", vertical: vertical)
            let sc = PunctuationPlacement.position(of: "。", in: try font("PingFangSC-Regular") as CTFont, language: "zh-Hans", vertical: vertical)
            let ja = PunctuationPlacement.position(of: "。", in: try font("HiraginoSans-W3") as CTFont, language: "ja", vertical: vertical)
            #expect(isCentred(tc), "TC vertical=\(vertical): \(String(describing: tc))")
            #expect(isCornered(sc), "SC vertical=\(vertical): \(String(describing: sc))")
            #expect(isCornered(ja), "ja vertical=\(vertical): \(String(describing: ja))")
        }
    }

    @Test("A font of the same convention keeps its own design")
    func sameConventionStays() throws {
        let text = NSMutableAttributedString(string: "国。国，", attributes: [
            .font: try font("HiraginoSans-W3"),
            NSAttributedString.Key(kCTLanguageAttributeName as String): "zh-Hans",
        ])
        let before = NSAttributedString(attributedString: text)
        CJKTypography.applyPositions(to: text, style: .simplified, vertical: true)
        #expect(text.isEqual(to: before))
    }

    @Test("A mark already in its style's font is left alone")
    func styleFontStays() throws {
        let text = NSMutableAttributedString(string: "國。國", attributes: [.font: try font("PingFangTC-Regular")])
        let before = NSAttributedString(attributedString: text)
        CJKTypography.applyPositions(to: text, style: .traditional, vertical: true)
        #expect(text.isEqual(to: before))
    }

    @Test("A mark in another region's font moves to where its style's font sets it", arguments: [
        ("PingFangSC-Regular", CJKTypographyStyle.traditional, true),
        ("PingFangTC-Regular", .simplified, true),
        ("PingFangTC-Regular", .japanese, true),
        ("PingFangTC-Regular", .japanese, false),
        ("HiraginoSans-W3", .traditional, true),
        ("HiraginoSans-W3", .traditional, false),
    ])
    func foreignFontMoves(fontName: String, style: CJKTypographyStyle, vertical: Bool) throws {
        let reference = CJKFontLookup.standIn(for: style, like: try font(fontName) as CTFont) as CTFont
        var moved = 0
        for mark in ["。", "，", "、", "：", "？"] {
            let text = NSMutableAttributedString(string: "國\(mark)國", attributes: [
                .font: try font(fontName),
                NSAttributedString.Key(kCTLanguageAttributeName as String): style.languageTag,
            ])
            let before = NSAttributedString(attributedString: text)
            CJKTypography.applyPositions(to: text, style: style, vertical: vertical)
            if !text.isEqual(to: before) { moved += 1 }
            let target = PunctuationPlacement.position(of: mark, in: reference, language: style.languageTag, vertical: vertical)
            let drawn = drawnPosition(of: text, vertical: vertical)
            let label = "\(fontName) \(style) vertical=\(vertical) \(mark): target \(String(describing: target)) drawn \(String(describing: drawn))"
            guard let target, let drawn else { Issue.record("unmeasured: \(label)"); continue }
            // Moved marks land on the style's font's place; marks of the style's own
            // convention keep their design, which stays within this of it here.
            #expect(abs(drawn.along - target.along) <= 0.15 && abs(drawn.across - target.across) <= 0.15, "\(label)")
        }
        // Fonts that share a design can agree through their language forms (PingFang
        // SC tagged zh-Hant centres 。、); each case still has marks of its own to move.
        #expect(moved > 0, "\(fontName) \(style) vertical=\(vertical): nothing needed moving")
    }

    @Test("The move keeps every advance: the line is as long as before")
    func advancesStay() throws {
        let text = NSMutableAttributedString(string: "國，國。", attributes: [.font: try font("PingFangSC-Regular")])
        let before = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
        CJKTypography.applyPositions(to: text, style: .traditional, vertical: false)
        let after = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
        #expect(abs(after - before) < 0.01)
        #expect(text.attribute(.kern, at: 0, effectiveRange: nil) != nil)
    }
}
