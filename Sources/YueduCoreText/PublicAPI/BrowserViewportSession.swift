import UIKit
import CoreText

/// One continuous document's content and estimated/measured geometry. Unlike a
/// prepared chapter, this session shapes only demanded inline contexts. The
/// caller serializes access and commits viewport geometry as one transaction.
///
/// TextKit 2's viewport/element split informs this API; this is a CoreText
/// implementation, not an NSTextLayoutManager adapter. Cache bounds and CSS
/// dependency handling below are our policies, not claims about TextKit internals.
public final class BrowserViewportSession {
    private let pipeline: BrowserLayoutDocument.BrowserLayoutPipelineResult
    private let config: BrowserLayoutConfig
    private let imageLoader: (String) -> UIImage?
    private let state = BrowserViewportLayoutState()
    public private(set) var geometryPassCount = 0
    public private(set) var retainedViewportReuseCount = 0
    public private(set) var snapshotCount = 0
    public private(set) var lastReuseCandidateCount = 0
    /// Inline boxes of the committed geometry, in `positions.blocks` order;
    /// retained-viewport candidates are looked up by the same ordinals.
    private var positionGeometry: [BrowserViewportLayoutState.Geometry] = []
    private var positions = BrowserViewportPositions.empty
    private var sourceIndex = BrowserViewportIntervalIndex()
    private var indexedGeometryRevision: UInt64 = 0
    private var hasCommittedGeometry = false
    private struct PaintKey: Hashable {
        let line: ObjectIdentifier
        let range: NSRange
        let node: Int
        let text: String
        let font: UIFont
        let color: UIColor
        let mappingKind: Int
        let mappingRange: NSRange

        init?(_ text: DisplayTextItem) {
            guard let line = text.ctLine else { return nil }
            self.line = ObjectIdentifier(line)
            range = text.sourceRange; node = text.nodeID; self.text = text.text
            font = text.font; color = text.color
            switch text.sourceMapping {
            case .linear(let range): mappingKind = 0; mappingRange = range
            case .annotation(let range): mappingKind = 1; mappingRange = range
            case .wholeRange: mappingKind = 2; mappingRange = NSRange(location: 0, length: 0)
            }
        }
    }
    private struct PaintResource {
        // Retain identity until eviction so a newly allocated CTLine cannot
        // accidentally match an old address in the resource map.
        let layoutLine: CTLine
        let drawing: TextDrawingResources
    }
    private var paintResources: [PaintKey: PaintResource] = [:]
    public var retainedPaintResourceCount: Int { paintResources.count }
    /// Published at the end of every transaction. A host that lays out on
    /// another thread reads only this (and `facts`), never the live session.
    public private(set) var published = BrowserViewportSnapshot.empty
    public let facts: BrowserViewportChapterFacts
    public private(set) var document: BrowserScrollDocument = .empty
    public private(set) var materializedBounds = CGRect.null
    public var sourceText: String { facts.sourceText }
    public var anchorOffsets: [String: Int] { facts.anchorOffsets }
    public var footnotes: [String: String] { facts.footnotes }
    public var pronunciationHints: [TTSPronunciationHint] { facts.pronunciationHints }
    public var mediaAttachments: [Int: EPUBMediaAttachment] { facts.mediaAttachments }
    public var paragraphRanges: [NSRange] { facts.paragraphRanges }
    public var backgroundImageSource: String? { facts.backgroundImageSource }
    public var shapedLineCount: Int { state.shapedLineCount }
    /// Updated at the resource commit boundary. Hosts query this every scroll
    /// tick for offscreen chapters, including chapters whose resources are gone.
    public private(set) var retainedLineCount: Int = 0
    public var measuredLineCount: Int { state.measuredLineCount }
    public var estimatedBoxCount: Int { state.estimatedBoxCount }

    init(pipeline: BrowserLayoutDocument.BrowserLayoutPipelineResult, configuration: BrowserLayoutConfig,
         imageLoader: @escaping (String) -> UIImage?) {
        self.pipeline = pipeline; config = configuration; self.imageLoader = imageLoader
        facts = BrowserViewportChapterFacts(sourceText: pipeline.sourceText, anchorOffsets: pipeline.anchorOffsets,
            footnotes: pipeline.footnotes, pronunciationHints: pipeline.pronunciationHints,
            mediaAttachments: pipeline.mediaAttachments,
            paragraphRanges: BrowserLayoutSemanticContent.paragraphRanges(in: pipeline.rootBox),
            pageBackground: BrowserPageBackground(BrowserLayoutDocument.bodyBackground(rootBox: pipeline.rootBox)))
        resolveGeometry()
        updatePositionIndex()
        document = snapshot()
        hasCommittedGeometry = true
        publish()
    }

    /// Resolve geometry without imposing the paged engine's image-fitting rules.
    private func resolveGeometry() {
        geometryPassCount += 1
        let trace = ReaderPerfTrace.begin(.viewportGeometry, metadata: .init(generation: geometryPassCount))
        defer { ReaderPerfTrace.end(trace) }
        _ = BlockLayout.layOut(root: pipeline.rootBox, containerWidth: config.renderWidth,
            rootFontSize: config.rootFontSize, sourceText: pipeline.sourceText,
            fontResolver: config.fontResolver, viewport: state)
        state.updateGeometry(root: pipeline.rootBox, origin: CGPoint(x: config.contentInsets.left, y: config.contentInsets.top))
    }

    private func updatePositionIndex() {
        // Rebuild only after geometry changes, never on each scroll callback.
        // Keep dictionary iteration order so overlap/equidistance ties preserve
        // the existing source-position semantics.
        positionGeometry = state.geometry.values.filter { !$0.box.inlineRuns.isEmpty }
        positions = BrowserViewportPositions(blocks: positionGeometry.map(liveBlock))
        sourceIndex.update(positionGeometry.map {
            CGFloat($0.range.location)...CGFloat(NSMaxRange($0.range))
        })
        indexedGeometryRevision = state.geometryRevision
    }

    /// One inline box as positions read it: its origin and range with the entry
    /// values as they are now.
    private func liveBlock(_ geometry: BrowserViewportLayoutState.Geometry) -> BrowserViewportPositions.Block {
        let entry = state.entries[ObjectIdentifier(geometry.box)]
        return .init(originY: geometry.origin.y, range: geometry.range, height: entry?.height,
                     lines: entry?.geometry ?? [])
    }

    /// The transaction boundary: everything a host may read, as one value.
    private func publish() {
        published = BrowserViewportSnapshot(document: document, materializedBounds: materializedBounds,
                                            retainedLineCount: retainedLineCount, positions: positions)
    }

    /// The returned document carries whole-document source coordinates and
    /// estimated size, but only the demanded region's text drawing resources.
    /// `anchorOffset` identifies a source character, never a global page index.
    @discardableResult
    public func layout(in bounds: CGRect, anchorOffset: Int? = nil) throws -> BrowserScrollDocument {
        var geometryResolved = false
        // Cancellation/convergence failures can also leave retained line work.
        // Keep the residency snapshot accurate on every exit, not only success.
        defer {
            retainedLineCount = state.retainedLineCount
            // Intermediate convergence passes use documentY, not sourceOffset.
            // Index only the committed geometry, including failure exits.
            if geometryResolved { updatePositionIndex() }
            publish()
        }
        if Task.isCancelled { throw HTMLLayoutError.cancelled }
        let anchor = anchorOffset.map { min(max(0, $0), (sourceText as NSString).length) }
        var demand = bounds
        state.targetOffset = anchor
        // Estimate corrections can expose another paragraph at the trailing
        // edge. Continue until the complete demand has stable geometry; never
        // publish the intermediate estimates as if their text were available.
        var passes = 0
        let reuseTrace = ReaderPerfTrace.begin(.viewportReuse, metadata: .init(generation: geometryPassCount))
        var candidateIndices = Set(positions.index.intersecting(demand.minY...demand.maxY))
        if let anchor { candidateIndices.formUnion(sourceIndex.intersecting(CGFloat(anchor)...CGFloat(anchor))) }
        lastReuseCandidateCount = candidateIndices.count
        let reused = hasCommittedGeometry && state.restoreRetainedViewport(in: demand, anchor: anchor,
            candidates: candidateIndices.sorted().map { positionGeometry[$0] }, indexedRevision: indexedGeometryRevision)
        ReaderPerfTrace.end(reuseTrace, metadata: .init(elementCount: lastReuseCandidateCount, cacheResult: reused ? "hit" : "miss"))
        hasCommittedGeometry = false
        if reused { retainedViewportReuseCount += 1 }
        while !reused {
            if Task.isCancelled { throw HTMLLayoutError.cancelled }
            let oldY = anchor.map { liveDocumentY(for: $0) }
            let before = state.revision
            state.viewport = demand
            geometryResolved = true
            resolveGeometry()
            if let anchor, let oldY {
                demand.origin.y += liveDocumentY(for: anchor) - oldY
            }
            passes += 1
            if before == state.revision && abs(demand.minY - state.viewport.minY) < 0.01 { break }
            guard passes < 64 else { throw HTMLLayoutError.layoutFailure("viewport geometry did not converge") }
        }
        materializedBounds = demand
        // Hysteresis retains more than the demanded paint window so a quick
        // reversal reuses resources. Offscreen geometry/checkpoints stay small.
        // Resource residency must not shrink with the immediate paint demand.
        // Keep a bounded reversal window comparable to the former ~8-screen
        // demand; otherwise right-sizing layout evicts lines just before the
        // reader reverses into them. This retains measured lines, never shapes
        // the retention window or preloads additional paragraphs.
        let retentionMargin = max(demand.height, max(1, config.renderHeight) * 8)
        ReaderPerfTrace.span(.viewportTrim) {
            state.trim(to: demand.insetBy(dx: 0, dy: -retentionMargin))
        }
        document = snapshot()
        hasCommittedGeometry = true
        return document
    }

    public func discardRenderingResources() {
        let trace = ReaderPerfTrace.begin(.viewportRetirement, metadata: .init(elementCount: retainedLineCount))
        defer { ReaderPerfTrace.end(trace) }
        state.trim(to: .null)
        retainedLineCount = 0
        materializedBounds = .null
        // Retirement changes ownership, not document geometry. Walking the
        // entire chapter and rebuilding a display list here delayed a scroll
        // callback even though this chapter had just left the retention window.
        paintResources.removeAll()
        document = BrowserScrollDocument(displayList: DisplayList(items: document.displayList.items.filter {
            if case .text = $0 { return false }
            return true
        }), contentHeight: document.contentHeight, sourceText: document.sourceText,
            anchorOffsets: document.anchorOffsets, linkAnchors: document.linkAnchors,
            contentWidth: document.contentWidth)
        publish()
    }

    /// Committed geometry, as published (see `BrowserViewportSnapshot`).
    public func documentY(for offset: Int) -> CGFloat { published.documentY(for: offset) }

    public func sourceOffset(at y: CGFloat) -> Int { published.sourceOffset(at: y) }

    /// The same query against the geometry of the pass in progress, for
    /// convergence inside a transaction.
    private func liveDocumentY(for offset: Int) -> CGFloat {
        BrowserViewportPositions.documentY(for: offset,
            in: state.geometry.values.lazy.filter { !$0.box.inlineRuns.isEmpty }.map(liveBlock)) {
            document.documentY(forCharOffset: offset)
        }
    }

    private func snapshot() -> BrowserScrollDocument {
        snapshotCount += 1
        let trace = ReaderPerfTrace.begin(.layoutDisplayList, metadata: .init(resourceID: "viewport.snapshot", generation: snapshotCount))
        defer { ReaderPerfTrace.end(trace) }
        let prepared = BrowserContinuousLayout(pipeline: pipeline, configuration: config, imageLoader: imageLoader)
        // Line geometry persists when the corresponding CTLine is discarded.
        // Compute the same painted bottom used by BrowserScrollDocument.make,
        // including estimated inline extents but excluding paragraph trailing spacing.
        var bottom: CGFloat = 0
        for g in state.geometry.values where !g.box.inlineRuns.isEmpty {
            if let entry = state.entries[ObjectIdentifier(g.box)] {
                bottom = max(bottom, g.origin.y + entry.height + config.contentInsets.bottom)
            }
        }
        let withBackground = prepared.makeDocument(estimatedContentHeight: bottom, paintsPageBackground: false)
        ReaderPerfTrace.span(.viewportPaintEviction, metadata: .init(elementCount: paintResources.count)) {
            let retained = state.retainedDrawingLineIDs
            // Keep surviving entries in place. Dictionary.filter rehashed every
            // UIFont/string key on every boundary, including a warm reverse scroll.
            let expired = paintResources.keys.filter { !retained.contains($0.line) }
            for key in expired { paintResources.removeValue(forKey: key) }
        }
        let items = withBackground.displayList.items.map { item -> DisplayItem in
            guard case .text(var text) = item else { return item }
            if let key = PaintKey(text), let line = text.ctLine {
                if let resource = paintResources[key] {
                    text.preparedDrawing = resource.drawing
                } else {
                    let drawing = TextDrawingResources(text)
                    paintResources[key] = PaintResource(layoutLine: line, drawing: drawing)
                    text.preparedDrawing = drawing
                }
            } else {
                text.preparedDrawing = TextDrawingResources(text)
            }
            return .text(text)
        }
        return BrowserScrollDocument(displayList: DisplayList(items: items), contentHeight: max(bottom, withBackground.contentHeight),
            sourceText: sourceText, anchorOffsets: anchorOffsets, linkAnchors: pipeline.linkAnchors,
            contentWidth: withBackground.contentWidth)
    }
}

extension HTMLLayoutDocument {
    /// Content preparation builds the CSS/semantic tree once, without shaping
    /// the chapter. Horizontal continuous hosts demand layout through this session.
    public func makeViewportSession(validateCapabilities: Bool = true) throws -> BrowserViewportSession {
        try makeViewportSessionImpl(validateCapabilities: validateCapabilities)
    }
}
