import Testing
@testable import YueduCoreText

/// A chapter in which some list item would draw an inside marker goes to the
/// legacy engine (design §4): judged on computed values, never on what a
/// stylesheet merely says. Outside markers, in either writing mode, stay.
@Suite
struct ListMarkerAdmissionTests {

    private static func reasons(_ body: String, css: String = "",
                                writingMode: ReaderWritingMode = .horizontal) -> [UnsupportedFeature] {
        BrowserLayoutCapabilityScanner.scan(html: "<html><head></head><body>\(body)</body></html>",
                                            cssTexts: [css], writingMode: writingMode).unsupportedFeatures
    }

    private static let list = "<ol><li>一。</li><li>二。</li></ol>"

    @Test func outsideMarkersAreAdmittedInBothWritingModes() {
        for mode in ReaderWritingMode.allCases {
            #expect(Self.reasons(Self.list, writingMode: mode).isEmpty, "\(mode)")
            #expect(Self.reasons("<ul><li>圓點。</li></ul>", css: "ul { list-style: square outside }", writingMode: mode).isEmpty)
        }
    }

    @Test func anInsideMarkerSendsTheChapterToTheLegacyEngine() {
        let cases: [(body: String, css: String)] = [
            (Self.list, "ol { list-style-position: inside }"),
            // The shorthand resets the type to disc: a visible marker.
            (Self.list, "ol { list-style: inside }"),
            // Inherited from far above the list.
            (Self.list, "body { list-style-position: inside }"),
            (Self.list.replacingOccurrences(of: "<li>二", with: "<li style=\"list-style-position: inside\">二"), ""),
            // Any list item, not only li.
            ("<div style=\"display: list-item; list-style-position: inside\">項目。</div>", ""),
            // A name with no definition still draws, as decimal.
            (Self.list, "ol { list-style: hiragana inside }"),
        ]
        for mode in ReaderWritingMode.allCases {
            for (body, css) in cases {
                #expect(Self.reasons(body, css: css, writingMode: mode) == [.listMarker], "\(mode) \(body) \(css)")
            }
        }
        #expect(UnsupportedFeature.listMarker.description == "list-marker")
    }

    @Test func insideWithNoVisibleMarkerIsAdmitted() {
        let cases: [(body: String, css: String)] = [
            // No marker to draw.
            (Self.list, "ol { list-style: none inside }"),
            (Self.list, "ol { list-style-position: inside; list-style-type: none }"),
            // Declared, then overridden: the computed value is outside.
            (Self.list, "ol { list-style-position: inside } li { list-style-position: outside }"),
            // Inside, but nothing is a list item.
            ("<p>段落。</p>", "body { list-style-position: inside }"),
            ("<ol style=\"list-style-position: inside\"><li style=\"display: block\">一。</li></ol>", ""),
            // Hidden lists draw nothing.
            ("<ol style=\"display: none; list-style-position: inside\"><li>一。</li></ol>", ""),
            ("<ol hidden style=\"list-style-position: inside\"><li>一。</li></ol>", ""),
        ]
        for (body, css) in cases {
            #expect(Self.reasons(body, css: css).isEmpty, "\(body) \(css)")
        }
    }
}
