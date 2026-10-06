import CoreText
import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("CJK typography: fonts by language")
struct CJKTypographyFontTests {
    private static let language = NSAttributedString.Key(kCTLanguageAttributeName as String)
    private static let size: CGFloat = 17

    /// The font CoreText draws each character with, and the language it was told.
    private func shaped(_ text: NSAttributedString) -> [(character: String, font: String, language: String?)] {
        let line = CTLineCreateWithAttributedString(text)
        var fonts: [Int: String] = [:]
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let range = CTRunGetStringRange(run)
            for index in range.location..<(range.location + range.length) {
                fonts[index] = CTFontCopyPostScriptName(font) as String
            }
        }
        let ns = text.string as NSString
        var result: [(String, String, String?)] = []
        var index = 0
        while index < ns.length {
            let range = ns.rangeOfComposedCharacterSequence(at: index)
            result.append((ns.substring(with: range), fonts[range.location] ?? "-",
                           text.attribute(Self.language, at: range.location, effectiveRange: nil) as? String))
            index = NSMaxRange(range)
        }
        return result
    }

    private func set(_ string: String, style: CJKTypographyStyle, font: UIFont = .systemFont(ofSize: size))
        -> [(character: String, font: String, language: String?)] {
        let text = NSMutableAttributedString(string: string, attributes: [.font: font])
        CJKTypography.applyFonts(to: text, style: style)
        return shaped(text)
    }

    private func font(of character: String, in facts: [(character: String, font: String, language: String?)]) -> String? {
        facts.first { $0.character == character }?.font
    }

    private func language(of character: String, in facts: [(character: String, font: String, language: String?)]) -> String? {
        facts.first { $0.character == character }?.language
    }

    @Test("Han takes the style's language and font", arguments: [
        (CJKTypographyStyle.traditional, "國", "PingFangTC-Regular"),
        (.simplified, "国", "PingFangSC-Regular"),
        (.japanese, "国", "HiraginoSans-W3"),
        (.korean, "國", "AppleSDGothicNeo-Regular"),
    ])
    func hanByStyle(style: CJKTypographyStyle, han: String, expected: String) {
        let facts = set("A\(han)，B", style: style)
        #expect(font(of: han, in: facts) == expected, "\(facts)")
        #expect(language(of: han, in: facts) == style.languageTag)
        #expect(font(of: "，", in: facts) == expected, "\(facts)")
        #expect(font(of: "A", in: facts) == UIFont.systemFont(ofSize: Self.size).fontName)
        #expect(language(of: "A", in: facts) == nil)
    }

    @Test("Kana are Japanese and Hangul Korean, whatever the book's style")
    func kanaAndHangul() {
        let facts = set("國かカ한글", style: .traditional)
        #expect(font(of: "か", in: facts) == "HiraginoSans-W3", "\(facts)")
        #expect(font(of: "カ", in: facts) == "HiraginoSans-W3")
        #expect(language(of: "か", in: facts) == "ja")
        #expect(font(of: "한", in: facts) == "AppleSDGothicNeo-Regular", "\(facts)")
        #expect(language(of: "한", in: facts) == "ko")
    }

    @Test("Dashes and ellipses next to CJK text are CJK ones; next to Latin they stay")
    func sharedMarks() {
        let cjk = set("他——你……", style: .traditional)
        #expect(font(of: "—", in: cjk) == "PingFangTC-Regular", "\(cjk)")
        #expect(font(of: "…", in: cjk) == "PingFangTC-Regular")
        let latin = set("one—two…", style: .traditional)
        #expect(font(of: "—", in: latin) == UIFont.systemFont(ofSize: Self.size).fontName, "\(latin)")
        #expect(language(of: "—", in: latin) == nil)
        // Digits side with neither: the range dash in 3——5人 is Chinese text's.
        let digits = set("共3——5人", style: .simplified)
        #expect(font(of: "—", in: digits) == "PingFangSC-Regular", "\(digits)")
        // Alone, as in a line of dialogue that is only “……”, they are the book's.
        let alone = set("“……”", style: .simplified)
        #expect(font(of: "…", in: alone) == "PingFangSC-Regular", "\(alone)")
        #expect(font(of: "“", in: alone) == "PingFangSC-Regular")
    }

    @Test("A symbol the text's fonts lack takes the style's font next to CJK text only")
    func symbolsFollowTheirText() throws {
        let japanese = set("見※て", style: .japanese)
        #expect(font(of: "※", in: japanese) == "HiraginoSans-W3", "\(japanese)")
        #expect(language(of: "※", in: japanese) == "ja")
        let text = NSMutableAttributedString(string: "see ※ here", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        CJKTypography.applyFonts(to: text, style: .japanese)
        #expect(text.attribute(CJKTypography.replacedFontAttribute, at: 4, effectiveRange: nil) == nil)
        // Spaces and format characters are never redrawn, so a zero-width space between
        // Han does not split their run.
        let spaced = NSMutableAttributedString(string: "国\u{200B}国", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        CJKTypography.applyFonts(to: spaced, style: .japanese)
        #expect(spaced.attribute(CJKTypography.replacedFontAttribute, at: 1, effectiveRange: nil) == nil)
    }

    @Test("A font that has the character keeps it")
    func authoredCJKFontStays() throws {
        let songti = try #require(UIFont(name: "PingFangSC-Regular", size: Self.size))
        let facts = set("國——", style: .traditional, font: songti)
        #expect(font(of: "國", in: facts) == "PingFangSC-Regular", "\(facts)")
        #expect(font(of: "—", in: facts) == "PingFangSC-Regular")
        #expect(language(of: "國", in: facts) == "zh-Hant")
    }

    @Test("An authored CJK fallback in the font's cascade keeps its characters")
    func authoredCascadeStays() throws {
        let georgia = try #require(UIFont(name: "Georgia", size: Self.size))
        let stacked = UIFont(descriptor: georgia.fontDescriptor.addingAttributes([
            .cascadeList: [UIFontDescriptor(name: "PingFangSC-Regular", size: Self.size)],
        ]), size: Self.size)
        let text = NSMutableAttributedString(string: "Ab國——", attributes: [.font: stacked])
        CJKTypography.applyFonts(to: text, style: .traditional)
        #expect(text.attribute(CJKTypography.replacedFontAttribute, at: 2, effectiveRange: nil) == nil)
        #expect(text.attribute(CJKTypography.replacedFontAttribute, at: 3, effectiveRange: nil) == nil)
        let facts = shaped(text)
        #expect(font(of: "國", in: facts) == "PingFangSC-Regular", "\(facts)")
        #expect(language(of: "國", in: facts) == "zh-Hant")
    }

    @Test("Han no candidate has still takes the stand-in, so a run of Han stays in one font")
    func extensionBStaysWithItsRun() throws {
        let text = NSMutableAttributedString(string: "國𠀋國", attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        CJKTypography.applyFonts(to: text, style: .traditional)
        var effective = NSRange()
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: &effective) as? UIFont)
        #expect(font.fontName == "PingFangTC-Regular")
        #expect(effective == NSRange(location: 0, length: text.length))
    }

    @Test("A stand-in is bold when the font is bold, slanted when it is italic")
    func traits() throws {
        let bold = set("國", style: .traditional, font: .systemFont(ofSize: Self.size, weight: .bold))
        #expect(font(of: "國", in: bold) == "PingFangTC-Semibold", "\(bold)")
        let japaneseBold = set("国か", style: .japanese, font: .systemFont(ofSize: Self.size, weight: .bold))
        #expect(font(of: "国", in: japaneseBold) == "HiraginoSans-W6", "\(japaneseBold)")

        let text = NSMutableAttributedString(string: "國", attributes: [.font: UIFont.italicSystemFont(ofSize: Self.size)])
        CJKTypography.applyFonts(to: text, style: .traditional)
        let standIn = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(CTFontGetMatrix(standIn as CTFont).c == 0.2)

        var shear = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)
        let oblique = CTFontCreateWithFontDescriptor(UIFont.systemFont(ofSize: Self.size).fontDescriptor as CTFontDescriptor,
                                                     Self.size, &shear) as UIFont
        let slanted = NSMutableAttributedString(string: "國", attributes: [.font: oblique])
        CJKTypography.applyFonts(to: slanted, style: .traditional)
        let slantedStandIn = try #require(slanted.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(CTFontGetMatrix(slantedStandIn as CTFont).c == 0.25)
        #expect(slantedStandIn.pointSize == Self.size)
    }

    @Test("A replaced range remembers the font it asked for")
    func replacedFontIsRecorded() throws {
        let system = UIFont.systemFont(ofSize: Self.size)
        let text = NSMutableAttributedString(string: "A國", attributes: [.font: system])
        CJKTypography.applyFonts(to: text, style: .traditional)
        #expect(text.attribute(CJKTypography.replacedFontAttribute, at: 0, effectiveRange: nil) == nil)
        let replaced = try #require(text.attribute(CJKTypography.replacedFontAttribute, at: 1, effectiveRange: nil) as? UIFont)
        #expect(replaced.fontName == system.fontName)
    }

    @Test("A variation selector stays with its base; the engine's own boxes are left alone")
    func clustersAndDelegates() throws {
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { _ in },
            getAscent: { _ in 10 }, getDescent: { _ in 0 }, getWidth: { _ in 10 })
        let delegate = CTRunDelegateCreate(&callbacks, nil)!
        let system = UIFont.systemFont(ofSize: Self.size)
        let text = NSMutableAttributedString(string: "葛\u{E0100}\u{3000}", attributes: [.font: system])
        text.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: delegate,
            range: NSRange(location: 3, length: 1))
        CJKTypography.applyFonts(to: text, style: .japanese)
        let base = text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let selector = text.attribute(.font, at: 1, effectiveRange: nil) as? UIFont
        #expect(base?.fontName == "HiraginoSans-W3")
        #expect(selector === base)
        #expect((text.attribute(.font, at: 3, effectiveRange: nil) as? UIFont)?.fontName == system.fontName)
        #expect(text.attribute(Self.language, at: 3, effectiveRange: nil) == nil)
    }

    @Test("Among Latin lines, a mark alone on its line is still the book's")
    func aloneAmongLatinLines() {
        let facts = set("Hello\n……\nWorld", style: .traditional)
        #expect(font(of: "…", in: facts) == "PingFangTC-Regular", "\(facts)")
        #expect(font(of: "H", in: facts) == UIFont.systemFont(ofSize: Self.size).fontName)
    }

    @Test("Latin text is left exactly as it was")
    func latinUntouched() {
        let text = NSMutableAttributedString(string: "Plain English, with an em dash—and more.",
                                             attributes: [.font: UIFont.systemFont(ofSize: Self.size)])
        let before = NSAttributedString(attributedString: text)
        CJKTypography.applyFonts(to: text, style: .traditional)
        #expect(text.isEqual(to: before))
    }
}
