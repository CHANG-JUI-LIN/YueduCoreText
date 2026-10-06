import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("CJK typography: vertical orientation")
struct CJKTypographyOrientationTests {
    private static let verticalForms = NSAttributedString.Key(kCTVerticalFormsAttributeName as String)

    private func upright(_ text: NSAttributedString) -> [String: Bool] {
        var result: [String: Bool] = [:]
        let ns = text.string as NSString
        for index in 0..<ns.length {
            result[ns.substring(with: NSRange(location: index, length: 1))] =
                (text.attribute(Self.verticalForms, at: index, effectiveRange: nil) as? Bool) == true
        }
        return result
    }

    @Test("Han, kana and CJK punctuation stand upright; Latin and digits lie on their side")
    func mixed() throws {
        let font = try #require(UIFont(name: "HiraginoSans-W3", size: 17))
        let text = NSMutableAttributedString(string: "漢かなカナKindle2014年、。ー「」", attributes: [.font: font])
        CJKTypography.applyOrientation(to: text)
        let flags = upright(text)
        for character in ["漢", "か", "な", "カ", "ナ", "年", "、", "。", "ー", "「", "」"] {
            #expect(flags[character] == true, "\(character) upright")
        }
        for character in ["K", "i", "n", "d", "l", "e", "2", "0", "1", "4"] {
            #expect(flags[character] == false, "\(character) on its side")
        }
    }

    @Test("Text on its side is centred on the column")
    func sidewaysIsCentred() throws {
        let font = try #require(UIFont(name: "PingFangTC-Regular", size: 20))
        let text = NSMutableAttributedString(string: "甲ABC乙", attributes: [.font: font])
        CJKTypography.applyOrientation(to: text)
        let offset = text.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? CGFloat
        #expect(offset != nil && offset! < 0)
        #expect(text.attribute(.baselineOffset, at: 0, effectiveRange: nil) == nil)
    }

    @Test("Centring adds to the baseline offset the text already has")
    func sidewaysKeepsTheTextsOwnOffset() throws {
        let font = try #require(UIFont(name: "PingFangTC-Regular", size: 20))
        let text = NSMutableAttributedString(string: "甲ABC乙", attributes: [.font: font, .baselineOffset: 3.0])
        CJKTypography.applyOrientation(to: text)
        let centring = -(CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
        let offset = try #require(text.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? NSNumber)
        #expect(abs(CGFloat(offset.doubleValue) - (3 + centring)) < 0.001)
        #expect((text.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue == 3)
    }

    @Test("The engine's own boxes keep what the engine gave them")
    func runDelegatesAreLeftAlone() throws {
        let font = try #require(UIFont(name: "PingFangTC-Regular", size: 17))
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { _ in },
            getAscent: { _ in 10 }, getDescent: { _ in 0 }, getWidth: { _ in 10 })
        let delegate = CTRunDelegateCreate(&callbacks, nil)!
        let text = NSMutableAttributedString(string: "A\u{FFFC}B", attributes: [.font: font])
        text.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: delegate,
            range: NSRange(location: 1, length: 1))
        text.addAttribute(Self.verticalForms, value: true, range: NSRange(location: 1, length: 1))
        CJKTypography.applyOrientation(to: text)
        #expect((text.attribute(Self.verticalForms, at: 1, effectiveRange: nil) as? Bool) == true)
        #expect(text.attribute(Self.verticalForms, at: 0, effectiveRange: nil) == nil)
    }
}
