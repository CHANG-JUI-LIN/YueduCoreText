import Testing
import UIKit
@testable import YueduCoreText

/// CSS 2.1 §9.2.1.1: a block inside an inline box splits the inline box.
/// The block is laid out as a block, and the inline content on each side of
/// it closes into an anonymous block, all in document order. The engine used
/// to drop the block and everything in it, so a chat bubble written as
/// `<span><p>…</p></span>` lost its whole message.
struct BrowserBlockInInlineTests {

    private struct Layout {
        let text: String
        let rects: [String: CGRect]
        let fills: [CGRect]
        let anchors: [String: Int]
        let source: NSString
    }

    private static func fills(_ fragments: [Fragment], into out: inout [CGRect]) {
        for fragment in fragments {
            switch fragment {
            case .fill(let fill): out.append(fill.rect.rawValue)
            case .group(let children): fills(children, into: &out)
            default: break
            }
        }
    }

    private static func layout(_ body: String) async throws -> Layout {
        let html = """
            <body style="margin:0;font-size:10px;line-height:1">\(body)</body>
            """
        let (pages, doc) = try await BrowserLayoutTestSupport.layout(
            html, cssTexts: [], width: 300, height: 800, rootFontSize: 10)
        let source = doc.lastSourceText as NSString
        var rects: [String: CGRect] = [:]
        for fragment in BrowserLayoutTestSupport.allTextFragments(pages) {
            guard case .linear = fragment.sourceMapping, fragment.sourceRange.length > 0,
                NSMaxRange(fragment.sourceRange) <= source.length
            else { continue }
            let word = source.substring(with: fragment.sourceRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rects[word] = fragment.rect.rawValue
        }
        var fills: [CGRect] = []
        for page in pages { Self.fills(page.fragments, into: &fills) }
        let text = BrowserLayoutTestSupport.visibleText(pages, sourceText: doc.lastSourceText)
        return Layout(
            text: text.filter { !$0.isWhitespace }, rects: rects, fills: fills,
            anchors: doc.lastAnchorOffsets, source: source)
    }

    @Test func blockInsideSpanKeepsEveryWordInOrder() async throws {
        let result = try await Self.layout("<div><span>before<div>inside</div>after</span></div>")
        #expect(result.text == "beforeinsideafter")
        let before = try #require(result.rects["before"])
        let inside = try #require(result.rects["inside"])
        let after = try #require(result.rects["after"])
        #expect(before.maxY <= inside.minY + 0.01)
        #expect(inside.maxY <= after.minY + 0.01)
    }

    /// Every inline ancestor splits, not just the nearest one: the text after
    /// the block shares a line with the outer span's own tail.
    @Test func blockInsideNestedInlinesSplitsEveryLevel() async throws {
        let result = try await Self.layout(
            "<div><span><b>one<div>two</div>three</b>four</span></div>")
        #expect(result.text == "onetwothreefour")
        let one = try #require(result.rects["one"])
        let two = try #require(result.rects["two"])
        let three = try #require(result.rects["three"])
        let four = try #require(result.rects["four"])
        #expect(one.maxY <= two.minY + 0.01)
        #expect(two.maxY <= three.minY + 0.01)
        #expect(abs(three.minY - four.minY) < 0.01)
        #expect(three.maxX <= four.minX + 0.01)
    }

    @Test func blockAtEitherEndOfSpanIsKept() async throws {
        let first = try await Self.layout("<div><span><div>first</div>tail</span></div>")
        #expect(first.text == "firsttail")
        let firstRect = try #require(first.rects["first"])
        let tail = try #require(first.rects["tail"])
        #expect(firstRect.maxY <= tail.minY + 0.01)

        let last = try await Self.layout("<div><span>head<div>last</div></span></div>")
        #expect(last.text == "headlast")
        let head = try #require(last.rects["head"])
        let lastRect = try #require(last.rects["last"])
        #expect(head.maxY <= lastRect.minY + 0.01)
    }

    /// The split pieces keep the inline box's padding, but only the first
    /// piece opens the box and only the last closes it.
    @Test func splitSpanPadsOnlyItsOuterEdges() async throws {
        let result = try await Self.layout(
            "<div><span style=\"padding:0 20px\">before<div>inside</div>after</span></div>")
        #expect(result.text == "beforeinsideafter")
        let before = try #require(result.rects["before"])
        let inside = try #require(result.rects["inside"])
        let after = try #require(result.rects["after"])
        #expect(abs(before.minX - 20) < 0.01)
        #expect(abs(inside.minX) < 0.01)
        #expect(abs(after.minX) < 0.01)
    }

    /// A float is out of flow and never splits an inline box. One nested in a
    /// span stays inline text on the paragraph's line, as it was before blocks
    /// in inline content were split out.
    @Test func floatNestedInSpanKeepsTheLine() async throws {
        let result = try await Self.layout(
            "<div>text <span><span style=\"float:right\">x</span></span> more</div>")
        #expect(result.text == "textxmore")
        let text = try #require(result.rects["text"])
        let more = try #require(result.rects["more"])
        #expect(abs(text.minY - more.minY) < 0.01)
    }

    /// The chat-bubble shape: an inline-block holding a paragraph, with
    /// whitespace around it. Splitting it must not leave an empty bubble above
    /// or below the message.
    @Test func inlineBlockHoldingABlockDrawsNoEmptyPieces() async throws {
        let result = try await Self.layout("""
            <div><div style="display:inline-block;background-color:#ccc;\
            padding:0 10px;border:1px solid #eee">
            <p style="margin:0">msg</p>
            </div></div>
            """)
        #expect(result.text == "msg")
        let msg = try #require(result.rects["msg"])
        #expect(msg.minY < 0.01)
        #expect(!result.fills.contains { $0.maxY <= msg.minY + 0.01 || $0.minY >= msg.maxY - 0.01 })
    }

    /// An id on the split inline box resolves to where its content starts,
    /// even when that content is the block.
    @Test func anchorOnSplitSpanResolvesToTheBlock() async throws {
        let result = try await Self.layout(
            "<div><span id=\"note\"><div>inside</div></span>tail</div>")
        #expect(result.text == "insidetail")
        let offset = try #require(result.anchors["note"])
        #expect(result.source.range(of: "inside").location == offset)
    }
}
