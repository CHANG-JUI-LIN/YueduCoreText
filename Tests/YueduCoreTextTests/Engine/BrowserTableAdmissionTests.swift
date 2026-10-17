import Foundation
import Testing

@testable import YueduCoreText

/// Table admission (TableSupport): the supported subset renders through the
/// engine; anything outside it keeps the chapter on the webview path.
struct BrowserTableAdmissionTests {

    private func scan(_ html: String, css: [String] = [], writingMode: ReaderWritingMode = .horizontal)
        -> BrowserLayoutCapabilityResult
    {
        BrowserLayoutCapabilityScanner.scan(html: html, cssTexts: css, writingMode: writingMode)
    }

    private let simpleTable = """
        <html><body><table>
        <thead><tr><th>H1</th><th>H2</th></tr></thead>
        <tbody><tr><td>A</td><td>B</td></tr></tbody>
        <tfoot><tr><td colspan="2">F</td></tr></tfoot>
        </table></body></html>
        """

    @Test func basicTableIsSupported() {
        let result = scan(simpleTable)
        #expect(result.supported)
        #expect(result.unsupportedFeatures.isEmpty)
    }

    @Test func bareRowsAreSupported() {
        let result = scan("<html><body><table><tr><td>A</td></tr></table></body></html>")
        #expect(result.supported)
    }

    @Test func displayTableOnDivIsSupported() {
        let result = scan(
            "<html><body><div class=\"t\"><div class=\"r\"><div class=\"c\">A</div></div></div></body></html>",
            css: [".t { display: table } .r { display: table-row } .c { display: table-cell }"]
        )
        #expect(result.supported)
    }

    @Test func cellTextIndentIsSupported() {
        let result = scan(
            "<html><body><table><tr><td class=\"i\">A</td></tr></table></body></html>",
            css: [".i { text-indent: 1em; text-align: left; }"]
        )
        #expect(result.supported)
    }

    @Test func rowspanIsRejected() {
        let result = scan("<html><body><table><tr><td rowspan=\"2\">A</td></tr></table></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func colspanZeroIsRejected() {
        let result = scan("<html><body><table><tr><td colspan=\"0\">A</td></tr></table></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func nestedTableIsRejected() {
        let result = scan(
            "<html><body><table><tr><td><table><tr><td>N</td></tr></table></td></tr></table></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func borderCollapseIsRejected() {
        let result = scan(simpleTable, css: ["table { border-collapse: collapse }"])
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func fosterParentedTextIsRejected() {
        let result = scan("<html><body><table>stray<tr><td>A</td></tr></table></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func captionIsRejected() {
        let result = scan("<html><body><table><caption>C</caption><tr><td>A</td></tr></table></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func colgroupIsRejected() {
        let result = scan("<html><body><table><colgroup><col/></colgroup><tr><td>A</td></tr></table></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func inlineTableIsRejected() {
        let result = scan(
            "<html><body><div class=\"t\"><span>x</span></div></body></html>",
            css: [".t { display: inline-table }"]
        )
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func strayCellOutsideTableIsRejected() {
        let result = scan("<html><body><div style=\"display: table-cell\">x</div></body></html>")
        #expect(!result.supported)
        #expect(result.unsupportedFeatures.contains(.table))
    }

    @Test func elementInsideRowGroupIsFosteredOutByTheParser() {
        // HTML5 tree construction foster-parents non-row elements out of a row
        // group before the cascade ever runs, exactly like a browser — the
        // style tree only ever holds conforming structure, so this is supported.
        let result = scan("<html><body><table><tbody><div>x</div></tbody></table></body></html>")
        #expect(result.supported)
    }

    @Test func verticalWritingModeRejectsTables() {
        let result = scan(simpleTable, writingMode: .verticalRTL)
        #expect(!result.supported)
    }
}
