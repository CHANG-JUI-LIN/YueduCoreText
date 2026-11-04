import Testing
@testable import YueduCoreText

/// Marker text: CSS Counter Styles 3 over an item's ordinal, with the
/// descriptors WebKit's UA sheet gives each style in the iOS 27.2 runtime.
/// A test that names an S001c case (`scripts/fidelity/fixtures/gaps/S001c-list-markers`
/// in the App repository) checks a value the iOS 27.2 WKWebView drew: the marker's
/// ink width there matched the text expected here. Every other value follows
/// WebKit's code and the specification, unmeasured.
@Suite
struct CounterStyleTests {

    private static func text(_ name: String, _ ordinal: Int) -> String? {
        ListMarkerText(type: .counterStyle(name), ordinal: ordinal)?.string
    }

    private static func texts(_ name: String, _ ordinals: [Int]) -> [String?] {
        ordinals.map { text(name, $0) }
    }

    // MARK: - Measured

    @Test func measuredNumbersAndTheirRangeEdges() {
        // 01-ol-text, 06-value, 06-reversed-start.
        #expect(Self.texts("decimal", [1, 9, 10, 12, 0, -1, -2]) == ["1. ", "9. ", "10. ", "12. ", "0. ", "-1. ", "-2. "])
        // 06-alpha-range: 0 is outside alphabetic's range and falls back to decimal.
        #expect(Self.texts("lower-alpha", [0, 1, 26, 27]) == ["0. ", "a. ", "z. ", "aa. "])
        // 06-roman-range.
        #expect(Self.texts("upper-roman", [3998, 3999, 4000]) == ["MMMCMXCVIII. ", "MMMCMXCIX. ", "4000. "])
        // 06-type-A, 06-type-i.
        #expect(Self.texts("upper-alpha", [1, 2, 23]) == ["A. ", "B. ", "W. "])
        #expect(Self.texts("lower-roman", [1, 2, 4, 8, 9]) == ["i. ", "ii. ", "iv. ", "viii. ", "ix. "])
    }

    @Test func measuredPredefinedStyles() {
        // S001c chapter 3, one row per case.
        #expect(Self.texts("lower-alpha", [1, 2, 13]) == ["a. ", "b. ", "m. "])
        #expect(Self.texts("upper-roman", [1, 14]) == ["I. ", "XIV. "])
        #expect(Self.texts("decimal-leading-zero", [1, 10, 100]) == ["01. ", "10. ", "100. "])
        #expect(Self.texts("cjk-ideographic", [1, 2, 10, 11, 20, 101]) == ["一、", "二、", "十、", "十一、", "二十、", "一百零一、"])
        #expect(Self.texts("trad-chinese-informal", [1, 10, 110]) == ["一、", "十、", "一百一十、"])
        #expect(Self.texts("simp-chinese-informal", [1, 10]) == ["一、", "十、"])
        #expect(Self.texts("cjk-decimal", [1, 10]) == ["一、", "一〇、"])
    }

    @Test func bulletsAreShapesNotText() {
        #expect(ListMarkerText(type: .counterStyle("disc"), ordinal: 1) == .bullet(.disc))
        #expect(ListMarkerText(type: .counterStyle("circle"), ordinal: 2) == .bullet(.circle))
        #expect(ListMarkerText(type: .counterStyle("square"), ordinal: -3) == .bullet(.square))
        #expect(ListMarkerText(type: .counterStyle("disc"), ordinal: 1)?.string == nil)
    }

    @Test func noneHasNoMarker() {
        #expect(ListMarkerText(type: .none, ordinal: 1) == nil)
    }

    @Test func suffixStaysApartFromTheRepresentation() {
        #expect(ListMarkerText(type: .counterStyle("decimal"), ordinal: -7) == .counter(representation: "-7", suffix: ". "))
        #expect(ListMarkerText(type: .counterStyle("cjk-ideographic"), ordinal: 3) == .counter(representation: "三", suffix: "、"))
    }

    // MARK: - Unmeasured: WebKit's code and the specification

    @Test func boundaryValuesForEveryStyle() {
        let values = [0, 1, 9, 10, 11, 19, 20, 101, 3999, 4000, -1]
        #expect(Self.texts("decimal", values)
            == ["0. ", "1. ", "9. ", "10. ", "11. ", "19. ", "20. ", "101. ", "3999. ", "4000. ", "-1. "])
        #expect(Self.texts("lower-latin", values)
            == ["0. ", "a. ", "i. ", "j. ", "k. ", "s. ", "t. ", "cw. ", "ewu. ", "ewv. ", "-1. "])
        #expect(Self.texts("upper-latin", [1, 26, 27, 52, 53, 702, 703])
            == ["A. ", "Z. ", "AA. ", "AZ. ", "BA. ", "ZZ. ", "AAA. "])
        #expect(Self.texts("lower-roman", values)
            == ["0. ", "i. ", "ix. ", "x. ", "xi. ", "xix. ", "xx. ", "ci. ", "mmmcmxcix. ", "4000. ", "-1. "])
        #expect(Self.texts("cjk-decimal", values)
            == ["〇、", "一、", "九、", "一〇、", "一一、", "一九、", "二〇、", "一〇一、", "三九九九、", "四〇〇〇、", "-1、"])
        #expect(Self.texts("trad-chinese-informal", values)
            == ["零、", "一、", "九、", "十、", "十一、", "十九、", "二十、", "一百零一、", "三千九百九十九、", "四千、", "負一、"])
    }

    @Test func chineseLonghandDropsAndCollapsesZeros() {
        #expect(Self.texts("trad-chinese-informal", [100, 105, 1000, 1001, 1010, 1100, 9999])
            == ["一百、", "一百零五、", "一千、", "一千零一、", "一千零一十、", "一千一百、", "九千九百九十九、"])
        // Only 10–19 drop the tens digit; 110 keeps its 一十.
        #expect(Self.texts("trad-chinese-informal", [12, -12, 110, 210]) == ["十二、", "負十二、", "一百一十、", "二百一十、"])
        #expect(Self.texts("simp-chinese-informal", [-1, -12]) == ["负一、", "负十二、"])
    }

    @Test func outOfRangeFallsBackButKeepsItsOwnSuffix() {
        // Only the representation falls back; the marker keeps the style's suffix.
        #expect(Self.text("cjk-decimal", -1) == "-1、")
        // ±9999 is iOS 27.2's range: past it, cjk-decimal; past that, decimal.
        #expect(Self.texts("trad-chinese-informal", [9999, 10000, -9999, -10000])
            == ["九千九百九十九、", "一〇〇〇〇、", "負九千九百九十九、", "-10000、"])
        #expect(Self.texts("simp-chinese-informal", [10000, -10000]) == ["一〇〇〇〇、", "-10000、"])
        #expect(Self.texts("upper-roman", [0, -4]) == ["0. ", "-4. "])
    }

    @Test func leadingZeroPadCountsTheNegativeSign() {
        // WebKit's applyPadSymbols takes the sign out of the pad length.
        #expect(Self.texts("decimal-leading-zero", [0, 5, -1, -5, -10]) == ["00. ", "05. ", "-1. ", "-5. ", "-10. "])
    }

    @Test func aNameWithoutAStyleDrawsAsDecimal() {
        // hiragana is predefined in WebKit but not implemented here; the other
        // names have no style at all. All of them draw as decimal, suffix included.
        #expect(Self.text("hiragana", 3) == "3. ")
        #expect(Self.text("no-such-style", -2) == "-2. ")
        #expect(CounterStyle.predefined["hiragana"] == nil)
    }

    @Test func thirtyTwoBitOrdinalsStayExact() {
        #expect(Self.text("decimal", Int(Int32.max)) == "2147483647. ")
        #expect(Self.text("decimal", Int(Int32.min)) == "-2147483648. ")
        #expect(Self.text("lower-alpha", Int(Int32.max)) == "fxshrxw. ")
    }
}
