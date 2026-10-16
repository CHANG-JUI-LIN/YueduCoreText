import CoreGraphics
import CoreText
import Foundation
import UIKit

public enum TextSourceMapping: Equatable {
    /// Source and shaped UTF-16 coordinates advance together within the line.
    case linear(shapedRange: NSRange)
    /// The rendered text has no source span of its own and maps to the entire
    /// owning range (horizontal Ruby annotation → Ruby base).
    case wholeRange
    /// One styled annotation slice, still mapped atomically to the owning base.
    case annotation(shapedRange: NSRange)
}

/// A paint-time 2D transform (CSS `transform`), applied at draw time only.
/// Layout, pagination and hit-testing all use the untransformed rects; only
/// drawing concatenates it. Carriers hold it in their own coordinate space:
/// steps in document coordinates, fragments/items in page-canvas coordinates.
public struct PaintTransform: Equatable, Sendable {
    public let matrix: CGAffineTransform

    public init(matrix: CGAffineTransform) {
        self.matrix = matrix
    }

    /// Rotate `degrees` about `center` — the shape CSS `rotate()` produces.
    public init(rotatingDegrees degrees: CGFloat, about center: CGPoint) {
        // CGAffineTransform.concatenating applies the RECEIVER first: the
        // pivot chain reads translate(-c) → rotate → translate(+c).
        matrix = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// The receiver applied first, then `other` — parent transforms compose
    /// outside their descendant's.
    public func concatenating(_ other: PaintTransform) -> PaintTransform {
        PaintTransform(matrix: matrix.concatenating(other.matrix))
    }

    /// The transform after the carrier moved by (dx, dy) in its own space —
    /// a change of basis, not a pre-multiplied translation: the rotated box
    /// lands exactly (dx, dy) away from where it was.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> PaintTransform {
        rebased(by: CGPoint(x: dx, y: dy))
    }

    /// The same transform expressed for a carrier translated by `t`
    /// (document → page-canvas coordinates).
    public func rebased(by t: CGPoint) -> PaintTransform {
        PaintTransform(
            matrix: CGAffineTransform(translationX: -t.x, y: -t.y)
                .concatenating(matrix)
                .concatenating(CGAffineTransform(translationX: t.x, y: t.y))
        )
    }

    public static func == (lhs: PaintTransform, rhs: PaintTransform) -> Bool {
        lhs.matrix == rhs.matrix
    }
}

/// Page-local fragment: `rect` is PAGE CANVAS-local (viewport coordinates,
/// origin = viewport top-left). Selection/annotation additionally keeps the
/// DOCUMENT-absolute rect so ranges stay meaningful across pages/relayouts.
public struct TextFragment {
    public let sourceRange: NSRange
    public let nodeID: Int
    public let linkTarget: String?
    public let writingMode: ReaderWritingMode
    /// Page canvas-local rect (Phase 2C contract: `PageLocalRect`).
    public let rect: PageLocalRect
    /// Document-absolute rect (for cross-page selection mapping).
    public let documentRect: DocumentRect
    public let baselineY: CGFloat
    public let font: UIFont
    public let color: UIColor
    /// The shaped line this fragment's run belongs to (full, untrimmed line
    /// range), for precise string-index → typographic-offset mapping.
    public let ctLine: CTLine?
    public let sourceMapping: TextSourceMapping
    public let renderedTextOverride: String?
    /// Authored 縦中横: horizontal text in one upright cell of a vertical line. The
    /// walker emits it in the line's canonical axes; `LogicalFlow.page` keeps it
    /// horizontal and centres it in the cell.
    var isCombinedUpright = false
    var paintTransform: PaintTransform? = nil

    public init(
        sourceRange: NSRange,
        nodeID: Int,
        linkTarget: String?,
        writingMode: ReaderWritingMode,
        rect: PageLocalRect,
        documentRect: DocumentRect,
        baselineY: CGFloat,
        font: UIFont,
        color: UIColor,
        ctLine: CTLine?,
        sourceMapping: TextSourceMapping? = nil,
        renderedTextOverride: String? = nil
    ) {
        self.sourceRange = sourceRange
        self.nodeID = nodeID
        self.linkTarget = linkTarget
        self.writingMode = writingMode
        self.rect = rect
        self.documentRect = documentRect
        self.baselineY = baselineY
        self.font = font
        self.color = color
        self.ctLine = ctLine
        self.sourceMapping = sourceMapping ?? .linear(shapedRange: sourceRange)
        self.renderedTextOverride = renderedTextOverride
    }
}

/// Physical position of one fragment of a CSS border box under the engine's
/// `box-decoration-break: slice` policy.
public enum BlockDecorationFragmentPosition: Equatable {
    case single
    case first
    case middle
    case last
}

/// A filled/bordered box fragment in page canvas-local coordinates.
public struct FillFragment {
    public let rect: PageLocalRect
    public let documentRect: DocumentRect
    public let color: UIColor
    public let cornerRadius: CGFloat
    /// Full four-edge border (Phase 2C: dotted must render all four sides).
    public let borderTop: BorderEdge
    public let borderBottom: BorderEdge
    public let borderLeft: BorderEdge
    public let borderRight: BorderEdge
    public let nodeID: Int
    public let writingMode: ReaderWritingMode
    public let fragmentPosition: BlockDecorationFragmentPosition
    /// Walker-private identity used to replace a provisional fragment once the
    /// box end is known. It never participates in layout, paint, or hit-test.
    public let decorationID: Int
    /// True for the injected page-canvas fill that carries the document's own
    /// `background-color`. Paired with the `isBackgroundPaint` image fragment:
    /// together they ARE the authored page surface, which a reader-chosen
    /// background image replaces outright (`CoreTextPageView` resolves the same
    /// precedence as `readerBackgroundImage ?? pageBackgroundImage`).
    public let isBackgroundPaint: Bool

    public init(
        rect: PageLocalRect,
        documentRect: DocumentRect,
        color: UIColor,
        cornerRadius: CGFloat,
        borderTop: BorderEdge,
        borderBottom: BorderEdge,
        borderLeft: BorderEdge,
        borderRight: BorderEdge,
        nodeID: Int,
        writingMode: ReaderWritingMode,
        fragmentPosition: BlockDecorationFragmentPosition = .single,
        decorationID: Int = -1,
        isBackgroundPaint: Bool = false
    ) {
        self.rect = rect
        self.documentRect = documentRect
        self.color = color
        self.cornerRadius = cornerRadius
        self.borderTop = borderTop
        self.borderBottom = borderBottom
        self.borderLeft = borderLeft
        self.borderRight = borderRight
        self.nodeID = nodeID
        self.writingMode = writingMode
        self.fragmentPosition = fragmentPosition
        self.decorationID = decorationID
        self.isBackgroundPaint = isBackgroundPaint
    }

    var paintTransform: PaintTransform? = nil
}

public struct ImageFragment {
    public let source: String
    public let image: UIImage?
    public let sourceRange: NSRange
    public let nodeID: Int
    public let linkTarget: String?
    public let writingMode: ReaderWritingMode
    public let rect: PageLocalRect
    public let documentRect: DocumentRect
    public let alt: String?
    /// True for a CSS `background-image` painted across the page canvas.
    ///
    /// A CSS background is PAINT, not content: in a browser it has no element,
    /// so it never hit-tests, cannot be opened, and never swallows a click.
    /// The injected canvas fragment covers the whole page, so without this flag
    /// it captured every tap on the page — the reader's page-turn/menu zones
    /// stopped firing and tapping anywhere opened a full-screen preview of the
    /// wallpaper, while real `<img>` illustrations underneath became untappable.
    public let isBackgroundPaint: Bool

    public init(
        source: String,
        image: UIImage?,
        sourceRange: NSRange,
        nodeID: Int,
        linkTarget: String?,
        writingMode: ReaderWritingMode,
        rect: PageLocalRect,
        documentRect: DocumentRect,
        alt: String?,
        isBackgroundPaint: Bool = false
    ) {
        self.source = source
        self.image = image
        self.sourceRange = sourceRange
        self.nodeID = nodeID
        self.linkTarget = linkTarget
        self.writingMode = writingMode
        self.rect = rect
        self.documentRect = documentRect
        self.alt = alt
        self.isBackgroundPaint = isBackgroundPaint
    }

    var paintTransform: PaintTransform? = nil
}

public indirect enum Fragment {
    case text(TextFragment)
    case fill(FillFragment)
    case image(ImageFragment)
    case group([Fragment])
}

public struct PageFragments {
    public init(index: Int, pageRect: PageLocalRect, fragments: [Fragment]) { self.index = index; self.pageRect = pageRect; self.fragments = fragments }
    public let index: Int
    /// The page canvas rect = the actual page viewport (Phase 2C).
    public let pageRect: PageLocalRect
    public let fragments: [Fragment]
}

/// Resumable page fragmentation. Walks the laid-out block tree with an
/// EXPLICIT stack (boxes + per-box child/line/run indices) so the walk can be
/// paused after every emitted fragment and resumed later — this is the single
/// source of truth for BOTH batch pagination (`fragment(box:pageSize:)`) and
/// incremental layout (`BrowserLayoutSession`): identical geometry by
/// construction.
///
/// Coordinate contract (Phase 2C):
/// - `Step` rects are DOCUMENT-absolute (relative to the root content origin).
/// - `place*` maps document → page canvas-local (subtract page block offset,
///   add `contentInsets`) so fragments land inside the real viewport.
/// - `PageFragments.pageRect` is the full viewport canvas, never the content
///   bounds — the canvas height never shrinks to the chapter's content height.
struct PageWalker {

    /// Document-space step emitted by `nextStep` (BEFORE paging).
    enum Step {
        case inlineLineStart(StepInlineLineStart)
        case floatBoundary(StepFloat)
        case fill(StepFill)
        case fillEnd(StepFillEnd)
        case text(StepText)
        case ruby(StepRuby)
        case image(StepImage)
    }

    struct StepInlineLineStart {
        let placementRect: DocumentRect
        let fills: [StepFill]
        /// The line box this step belongs to; see `lineSerialCounter`.
        var lineSerial: Int? = nil
    }

    struct StepFloat {
        let marginRect: DocumentRect
        let nodeID: Int
        let isReplaced: Bool
    }

    struct StepText {
        let sourceRange: NSRange
        let nodeID: Int
        let linkTarget: String?
        let writingMode: ReaderWritingMode
        let rect: DocumentRect
        let baselineY: CGFloat
        let font: UIFont
        let color: UIColor
        let ctLine: CTLine?
        let sourceMapping: TextSourceMapping
        let renderedTextOverride: String?
        var isCombinedUpright = false
        var lineSerial: Int? = nil
        /// Rotation about the owning box's center, in DOCUMENT coordinates.
        var rotation: PaintTransform? = nil
    }

    struct StepRuby {
        let placementRect: DocumentRect
        let baseBaselineY: CGFloat
        let ruby: RubyBox
        let originX: CGFloat
        let writingMode: ReaderWritingMode
        var lineSerial: Int? = nil
        var rotation: PaintTransform? = nil
    }

    struct StepFill {
        let rect: DocumentRect
        let color: UIColor
        let cornerRadius: CGFloat
        let borderTop: BorderEdge
        let borderBottom: BorderEdge
        let borderLeft: BorderEdge
        let borderRight: BorderEdge
        let nodeID: Int
        let writingMode: ReaderWritingMode
        var rotation: PaintTransform? = nil
    }

    struct StepFillEnd {
        let nodeID: Int
        let originalEndY: CGFloat
    }

    struct StepImage {
        let source: String
        let image: UIImage?
        let sourceRange: NSRange
        let nodeID: Int
        let linkTarget: String?
        let writingMode: ReaderWritingMode
        let rect: DocumentRect
        let alt: String?
        /// Block extent of the image's line box below the image itself — the
        /// parent strut's descent (CSS 2.1 §10.8.1) plus any Reader line
        /// spacing. Zero for block images, and for an inline image that does
        /// not end its line, whose remaining runs still sit on this line.
        var trailingLineExtent: CGFloat = 0
        /// The line box an inline image sits on, or the block image's own line.
        var lineSerial: Int? = nil
        var rotation: PaintTransform? = nil
    }

    private struct BoxFrame {
        let box: BlockBox
        let contentOrigin: CGPoint
        let borderX: CGFloat
        let borderY: CGFloat
        /// The composed transform of the nearest transformed ancestor chain,
        /// in DOCUMENT coordinates.
        let rotation: PaintTransform?
        var childIndex = 0
        var lineIndex = 0
        var runIndex = 0
        var inlineDecorationsEmitted = false
        var fillsEmitted = false
        var decorationStarted = false
        var decorationEndEmitted = false
        var imageEmitted = false
        var floatBoundaryEmitted = false
        /// The root (html/body) frame. Its background belongs to the CANVAS,
        /// not to the box — see the paint guard in `nextStep`.
        var isRoot = false
    }

    /// Page block extent in DOCUMENT space (the content flow page height).
    let pageHeight: CGFloat
    /// The fragmentainer has NO bottom: the whole chapter is one continuous
    /// flow (scroll mode).
    ///
    /// Not "a page tall enough to never break". A height large enough today is
    /// still a height, and the first chapter that exceeds it silently paginates
    /// — which is exactly how this went wrong: bounding the fragmentainer by the
    /// laid-out content height was short by the root's block-start margin, so
    /// the tail of every chapter wrapped back to the top. Scroll mode has no
    /// page, so the paging rules are SKIPPED rather than given a number.
    let isContinuous: Bool
    /// The page canvas rect (full viewport).
    let pageRect: PageLocalRect
    /// Reader page margins: content sits inside these within the canvas.
    let contentInsets: UIEdgeInsets
    let writingMode: ReaderWritingMode
    private var stack: [BoxFrame] = []
    private(set) var currentIndex = 0
    private(set) var currentPage: [Fragment] = []
    private(set) var completedPages: [PageFragments] = []
    /// Accumulated block-axis displacement for content not yet placed.
    ///
    /// Pagination relocates a fragment that would straddle a page boundary to
    /// the next page top, and scales a replaced element that exceeds a whole
    /// page. Both change how much block space the fragment actually consumes,
    /// so everything AFTER it in document order must move by the same amount —
    /// otherwise the relocated fragment paints over its own following content
    /// (a 627.2pt gallery image landing on the caption of its own cell) or
    /// leaves a blank page behind (flow reserved 627.2pt, page consumed 400pt).
    /// One shift for every step kind: never a per-kind nudge.
    private var flowShift: CGFloat = 0

    /// Decorations stay active until their owning box exits. Content may add a
    /// pagination displacement after the box start, so the final block-end is
    /// only known at that exit. Earlier pages can still be finalized safely:
    /// an active slice always reaches that fragmentainer's block-end.
    private struct ActiveDecoration {
        let id: Int
        let step: StepFill
        let startY: CGFloat
    }
    private var activeDecorations: [ActiveDecoration] = []
    private var nextDecorationID = 0

    /// How the in-progress fragmentainer was entered — the input to the CSS
    /// Fragmentation §4.2 margin rule.
    ///
    /// - `flowStart`: the first page. Not a break, so its leading margin is
    ///   retained (a body `margin-top` still shows above the first line).
    /// - `unforcedBreak`: pagination ran out of room. The block-start margin
    ///   adjoining the break is discarded.
    /// - `forcedBreak`: an author break (`break-before`/`page-break-before`).
    ///   The margin AFTER the break is retained.
    ///
    /// The engine does not parse `break-before`/`break-after` yet, so nothing
    /// produces `forcedBreak` today. The case is modeled rather than assumed so
    /// that adding forced breaks cannot silently start eating their margins.
    private enum FragmentainerEntry {
        case flowStart
        case unforcedBreak
        case forcedBreak
    }
    private var pageEntry: FragmentainerEntry = .flowStart

    /// 底部對齊 (legado `textBottomJustify`): when a page ends because the next
    /// text line no longer fits, the leftover space below its last line is spread
    /// evenly over its line gaps so the last line sits on the content bottom.
    let bottomJustify: Bool
    /// Identity of every line box (and every block image, which stands alone in
    /// the flow) in walk order. Fragments carry it so a finished page can be
    /// regrouped into its lines: runs of one line are separate fragments.
    private var lineSerialCounter = 0
    private var currentLineSerial = 0
    private var blockImageLineSerials: Set<Int> = []
    /// `currentPage[i]`'s line, or nil for a block decoration, which spans lines.
    private var currentPageLineSerials: [Int?] = []

    /// Block-start margin adjoining the next content to be placed: the sum of
    /// the block-start margins of the boxes entered since the last emitted
    /// fragment, seeded with the root's own (collapsed) block-start margin.
    ///
    /// Only margins are accumulated — border and padding are deliberately
    /// excluded, because only margins are discardable at a break. Where a
    /// sibling margin collapsed to the PREVIOUS box's larger block-end margin,
    /// this under-counts, which is the safe direction: it can leave a gap but
    /// never eats a box's border or padding.
    private var adjoiningBlockStartMargin: CGFloat
    /// Defensive step budget: a corrupted box tree must never hang pagination
    /// forever. Each `nextStep` consumes one; exceeding the budget throws.
    private var stepBudget = 0
    static let maxWalkerSteps = 2_000_000

    init(
        box: BlockBox,
        pageSize: CGSize,
        writingMode: ReaderWritingMode = .horizontal,
        contentInsets: UIEdgeInsets = .zero,
        isContinuous: Bool = false,
        bottomJustify: Bool = false
    ) {
        // Phase 2C: the canvas is the actual page viewport, not the content
        // bounds. pageHeight (the paging stride in document space) is the
        // content flow height inside the canvas.
        self.isContinuous = isContinuous
        // A scroll column has no page bottom. The paged callers walk in logical
        // coordinates, so they decide the writing mode (`BrowserLayoutConfig`).
        self.bottomJustify = bottomJustify && !isContinuous
        self.pageHeight = max(1, pageSize.height - contentInsets.top - contentInsets.bottom)
        self.pageRect = PageLocalRect(rawValue: CGRect(origin: .zero, size: pageSize))
        self.contentInsets = contentInsets
        self.writingMode = writingMode
        // The root box's own block-start margin (which carries any folded
        // first-child margin from `BlockLayout` margin collapsing) pushes its
        // content down — the root frame origin is fixed at (0,0).
        let rootBlockStartInset: CGFloat
        switch writingMode {
        case .horizontal: rootBlockStartInset = box.margins.top
        case .verticalRTL: rootBlockStartInset = box.margins.right
        }
        // The root's block-start margin is the margin adjoining the first
        // content; page 0 is `flowStart`, so it is retained there.
        self.adjoiningBlockStartMargin = rootBlockStartInset
        // `BlockLayout` resolves the root content width after subtracting its
        // physical left/right margin, border and padding. Fragmentation must
        // place that already-resolved content box at the matching physical
        // inline origin; starting it at x=0 moved every left-side root inset
        // to the right edge instead. Reader contentInsets are added later by
        // `canvasRect`, so authored body geometry remains inside (and does not
        // replace) the reader's symmetric page viewport policy.
        let rootContentOriginX: CGFloat
        switch writingMode {
        case .horizontal:
            rootContentOriginX = box.margins.left + box.borders.left + box.padding.left
        case .verticalRTL:
            // Vertical root inline geometry is outside this horizontal
            // correctness phase; preserve its established coordinate contract.
            rootContentOriginX = 0
        }
        var rootFrame = Self.makeFrame(
            box,
            contentOrigin: CGPoint(x: rootContentOriginX, y: rootBlockStartInset)
        )
        rootFrame.isRoot = true
        self.stack = [rootFrame]
    }

    /// Maps a document-absolute rect to page canvas-local coordinates for page
    /// `pageIndex`: subtract the page block offset, add the content insets so
    /// content lands inside the viewport margins.
    func canvasRect(forDocument doc: DocumentRect, pageIndex: Int) -> PageLocalRect {
        PageLocalRect(rawValue: CGRect(
            x: doc.minX + contentInsets.left,
            y: doc.minY - CGFloat(pageIndex) * pageHeight + contentInsets.top,
            width: doc.width,
            height: doc.height
        ))
    }

    /// Emits the next fragment step in document order, or nil when the walk
    /// is exhausted.
    mutating func nextStep() -> Step? {
        stepBudget += 1
        if stepBudget > Self.maxWalkerSteps {
            assertionFailure("PageWalker exceeded step budget \(Self.maxWalkerSteps) — corrupted box tree?")
            return nil
        }
        #if DEBUG
        if stepBudget % 100_000 == 0 {
            BrowserLayoutDeviceDiagnostic.summary("🔬 BROWSER_DEVICE walkerProgress steps=\(stepBudget) stack=\(stack.count) page=\(currentIndex) fragments=\(currentPage.count) topTag=\(stack.last?.box.debugTag ?? "-")")
        }
        #endif
        while !stack.isEmpty {
            let index = stack.count - 1
            if stack[index].box.isFloated, !stack[index].floatBoundaryEmitted {
                stack[index].floatBoundaryEmitted = true
                let frame = stack[index]
                let borderRect = CGRect(
                    x: frame.borderX,
                    y: frame.borderY,
                    width: frame.box.frame.width,
                    height: frame.box.frame.height
                )
                return .floatBoundary(StepFloat(
                    marginRect: DocumentRect(rawValue: CGRect(
                        x: borderRect.minX - frame.box.margins.left,
                        y: borderRect.minY - frame.box.margins.top,
                        width: borderRect.width + frame.box.margins.horizontal,
                        height: borderRect.height + frame.box.margins.vertical
                    )),
                    nodeID: frame.box.debugNodeID,
                    isReplaced: frame.box.imageAttachment != nil
                ))
            }
            if !stack[index].fillsEmitted {
                stack[index].fillsEmitted = true
                let frame = stack[index]
                let boxRect = DocumentRect(rawValue: CGRect(
                    x: frame.borderX, y: frame.borderY,
                    width: frame.box.frame.width, height: frame.box.frame.height
                ))
                // CSS Backgrounds §2.11.2: the ROOT element's background is
                // propagated to the canvas and the root box does NOT paint it
                // again. `BrowserLayoutDocument.bodyBackground` already hoists
                // body's colour + image to the page canvas, UNDER the wallpaper.
                // Painting it here too laid an OPAQUE `background-color: #fff`
                // band back over that wallpaper — the content-column-wide white
                // stripe across title pages, sized to the body's
                // content box (which is why the correctly centred 15em dotted
                // frame sat inside a much wider white plate).
                //
                // Root BORDERS are not propagated, so those still paint below.
                if let bg = frame.box.style.backgroundColor, !frame.isRoot {
                    stack[index].decorationStarted = true
                    return .fill(StepFill(
                        rect: boxRect,
                        color: bg,
                        cornerRadius: frame.box.style.borderRadius,
                        borderTop: Self.edge(frame.box.borders.top, frame.box.style.borderTopStyle, frame.box.style.borderColor),
                        borderBottom: Self.edge(frame.box.borders.bottom, frame.box.style.borderBottomStyle, frame.box.style.borderColor),
                        borderLeft: Self.edge(frame.box.borders.left, frame.box.style.borderLeftStyle, frame.box.style.borderColor),
                        borderRight: Self.edge(frame.box.borders.right, frame.box.style.borderRightStyle, frame.box.style.borderColor),
                        nodeID: frame.box.debugNodeID,
                        writingMode: writingMode,
                        rotation: frame.rotation
                    ))
                }
                // A box with a border but no background still emits its full
                // bordered rect.
                let hasAnyBorder = frame.box.borders.top > 0 || frame.box.borders.bottom > 0
                    || frame.box.borders.left > 0 || frame.box.borders.right > 0
                if hasAnyBorder {
                    stack[index].decorationStarted = true
                    return .fill(StepFill(
                        rect: boxRect,
                        color: .clear,
                        cornerRadius: frame.box.style.borderRadius,
                        borderTop: Self.edge(frame.box.borders.top, frame.box.style.borderTopStyle, frame.box.style.borderColor),
                        borderBottom: Self.edge(frame.box.borders.bottom, frame.box.style.borderBottomStyle, frame.box.style.borderColor),
                        borderLeft: Self.edge(frame.box.borders.left, frame.box.style.borderLeftStyle, frame.box.style.borderColor),
                        borderRight: Self.edge(frame.box.borders.right, frame.box.style.borderRightStyle, frame.box.style.borderColor),
                        nodeID: frame.box.debugNodeID,
                        writingMode: writingMode,
                        rotation: frame.rotation
                    ))
                }
                continue
            }
            if stack[index].childIndex < stack[index].box.children.count {
                let child = stack[index].box.children[stack[index].childIndex]
                stack[index].childIndex += 1
                let parent = stack[index]
                let childOrigin = CGPoint(
                    x: parent.contentOrigin.x + child.frame.minX + child.borders.left + child.padding.left,
                    y: parent.contentOrigin.y + child.frame.minY + child.borders.top + child.padding.top
                )
                // Entering a box contributes its block-start margin to the
                // margin adjoining the next content. Reset by `place`, so this
                // only ever accumulates across boxes entered back-to-back with
                // nothing emitted between them.
                adjoiningBlockStartMargin += LogicalGeometry.blockStart(edge: child.margins, mode: writingMode)
                stack.append(Self.makeFrame(child, contentOrigin: childOrigin, parentRotation: parent.rotation))
                continue
            }
            if let attachment = stack[index].box.imageAttachment,
               !stack[index].imageEmitted {
                stack[index].imageEmitted = true
                lineSerialCounter += 1
                blockImageLineSerials.insert(lineSerialCounter)
                let frame = stack[index]
                let rect = DocumentRect(rawValue: CGRect(
                    x: frame.contentOrigin.x,
                    y: frame.contentOrigin.y,
                    width: attachment.usedSize.width,
                    height: attachment.usedSize.height
                ))
                return .image(StepImage(
                    source: attachment.source,
                    image: attachment.image,
                    sourceRange: NSRange(location: 0, length: 0),
                    // A block-level replaced element has no line run, so the
                    // attachment is the ONLY carrier of its DOM identity. These
                    // were hardcoded to `-1`/`nil`, which erased the ancestor
                    // anchor of every `<a href><img style="display:block"></a>`.
                    nodeID: attachment.nodeID,
                    linkTarget: attachment.linkTarget,
                    writingMode: writingMode,
                    rect: rect,
                    alt: nil,
                    lineSerial: lineSerialCounter,
                    rotation: frame.rotation
                ))
            }
            if stack[index].lineIndex < stack[index].box.lines.count {
                let line = stack[index].box.lines[stack[index].lineIndex]
                if !stack[index].inlineDecorationsEmitted {
                    stack[index].inlineDecorationsEmitted = true
                    lineSerialCounter += 1
                    currentLineSerial = lineSerialCounter
                    if !line.inlineDecorations.isEmpty {
                        let frame = stack[index]
                        return .inlineLineStart(StepInlineLineStart(
                            placementRect: DocumentRect(rawValue: CGRect(
                                x: frame.contentOrigin.x + line.contentX,
                                y: frame.contentOrigin.y + line.top,
                                width: frame.box.contentSize.width, height: line.height
                            )),
                            fills: line.inlineDecorations.map { decoration in
                                let style = decoration.owner.style
                                return StepFill(
                                    rect: DocumentRect(rawValue: decoration.rect.offsetBy(
                                        dx: frame.contentOrigin.x + line.contentX, dy: frame.contentOrigin.y)),
                                    color: style.backgroundColor ?? .clear,
                                    cornerRadius: style.borderRadius,
                                    borderTop: Self.edge(style.borderTopWidth, style.borderTopStyle, style.borderColor),
                                    borderBottom: Self.edge(style.borderBottomWidth, style.borderBottomStyle, style.borderColor),
                                    borderLeft: decoration.paintsStartEdge ? Self.edge(style.borderLeftWidth, style.borderLeftStyle, style.borderColor) : .zero,
                                    borderRight: decoration.paintsEndEdge ? Self.edge(style.borderRightWidth, style.borderRightStyle, style.borderColor) : .zero,
                                    nodeID: decoration.owner.nodeID, writingMode: writingMode,
                                    rotation: frame.rotation
                                )
                            },
                            lineSerial: currentLineSerial
                        ))
                    }
                }
                if stack[index].runIndex < line.runs.count {
                    let run = line.runs[stack[index].runIndex]
                    stack[index].runIndex += 1
                    if run.isDecorationEdge { continue }
                    let frame = stack[index]
                    if let ruby = run.ruby {
                        return .ruby(StepRuby(
                            placementRect: DocumentRect(rawValue: CGRect(
                                x: frame.contentOrigin.x + line.contentX + run.x,
                                y: frame.contentOrigin.y + line.top,
                                width: run.width,
                                height: line.height
                            )),
                            baseBaselineY: frame.contentOrigin.y + line.baseline,
                            ruby: ruby,
                            originX: frame.contentOrigin.x + line.contentX + run.x,
                            writingMode: writingMode,
                            lineSerial: currentLineSerial,
                            rotation: frame.rotation
                        ))
                    }
                    if let combined = run.combined {
                        // The line box, as for text; the cell's own place is the line's
                        // inline position and its centre line.
                        return .text(StepText(
                            sourceRange: run.sourceRange,
                            nodeID: run.nodeID,
                            linkTarget: run.linkTarget,
                            writingMode: writingMode,
                            rect: DocumentRect(rawValue: CGRect(
                                x: frame.contentOrigin.x + line.contentX + run.x,
                                y: frame.contentOrigin.y + line.top,
                                width: run.width,
                                height: line.height
                            )),
                            baselineY: frame.contentOrigin.y + line.baseline,
                            font: run.font,
                            color: run.style.color ?? .black,
                            ctLine: combined.line,
                            sourceMapping: .linear(shapedRange: NSRange(
                                location: 0, length: CTLineGetStringRange(combined.line).length)),
                            renderedTextOverride: nil,
                            isCombinedUpright: true,
                            lineSerial: currentLineSerial,
                            rotation: frame.rotation
                        ))
                    }
                    if let atomic = run.atomic {
                        let rect = DocumentRect(rawValue: CGRect(
                            x: frame.contentOrigin.x + line.contentX + run.x,
                            y: frame.contentOrigin.y + line.baseline - atomic.usedSize.height,
                            width: atomic.usedSize.width,
                            height: atomic.usedSize.height
                        ))
                        #if DEBUG
                        // Gallery pagination diagnostics (画册 regression): the
                        // real DOM chain — documentY, line box, containing box
                        // frame, sibling offset, before pagination.
                        let cell = stack[index]
                        let walkLine = "\(BrowserLayoutDeviceDiagnostic.prefix) galleryImageWalk "
                            + "docY=\(String(format: "%.2f", rect.minY)) "
                            + "lineH=\(String(format: "%.2f", line.height)) "
                            + "lineTop=\(String(format: "%.2f", line.top)) "
                            + "contentX=\(String(format: "%.2f", line.contentX)) "
                            + "runX=\(String(format: "%.2f", run.x)) "
                            + "cellFrame=\(BrowserLayoutDeviceDiagnostic.rect(cell.box.frame.rawValue, space: "parentLocal")) "
                            + "cellContentOrigin=\(cell.contentOrigin.x), \(cell.contentOrigin.y) "
                            + "parentFrame=\(stack.count > 1 ? BrowserLayoutDeviceDiagnostic.rect(stack[stack.count-2].box.frame.rawValue, space: "parentLocal") : "none") "
                            + "atomicSize=\(atomic.usedSize.width)x\(atomic.usedSize.height)"
                        BrowserLayoutDeviceDiagnostic.summary(walkLine)
                        #endif
                        let endsLine = !line.runs[frame.runIndex...].contains {
                            !$0.isDecorationEdge && ($0.atomic != nil || $0.ruby != nil || $0.combined != nil || $0.width > 0.001)
                        }
                        let lineBottom = frame.contentOrigin.y + line.top + line.height
                        return .image(StepImage(
                            source: atomic.source,
                            image: atomic.image,
                            sourceRange: run.sourceRange,
                            nodeID: run.nodeID,
                            linkTarget: run.linkTarget,
                            writingMode: writingMode,
                            rect: rect,
                            alt: nil,
                            trailingLineExtent: endsLine ? max(0, lineBottom - rect.maxY) : 0,
                            lineSerial: currentLineSerial,
                            rotation: frame.rotation
                        ))
                    }
                    let rect = DocumentRect(rawValue: CGRect(
                        x: frame.contentOrigin.x + line.contentX + run.x,
                        y: frame.contentOrigin.y + line.top,
                        width: run.width,
                        height: line.height
                    ))
                    return .text(StepText(
                        sourceRange: run.sourceRange,
                        nodeID: run.nodeID,
                        linkTarget: run.linkTarget,
                        writingMode: writingMode,
                        rect: rect,
                        baselineY: frame.contentOrigin.y + line.baseline,
                        font: run.font,
                        color: run.style.color ?? .black,
                        ctLine: line.ctLine,
                        sourceMapping: .linear(shapedRange: run.shapedRange ?? run.sourceRange),
                        renderedTextOverride: nil,
                        lineSerial: currentLineSerial,
                        rotation: frame.rotation
                    ))
                }
                stack[index].lineIndex += 1
                stack[index].runIndex = 0
                stack[index].inlineDecorationsEmitted = false
                continue
            }
            if stack[index].decorationStarted, !stack[index].decorationEndEmitted {
                stack[index].decorationEndEmitted = true
                let frame = stack[index]
                return .fillEnd(StepFillEnd(
                    nodeID: frame.box.debugNodeID,
                    originalEndY: frame.borderY + frame.box.frame.height
                ))
            }
            stack.removeLast()
        }
        return nil
    }

    private static func edge(_ width: CGFloat, _ style: BorderStyle, _ color: UIColor?) -> BorderEdge {
        BorderEdge(width: width, color: color ?? .black, style: width > 0 ? style : .none)
    }

    /// Feeds one step through the paging rules; returns a COMPLETED page when
    /// the step crosses a page boundary (or nil otherwise).
    mutating func place(_ step: Step) -> PageFragments? {
        // Fragment bytes are accounted by `BrowserChapterLayout`
        // (`refreshFragmentBytes`), which counts the finished pages and is the
        // only place that can release them again on eviction. Recording here as
        // well double-counted every fragment, and since eviction releases only
        // the layout's own figure, the second copy stayed on the tracker
        // forever — a chapter laid out and evicted leaked fragmentCount * 60
        // bytes of *accounting*, which is exactly the monotonic growth
        // MemoryTracker exists to disprove. One owner per artifact type.
        switch step {
        case .inlineLineStart(let line):
            return placeInlineLineStart(line)
        case .floatBoundary(let marker):
            return placeFloatBoundary(marker)
        case .fill(let frag):
            return placeFill(frag)
        case .fillEnd(let end):
            return placeFillEnd(end)
        case .text(let frag):
            return placeText(frag)
        case .ruby(let ruby):
            return placeRuby(ruby)
        case .image(let frag):
            return placeImage(frag)
        }
    }

    /// A float that fits a full fragmentainer is atomic. The structural marker
    /// is emitted before any of the float's paint/content, so one flowShift
    /// relocates the complete float and every following sibling together.
    /// Oversized replaced floats stay on the generic image scale-to-fit path;
    /// non-replaced oversized/complex floats are rejected by the scanner.
    private mutating func placeFloatBoundary(_ step: StepFloat) -> PageFragments? {
        guard !isContinuous else { return nil }

        let shiftedY = step.marginRect.minY + flowShift
        var target = max(0, Int(floor(shiftedY / pageHeight)))
        let pageLocalY = shiftedY - CGFloat(target) * pageHeight
        if step.marginRect.height <= pageHeight,
           pageLocalY + step.marginRect.height > pageHeight + 0.001 {
            target += 1
            let movedY = CGFloat(target) * pageHeight
            flowShift += movedY - shiftedY
        }
        return advanceToPage(target)
    }

    /// Walks until the next page completes. Returns the page, or nil when the
    /// walk is exhausted (flushing the final partial page).
    mutating func layoutNextPage() -> PageFragments? {
        while let step = nextStep() {
            if let page = place(step) { return page }
        }
        if !currentPage.isEmpty {
            // The end of the flow, not a full column: the last page keeps its lines where they are.
            finalizeActiveDecorationsForCurrentPage()
            let page = PageFragments(index: currentIndex, pageRect: pageRect, fragments: currentPage)
            completedPages.append(page)
            currentPage = []
            currentPageLineSerials = []
            currentIndex += 1
            return page
        }
        return nil
    }

    /// Source range of the last completed page (for offset-targeted layout).
    func sourceRange(ofPage page: PageFragments, sourceText: String) -> NSRange {
        let ns = sourceText as NSString
        var minLocation = ns.length
        var maxEnd = 0
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .text(let t):
                    if t.sourceRange.length > 0 {
                        minLocation = min(minLocation, t.sourceRange.location)
                        maxEnd = max(maxEnd, t.sourceRange.location + t.sourceRange.length)
                    }
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        walk(page.fragments)
        guard maxEnd > minLocation else { return NSRange(location: minLocation, length: 0) }
        return NSRange(location: minLocation, length: maxEnd - minLocation)
    }

    // MARK: - Paging rules (single source of truth with the batch path)

    /// True when the in-progress page already carries visible content (text or
    /// an image). Box backgrounds/borders alone do not count: a body-background
    /// fill spans the whole page and would otherwise make every page look
    /// occupied.
    private var currentPageHasInk: Bool {
        func hasInk(_ fragments: [Fragment]) -> Bool {
            for fragment in fragments {
                switch fragment {
                case .text, .image: return true
                case .fill: continue
                case .group(let children): if hasInk(children) { return true }
                }
            }
            return false
        }
        return hasInk(currentPage)
    }

    /// - Parameter overflowLineHeight: the line box height of the text line (or ruby,
    ///   or a line's inline decorations) moving to `target` because it no longer fits —
    ///   the page ends because its column is full of text, the one case 底部對齊
    ///   stretches. nil when an image, a float or a box start leaves the page.
    private mutating func advanceToPage(_ target: Int, overflowLineHeight: CGFloat? = nil) -> PageFragments? {
        var flushed: PageFragments? = nil
        while target > currentIndex {
            finalizeActiveDecorationsForCurrentPage()
            if let overflowLineHeight, flushed == nil, bottomJustify {
                currentPage = bottomJustifiedCurrentPage(overflowLineHeight: overflowLineHeight)
            }
            let page = PageFragments(index: currentIndex, pageRect: pageRect, fragments: currentPage)
            completedPages.append(page)
            flushed = flushed ?? page
            currentIndex += 1
            currentPage = []
            currentPageLineSerials = []
            appendActiveDecorationFragmentsForCurrentPage()
            // Pagination itself ran out of room: an UNFORCED break. Author
            // breaks would set `.forcedBreak` instead, and the engine does not
            // parse them yet.
            pageEntry = .unforcedBreak
        }
        return flushed
    }

    /// CSS Fragmentation §4.2 — discards the block-start margin adjoining an
    /// UNFORCED fragmentainer break, returning the possibly-raised block
    /// position. Applies to every step kind; call once per placed step, after
    /// `advanceToPage`, so the entry kind and ink state describe the page the
    /// content actually lands on.
    ///
    /// Deliberately narrow, per the three conditions the rule depends on:
    /// - only `unforcedBreak` — `flowStart` keeps the document's leading margin
    ///   and `forcedBreak` keeps the margin the author put after the break;
    /// - only while the page carries no ink, so a page with content on it can
    ///   never have a later margin swallowed;
    /// - bounded by the margin itself AND by the distance to the fragmentainer
    ///   top, so border/padding are never eaten and content never rises above
    ///   the page top.
    private mutating func discardMarginAdjoiningBreak(_ blockStart: CGFloat, target: Int) -> CGFloat {
        let margin = adjoiningBlockStartMargin
        adjoiningBlockStartMargin = 0
        guard case .unforcedBreak = pageEntry else { return blockStart }
        guard target == currentIndex, !currentPageHasInk else { return blockStart }
        let pageTop = CGFloat(target) * pageHeight
        let discard = min(margin, blockStart - pageTop)
        guard discard > 0 else { return blockStart }
        // The discarded margin is removed from the flow, so later content moves
        // up with it — same mechanism as any other displacement.
        flowShift -= discard
        return blockStart - discard
    }

    private mutating func placeInlineLineStart(_ step: StepInlineLineStart) -> PageFragments? {
        var flushed: PageFragments?
        if !isContinuous {
            let shiftedY = step.placementRect.minY + flowShift
            var target = max(0, Int(floor(shiftedY / pageHeight)))
            if step.placementRect.height <= pageHeight,
               shiftedY - CGFloat(target) * pageHeight + step.placementRect.height > pageHeight + 0.001 {
                target += 1
                flowShift += CGFloat(target) * pageHeight - shiftedY
            }
            flushed = advanceToPage(target, overflowLineHeight: step.placementRect.height)
            _ = discardMarginAdjoiningBreak(step.placementRect.minY + flowShift, target: target)
        }
        for fill in step.fills {
            let document = DocumentRect(rawValue: fill.rect.rawValue.offsetBy(dx: 0, dy: flowShift))
            var fragment = FillFragment(
                rect: canvasRect(forDocument: document, pageIndex: currentIndex),
                documentRect: fill.rect, color: fill.color, cornerRadius: fill.cornerRadius,
                borderTop: fill.borderTop, borderBottom: fill.borderBottom,
                borderLeft: fill.borderLeft, borderRight: fill.borderRight,
                nodeID: fill.nodeID, writingMode: fill.writingMode
            )
            fragment.paintTransform = pageTransform(fill.rotation, displacementY: flowShift, pageIndex: currentIndex)
            appendToCurrentPage(.fill(fragment), lineSerial: step.lineSerial)
        }
        return flushed
    }

    /// Re-expresses a step's document-space transform for the page canvas,
    /// applying the same document-space displacement the fragment's rect
    /// received, then the document → page translation.
    private func pageTransform(
        _ rotation: PaintTransform?,
        displacementY: CGFloat,
        pageIndex: Int
    ) -> PaintTransform? {
        guard let rotation else { return nil }
        return rotation
            .rebased(by: CGPoint(
                x: contentInsets.left,
                y: displacementY - CGFloat(pageIndex) * pageHeight + contentInsets.top
            ))
    }

    private mutating func placeText(_ step: StepText) -> PageFragments? {
        if isContinuous {
            // No break can occur, so nothing is ever relocated and `flowShift`
            // stays zero: the document position IS the final position.
            let canvas = canvasRect(forDocument: step.rect, pageIndex: 0)
            var fragment = TextFragment(
                sourceRange: step.sourceRange,
                nodeID: step.nodeID,
                linkTarget: step.linkTarget,
                writingMode: step.writingMode,
                rect: canvas,
                documentRect: step.rect,
                baselineY: canvas.minY + (step.baselineY - step.rect.minY),
                font: step.font,
                color: step.color,
                ctLine: step.ctLine,
                sourceMapping: step.sourceMapping,
                renderedTextOverride: step.renderedTextOverride
            )
            fragment.isCombinedUpright = step.isCombinedUpright
            fragment.paintTransform = pageTransform(step.rotation, displacementY: 0, pageIndex: 0)
            appendToCurrentPage(.text(fragment), lineSerial: step.lineSerial)
            return nil
        }
        let shiftedY = step.rect.minY + flowShift
        var target = max(0, Int(floor(shiftedY / pageHeight)))
        let pageLocalY = shiftedY - CGFloat(target) * pageHeight
        var adjustedDocY = shiftedY
        // Line boxes never split: a line that fits a page but not the
        // remaining space moves wholesale to the next page, carrying every
        // later line with it (flowShift) so the pushed line cannot overlap the
        // line that used to follow it.
        if step.rect.height <= pageHeight, pageLocalY + step.rect.height > pageHeight + 0.001 {
            target += 1
            adjustedDocY = CGFloat(target) * pageHeight
            flowShift += adjustedDocY - shiftedY
        }
        let flushed = advanceToPage(target, overflowLineHeight: step.rect.height)
        adjustedDocY = discardMarginAdjoiningBreak(adjustedDocY, target: target)
        let adjustedDoc = DocumentRect(rawValue: CGRect(
            x: step.rect.minX, y: adjustedDocY,
            width: step.rect.width, height: step.rect.height
        ))
        let canvas = canvasRect(forDocument: adjustedDoc, pageIndex: currentIndex)
        var fragment = TextFragment(
            sourceRange: step.sourceRange,
            nodeID: step.nodeID,
            linkTarget: step.linkTarget,
            writingMode: step.writingMode,
            rect: canvas,
            documentRect: step.rect,
            baselineY: canvas.minY + (step.baselineY - step.rect.minY),
            font: step.font,
            color: step.color,
            ctLine: step.ctLine,
            sourceMapping: step.sourceMapping,
            renderedTextOverride: step.renderedTextOverride
        )
        fragment.isCombinedUpright = step.isCombinedUpright
        fragment.paintTransform = pageTransform(
            step.rotation,
            displacementY: adjustedDocY - step.rect.minY,
            pageIndex: currentIndex
        )
        appendToCurrentPage(.text(fragment), lineSerial: step.lineSerial)
        return flushed
    }

    private mutating func placeRuby(_ step: StepRuby) -> PageFragments? {
        if isContinuous {
            appendToCurrentPage(makeRubyGroup(step, displacementY: 0, pageIndex: 0), lineSerial: step.lineSerial)
            return nil
        }

        let shiftedY = step.placementRect.minY + flowShift
        var target = max(0, Int(floor(shiftedY / pageHeight)))
        let pageLocalY = shiftedY - CGFloat(target) * pageHeight
        var adjustedDocY = shiftedY
        if step.placementRect.height <= pageHeight,
           pageLocalY + step.placementRect.height > pageHeight + 0.001 {
            target += 1
            adjustedDocY = CGFloat(target) * pageHeight
            flowShift += adjustedDocY - shiftedY
        }
        let flushed = advanceToPage(target, overflowLineHeight: step.placementRect.height)
        adjustedDocY = discardMarginAdjoiningBreak(adjustedDocY, target: target)
        appendToCurrentPage(makeRubyGroup(
            step,
            displacementY: adjustedDocY - step.placementRect.minY,
            pageIndex: currentIndex
        ), lineSerial: step.lineSerial)
        return flushed
    }

    private func makeRubyGroup(
        _ step: StepRuby,
        displacementY: CGFloat,
        pageIndex: Int
    ) -> Fragment {
        let ruby = step.ruby
        let baseBaseline = step.baseBaselineY + displacementY
        var children: [Fragment] = ruby.base.pieces.map { piece in
            let document = DocumentRect(rawValue: CGRect(
                x: step.originX + ruby.baseOffsetX + piece.x,
                y: baseBaseline - ruby.base.ascent,
                width: piece.width,
                height: ruby.base.ascent + ruby.base.descent
            ))
            let canvas = canvasRect(forDocument: document, pageIndex: pageIndex)
            var fragment = TextFragment(
                sourceRange: piece.sourceRange,
                nodeID: piece.nodeID,
                linkTarget: piece.linkTarget,
                writingMode: step.writingMode,
                rect: canvas,
                documentRect: document,
                baselineY: canvas.minY + ruby.base.ascent,
                font: piece.font,
                color: piece.style.color ?? .black,
                ctLine: ruby.base.line,
                sourceMapping: .linear(shapedRange: piece.shapedRange),
                renderedTextOverride: nil
            )
            fragment.paintTransform = pageTransform(step.rotation, displacementY: displacementY, pageIndex: pageIndex)
            return .text(fragment)
        }

        let annotationBaseline = baseBaseline + ruby.annotationBaselineOffset
        children.append(contentsOf: ruby.annotation.pieces.map { piece in
            let document = DocumentRect(rawValue: CGRect(
                x: step.originX + ruby.annotationOffsetX + piece.x,
                y: annotationBaseline - ruby.annotation.ascent,
                width: piece.width,
                height: ruby.annotation.ascent + ruby.annotation.descent
            ))
            let canvas = canvasRect(forDocument: document, pageIndex: pageIndex)
            var fragment = TextFragment(
                sourceRange: ruby.unit.sourceRange,
                nodeID: piece.nodeID,
                linkTarget: piece.linkTarget ?? ruby.unit.linkTarget,
                writingMode: step.writingMode,
                rect: canvas,
                documentRect: document,
                baselineY: canvas.minY + ruby.annotation.ascent,
                font: piece.font,
                color: piece.style.color ?? .black,
                ctLine: ruby.annotation.line,
                sourceMapping: ruby.annotation.pieces.count == 1 ? .wholeRange : .annotation(shapedRange: piece.shapedRange),
                renderedTextOverride: piece.text
            )
            fragment.paintTransform = pageTransform(step.rotation, displacementY: displacementY, pageIndex: pageIndex)
            return .text(fragment)
        })
        return .group(children)
    }

    private mutating func placeFill(_ step: StepFill) -> PageFragments? {
        if isContinuous {
            var fragment = FillFragment(
                rect: canvasRect(forDocument: step.rect, pageIndex: 0),
                documentRect: step.rect,
                color: step.color,
                cornerRadius: step.cornerRadius,
                borderTop: step.borderTop, borderBottom: step.borderBottom,
                borderLeft: step.borderLeft, borderRight: step.borderRight,
                nodeID: step.nodeID,
                writingMode: step.writingMode
            )
            fragment.paintTransform = pageTransform(step.rotation, displacementY: 0, pageIndex: 0)
            appendToCurrentPage(.fill(fragment), lineSerial: nil)
            return nil
        }
        let shiftedStartY = step.rect.minY + flowShift
        let target = max(0, Int(floor(shiftedStartY / pageHeight)))
        let flushed = advanceToPage(target)
        let adjustedStartY = discardMarginAdjoiningBreak(shiftedStartY, target: target)
        let decoration = ActiveDecoration(
            id: nextDecorationID,
            step: step,
            startY: adjustedStartY
        )
        nextDecorationID += 1
        activeDecorations.append(decoration)
        upsertDecorationFragment(
            decoration,
            endY: step.rect.maxY + flowShift,
            isFinal: false,
            pageIndex: currentIndex
        )
        return flushed
    }

    private mutating func placeFillEnd(_ step: StepFillEnd) -> PageFragments? {
        guard !isContinuous else { return nil }
        let decorations = activeDecorations.filter { $0.step.nodeID == step.nodeID }
        guard !decorations.isEmpty else {
            return nil
        }
        let finalEndY = max(
            decorations.map(\.startY).max() ?? 0,
            step.originalEndY + flowShift
        )
        let finalPage = max(0, Int(floor((finalEndY - 0.001) / pageHeight)))
        let flushed = advanceToPage(finalPage)
        for decoration in decorations {
            upsertDecorationFragment(
                decoration,
                endY: max(decoration.startY, finalEndY),
                isFinal: true,
                pageIndex: currentIndex
            )
        }
        activeDecorations.removeAll { $0.step.nodeID == step.nodeID }
        return flushed
    }

    /// Finalizes the open slices on a page that is about to be emitted. Their
    /// owning boxes have not ended, therefore each slice reaches the page's
    /// block-end and cannot carry a block-end border or lower corner radius.
    private mutating func finalizeActiveDecorationsForCurrentPage() {
        let pageEnd = CGFloat(currentIndex + 1) * pageHeight
        for decoration in activeDecorations {
            upsertDecorationFragment(
                decoration,
                endY: pageEnd,
                isFinal: false,
                pageIndex: currentIndex
            )
        }
    }

    /// A continuation decoration paints before the continued descendants on a
    /// new fragmentainer. Active decorations are kept in ancestor/start order,
    /// preserving the same background stacking as the document walk.
    private mutating func appendActiveDecorationFragmentsForCurrentPage() {
        let provisionalEnd = CGFloat(currentIndex + 1) * pageHeight
        for decoration in activeDecorations {
            upsertDecorationFragment(
                decoration,
                endY: provisionalEnd,
                isFinal: false,
                pageIndex: currentIndex
            )
        }
    }

    private mutating func upsertDecorationFragment(
        _ decoration: ActiveDecoration,
        endY: CGFloat,
        isFinal: Bool,
        pageIndex: Int
    ) {
        guard pageIndex == currentIndex,
              let fragment = makeDecorationFragment(
                decoration,
                endY: endY,
                isFinal: isFinal,
                pageIndex: pageIndex
              ) else { return }

        if let existing = currentPage.lastIndex(where: { item in
            guard case .fill(let fill) = item else { return false }
            return fill.decorationID == decoration.id
        }) {
            currentPage[existing] = .fill(fragment)
        } else {
            appendToCurrentPage(.fill(fragment), lineSerial: nil)
        }
    }

    private func makeDecorationFragment(
        _ decoration: ActiveDecoration,
        endY: CGFloat,
        isFinal: Bool,
        pageIndex: Int
    ) -> FillFragment? {
        let pageStart = CGFloat(pageIndex) * pageHeight
        let pageEnd = pageStart + pageHeight
        let fragmentStart = max(decoration.startY, pageStart)
        let fragmentEnd = min(max(endY, fragmentStart), pageEnd)
        guard fragmentEnd - fragmentStart > 0.0001 else { return nil }

        let firstPage = max(0, Int(floor(decoration.startY / pageHeight)))
        let isFirst = pageIndex == firstPage
        let isLast = isFinal && endY <= pageEnd + 0.001
        let position: BlockDecorationFragmentPosition
        switch (isFirst, isLast) {
        case (true, true): position = .single
        case (true, false): position = .first
        case (false, true): position = .last
        case (false, false): position = .middle
        }

        let document = DocumentRect(rawValue: CGRect(
            x: decoration.step.rect.minX,
            y: fragmentStart,
            width: decoration.step.rect.width,
            height: fragmentEnd - fragmentStart
        ))
        var fragment = FillFragment(
            rect: canvasRect(forDocument: document, pageIndex: pageIndex),
            documentRect: document,
            color: decoration.step.color,
            cornerRadius: decoration.step.cornerRadius,
            borderTop: isFirst ? decoration.step.borderTop : .zero,
            borderBottom: isLast ? decoration.step.borderBottom : .zero,
            borderLeft: decoration.step.borderLeft,
            borderRight: decoration.step.borderRight,
            nodeID: decoration.step.nodeID,
            writingMode: decoration.step.writingMode,
            fragmentPosition: position,
            decorationID: decoration.id
        )
        fragment.paintTransform = pageTransform(
            decoration.step.rotation,
            displacementY: decoration.startY - decoration.step.rect.minY,
            pageIndex: pageIndex
        )
        return fragment
    }

    private mutating func placeImage(_ step: StepImage) -> PageFragments? {
        if isContinuous {
            // Deliberately NO scale-to-fit here. The three replaced-element
            // rules below all exist to make an image fit a PAGE; with no page
            // there is nothing to fit it to, and block layout already resolved
            // the used size against the container width. An image that still
            // overflows overflows — which is what a browser does too.
            var fragment = ImageFragment(
                source: step.source,
                image: step.image,
                sourceRange: step.sourceRange,
                nodeID: step.nodeID,
                linkTarget: step.linkTarget,
                writingMode: step.writingMode,
                rect: canvasRect(forDocument: step.rect, pageIndex: 0),
                documentRect: step.rect,
                alt: step.alt
            )
            fragment.paintTransform = pageTransform(step.rotation, displacementY: 0, pageIndex: 0)
            appendToCurrentPage(.image(fragment), lineSerial: step.lineSerial)
            return nil
        }
        let shiftedY = step.rect.minY + flowShift
        var target = max(0, Int(floor(shiftedY / pageHeight)))
        let pageLocalY = shiftedY - CGFloat(target) * pageHeight
        var adjustedDocY = shiftedY
        var adjustedDocRect = step.rect.rawValue
        adjustedDocRect.origin.y = shiftedY

        // Replaced-element pagination (Phase 2C):
        // 1. Fits current page remainder → place.
        // 2. Does not fit remainder but fits a full page → move whole to next.
        // 3. Intrinsic size EXCEEDS a full page → scale to fit (aspect kept),
        //    never split into fragments.
        // Cases 2 and 3 change the block space the image consumes, so both feed
        // `flowShift` — the following content moves with the image.
        let contentWidth = max(1, pageRect.width - contentInsets.left - contentInsets.right)
        if step.rect.height <= pageHeight, pageLocalY + step.rect.height > pageHeight + 0.001 {
            // Case 2: move to next page.
            target += 1
            adjustedDocY = CGFloat(target) * pageHeight
            flowShift += adjustedDocY - shiftedY
            adjustedDocRect.origin.y = adjustedDocY
        } else if step.rect.height > pageHeight || step.rect.width > contentWidth {
            // Case 3: scale to fit the full page content area, aspect preserved.
            let scale = min(
                contentWidth / step.rect.width,
                pageHeight / step.rect.height
            )
            let newW = max(1, step.rect.width * scale)
            let newH = max(1, step.rect.height * scale)
            // Block layout reserved the UNSCALED height; the page consumes only
            // `newH`. Pull the following content up by the difference, or the
            // leftover band becomes an empty page.
            flowShift -= step.rect.height - newH
            // A scaled image that still doesn't fit the CURRENT page's
            // remainder moves to its own page (top-aligned).
            let pageBottom = CGFloat(target + 1) * pageHeight
            if adjustedDocY + newH > pageBottom + 0.001 {
                target += 1
                let movedY = CGFloat(target) * pageHeight
                flowShift += movedY - adjustedDocY
                adjustedDocY = movedY
            }
            adjustedDocRect = CGRect(
                x: step.rect.minX,
                y: adjustedDocY,
                width: newW,
                height: newH
            )
        }
        #if DEBUG
        BrowserLayoutDeviceDiagnostic.summary(
            "\(BrowserLayoutDeviceDiagnostic.prefix) galleryImagePlace "
            + "origDocY=\(String(format: "%.2f", step.rect.minY)) "
            + "adjustedDocY=\(String(format: "%.2f", adjustedDocY)) "
            + "assignedPage=\(target) "
            + "flowShift=\(String(format: "%.2f", flowShift)) "
            + "imageH=\(String(format: "%.2f", step.rect.height)) "
            + "pageH=\(String(format: "%.2f", pageHeight)) "
            + "contentW=\(String(format: "%.2f", max(1, pageRect.width - contentInsets.left - contentInsets.right)))"
        )
        #endif
        let flushed = advanceToPage(target)
        adjustedDocRect.origin.y = discardMarginAdjoiningBreak(adjustedDocY, target: target)
        // The band of the image's line box below the image (parent strut
        // descent) belongs to the same unsplittable line. Carried past the
        // bottom of this page it made the next page-tall image miss its page,
        // leaving an empty page between gallery images (3 images → 6 pages).
        // Like a margin adjoining an unforced break (§4.2), the part crossing
        // the break is discarded; following content starts at the next page top.
        let spill = adjustedDocRect.maxY + step.trailingLineExtent - CGFloat(target + 1) * pageHeight
        if step.trailingLineExtent > 0, spill > 0.001 {
            flowShift -= min(spill, step.trailingLineExtent)
        }
        let adjustedDoc = DocumentRect(rawValue: adjustedDocRect)
        let canvas = canvasRect(forDocument: adjustedDoc, pageIndex: currentIndex)
        var fragment = ImageFragment(
            source: step.source,
            image: step.image,
            sourceRange: step.sourceRange,
            nodeID: step.nodeID,
            linkTarget: step.linkTarget,
            writingMode: step.writingMode,
            rect: canvas,
            documentRect: step.rect,
            alt: step.alt
        )
        fragment.paintTransform = pageTransform(
            step.rotation,
            displacementY: adjustedDocRect.minY - step.rect.minY,
            pageIndex: currentIndex
        )
        appendToCurrentPage(.image(fragment), lineSerial: step.lineSerial)
        return flushed
    }

    private mutating func appendToCurrentPage(_ fragment: Fragment, lineSerial: Int?) {
        currentPage.append(fragment)
        currentPageLineSerials.append(lineSerial)
    }

    // MARK: - 底部對齊

    /// The in-progress page with its leftover space spread over its line gaps:
    /// line k moves down by k × surplus / (lines − 1), so the first line keeps its
    /// place and the last one's ink sits on the content bottom.
    ///
    /// Only for a page a text line overflowed, and only when that line is an
    /// ordinary one — at most twice the last line's box. A taller line (a display
    /// heading, a line carrying a tall inline image) can leave most of the page
    /// empty, and spreading that would tear the page apart. legado has no break
    /// reason and guesses from the leftover's size instead, which leaves every page
    /// that ends at a paragraph with wide spacing unaligned. Like legado, a page
    /// ending in a block image keeps its positions.
    ///
    /// Shifting the fragments here, before the page exists, keeps every consumer on
    /// one geometry: drawing, hit-testing, selection, links and highlights are all
    /// derived from the page's fragments. `documentRect` is left alone; it is the
    /// unpaginated flow position and nothing paints from it.
    private func bottomJustifiedCurrentPage(overflowLineHeight: CGFloat) -> [Fragment] {
        var lineOrdinal: [Int: Int] = [:]
        var lineSerials: [Int] = []
        for case let serial? in currentPageLineSerials where lineOrdinal[serial] == nil {
            lineOrdinal[serial] = lineSerials.count
            lineSerials.append(serial)
        }
        guard lineSerials.count > 1, let lastSerial = lineSerials.last,
              !blockImageLineSerials.contains(lastSerial) else { return currentPage }

        let lastLine = lineSerials.count - 1
        var lineTops = [CGFloat](repeating: .greatestFiniteMagnitude, count: lineSerials.count)
        var lineBottoms = [CGFloat](repeating: -.greatestFiniteMagnitude, count: lineSerials.count)
        var lastLineInkBottom = -CGFloat.greatestFiniteMagnitude
        for (index, fragment) in currentPage.enumerated() {
            guard let serial = currentPageLineSerials[index], let line = lineOrdinal[serial] else { continue }
            let bounds = Self.bounds(of: fragment)
            lineTops[line] = min(lineTops[line], bounds.minY)
            lineBottoms[line] = max(lineBottoms[line], bounds.maxY)
            if line == lastLine, let ink = Self.inkBottom(of: fragment) {
                lastLineInkBottom = max(lastLineInkBottom, ink)
            }
        }
        guard lastLineInkBottom > -.greatestFiniteMagnitude,
              overflowLineHeight <= 2 * (lineBottoms[lastLine] - lineTops[lastLine]) else { return currentPage }

        let contentBottom = contentInsets.top + pageHeight
        let surplus = contentBottom - lastLineInkBottom
        guard surplus > 0.5 else { return currentPage }
        // A box that opens below the last line (its top fits, its first line was
        // pushed) occupies the leftover space already: the lines may not move into it.
        let boxOpensBelowLastLine = currentPage.indices.contains { index in
            guard currentPageLineSerials[index] == nil, case .fill(let fill) = currentPage[index] else { return false }
            return fill.rect.minY >= lineBottoms[lastLine] - 0.5
        }
        guard !boxOpensBelowLastLine else { return currentPage }
        let step = surplus / CGFloat(lastLine)

        return currentPage.enumerated().map { index, fragment in
            if let serial = currentPageLineSerials[index], let line = lineOrdinal[serial] {
                return Self.offset(fragment, dy: step * CGFloat(line))
            }
            // A block decoration spans lines: its top follows the first line it
            // holds and its bottom the last; a slice running on past this page
            // already ends at the content bottom and stays there. One holding no
            // line (a rule between paragraphs) moves whole with the line below it.
            guard case .fill(let fill) = fragment else { return fragment }
            guard let firstHeld = lineTops.firstIndex(where: { $0 >= fill.rect.minY - 0.5 }) else { return fragment }
            let lastHeld = max(firstHeld, lineBottoms.lastIndex { $0 <= fill.rect.maxY + 0.5 } ?? firstHeld)
            let minY = fill.rect.minY + step * CGFloat(firstHeld)
            let maxY = fill.rect.maxY >= contentBottom - 0.5
                ? fill.rect.maxY
                : fill.rect.maxY + step * CGFloat(lastHeld)
            var rect = fill.rect.rawValue
            rect.origin.y = minY
            rect.size.height = max(0, maxY - minY)
            return .fill(fill.with(rect: PageLocalRect(rawValue: rect)))
        }
    }

    private static func bounds(of fragment: Fragment) -> CGRect {
        switch fragment {
        case .text(let text): return text.rect.rawValue
        case .fill(let fill): return fill.rect.rawValue
        case .image(let image): return image.rect.rawValue
        case .group(let children):
            return children.reduce(CGRect.null) { $0.union(bounds(of: $1)) }
        }
    }

    /// Where the fragment's glyphs end: the baseline plus the line's descent, not
    /// the line box, whose bottom carries the reader's line spacing.
    private static func inkBottom(of fragment: Fragment) -> CGFloat? {
        switch fragment {
        case .text(let text):
            guard let line = text.ctLine else { return text.rect.maxY }
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            return text.baselineY + descent
        case .image(let image):
            return image.rect.maxY
        case .fill:
            return nil
        case .group(let children):
            return children.compactMap { inkBottom(of: $0) }.max()
        }
    }

    private static func offset(_ fragment: Fragment, dy: CGFloat) -> Fragment {
        guard dy != 0 else { return fragment }
        switch fragment {
        case .text(let text): return .text(text.offsetBy(dy: dy))
        case .fill(let fill):
            return .fill(fill.with(rect: PageLocalRect(rawValue: fill.rect.rawValue.offsetBy(dx: 0, dy: dy))))
        case .image(let image): return .image(image.offsetBy(dy: dy))
        case .group(let children): return .group(children.map { offset($0, dy: dy) })
        }
    }

    private static func makeFrame(_ box: BlockBox, contentOrigin: CGPoint, parentRotation: PaintTransform? = nil) -> BoxFrame {
        let borderX = contentOrigin.x - box.borders.left - box.padding.left
        let borderY = contentOrigin.y - box.borders.top - box.padding.top
        var rotation = parentRotation
        if let degrees = box.style.transformRotate {
            let own = PaintTransform(
                rotatingDegrees: degrees,
                about: CGPoint(
                    x: borderX + box.frame.width / 2,
                    y: borderY + box.frame.height / 2
                )
            )
            rotation = rotation.map { own.concatenating($0) } ?? own
        }
        return BoxFrame(
            box: box,
            contentOrigin: contentOrigin,
            borderX: borderX,
            borderY: borderY,
            rotation: rotation
        )
    }
}

/// Batch pagination: runs the walker to completion. Geometry is identical to
/// incremental layout by construction (same walker).
enum PageFragmentation {

    static func fragment(
        box: BlockBox,
        pageSize: CGSize,
        writingMode: ReaderWritingMode = .horizontal,
        contentInsets: UIEdgeInsets = .zero,
        bottomJustify: Bool = false
    ) -> [PageFragments] {
        var walker = PageWalker(
            box: box, pageSize: pageSize, writingMode: writingMode,
            contentInsets: contentInsets, bottomJustify: bottomJustify
        )
        while walker.layoutNextPage() != nil {}
        return walker.completedPages
    }
}

// MARK: - Page-local moves (底部對齊)

extension TextFragment {
    func offsetBy(dy: CGFloat) -> TextFragment {
        var moved = TextFragment(
            sourceRange: sourceRange,
            nodeID: nodeID,
            linkTarget: linkTarget,
            writingMode: writingMode,
            rect: PageLocalRect(rawValue: rect.rawValue.offsetBy(dx: 0, dy: dy)),
            documentRect: documentRect,
            baselineY: baselineY + dy,
            font: font,
            color: color,
            ctLine: ctLine,
            sourceMapping: sourceMapping,
            renderedTextOverride: renderedTextOverride
        )
        moved.isCombinedUpright = isCombinedUpright
        moved.paintTransform = paintTransform?.offsetBy(dx: 0, dy: dy)
        return moved
    }
}

extension ImageFragment {
    func offsetBy(dy: CGFloat) -> ImageFragment {
        var moved = ImageFragment(
            source: source,
            image: image,
            sourceRange: sourceRange,
            nodeID: nodeID,
            linkTarget: linkTarget,
            writingMode: writingMode,
            rect: PageLocalRect(rawValue: rect.rawValue.offsetBy(dx: 0, dy: dy)),
            documentRect: documentRect,
            alt: alt,
            isBackgroundPaint: isBackgroundPaint
        )
        moved.paintTransform = paintTransform?.offsetBy(dx: 0, dy: dy)
        return moved
    }
}

extension FillFragment {
    func with(rect: PageLocalRect) -> FillFragment {
        var moved = FillFragment(
            rect: rect,
            documentRect: documentRect,
            color: color,
            cornerRadius: cornerRadius,
            borderTop: borderTop,
            borderBottom: borderBottom,
            borderLeft: borderLeft,
            borderRight: borderRight,
            nodeID: nodeID,
            writingMode: writingMode,
            fragmentPosition: fragmentPosition,
            decorationID: decorationID,
            isBackgroundPaint: isBackgroundPaint
        )
        moved.paintTransform = paintTransform?.offsetBy(dx: 0, dy: rect.rawValue.minY - self.rect.rawValue.minY)
        return moved
    }
}
