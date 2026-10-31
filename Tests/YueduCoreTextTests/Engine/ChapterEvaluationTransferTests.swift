import Foundation
import Testing
import UIKit
import YueduCoreText

/// A chapter's document and evaluation are not Sendable; they move between isolation
/// domains as `sending` values. These tests move them across threads and lay out from
/// them there. The compiler checks every transfer (this target builds in the Swift 6
/// language mode); the tests check that a moved evaluation lays out exactly what one
/// made and used on a single thread does.
@Suite("Chapter evaluation transfer")
struct ChapterEvaluationTransferTests {

    private static let input = CSSFrontendInput.currentCompatibility(html: """
        <html><head><style>p { margin: 0 0 1em; text-indent: 2em } .note { font-size: 0.8em }</style></head>
        <body style="zy-fontsize-adjust: fixed"><h1 id="top">Title</h1>
        <p>First paragraph with <em>emphasis</em> and a <a href="#n1">link</a>.</p>
        <p class="note">Second paragraph.</p><aside epub:type="footnote" id="n1">Note body</aside></body></html>
        """, cssTexts: [])

    private static var configuration: BrowserLayoutConfig {
        var config = BrowserLayoutConfig(renderWidth: 366, renderHeight: 776, rootFontSize: 19,
                                         fontFamilies: ["PingFangSC-Regular"], textColor: .darkGray,
                                         backgroundColor: .white)
        config.lineHeight = 1.5
        return config
    }

    /// What a layout produced, as values a task can hand back.
    private struct Layout: Equatable, Sendable {
        let sourceText: String
        let contentHeight: CGFloat
        let itemCount: Int
        let onMainThread: Bool
    }

    private static func layOut(_ evaluation: BrowserChapterEvaluation) throws -> Layout {
        let document = try HTMLLayoutDocument(evaluation: evaluation)
            .prepareContinuous(validateCapabilities: false).makeDocument()
        return Layout(sourceText: document.sourceText, contentHeight: document.contentHeight,
                      itemCount: document.displayList.items.count, onMainThread: pthread_main_np() != 0)
    }

    /// The layout of an evaluation made and used on the main thread.
    @MainActor
    private static func reference() throws -> Layout {
        try layOut(BrowserChapterDocument(input: input).evaluate(configuration: configuration))
    }

    @MainActor @Test func evaluationMadeOnTheMainThreadIsUsedOnAnother() async throws {
        let expected = try Self.reference()
        #expect(expected.onMainThread && expected.itemCount > 0)

        let evaluation = try BrowserChapterDocument(input: Self.input).evaluate(configuration: Self.configuration)
        // The task takes the evaluation; the main actor never touches it again.
        let moved = try await Task.detached {
            var wider = Self.configuration
            wider.renderHeight = 900
            let rebound = try #require(evaluation.rebound(to: wider))
            return try Self.layOut(rebound)
        }.value

        #expect(!moved.onMainThread)
        #expect(moved.sourceText == expected.sourceText)
        #expect(moved.contentHeight == expected.contentHeight)
        #expect(moved.itemCount == expected.itemCount)
    }

    @MainActor @Test func evaluationMadeOffTheMainThreadIsUsedOnIt() async throws {
        let expected = try Self.reference()

        let document = try await BrowserChapterDocument.parse(input: Self.input)
        #expect(document.bodyInlineStyle == "zy-fontsize-adjust: fixed")
        let evaluation = await BrowserChapterDocument.evaluate(document, configuration: Self.configuration)
        #expect(evaluation.capabilities.supported)
        #expect(evaluation.document.input.html == Self.input.html)

        #expect(try Self.layOut(evaluation) == expected)
    }

    @MainActor @Test func evaluationMovesBackAndForthBetweenThreads() async throws {
        // Made off the main actor, checked on it as a host would, then off it again for layout.
        let document = try await BrowserChapterDocument.parse(input: Self.input)
        let evaluation = await BrowserChapterDocument.evaluate(document, configuration: Self.configuration)

        // Read into locals: `#expect` wraps its argument in a closure, which would
        // capture the evaluation into the main actor's region.
        let onMainThread = pthread_main_np() != 0
        let accepted = evaluation.accepts(Self.configuration)
        #expect(onMainThread && accepted)

        let laidOut = try await Task.detached { try Self.layOut(evaluation) }.value
        let expected = try Self.reference()

        #expect(!laidOut.onMainThread)
        #expect(laidOut.sourceText == expected.sourceText)
        #expect(laidOut.itemCount == expected.itemCount)
    }
}
