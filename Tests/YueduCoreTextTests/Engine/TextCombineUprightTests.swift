import CoreText
import Testing
import UIKit
@testable import YueduCoreText
import YueduCoreTextTypography

@Suite("Authored 縦中横") @MainActor
struct TextCombineUprightTests {
    private static let em: CGFloat = 24

    private func layout(_ body: String, css: String = "", vertical: Bool = true) async throws
        -> (list: DisplayList, source: String, supported: Bool) {
        var config = BrowserLayoutConfig()
        config.writingMode = vertical ? .verticalRTL : .horizontal
        config.renderWidth = 240; config.renderHeight = 320
        config.rootFontSize = Self.em
        config.cjkTypographyStyle = .traditional
        let document = HTMLLayoutDocument(html: "<p>\(body)</p>",
            css: ["p{margin:0;line-height:1.75} .tcy{text-combine-upright:all}" + css], configuration: config)
        let supported = document.capabilities().supported
        guard supported else { return (DisplayList(items: []), "", false) }
        let session = try document.makePageSession()
        try await session.finish()
        let first = try #require(session.completedPages.first)
        return (DisplayListBuilder.build(for: first, sourceText: session.sourceText), session.sourceText, true)
    }

    private func texts(_ list: DisplayList) -> [DisplayTextItem] {
        list.items.compactMap { if case .text(let t) = $0 { return t }; return nil }
    }

    @Test("Values parse as CSS Writing Modes defines them")
    func parsing() {
        #expect(TextCombineUpright.parse("all") == .all)
        #expect(TextCombineUpright.parse("none") == TextCombineUpright.none)
        #expect(TextCombineUpright.parse("digits") == .digits(2))
        #expect(TextCombineUpright.parse("digits 4") == .digits(4))
        #expect(!TextCombineUpright.parse("digits 5").isSupported)
        #expect(!TextCombineUpright.parse("all 2").isSupported)
        #expect(TextCombineUpright.parseLegacy("horizontal") == .all)
        let parts = TextCombineUpright.digits(2).segments(of: "第12回と2014年")
        #expect(parts.map(\.text) == ["第", "12", "回と2014年"])
        #expect(parts.map(\.combined) == [false, true, false])
    }

    @Test("「12」 sits in one upright cell, centred on the column, its text kept")
    func oneCell() async throws {
        let (list, source, supported) = try await layout("第<span class='tcy'>12</span>回")
        #expect(supported)
        #expect(source.contains("第12回"))
        let items = texts(list)
        let cell = try #require(items.first { $0.writingMode == .horizontal })
        #expect(cell.text == "12")
        #expect(cell.sourceRange == (source as NSString).range(of: "12"))
        let before = try #require(items.first { $0.writingMode == .verticalRTL && $0.text.hasSuffix("第") })
        let after = try #require(items.first { $0.writingMode == .verticalRTL && $0.text.hasPrefix("回") })
        // Across: centred on the column the ideographs stand in.
        #expect(abs(cell.rect.rawValue.midX - before.rect.rawValue.midX) < 0.5, "cell \(cell.rect.rawValue) column \(before.rect.rawValue)")
        #expect(cell.rect.rawValue.width <= Self.em + 0.01)
        // Along: one em, between its neighbours.
        #expect(abs(cell.rect.rawValue.height - Self.em) < 0.01)
        #expect(abs(cell.rect.rawValue.minY - before.rect.rawValue.maxY) < 0.5 && abs(after.rect.rawValue.minY - cell.rect.rawValue.maxY) < 0.5,
                "before \(before.rect.rawValue) cell \(cell.rect.rawValue) after \(after.rect.rawValue)")
        // Selection and hits reach each digit.
        let one = (source as NSString).range(of: "12").location
        let rect = try #require(list.selectionRects(for: NSRange(location: one, length: 1)).first)
        #expect(cell.rect.rawValue.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        #expect(list.sourceRange(at: CGPoint(x: rect.midX, y: rect.midY), sourceText: source) == NSRange(location: one, length: 1))
    }

    @Test("A wider run is compressed into the cell")
    func compressed() async throws {
        let (list, _, _) = try await layout("第<span class='tcy'>2014</span>年")
        let cell = try #require(texts(list).first { $0.writingMode == .horizontal })
        #expect(cell.text == "2014")
        #expect(cell.rect.rawValue.width <= Self.em + 0.01 && cell.rect.rawValue.width > Self.em * 0.9)
    }

    @Test("`digits 2` combines two-digit runs only")
    func digits() async throws {
        let (list, _, supported) = try await layout("第12回と2014年", css: " p{text-combine-upright:digits 2}")
        #expect(supported)
        let cells = texts(list).filter { $0.writingMode == .horizontal }
        #expect(cells.map(\.text) == ["12"])
    }

    @Test("Ruby with 縦中横 is not laid out here, and horizontal text ignores the property")
    func outsideScope() async throws {
        let (_, _, rubySupported) = try await layout("<ruby class='tcy'>12<rt>じゅうに</rt></ruby>")
        #expect(!rubySupported)
        let (list, _, supported) = try await layout("第<span class='tcy'>12</span>回", vertical: false)
        #expect(supported)
        #expect(texts(list).allSatisfy { $0.writingMode == .horizontal })
        #expect(texts(list).map(\.text).joined().contains("第12回"))
    }
}
