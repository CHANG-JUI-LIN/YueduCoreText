import os
import UIKit

/// Lays out one paged chapter away from the host's main thread.
///
/// Every session step runs on this actor: the chapter pipeline (box tree and
/// block layout, the expensive part: seconds for a chapter of a few MB) and
/// each page. A host never touches the session; it reads the chapter facts
/// `prepare()` returns and the pages the other steps return.
///
/// Cancelling the task that awaits a step stops it: a page step at its next
/// page, `prepare()` at its next block, and the owner is finished from then on.
/// `cancel()` does the same for a step running in a task the host does not hold.
public actor BrowserPageLayoutOwner {
    private let session: BrowserLayoutSession
    public nonisolated let generation: Int
    private let cancelled: OSAllocatedUnfairLock<Bool>
    private var mainThreadSteps = 0

    /// Stores the evaluation; nothing is laid out until `prepare()`.
    public init(
        evaluation: sending BrowserChapterEvaluation,
        configuration: sending BrowserLayoutConfig? = nil,
        imageLoader: @escaping @Sendable (String) -> UIImage?,
        generation: Int,
        diagnosticSpine: Int = -1
    ) throws {
        let session = try BrowserLayoutSession(
            evaluation: evaluation, configuration: configuration,
            imageLoader: imageLoader, generation: generation
        )
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        session.cancellationSignal = { cancelled.withLock { $0 } }
        session.diagnosticSpine = diagnosticSpine
        self.session = session
        self.cancelled = cancelled
        self.generation = generation
    }

    /// Builds the chapter pipeline without laying out a page (see
    /// `BrowserLayoutSession.prepare()`), and returns the chapter's facts.
    public func prepare() throws -> BrowserPageChapterFacts {
        noteThread()
        let backgroundImageSource = try session.prepare()
        return BrowserPageChapterFacts(
            backgroundImageSource: backgroundImageSource,
            sourceText: session.sourceText,
            pictureOffsets: session.pictureOffsets,
            anchorOffsets: session.anchorOffsets,
            footnotes: session.pipelineFootnotes,
            linkAnchors: session.pipelineLinkAnchors,
            mediaAttachments: session.pipelineMediaAttachments,
            pronunciationHints: session.pipelinePronunciationHints,
            paragraphRanges: session.pipelineParagraphRanges,
            nodeCount: session.pipelineNodeCount,
            boxCount: session.pipelineBoxCount
        )
    }

    /// The next page, or nil when the chapter is exhausted.
    public func layoutNextPage() throws -> PageFragments? {
        noteThread()
        return try session.nextPage()
    }

    /// Lays out pages until the one containing `offset` is complete; returns every
    /// page completed so far.
    public func layout(untilSourceOffset offset: Int) throws -> [PageFragments] {
        noteThread()
        try session.layoutPages(untilSourceOffset: offset)
        return session.completedPages
    }

    /// Lays out every remaining page; returns all of the chapter's pages.
    public func finish() throws -> [PageFragments] {
        noteThread()
        try session.finishPages()
        return session.completedPages
    }

    /// Stops the owner's current and future steps. Safe from any thread.
    public nonisolated func cancel() {
        cancelled.withLock { $0 = true }
    }

    /// Evidence for the contract: steps never run on the main thread.
    public func mainThreadStepCount() -> Int { mainThreadSteps }

    private func noteThread() {
        if Thread.isMainThread { mainThreadSteps += 1 }
    }
}

/// A paged chapter's content facts, taken once by `BrowserPageLayoutOwner.prepare()`.
/// Plain values: no page step changes them.
public struct BrowserPageChapterFacts: @unchecked Sendable {
    /// The authored root background-image source; the host loads it before paint.
    public let backgroundImageSource: String?
    public let sourceText: String
    /// The pictures' characters in `sourceText`, and the map for offsets saved before 0.11.
    public let pictureOffsets: BrowserPictureOffsets
    public let anchorOffsets: [String: Int]
    /// 多看 popup footnotes (`noteID → text`).
    public let footnotes: [String: String]
    /// nodeID → owning `<a href>`.
    public let linkAnchors: [Int: LinkAnchorInfo]
    public let mediaAttachments: [Int: EPUBMediaAttachment]
    public let pronunciationHints: [TTSPronunciationHint]
    public let paragraphRanges: [NSRange]
    /// Lifecycle accounting: style-tree and box-tree sizes.
    public let nodeCount: Int
    public let boxCount: Int
}

/// A finished page is a value: every fragment is immutable (`let` all the way down),
/// and the objects it holds (CTLine, UIFont, UIColor, UIImage) are immutable and safe
/// to read from any thread. The layout that made it never touches it again, so it
/// may cross from the layout owner to the thread that draws it.
extension PageFragments: @unchecked Sendable {}

/// Layout that a cancelled caller is about to discard may stop part-way.
///
/// Within `withValue(true)`, block layout stops laying out children once the
/// current task is cancelled, leaving the tree incomplete. Only a caller that
/// checks for cancellation after the layout returns, and then drops the tree,
/// may opt in. Elsewhere (the scroll viewport's geometry passes, batch
/// pagination) layout still runs to completion.
enum LayoutAbandonment {
    @TaskLocal static var whenCancelled = false
}
