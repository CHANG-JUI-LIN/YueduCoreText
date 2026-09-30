import Testing
import YueduCoreText

@Suite("Browser font demand public API")
struct BrowserFontDemandAPITests {
    @Test func existingScannerFunctionSignatureRemainsCallable() {
        let scan: (CSSFrontendInput, ReaderWritingMode) -> BrowserLayoutCapabilityResult =
            BrowserLayoutCapabilityScanner.scan(input:writingMode:)
        let input = CSSFrontendInput.currentCompatibility(
            html: "<p>Text</p>", cssTexts: ["body { font-family: Primary }"])
        let result = scan(input, .horizontal)
        #expect(result.supported)
        #expect(result.fontRequests.contains(BrowserFontRequest(family: "primary", weight: 400, italic: false)))
        #expect(BrowserLayoutCapabilityResult(supported: true, unsupportedFeatures: []).fontRequests.isEmpty)
    }

    @Test func demandUsesMatchedStylesAndEffectiveReaderBold() {
        let input = CSSFrontendInput.currentCompatibility(
            html: "<p>A<em>B</em><ruby>C<rt>D</rt></ruby></p><p hidden>Hidden</p>",
            cssTexts: ["""
            body { font-family: Primary, Fallback }
            p::first-letter { font-family: Initial }
            rt { font-family: Ruby }
            [hidden] { display: none; font-family: Hidden }
            .unmatched { font-family: Unused }
            """])
        let regular = BrowserLayoutCapabilityScanner.scan(input: input)
        let bold = BrowserLayoutCapabilityScanner.scan(
            input: input, configuration: BrowserLayoutConfig(isBold: true))
        #expect(regular.supported && bold.supported)
        #expect(regular.fontRequests.contains(BrowserFontRequest(family: "primary", weight: 400, italic: true)))
        #expect(Set(regular.fontRequests.map(\.family)) == ["primary", "fallback", "initial", "ruby"])
        #expect(bold.fontRequests == Set(regular.fontRequests.map {
            BrowserFontRequest(family: $0.family, weight: max(700, $0.weight), italic: $0.italic)
        }))
    }
}
