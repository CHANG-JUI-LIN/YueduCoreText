import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// CSS logical properties (`margin-inline-start`, `max-inline-size`, …) say the same
/// thing in both writing modes: a stylesheet written once with them is right in
/// horizontal-tb and vertical-rl. The cascade maps each to the physical side the
/// configured writing mode gives it, so precedence against a physical declaration
/// of the same side is plain declaration order.
@Suite @MainActor
struct LogicalPropertyTests {

    // MARK: - Cascade

    private static func paragraphStyle(_ css: String, mode: ReaderWritingMode,
                                       inline: String? = nil) throws -> ComputedStyle {
        let html = inline.map { "<p style=\"\($0)\">x</p>" } ?? "<p>x</p>"
        let document = try SwiftSoup.parse(html)
        var config = BrowserLayoutConfig(rootFontSize: 20)
        config.writingMode = mode
        let tree = ComputedStyleTreeBuilder(rules: CSSParser.parse(css: css), config: config)
            .buildTree(body: try #require(document.body()))
        let node = try #require(tree.children.compactMap { child -> ComputedStyleNode? in
            if case .element(let node) = child, node.tag == "p" { return node }
            return nil
        }.first)
        return node.style
    }

    /// The physical side each logical side lands on.
    private static let sides: [(logical: String, horizontal: KeyPath<ComputedStyle, CSSLength>,
                                vertical: KeyPath<ComputedStyle, CSSLength>)] = [
        ("margin-inline-start", \.marginLeft, \.marginTop),
        ("margin-inline-end", \.marginRight, \.marginBottom),
        ("margin-block-start", \.marginTop, \.marginRight),
        ("margin-block-end", \.marginBottom, \.marginLeft),
        ("padding-inline-start", \.paddingLeft, \.paddingTop),
        ("padding-inline-end", \.paddingRight, \.paddingBottom),
        ("padding-block-start", \.paddingTop, \.paddingRight),
        ("padding-block-end", \.paddingBottom, \.paddingLeft),
    ]

    @Test func everyLogicalSideMapsToItsPhysicalSide() throws {
        for side in Self.sides {
            for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
                let style = try Self.paragraphStyle("p { margin: 0; padding: 0; \(side.logical): 3em }", mode: mode)
                let target = mode == .horizontal ? side.horizontal : side.vertical
                #expect(style[keyPath: target] == .em(3), "\(side.logical) mode=\(mode)")
                // Only that side moves.
                let others = Self.sides.flatMap { [$0.horizontal, $0.vertical] }.filter { $0 != target }
                for other in Set(others) {
                    #expect(style[keyPath: other] == .px(0), "\(side.logical) mode=\(mode) moved another side")
                }
            }
        }
    }

    @Test func inlineSizesMapToWidthOrHeight() throws {
        let horizontal = try Self.paragraphStyle(
            "p { inline-size: 12em; max-inline-size: 10em; min-inline-size: 4em }", mode: .horizontal)
        #expect(horizontal.width == .em(12))
        #expect(horizontal.height == .auto)
        #expect(horizontal.maxWidth == .em(10))
        #expect(horizontal.maxHeight == nil)
        #expect(horizontal.minWidth == .em(4))
        #expect(horizontal.minHeight == nil)

        let vertical = try Self.paragraphStyle(
            "p { inline-size: 12em; max-inline-size: 10em; min-inline-size: 4em }", mode: .verticalRTL)
        #expect(vertical.height == .em(12))
        #expect(vertical.width == .auto)
        #expect(vertical.maxHeight == .em(10))
        #expect(vertical.maxWidth == nil)
        #expect(vertical.minHeight == .em(4))
        #expect(vertical.minWidth == nil)
    }

    @Test func noneAndAutoLiftAnEarlierLimit() throws {
        for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
            let style = try Self.paragraphStyle(
                "p { max-inline-size: 10em; min-inline-size: 4em } p { max-inline-size: none; min-inline-size: auto }",
                mode: mode)
            #expect(style.maxWidth == nil && style.maxHeight == nil, "mode=\(mode)")
            #expect(style.minWidth == nil && style.minHeight == nil, "mode=\(mode)")
            let invalid = try Self.paragraphStyle("p { max-inline-size: 10em } p { max-inline-size: wide }", mode: mode)
            #expect((mode == .horizontal ? invalid.maxWidth : invalid.maxHeight) == .em(10),
                    "an invalid value is dropped, mode=\(mode)")
        }
    }

    @Test func theLaterOfALogicalAndAPhysicalDeclarationWins() throws {
        // Same declaration block: source order.
        let logicalLast = try Self.paragraphStyle("p { margin-left: 1em; margin-inline-start: 2em }", mode: .horizontal)
        #expect(logicalLast.marginLeft == .em(2))
        let physicalLast = try Self.paragraphStyle("p { margin-inline-start: 2em; margin-left: 1em }", mode: .horizontal)
        #expect(physicalLast.marginLeft == .em(1))
        let verticalLogicalLast = try Self.paragraphStyle("p { margin-top: 1em; margin-inline-start: 2em }", mode: .verticalRTL)
        #expect(verticalLogicalLast.marginTop == .em(2))
        let verticalPhysicalLast = try Self.paragraphStyle("p { margin-inline-start: 2em; margin-top: 1em }", mode: .verticalRTL)
        #expect(verticalPhysicalLast.marginTop == .em(1))
        // A shorthand before a logical longhand, and after it.
        let shorthandFirst = try Self.paragraphStyle("p { margin: 0; margin-inline-start: 2em }", mode: .verticalRTL)
        #expect(shorthandFirst.marginTop == .em(2))
        let shorthandLast = try Self.paragraphStyle("p { margin-inline-start: 2em; margin: 0 }", mode: .verticalRTL)
        #expect(shorthandLast.marginTop == .px(0))
        // Across rules: the cascade order (specificity, then source order).
        let laterRule = try Self.paragraphStyle("p { margin-inline-start: 2em } p { margin-left: 1em }", mode: .horizontal)
        #expect(laterRule.marginLeft == .em(1))
        let moreSpecific = try Self.paragraphStyle("body p { margin-inline-start: 2em } p { margin-left: 1em }", mode: .horizontal)
        #expect(moreSpecific.marginLeft == .em(2))
        // Inline style after author rules.
        let inline = try Self.paragraphStyle("p { margin-left: 1em }", mode: .horizontal, inline: "margin-inline-start: 3em")
        #expect(inline.marginLeft == .em(3))
    }

    @Test func theEvaluationCascadesForTheWritingModeItJudges() throws {
        let input = CSSFrontendInput.currentCompatibility(
            html: "<html><body><p>x</p></body></html>", cssTexts: ["p { margin-inline-start: 2em }"])
        let horizontalConfig = BrowserLayoutConfig(rootFontSize: 20)
        let evaluation = try BrowserChapterDocument(input: input)
            .evaluate(configuration: horizontalConfig, writingMode: .verticalRTL)
        #expect(evaluation.configuration.writingMode == .verticalRTL)
        let root = try #require(evaluation.preparedFrontend?.result.rootNode)
        let p = try #require(root.children.compactMap { child -> ComputedStyleNode? in
            if case .element(let node) = child { return node }
            return nil
        }.first)
        #expect(p.style.marginTop == .em(2))
        #expect(p.style.marginLeft == .px(0))
        // A session under the other writing mode needs a new evaluation.
        #expect(!evaluation.accepts(horizontalConfig))
    }

    // MARK: - Admission

    @Test func theScannerAcceptsLogicalPropertiesInBothModes() {
        let css = """
        p { margin-inline-start: 2em; margin-inline-end: 1em; margin-block-start: 1em; margin-block-end: 1em;
            padding-inline-start: 1em; padding-inline-end: 1em; padding-block-start: 1em; padding-block-end: 1em;
            inline-size: 20em; max-inline-size: 10em; min-inline-size: 2em; text-align: end }
        """
        for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
            let result = BrowserLayoutCapabilityScanner.scan(
                html: "<html><body><p>山路を登りながら</p></body></html>", cssTexts: [css], writingMode: mode)
            #expect(result.supported, "mode=\(mode): \(result.unsupportedFeatures)")
        }
    }

    // MARK: - Geometry

    private static let fontSize: CGFloat = 20
    private static let text = String(repeating: "山", count: 30)

    /// The first page and the continuous flow of one paragraph, with the character
    /// rects of each, in physical coordinates.
    private static func layouts(_ css: String, mode: ReaderWritingMode,
                                text: String = text) async throws -> [(name: String, rects: [CGRect])] {
        let config = BrowserLayoutConfig(renderWidth: 300, renderHeight: 300, rootFontSize: fontSize,
                                         fontFamilies: ["HiraginoSans-W3"], writingMode: mode)
        let document = HTMLLayoutDocument(html: "<p>\(text)</p>",
                                          css: ["body { margin: 0 } p { margin: 0; line-height: 1.5 } " + css],
                                          configuration: config)
        #expect(document.capabilities().supported, "mode=\(mode)")
        let session = try document.makePageSession()
        try await session.finish()
        let page = try #require(session.completedPages.first)
        let paged = DisplayListBuilder.build(for: page, sourceText: session.sourceText)
        let flow = try document.prepareContinuous().makeDocument()
        let length = (text as NSString).length
        func rects(_ list: DisplayList) throws -> [CGRect] {
            try (0..<length).map { try #require(list.selectionRects(for: NSRange(location: $0, length: 1)).first) }
        }
        return [("paged", try rects(paged)), ("scroll", try rects(flow.displayList))]
    }

    @Test func marginInlineStartIndentsFromTheInlineStart() async throws {
        for (name, rects) in try await Self.layouts("p { margin-inline-start: 2em }", mode: .horizontal) {
            #expect(abs(rects[0].minX - 2 * Self.fontSize) < 0.5, "\(name): \(rects[0])")
        }
        for (name, rects) in try await Self.layouts("p { margin-inline-start: 2em }", mode: .verticalRTL) {
            #expect(abs(rects[0].minY - 2 * Self.fontSize) < 0.5, "\(name): \(rects[0])")
        }
    }

    @Test func maxInlineSizeWrapsAtTenCharactersInBothModes() async throws {
        for (name, rects) in try await Self.layouts("p { max-inline-size: 10em }", mode: .horizontal) {
            // Characters 0…9 share the first line; character 10 starts the next one.
            #expect(rects[0..<10].allSatisfy { abs($0.minY - rects[0].minY) < 0.5 }, "\(name)")
            #expect(rects[10].minY > rects[9].maxY - 0.5, "\(name)")
            #expect(abs(rects[10].minX - rects[0].minX) < 0.5, "\(name)")
            #expect(rects[9].maxX <= 10 * Self.fontSize + 0.5, "\(name)")
        }
        for (name, rects) in try await Self.layouts("p { max-inline-size: 10em }", mode: .verticalRTL) {
            // Columns run right to left: character 10 starts the next column, to the left.
            #expect(rects[0..<10].allSatisfy { abs($0.minX - rects[0].minX) < 0.5 }, "\(name)")
            #expect(rects[10].maxX < rects[9].minX + 0.5, "\(name)")
            #expect(abs(rects[10].minY - rects[0].minY) < 0.5, "\(name)")
            #expect(rects[9].maxY <= 10 * Self.fontSize + 0.5, "\(name)")
        }
    }

    @Test func minInlineSizeWinsOverMaxInlineSize() async throws {
        for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
            for (name, rects) in try await Self.layouts("p { max-inline-size: 5em; min-inline-size: 10em }", mode: mode) {
                let along = mode == .horizontal ? rects[9].maxX : rects[9].maxY
                let first = mode == .horizontal ? rects[0].minY : rects[0].minX
                let tenth = mode == .horizontal ? rects[9].minY : rects[9].minX
                #expect(abs(first - tenth) < 0.5, "\(name) mode=\(mode): ten characters on the first line")
                #expect(along <= 10 * Self.fontSize + 0.5, "\(name) mode=\(mode)")
            }
        }
    }

    @Test func textAlignEndAlignsToTheInlineEnd() async throws {
        let short = "山路"
        for (name, rects) in try await Self.layouts("p { text-align: end }", mode: .horizontal, text: short) {
            #expect(abs(rects[1].maxX - 300) < 0.5, "\(name): \(rects[1])")
        }
        for (name, rects) in try await Self.layouts("p { text-align: end }", mode: .verticalRTL, text: short) {
            #expect(abs(rects[1].maxY - 300) < 0.5, "\(name): \(rects[1])")
        }
        // With margin-inline-end, the end edge moves in by that margin.
        for (name, rects) in try await Self.layouts("p { text-align: end; margin-inline-end: 3em }",
                                                    mode: .verticalRTL, text: short) {
            #expect(abs(rects[1].maxY - (300 - 3 * Self.fontSize)) < 0.5, "\(name): \(rects[1])")
        }
    }
}
