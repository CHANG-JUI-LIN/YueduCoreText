import UIKit

/// A chapter's content facts that no layout transaction changes. Taken once
/// when the viewport session is created, on whichever thread creates it.
public struct BrowserViewportChapterFacts: @unchecked Sendable {
    public let sourceText: String
    public let anchorOffsets: [String: Int]
    public let footnotes: [String: String]
    public let pronunciationHints: [TTSPronunciationHint]
    public let mediaAttachments: [Int: EPUBMediaAttachment]
    public let paragraphRanges: [NSRange]
    /// Not part of the published documents: the host draws it (see the type).
    public let pageBackground: BrowserPageBackground?
    public var backgroundImageSource: String? { pageBackground?.imageSource }
}

/// What a host reads between layout transactions: the published document and
/// the committed geometry it was laid out with. A value — it stays valid while
/// the session goes on laying out, on this thread or another.
///
/// The document's text lines were created by the transaction that published it
/// and are not used by the session afterwards; the host owns them from here.
public struct BrowserViewportSnapshot: @unchecked Sendable {
    public let document: BrowserScrollDocument
    /// Region whose lines are laid out; `.null` before the first transaction.
    public let materializedBounds: CGRect
    /// Lines resident after the transaction, for residency decisions.
    public let retainedLineCount: Int
    let positions: BrowserViewportPositions

    static let empty = BrowserViewportSnapshot(document: .empty, materializedBounds: .null,
                                               retainedLineCount: 0, positions: .empty)

    /// Document y of a source offset under the committed geometry.
    public func documentY(for offset: Int) -> CGFloat {
        BrowserViewportPositions.documentY(for: offset, in: positions.blocks) {
            document.documentY(forCharOffset: offset)
        }
    }

    /// Source offset at a document y under the committed geometry.
    public func sourceOffset(at y: CGFloat) -> Int { positions.sourceOffset(at: y) }
}

/// Committed source ↔ document-y geometry: every inline box, in the order the
/// session indexes them, with the lines measured so far.
struct BrowserViewportPositions {
    struct Block {
        let originY: CGFloat
        let range: NSRange
        /// nil while the box has no layout entry yet.
        let height: CGFloat?
        let lines: [BrowserViewportLayoutState.LineGeometry]
    }
    let blocks: [Block]
    /// Over each block's `originY...originY + height`.
    let index: BrowserViewportIntervalIndex

    static let empty = BrowserViewportPositions(blocks: [])

    init(blocks: [Block]) {
        self.blocks = blocks
        index = BrowserViewportIntervalIndex(blocks.map { $0.originY...($0.originY + max(0, $0.height ?? 0)) })
    }

    /// The one implementation, used for committed snapshots and for the live
    /// geometry of convergence passes inside a transaction.
    static func documentY<Blocks: Sequence>(for offset: Int, in blocks: Blocks,
                                            fallback: () -> CGFloat) -> CGFloat where Blocks.Element == Block {
        // Source ranges are half-open. At a paragraph boundary the offset
        // belongs to the next paragraph, not the previous paragraph's end.
        // Mixing both made dictionary iteration/range length choose an anchor
        // on the wrong side of the collapsed margin (a visible 12pt jump).
        var containing: Block?
        var ending: Block?
        for block in blocks {
            if NSLocationInRange(offset, block.range) {
                if containing == nil || block.range.length < containing!.range.length { containing = block }
            } else if offset == NSMaxRange(block.range) {
                if ending == nil || block.range.length < ending!.range.length { ending = block }
            }
        }
        guard let g = containing ?? ending, let height = g.height else { return fallback() }
        if let line = g.lines.first(where: { NSLocationInRange(offset, $0.source) || $0.source.location >= offset }) {
            return g.originY + line.start.y
        }
        let fraction = CGFloat(max(0, offset - g.range.location)) / CGFloat(max(1, g.range.length))
        return g.originY + fraction * height
    }

    func sourceOffset(at y: CGFloat) -> Int {
        guard let nearest = index.nearest(to: y) else { return 0 }
        let g = blocks[nearest]
        // Preserve the existing zero-height candidate and unresolved result
        // when the nearest inline box does not yet have a layout entry.
        guard let height = g.height else { return 0 }
        if let line = g.lines.first(where: { $0.end.y + g.originY >= y }) { return line.source.location }
        let fraction = min(1, max(0, (y - g.originY) / max(1, height)))
        return g.range.location + Int(fraction * CGFloat(g.range.length))
    }
}
