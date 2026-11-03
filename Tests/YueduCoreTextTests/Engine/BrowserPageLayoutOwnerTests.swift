import Testing
import UIKit
@testable import YueduCoreText

/// The paged layout owner: the same pages as a session, laid out off the main
/// thread, and a cancelled layout that stops part-way instead of finishing first.
@MainActor
struct BrowserPageLayoutOwnerTests {

    private nonisolated static func config() -> BrowserLayoutConfig {
        BrowserLayoutConfig(
            renderWidth: 300, renderHeight: 160, rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white
        )
    }

    private nonisolated static func html(paragraphs: Int) -> String {
        let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 6)
        let body = (0..<paragraphs).map { "<p id=\"p\($0)\">\($0) \(paragraph)</p>" }.joined()
        return "<html><body>\(body)</body></html>"
    }

    private nonisolated static func evaluation(_ html: String) throws -> BrowserChapterEvaluation {
        try BrowserChapterDocument(input: .currentCompatibility(html: html, cssTexts: []))
            .evaluate(configuration: config())
    }

    @Test func ownerPagesMatchSessionPages() async throws {
        let html = Self.html(paragraphs: 20)
        let session = try BrowserLayoutSession(evaluation: Self.evaluation(html), imageLoader: { _ in nil }, generation: 0)
        try await session.finish()
        let expected = session.completedPages

        let owner = try BrowserPageLayoutOwner(evaluation: Self.evaluation(html), imageLoader: { _ in nil }, generation: 0)
        let facts = try await owner.prepare()
        let first = try #require(try await owner.layoutNextPage())
        let pages = try await owner.finish()

        #expect(facts.sourceText == session.sourceText)
        #expect(facts.anchorOffsets == session.anchorOffsets)
        #expect(facts.paragraphRanges == session.pipelineParagraphRanges)
        #expect(first.index == 0)
        #expect(pages.count == expected.count)
        #expect(pages.count >= 2)
        for (page, other) in zip(pages, expected) {
            #expect(page.index == other.index)
            #expect(page.fragments.count == other.fragments.count)
            for (a, b) in zip(page.fragments, other.fragments) {
                switch (a, b) {
                case (.text(let a), .text(let b)):
                    #expect(a.sourceRange == b.sourceRange)
                    #expect(a.rect == b.rect)
                    #expect(a.baselineY == b.baselineY)
                case (.fill(let a), .fill(let b)):
                    #expect(a.rect == b.rect)
                case (.image(let a), .image(let b)):
                    #expect(a.rect == b.rect)
                default:
                    Issue.record("page \(page.index): fragment kinds differ")
                }
            }
        }
    }

    /// Called from the main actor, every step still runs on the owner.
    @Test func stepsNeverRunOnTheMainThread() async throws {
        let owner = try BrowserPageLayoutOwner(evaluation: Self.evaluation(Self.html(paragraphs: 20)),
                                               imageLoader: { _ in nil }, generation: 0)
        _ = try await owner.prepare()
        _ = try await owner.layoutNextPage()
        _ = try await owner.layout(untilSourceOffset: 400)
        _ = try await owner.finish()
        #expect(await owner.mainThreadStepCount() == 0)
    }

    @Test func cancelledOwnerThrowsCancelled() async throws {
        let owner = try BrowserPageLayoutOwner(evaluation: Self.evaluation(Self.html(paragraphs: 20)),
                                               imageLoader: { _ in nil }, generation: 0)
        _ = try await owner.prepare()
        owner.cancel()
        await #expect(throws: HTMLLayoutError.self) { try await owner.layoutNextPage() }
    }

    /// Block layout in a cancelled task stops at the next block when its caller will
    /// discard the tree, and only then.
    @Test func cancelledLayoutStopsPartWayOnlyWhenTheCallerOptsIn() async throws {
        func laidOutLines(cancelled: Bool, abandons: Bool) async -> Int {
            await Task.detached {
                if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
                let document = BrowserLayoutDocument(input: .currentCompatibility(html: Self.html(paragraphs: 30), cssTexts: []),
                                                     config: Self.config())
                guard let result = try? LayoutAbandonment.$whenCancelled.withValue(abandons, operation: {
                    try document.makeLayout(containerSize: CGSize(width: 300, height: 160), fragmentHeight: 160)
                }) else { return -1 }
                func count(_ box: BlockBox) -> Int { box.lines.count + box.children.reduce(0) { $0 + count($1) } }
                return count(result.rootBox)
            }.value
        }
        let complete = await laidOutLines(cancelled: false, abandons: true)
        #expect(complete > 30)
        #expect(await laidOutLines(cancelled: true, abandons: false) == complete)
        #expect(await laidOutLines(cancelled: true, abandons: true) < complete)
    }

    /// A session whose layout was abandoned reports the cancellation and pages nothing.
    @Test func cancelledPrepareEndsTheSession() async throws {
        let html = Self.html(paragraphs: 30)
        let outcome: String = await Task.detached {
            let session: BrowserLayoutSession
            do {
                session = try BrowserLayoutSession(evaluation: Self.evaluation(html), imageLoader: { _ in nil }, generation: 0)
            } catch { return "init failed" }
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try session.prepare(); return "prepared" } catch HTMLLayoutError.cancelled {} catch { return "\(error)" }
            return session.completedPages.isEmpty ? "cancelled" : "paged"
        }.value
        #expect(outcome == "cancelled")
    }
}
