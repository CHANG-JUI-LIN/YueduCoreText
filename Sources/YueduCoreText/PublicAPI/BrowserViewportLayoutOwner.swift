import UIKit

/// Lays out one chapter's viewport session away from the host's main thread.
///
/// Every session operation runs on this actor: creating the session (CSS
/// cascade and box tree), each layout transaction and resource retirement.
/// A host never touches the session; it reads the chapter `facts` and the
/// snapshots these operations return. A scroll callback therefore never lays
/// out — it asks for a region and keeps scrolling with what it has.
public actor BrowserViewportLayoutOwner {
    private let session: BrowserViewportSession
    public nonisolated let facts: BrowserViewportChapterFacts
    /// The snapshot published when the session was created: estimated geometry,
    /// no lines yet.
    public nonisolated let initialSnapshot: BrowserViewportSnapshot

    /// Builds the session on the calling thread; create it from a background task.
    public init(document: sending HTMLLayoutDocument, validateCapabilities: Bool = false) throws {
        let session = try document.makeViewportSession(validateCapabilities: validateCapabilities)
        self.session = session
        facts = session.facts
        initialSnapshot = session.published
    }

    private var mainThreadTransactions = 0

    /// One layout transaction for `bounds` (see `BrowserViewportSession.layout`).
    public func layout(in bounds: CGRect, anchorOffset: Int? = nil) throws -> BrowserViewportSnapshot {
        if Thread.isMainThread { mainThreadTransactions += 1 }
        try session.layout(in: bounds, anchorOffset: anchorOffset)
        return session.published
    }

    /// Drops every retained line and its drawing resources; geometry survives.
    public func discardRenderingResources() -> BrowserViewportSnapshot {
        session.discardRenderingResources()
        return session.published
    }

    public struct Diagnostics: Sendable {
        public let shapedLineCount: Int
        public let measuredLineCount: Int
        public let estimatedBoxCount: Int
        public let retainedLineCount: Int
        public let retainedPaintResourceCount: Int
        public let geometryPassCount: Int
        public let retainedViewportReuseCount: Int
        public let snapshotCount: Int
        /// Evidence for the contract: transactions never run on the main thread.
        public let mainThreadTransactionCount: Int
    }

    public func diagnostics() -> Diagnostics {
        Diagnostics(shapedLineCount: session.shapedLineCount, measuredLineCount: session.measuredLineCount,
                    estimatedBoxCount: session.estimatedBoxCount, retainedLineCount: session.retainedLineCount,
                    retainedPaintResourceCount: session.retainedPaintResourceCount,
                    geometryPassCount: session.geometryPassCount,
                    retainedViewportReuseCount: session.retainedViewportReuseCount,
                    snapshotCount: session.snapshotCount, mainThreadTransactionCount: mainThreadTransactions)
    }
}
