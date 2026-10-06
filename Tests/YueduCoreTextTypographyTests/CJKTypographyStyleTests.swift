import Foundation
import Testing
@testable import YueduCoreTextTypography

@Suite("CJK typography style")
struct CJKTypographyStyleTests {
    @Test("The text's script decides, not its declared language")
    func detection() {
        #expect(CJKTypographyStyle.detect(in: "這裡說的是舊時候的事。後來聽說花還開著。") == .traditional)
        #expect(CJKTypographyStyle.detect(in: "这里说的是旧时候的事。后来听说花还开着。") == .simplified)
        #expect(CJKTypographyStyle.detect(in: "これは昔の話である。誰もよく覚えていない。") == .japanese)
        #expect(CJKTypographyStyle.detect(in: "我的天") == nil)
    }

    @Test("Declared languages map to a style only when the text says nothing")
    func declared() {
        #expect(CJKTypographyStyle.declared("zh-cn") == .simplified)
        #expect(CJKTypographyStyle.declared("zh-TW") == .traditional)
        #expect(CJKTypographyStyle.declared("ja") == .japanese)
        #expect(CJKTypographyStyle.declared("fr") == nil)
    }

    @Test("Each style names its language and reference font")
    func languageAndFont() {
        #expect(CJKTypographyStyle.traditional.languageTag == "zh-Hant")
        #expect(CJKTypographyStyle.simplified.referenceFontName == "PingFangSC-Regular")
        #expect(CJKTypographyStyle.japanese.referenceFontName == "HiraginoSans-W3")
    }
}
