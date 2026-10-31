import CoreText
import Foundation
import UIKit
import YueduCoreTextTypography

/// Accumulates the chapter's collapsed source text. Runs' `sourceRange`s point
/// into `text`; concatenating them in document order reassembles the text.
struct SourceTextBuilder {
    private(set) var text = ""
    // Re-bridging the growing chapter for every inline run makes content
    // preparation quadratic. UTF-16 offsets are additive, including surrogate pairs.
    private(set) var currentOffset = 0

    @discardableResult
    mutating func append(_ s: String) -> NSRange {
        let range = NSRange(location: currentOffset, length: (s as NSString).length)
        text.append(s)
        currentOffset += range.length
        return range
    }
}

/// ComputedStyleNode tree → block box tree, preserving DOM order.
///
/// A block's children are either block boxes or inline content. Inline content
/// is gathered into runs; whenever a block sibling interrupts the inline flow,
/// the pending runs are flushed into a NEW anonymous block AT THAT POSITION —
/// interleaving order (inline/block/inline) is fully preserved, and content is
/// never merged across a block sibling.
///
/// This stage also builds the chapter `sourceText` (one collapse pass, shared
/// with line layout) and resolves replaced elements (`<img>`).
enum BoxTreeBuilder {

    static func buildBlock(
        for node: ComputedStyleNode,
        config: BrowserLayoutConfig,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        imageLoader: (String) -> UIImage?
    ) -> BlockBox {
        var boxCount = 0
        let box = buildBlockInternal(
            for: node, config: config, containerWidth: config.renderWidth,
            sourceText: &sourceText, anchors: &anchors,
            imageLoader: imageLoader, boxCount: &boxCount
        )
        Self.linkParents(box)
        BrowserReaderTextStyling.prepare(root: box, sourceText: sourceText.text, config: config)
        #if DEBUG
        assertUnformatted(box)
        #endif
        return box
    }

    /// DEBUG-only: links each box to its parent for ancestry diagnostics.
    static func linkParents(_ box: BlockBox) {
        for child in box.children {
            child.parentBox = box
            linkParents(child)
        }
    }

    private static func buildBlockInternal(
        for node: ComputedStyleNode,
        config: BrowserLayoutConfig,
        containerWidth: CGFloat,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        imageLoader: (String) -> UIImage?,
        boxCount: inout Int
    ) -> BlockBox {
        boxCount += 1
        var kids: [BlockBox] = []
        var pendingInline: [InlineRun] = []
        var assignedFirstInlineContext = false
        // anchor IDs that will register at the first text run appended under them
        var anchorStack: [String] = []
        if let anchor = node.anchorID { anchorStack.append(anchor) }

        for child in node.children {
            switch child {
            case .text(let raw):
                appendTextNode(
                    raw, style: node.style, nodeID: node.nodeID, link: node.linkTarget,
                    combinesUpright: config.writingMode == .verticalRTL,
                    to: &pendingInline, sourceText: &sourceText,
                    anchors: &anchors, anchorStack: &anchorStack
                )
            case .element(let elementNode):
                if elementNode.tag == "br" {
                    // Forced line break: survives every whitespace mode.
                    let range = sourceText.append("\n")
                    pendingInline.append(InlineRun(
                        text: "\n", style: elementNode.style,
                        sourceRange: range, nodeID: elementNode.nodeID,
                        linkTarget: elementNode.linkTarget, isHardBreak: true
                    ))
                } else if let element = elementNode.semanticElement,
                          let svgSource = Self.svgWrappedImageSource(element) {
                    registerAnchors(&anchorStack, ownID: elementNode.anchorID,
                                    anchors: &anchors, at: sourceText.currentOffset)
                    appendSVGImageRun(elementNode, source: svgSource, to: &pendingInline,
                                      sourceText: &sourceText, imageLoader: imageLoader)
                } else if elementNode.tag == "img" {
                    registerAnchors(&anchorStack, ownID: elementNode.anchorID,
                                    anchors: &anchors, at: sourceText.currentOffset)
                    if elementNode.style.isFloated || elementNode.style.display == .block {
                        flushGroup(
                            &pendingInline,
                            style: node.style,
                            into: &kids,
                            assignedFirstInlineContext: &assignedFirstInlineContext
                        )
                        let attachment = makeBlockImage(for: elementNode, imageLoader: imageLoader)
                        let box = BlockBox(style: elementNode.style, boxType: .block)
                        box.imageAttachment = attachment
                        Self.attachDebugIdentity(box, node: elementNode)
                        kids.append(box)
                    } else {
                        appendImageRun(elementNode, to: &pendingInline, sourceText: &sourceText,
                                       imageLoader: imageLoader)
                    }
                } else if elementNode.tag == "ruby" {
                    appendRubyRun(
                        elementNode,
                        to: &pendingInline,
                        sourceText: &sourceText,
                        anchors: &anchors,
                        anchorStack: &anchorStack
                    )
                } else if formsOwnBox(elementNode.style) {
                    flushGroup(
                        &pendingInline,
                        style: node.style,
                        into: &kids,
                        assignedFirstInlineContext: &assignedFirstInlineContext
                    )
                    kids.append(buildOwnBox(
                        for: elementNode, config: config,
                        containerWidth: containerWidth,
                        sourceText: &sourceText, anchors: &anchors,
                        imageLoader: imageLoader, boxCount: &boxCount
                    ))
                } else if elementNode.style.display == .none {
                    continue
                } else {
                    // A block inside inline content splits it (CSS 2.1 §9.2.1.1):
                    // the inline content so far closes into an anonymous block and
                    // the block joins this container's children, in document order.
                    collectInline(
                        elementNode, into: &pendingInline, config: config,
                        sourceText: &sourceText, anchors: &anchors,
                        anchorStack: &anchorStack, imageLoader: imageLoader
                    ) { block, runs, sourceText, anchors, pendingAnchors in
                        flushGroup(
                            &runs,
                            style: node.style,
                            into: &kids,
                            assignedFirstInlineContext: &assignedFirstInlineContext
                        )
                        registerAnchors(&pendingAnchors, anchors: &anchors, at: sourceText.currentOffset)
                        kids.append(buildOwnBox(
                            for: block, config: config,
                            containerWidth: containerWidth,
                            sourceText: &sourceText, anchors: &anchors,
                            imageLoader: imageLoader, boxCount: &boxCount
                        ))
                    }
                }
            }
        }
        // A container with in-flow block children holds block boxes only (CSS
        // 2.1 §9.2.1.1). Inline content after the last block closes into an
        // anonymous block too; left on the container, its lines started at the
        // container's top and were painted over the first block. Floats are
        // out of flow and do not count: text after a drop cap stays the
        // container's own and wraps around it.
        if kids.contains(where: { !$0.style.isFloated }) {
            flushGroup(
                &pendingInline,
                style: node.style,
                into: &kids,
                assignedFirstInlineContext: &assignedFirstInlineContext
            )
        }

        var boxStyle = node.style
        if node.tag == "::first-letter", boxStyle.isFloated, boxStyle.width == .auto {
            let attributed = NSMutableAttributedString()
            for run in pendingInline {
                attributed.append(NSAttributedString(string: run.text, attributes: InlineLayout.textAttributes(for: run.style, resolver: config.fontResolver)))
            }
            let line = CTLineCreateWithAttributedString(attributed)
            boxStyle.width = .px(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        } else if boxStyle.isFloated, boxStyle.width == .auto, config.writingMode == .horizontal {
            // CSS §10.3.5 shrink-to-fit: the float needs a definite used width
            // before layout, measured from its own content.
            let available = max(
                0,
                containerWidth - horizontalExtras(of: boxStyle, percentBase: containerWidth, config: config)
            )
            boxStyle.width = .px(shrinkToFitWidth(
                kids: kids, trailingInline: visibleRuns(pendingInline),
                available: available, config: config
            ))
        }
        let box = BlockBox(style: boxStyle, boxType: .block, children: kids)
        Self.attachDebugIdentity(box, node: node)
        let trailingVisibleRuns = visibleRuns(pendingInline)
        if !trailingVisibleRuns.isEmpty {
            box.inlineRuns = trailingVisibleRuns
            box.ownsFirstFormattedLine = !assignedFirstInlineContext
            assignedFirstInlineContext = true
        }
        _ = assignedFirstInlineContext
        return box
    }

    /// The containing-block inline size for THIS node's children: the node's
    /// resolved width when non-auto, else the parent width. Percent widths
    /// resolve against the parent width (CSS 2.1 §10.3).
    private static func childContainerWidth(
        of node: ComputedStyleNode,
        parentWidth: CGFloat,
        config: BrowserLayoutConfig
    ) -> CGFloat {
        let resolved = CSSLengthResolver.resolve(node.style.width, emBase: node.style.fontSize, remBase: config.rootFontSize, percentBase: parentWidth)
        guard case .auto = node.style.width, resolved == nil else {
            return min(max(resolved ?? parentWidth, 0), parentWidth)
        }
        return parentWidth
    }

    /// Children laid out as boxes of their own, never as inline content: block
    /// containers, tables and floats.
    private static func formsOwnBox(_ style: ComputedStyle) -> Bool {
        style.display == .table || style.isFloated || style.display == .block
    }

    /// Block-level boxes met inside inline content. They split it (CSS 2.1
    /// §9.2.1.1) and are built by `buildOwnBox` like a direct child. A float
    /// whose display is still inline is not one: floats are out of flow and
    /// never split an inline box, and the engine has no float anchored inside
    /// a line, so such a float stays inline text as it always has.
    private static func splitsInlineBox(_ style: ComputedStyle) -> Bool {
        style.display == .table || style.display == .block
    }

    private static func buildOwnBox(
        for node: ComputedStyleNode,
        config: BrowserLayoutConfig,
        containerWidth: CGFloat,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        imageLoader: (String) -> UIImage?,
        boxCount: inout Int
    ) -> BlockBox {
        if node.style.display == .table {
            return buildTable(
                for: node, config: config,
                containerWidth: containerWidth,
                sourceText: &sourceText, anchors: &anchors,
                imageLoader: imageLoader, boxCount: &boxCount
            )
        }
        let childContainer = Self.childContainerWidth(
            of: node, parentWidth: containerWidth, config: config
        )
        return buildBlockInternal(
            for: node, config: config,
            containerWidth: childContainer,
            sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader,
            boxCount: &boxCount
        )
    }

    // MARK: - Shrink-to-fit (CSS 2.1 §10.3.5)

    /// Preferred (max-content) width of a width:auto float, clamped to the
    /// available width. The preferred-minimum side of the formula only
    /// diverges for unbreakable content wider than the page; clamping there is
    /// the non-overflowing reading, so it is not measured separately.
    private static func shrinkToFitWidth(
        kids: [BlockBox],
        trailingInline: [InlineRun],
        available: CGFloat,
        config: BrowserLayoutConfig
    ) -> CGFloat {
        let own = maxInlineWidth(trailingInline, config: config)
        let inner = max(own, kids.map { preferredOuterWidth(of: $0, available: available, config: config) }.max() ?? 0)
        return min(max(inner, 0), available)
    }

    /// A child box's margin-box contribution to its parent's preferred width.
    private static func preferredOuterWidth(of box: BlockBox, available: CGFloat, config: BrowserLayoutConfig) -> CGFloat {
        let style = box.style
        let extras = horizontalExtras(of: style, percentBase: available, config: config)
        if let attachment = box.imageAttachment {
            return attachment.usedSize.width + extras
        }
        if let explicit = CSSLengthResolver.resolve(style.width, emBase: style.fontSize, remBase: config.rootFontSize, percentBase: available) {
            return max(explicit, 0) + extras
        }
        var indent: CGFloat = 0
        if box.ownsFirstFormattedLine, case .length(let length) = style.textIndent {
            indent = CSSLengthResolver.resolve(length, emBase: style.fontSize, remBase: config.rootFontSize, percentBase: available) ?? 0
        }
        let own = maxInlineWidth(box.inlineRuns, indent: indent, config: config)
        let kids = box.children.map { preferredOuterWidth(of: $0, available: available, config: config) }.max() ?? 0
        return max(own, kids) + extras
    }

    /// The widest single line the runs form without wrapping: hard breaks end
    /// a line, and the first formatted line carries the box's text-indent.
    private static func maxInlineWidth(_ runs: [InlineRun], indent: CGFloat = 0, config: BrowserLayoutConfig) -> CGFloat {
        var maxWidth: CGFloat = 0
        var segment = NSMutableAttributedString()
        var isFirstSegment = true
        func flushSegment() {
            guard segment.length > 0 else { return }
            let line = CTLineCreateWithAttributedString(segment)
            var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            if isFirstSegment { width += indent }
            isFirstSegment = false
            maxWidth = max(maxWidth, width)
            segment = NSMutableAttributedString()
        }
        for run in runs {
            if run.isHardBreak {
                flushSegment()
                continue
            }
            if let atomic = run.atomic {
                flushSegment()
                maxWidth = max(maxWidth, atomic.usedSize.width)
                continue
            }
            segment.append(NSAttributedString(string: run.text, attributes: InlineLayout.textAttributes(for: run.style, resolver: config.fontResolver)))
        }
        flushSegment()
        return maxWidth
    }

    private static func horizontalExtras(of style: ComputedStyle, percentBase: CGFloat, config: BrowserLayoutConfig) -> CGFloat {
        func resolve(_ length: CSSLength?) -> CGFloat {
            length.flatMap {
                CSSLengthResolver.resolve($0, emBase: style.fontSize, remBase: config.rootFontSize, percentBase: percentBase)
            } ?? 0
        }
        return resolve(style.paddingLeft) + resolve(style.paddingRight)
            + style.borderLeftWidth + style.borderRightWidth
            + resolve(style.marginLeft) + resolve(style.marginRight)
    }

    // MARK: - Tables

    /// Builds a table box. Row groups and rows are pure structure; cells are
    /// ordinary block containers. Bare rows stay direct children (TableLayout
    /// accepts them, so the CSS anonymous-row-group fixup buys nothing), and
    /// groups are reordered per CSS 2.1 §17.2.1: header groups first, footer
    /// groups last. Admission guarantees only supported structure reaches here.
    ///
    /// A `width: auto` table shrink-to-fits the columns' max-content widths.
    /// The value is pinned here — where the font resolver is available — so the
    /// ordinary block path sees a definite used width and can center the table
    /// through its auto margins. The per-column bases ride on the box for
    /// TableLayout's final distribution.
    private static func buildTable(
        for node: ComputedStyleNode,
        config: BrowserLayoutConfig,
        containerWidth: CGFloat,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        imageLoader: (String) -> UIImage?,
        boxCount: inout Int
    ) -> BlockBox {
        var anchorStack: [String] = []
        registerAnchors(&anchorStack, ownID: node.anchorID, anchors: &anchors, at: sourceText.currentOffset)

        var headers: [BlockBox] = []
        var bodies: [BlockBox] = []
        var footers: [BlockBox] = []
        for child in node.children {
            guard case .element(let element) = child else { continue }
            switch element.style.display {
            case .tableHeaderGroup:
                headers.append(buildTableRowGroup(
                    for: element, config: config, containerWidth: containerWidth,
                    sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader, boxCount: &boxCount
                ))
            case .tableFooterGroup:
                footers.append(buildTableRowGroup(
                    for: element, config: config, containerWidth: containerWidth,
                    sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader, boxCount: &boxCount
                ))
            case .tableRowGroup:
                bodies.append(buildTableRowGroup(
                    for: element, config: config, containerWidth: containerWidth,
                    sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader, boxCount: &boxCount
                ))
            case .tableRow:
                bodies.append(buildTableRow(
                    for: element, config: config, containerWidth: containerWidth,
                    sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader, boxCount: &boxCount
                ))
            default:
                continue
            }
        }
        let groups = headers + bodies + footers

        let extras = horizontalExtras(of: node.style, percentBase: containerWidth, config: config)
        let available = max(0, containerWidth - extras)
        let columns = measureTableColumns(groups: groups, available: available, config: config)

        var boxStyle = node.style
        if case .auto = boxStyle.width, !columns.isEmpty {
            let spacingH = TableLayout.borderSpacing(of: boxStyle, rootFontSize: config.rootFontSize).horizontal
            let total = spacingH * CGFloat(columns.count + 1) + columns.reduce(0, +)
            boxStyle.width = .px(min(total, available))
        }
        let box = BlockBox(style: boxStyle, boxType: .block, children: groups)
        box.tableColumnMaxContent = columns
        Self.attachDebugIdentity(box, node: node)
        return box
    }

    private static func buildTableRowGroup(
        for node: ComputedStyleNode,
        config: BrowserLayoutConfig,
        containerWidth: CGFloat,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        imageLoader: (String) -> UIImage?,
        boxCount: inout Int
    ) -> BlockBox {
        var anchorStack: [String] = []
        registerAnchors(&anchorStack, ownID: node.anchorID, anchors: &anchors, at: sourceText.currentOffset)
        var rows: [BlockBox] = []
        for child in node.children {
            guard case .element(let element) = child, element.style.display == .tableRow else { continue }
            rows.append(buildTableRow(
                for: element, config: config, containerWidth: containerWidth,
                sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader, boxCount: &boxCount
            ))
        }
        let box = BlockBox(style: tableStructureStyle(node.style), boxType: .block, children: rows)
        Self.attachDebugIdentity(box, node: node)
        return box
    }

    private static func buildTableRow(
        for node: ComputedStyleNode,
        config: BrowserLayoutConfig,
        containerWidth: CGFloat,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        imageLoader: (String) -> UIImage?,
        boxCount: inout Int
    ) -> BlockBox {
        var anchorStack: [String] = []
        registerAnchors(&anchorStack, ownID: node.anchorID, anchors: &anchors, at: sourceText.currentOffset)
        var cells: [BlockBox] = []
        for child in node.children {
            guard case .element(let element) = child, element.style.display == .tableCell else { continue }
            var cellStyle = element.style
            // Margins do not apply to table cells (CSS 2.1 §17.5).
            cellStyle.marginTop = .px(0); cellStyle.marginRight = .px(0)
            cellStyle.marginBottom = .px(0); cellStyle.marginLeft = .px(0)
            let adjusted = ComputedStyleNode(
                tag: element.tag, semanticElement: element.semanticElement,
                style: cellStyle, children: element.children, nodeID: element.nodeID,
                linkTarget: element.linkTarget, anchorID: element.anchorID
            )
            let cell = buildBlockInternal(
                for: adjusted, config: config, containerWidth: containerWidth,
                sourceText: &sourceText, anchors: &anchors, imageLoader: imageLoader,
                boxCount: &boxCount
            )
            cell.tableColspan = tableColspan(of: element)
            cells.append(cell)
        }
        let box = BlockBox(style: tableStructureStyle(node.style), boxType: .block, children: cells)
        Self.attachDebugIdentity(box, node: node)
        return box
    }

    /// Rows and row groups take no margins, padding or borders in the separated
    /// model; their backgrounds survive for paint.
    private static func tableStructureStyle(_ style: ComputedStyle) -> ComputedStyle {
        var style = style
        style.marginTop = .px(0); style.marginRight = .px(0)
        style.marginBottom = .px(0); style.marginLeft = .px(0)
        style.paddingTop = .px(0); style.paddingRight = .px(0)
        style.paddingBottom = .px(0); style.paddingLeft = .px(0)
        style.borderTopWidth = 0; style.borderRightWidth = 0
        style.borderBottomWidth = 0; style.borderLeftWidth = 0
        style.width = .auto; style.height = .auto
        return style
    }

    private static func tableColspan(of node: ComputedStyleNode) -> Int {
        guard let raw = node.semanticElement?.attribute("colspan"),
              let value = Int(raw.trimmingCharacters(in: .whitespaces)) else { return 1 }
        return max(1, value)
    }

    /// A cell's border-box max-content width: its explicit width when given,
    /// else the widest unwrapped line of its content, plus padding and borders.
    private static func tableCellMaxContentWidth(
        of box: BlockBox,
        available: CGFloat,
        config: BrowserLayoutConfig
    ) -> CGFloat {
        let style = box.style
        let extras = horizontalExtras(of: style, percentBase: available, config: config)
        if let attachment = box.imageAttachment {
            return attachment.usedSize.width + extras
        }
        if let explicit = CSSLengthResolver.resolve(style.width, emBase: style.fontSize, remBase: config.rootFontSize, percentBase: available) {
            return max(explicit, 0) + extras
        }
        var indent: CGFloat = 0
        if box.ownsFirstFormattedLine, case .length(let length) = style.textIndent {
            indent = CSSLengthResolver.resolve(length, emBase: style.fontSize, remBase: config.rootFontSize, percentBase: available) ?? 0
        }
        let own = maxInlineWidth(box.inlineRuns, indent: indent, config: config)
        let kids = box.children.map { tableCellMaxContentWidth(of: $0, available: available, config: config) }.max() ?? 0
        return max(own, kids) + extras
    }

    /// Per-column max-content widths on the cell border-box basis (CSS 2.1
    /// §17.5.2.2 automatic layout). Single-column cells contribute their
    /// explicit width or their measured content width; spanning cells then
    /// distribute any deficit equally across their non-explicit columns.
    private static func measureTableColumns(
        groups: [BlockBox],
        available: CGFloat,
        config: BrowserLayoutConfig
    ) -> [CGFloat] {
        var rows: [BlockBox] = []
        for group in groups {
            if group.style.display == .tableRow {
                rows.append(group)
            } else {
                rows.append(contentsOf: group.children)
            }
        }
        var columnCount = 0
        for row in rows {
            columnCount = max(columnCount, row.children.reduce(0) { $0 + $1.tableColspan })
        }
        guard columnCount > 0 else { return [] }
        var columns = [CGFloat](repeating: 0, count: columnCount)
        var explicit = [Bool](repeating: false, count: columnCount)
        var spanned: [(column: Int, span: Int, width: CGFloat)] = []
        for row in rows {
            var cursor = 0
            for cell in row.children {
                let span = min(cell.tableColspan, columnCount - cursor)
                let width = tableCellMaxContentWidth(of: cell, available: available, config: config)
                if span == 1 {
                    columns[cursor] = max(columns[cursor], width)
                    if case .auto = cell.style.width {} else { explicit[cursor] = true }
                } else if span > 1 {
                    spanned.append((cursor, span, width))
                }
                cursor += max(span, 1)
            }
        }
        for entry in spanned.sorted(by: { $0.span < $1.span }) {
            let current = (entry.column..<(entry.column + entry.span)).reduce(0) { $0 + columns[$1] }
            guard entry.width > current else { continue }
            let autoColumns = (entry.column..<(entry.column + entry.span)).filter { !explicit[$0] }
            guard !autoColumns.isEmpty else { continue }
            let share = (entry.width - current) / CGFloat(autoColumns.count)
            for column in autoColumns { columns[column] += share }
        }
        return columns
    }

    // MARK: - Inline gathering

    /// Takes a block met inside inline content out to the enclosing block
    /// container: closes the pending runs into an anonymous block, then builds
    /// the block, both in document order.
    typealias BlockHoist = (
        _ block: ComputedStyleNode,
        _ runs: inout [InlineRun],
        _ sourceText: inout SourceTextBuilder,
        _ anchors: inout [String: Int],
        _ anchorStack: inout [String]
    ) -> Void

    private static func collectInline(
        _ node: ComputedStyleNode,
        into runs: inout [InlineRun],
        config: BrowserLayoutConfig,
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        anchorStack: inout [String],
        imageLoader: (String) -> UIImage?,
        hoist: BlockHoist
    ) {
        var localStack = anchorStack
        if let anchor = node.anchorID { localStack.append(anchor) }
        // A block child splits this inline box into pieces. Each piece keeps the
        // box's decoration; the start edge goes on the first, the end edge on the last.
        var firstRun = runs.count
        var sourceStart = sourceText.currentOffset
        var opensBox = true
        func closePiece(closesBox: Bool, runs: inout [InlineRun], sourceEnd: Int) {
            guard runs.count > firstRun else { return }
            preserveInlineDecoration(node, firstRun: firstRun, sourceStart: sourceStart,
                sourceEnd: sourceEnd, runs: &runs, opensBox: opensBox, closesBox: closesBox)
            opensBox = false
        }
        func split(
            _ block: ComputedStyleNode,
            runs: inout [InlineRun],
            sourceText: inout SourceTextBuilder,
            anchors: inout [String: Int],
            anchorStack: inout [String]
        ) {
            closePiece(closesBox: false, runs: &runs, sourceEnd: sourceText.currentOffset)
            hoist(block, &runs, &sourceText, &anchors, &anchorStack)
            firstRun = runs.count
            sourceStart = sourceText.currentOffset
        }
        defer { closePiece(closesBox: true, runs: &runs, sourceEnd: sourceText.currentOffset) }
        for child in node.children {
            switch child {
            case .text(let raw):
                appendTextNode(
                    raw, style: node.style, nodeID: node.nodeID, link: node.linkTarget,
                    combinesUpright: config.writingMode == .verticalRTL,
                    to: &runs, sourceText: &sourceText, anchors: &anchors, anchorStack: &localStack
                )
            case .element(let elementNode):
                if elementNode.tag == "br" {
                    let range = sourceText.append("\n")
                    runs.append(InlineRun(
                        text: "\n", style: elementNode.style,
                        sourceRange: range, nodeID: elementNode.nodeID,
                        linkTarget: elementNode.linkTarget, isHardBreak: true
                    ))
                } else if let element = elementNode.semanticElement,
                          let svgSource = Self.svgWrappedImageSource(element) {
                    registerAnchors(&localStack, ownID: elementNode.anchorID,
                                    anchors: &anchors, at: sourceText.currentOffset)
                    appendSVGImageRun(elementNode, source: svgSource, to: &runs,
                                      sourceText: &sourceText, imageLoader: imageLoader)
                } else if elementNode.tag == "img" {
                    registerAnchors(&localStack, ownID: elementNode.anchorID,
                                    anchors: &anchors, at: sourceText.currentOffset)
                    appendImageRun(elementNode, to: &runs, sourceText: &sourceText,
                                   imageLoader: imageLoader)
                } else if elementNode.tag == "ruby" {
                    appendRubyRun(
                        elementNode,
                        to: &runs,
                        sourceText: &sourceText,
                        anchors: &anchors,
                        anchorStack: &localStack
                    )
                } else if splitsInlineBox(elementNode.style) {
                    split(elementNode, runs: &runs, sourceText: &sourceText,
                          anchors: &anchors, anchorStack: &localStack)
                } else if elementNode.style.display == .none {
                    continue
                } else {
                    collectInline(
                        elementNode, into: &runs, config: config,
                        sourceText: &sourceText, anchors: &anchors,
                        anchorStack: &localStack, imageLoader: imageLoader,
                        hoist: split
                    )
                }
            }
        }
    }

    private static func preserveInlineDecoration(
        _ node: ComputedStyleNode, firstRun: Int, sourceStart: Int,
        sourceEnd: Int, runs: inout [InlineRun], opensBox: Bool = true, closesBox: Bool = true
    ) {
        let style = node.style
        let startEdge = opensBox && (style.paddingLeft != .px(0) || style.borderLeftWidth > 0)
        let endEdge = closesBox && (style.paddingRight != .px(0) || style.borderRightWidth > 0)
        let hasPaint = style.backgroundColor != nil || style.borderTopWidth > 0
            || style.borderBottomWidth > 0 || startEdge || endEdge
        guard hasPaint else { return }
        let decoration = InlineDecoration(nodeID: node.nodeID, style: style,
            sourceRange: NSRange(location: sourceStart, length: sourceEnd - sourceStart))
        for index in firstRun..<runs.count {
            runs[index].inlineDecorations.insert(decoration, at: 0)
        }
        // U+FFFC reserves shaped-only padding. U+2060 joins each edge to
        // its adjacent glyph so padding cannot be orphaned on a wrapped line.
        func edge(_ isStart: Bool) -> InlineRun {
            var run = InlineRun(text: isStart ? "\u{FFFC}\u{2060}" : "\u{2060}\u{FFFC}", style: style,
                sourceRange: NSRange(location: isStart ? sourceStart : sourceEnd, length: 0),
                nodeID: node.nodeID, linkTarget: node.linkTarget)
            run.inlineDecorations = [decoration]
            run.decorationEdge = isStart
            return run
        }
        if endEdge { runs.append(edge(false)) }
        if startEdge { runs.insert(edge(true), at: firstRun) }
    }

    // MARK: - Anchor registration

    /// Binds the pending `id`s to the source offset where their content starts,
    /// then clears the stack. The single registration point for
    /// `charOffset(forSpine:fragment:)` — TOC entries, search results, restored
    /// reading positions and link targets all read the same map.
    ///
    /// Also called for replaced elements (Phase 3A). Registering only at text
    /// used to lose every id whose element contains no text of its own, and the
    /// 多看 footnote idiom is exactly that shape: the reference marker is
    /// `<a id="ref_1" href="#note_1"><img/></a>`, so "回到正文" resolved to a
    /// missing anchor and jumped to the top of the chapter instead of back to
    /// the sentence. `ownID` covers an id on the replaced element itself, which
    /// no ancestor stack can carry.
    private static func registerAnchors(
        _ anchorStack: inout [String],
        ownID: String? = nil,
        anchors: inout [String: Int],
        at offset: Int
    ) {
        if let ownID, anchors[ownID] == nil {
            anchors[ownID] = offset
        }
        guard !anchorStack.isEmpty else { return }
        for id in anchorStack where anchors[id] == nil {
            anchors[id] = offset
        }
        anchorStack.removeAll()
    }

    // MARK: - Run creation

    private static func appendTextNode(
        _ raw: String,
        style: ComputedStyle,
        nodeID: Int,
        link: String?,
        combinesUpright: Bool,
        to runs: inout [InlineRun],
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        anchorStack: inout [String]
    ) {
        let collapsed = InlineLayout.collapseText(raw, mode: style.whiteSpace)
        guard !collapsed.isEmpty else { return }
        let isWhitespaceOnly = collapsed.allSatisfy { $0 == " " || $0 == "\t" }
        if isWhitespaceOnly && runs.isEmpty {
            // Leading whitespace at a group start (e.g. pretty-printed XHTML
            // between block siblings): dropped, never rendered.
            return
        }
        if !isWhitespaceOnly {
            registerAnchors(&anchorStack, anchors: &anchors, at: sourceText.currentOffset)
        }
        let range = sourceText.append(collapsed)
        // Authored 縦中横 in vertical text: each combined part keeps its characters in
        // sourceText and becomes one upright cell, like a ruby base.
        let segments = combinesUpright && !isWhitespaceOnly
            ? style.textCombineUpright.segments(of: collapsed) : [(text: collapsed, combined: false)]
        guard segments.contains(where: \.combined) else {
            runs.append(InlineRun(
                text: collapsed, style: style,
                sourceRange: range, nodeID: nodeID, linkTarget: link
            ))
            return
        }
        var location = range.location
        for segment in segments {
            let part = NSRange(location: location, length: (segment.text as NSString).length)
            location = NSMaxRange(part)
            if segment.combined {
                runs.append(InlineRun(
                    text: "\u{FFFC}", style: style, sourceRange: part, nodeID: nodeID, linkTarget: link,
                    combined: CombinedUprightUnit(text: segment.text, style: style, sourceRange: part,
                                                  nodeID: nodeID, linkTarget: link)
                ))
            } else {
                runs.append(InlineRun(text: segment.text, style: style, sourceRange: part, nodeID: nodeID, linkTarget: link))
            }
        }
    }

    private static func appendRubyRun(
        _ node: ComputedStyleNode,
        to runs: inout [InlineRun],
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        anchorStack: inout [String]
    ) {
        guard let structures = HorizontalRubySupport.structures(for: node) else {
            assertionFailure("unsupported Ruby reached BoxTreeBuilder")
            return
        }

        for structure in structures {
            var baseRuns: [InlineRun] = []
            var localAnchors = anchorStack
            if let own = node.anchorID { localAnchors.append(own) }
            collectRubyBase(
                structure.baseChildren,
                inheritedNode: node,
                runs: &baseRuns,
                sourceText: &sourceText,
                anchors: &anchors,
                anchorStack: &localAnchors
            )
            let pieces = baseRuns.map {
                RubyInlinePiece(
                    text: $0.text,
                    style: $0.style,
                    sourceRange: $0.sourceRange,
                    nodeID: $0.nodeID,
                    linkTarget: $0.linkTarget
                )
            }
            guard let first = pieces.first, let last = pieces.last else {
                assertionFailure("validated Ruby produced no base pieces")
                return
            }
            anchorStack.removeAll()

            var annotationPieces: [RubyAnnotationPiece] = []
            collectRubyAnnotation(
                structure.annotation.children,
                inheritedNode: structure.annotation,
                pieces: &annotationPieces
            )
            annotationPieces = trimRubyAnnotationEdges(annotationPieces)
            let range = NSRange(
                location: first.sourceRange.location,
                length: NSMaxRange(last.sourceRange) - first.sourceRange.location
            )
            let unit = RubyInlineUnit(
                base: pieces,
                annotation: RubyAnnotation(
                    pieces: annotationPieces
                ),
                sourceRange: range,
                nodeID: node.nodeID,
                linkTarget: node.linkTarget,
                alignment: node.style.rubyAlign,
                position: node.style.rubyPosition
            )
            runs.append(InlineRun(
                text: "\u{FFFC}",
                style: node.style,
                sourceRange: range,
                nodeID: node.nodeID,
                linkTarget: node.linkTarget,
                ruby: unit
            ))
        }
    }

    private static func collectRubyBase(
        _ children: [StyleTreeChild],
        inheritedNode: ComputedStyleNode,
        runs: inout [InlineRun],
        sourceText: inout SourceTextBuilder,
        anchors: inout [String: Int],
        anchorStack: inout [String]
    ) {
        for child in children {
            switch child {
            case .text(let raw):
                appendTextNode(
                    raw,
                    style: inheritedNode.style,
                    nodeID: inheritedNode.nodeID,
                    link: inheritedNode.linkTarget,
                    combinesUpright: false,
                    to: &runs,
                    sourceText: &sourceText,
                    anchors: &anchors,
                    anchorStack: &anchorStack
                )
            case .element(let element):
                guard element.tag != "rp" else { continue }
                var nestedAnchors = anchorStack
                if let own = element.anchorID { nestedAnchors.append(own) }
                collectRubyBase(
                    element.children,
                    inheritedNode: element,
                    runs: &runs,
                    sourceText: &sourceText,
                    anchors: &anchors,
                    anchorStack: &nestedAnchors
                )
            }
        }
    }

    private static func collectRubyAnnotation(
        _ children: [StyleTreeChild],
        inheritedNode: ComputedStyleNode,
        pieces: inout [RubyAnnotationPiece]
    ) {
        for child in children {
            switch child {
            case .text(let raw):
                let text = InlineLayout.collapseText(
                    raw,
                    mode: inheritedNode.style.whiteSpace
                )
                guard !text.isEmpty else { continue }
                pieces.append(RubyAnnotationPiece(
                    text: text,
                    style: inheritedNode.style,
                    nodeID: inheritedNode.nodeID,
                    linkTarget: inheritedNode.linkTarget
                ))
            case .element(let element):
                collectRubyAnnotation(
                    element.children,
                    inheritedNode: element,
                    pieces: &pieces
                )
            }
        }
    }

    private static func trimRubyAnnotationEdges(
        _ pieces: [RubyAnnotationPiece]
    ) -> [RubyAnnotationPiece] {
        var result = pieces
        while let first = result.first {
            let text = first.text.drop(while: { $0.isWhitespace })
            if text.isEmpty {
                result.removeFirst()
            } else if text.count != first.text.count {
                result[0] = RubyAnnotationPiece(
                    text: String(text),
                    style: first.style,
                    nodeID: first.nodeID,
                    linkTarget: first.linkTarget
                )
                break
            } else {
                break
            }
        }
        while let last = result.last {
            let text = last.text.reversed().drop(while: { $0.isWhitespace }).reversed()
            if text.isEmpty {
                result.removeLast()
            } else if text.count != last.text.count {
                result[result.count - 1] = RubyAnnotationPiece(
                    text: String(text),
                    style: last.style,
                    nodeID: last.nodeID,
                    linkTarget: last.linkTarget
                )
                break
            } else {
                break
            }
        }
        return result
    }

    /// The EPUB cover idiom: `<svg viewBox="0 0 1000 1333" width="100%"
    /// height="100%"><image xlink:href="cover.jpg"/></svg>` — an SVG element
    /// used purely as a wrapper around one raster image. Returns the image
    /// source, or nil when the SVG carries any real vector content.
    ///
    /// This is NOT general SVG support: a single `<image>` and nothing else to
    /// draw. `BrowserLayoutCapabilityScanner` calls the SAME predicate, so the
    /// scanner and the box tree can never disagree about which SVGs are
    /// renderable.
    static func svgWrappedImageSource(_ element: HTMLDOMElementSnapshot) -> String? {
        guard element.tagName == "svg" else { return nil }
        guard case .rasterWrapper(let source) = element.svgRenderability else {
            return nil
        }
        return source
    }

    /// Emits an SVG-wrapped cover image as a replaced element. BoxTreeBuilder
    /// records intrinsic data only; BlockLayout owns its final used size once
    /// the containing block is known.
    private static func appendSVGImageRun(
        _ node: ComputedStyleNode,
        source: String,
        to runs: inout [InlineRun],
        sourceText: inout SourceTextBuilder,
        imageLoader: (String) -> UIImage?
    ) {
        guard let image = imageLoader(source) else { return }
        let intrinsic = image.size
        guard intrinsic.width > 0, intrinsic.height > 0 else { return }
        runs.append(InlineRun(
            text: "\u{FFFC}", style: node.style,
            sourceRange: NSRange(location: sourceText.currentOffset, length: 0),
            nodeID: node.nodeID, linkTarget: node.linkTarget,
            atomic: AtomicInline(
                source: source, image: image, usedSize: intrinsic,
                nodeID: node.nodeID, linkTarget: node.linkTarget
            )
        ))
    }

    private static func appendImageRun(
        _ node: ComputedStyleNode,
        to runs: inout [InlineRun],
        sourceText: inout SourceTextBuilder,
        imageLoader: (String) -> UIImage?
    ) {
        let src = node.semanticElement?.attribute("src") ?? ""
        let image = imageLoader(src)
        let intrinsic = image?.size ?? .zero
        guard intrinsic.width > 0, intrinsic.height > 0, let image else { return }
        runs.append(InlineRun(
            text: "\u{FFFC}", style: node.style,
            sourceRange: NSRange(location: sourceText.currentOffset, length: 0),
            nodeID: node.nodeID, linkTarget: node.linkTarget,
            atomic: AtomicInline(
                source: src, image: image, usedSize: intrinsic,
                nodeID: node.nodeID, linkTarget: node.linkTarget
            )
        ))
    }

    private static func makeBlockImage(
        for node: ComputedStyleNode,
        imageLoader: (String) -> UIImage?
    ) -> AtomicInline? {
        let src = node.semanticElement?.attribute("src") ?? ""
        guard let image = imageLoader(src) else { return nil }
        return AtomicInline(
            source: src, image: image, usedSize: image.size,
            nodeID: node.nodeID, linkTarget: node.linkTarget
        )
    }

    // MARK: - Group lifecycle

    /// Closes the pending inline group as an anonymous block at the CURRENT
    /// position in the sibling order (a block sibling is about to follow).
    private static func flushGroup(
        _ runs: inout [InlineRun],
        style: ComputedStyle,
        into kids: inout [BlockBox],
        assignedFirstInlineContext: inout Bool
    ) {
        let visible = visibleRuns(runs)
        guard !visible.isEmpty else {
            runs = []
            return
        }
        kids.append(BlockBox(
            style: anonymousBlockStyle(inheriting: style),
            boxType: .anonymous,
            inlineRuns: visible,
            ownsFirstFormattedLine: !assignedFirstInlineContext
        ))
        assignedFirstInlineContext = true
        runs = []
    }

    /// Anonymous boxes inherit only the inheritable properties (CSS 2.1
    /// §9.2.1.1). Passing the parent style through verbatim leaks `float`,
    /// margins and sizing into the wrapper: a leaked float turns it into an
    /// occlusion that shoves following siblings' line bands below itself.
    private static func anonymousBlockStyle(inheriting style: ComputedStyle) -> ComputedStyle {
        var style = style
        style.display = .block
        style.cssFloat = .none
        style.cssClear = .none
        style.marginTop = .px(0); style.marginRight = .px(0)
        style.marginBottom = .px(0); style.marginLeft = .px(0)
        style.paddingTop = .px(0); style.paddingRight = .px(0)
        style.paddingBottom = .px(0); style.paddingLeft = .px(0)
        style.width = .auto; style.height = .auto
        style.minWidth = nil; style.maxWidth = nil
        style.minHeight = nil; style.maxHeight = nil
        style.borderTopWidth = 0; style.borderRightWidth = 0
        style.borderBottomWidth = 0; style.borderLeftWidth = 0
        style.pendingBorderTopWidth = nil; style.pendingBorderRightWidth = nil
        style.pendingBorderBottomWidth = nil; style.pendingBorderLeftWidth = nil
        style.borderTopStyle = .solid; style.borderRightStyle = .solid
        style.borderBottomStyle = .solid; style.borderLeftStyle = .solid
        style.borderColor = nil
        style.borderRadius = 0; style.pendingBorderRadius = nil
        style.backgroundColor = nil; style.backgroundImage = nil
        // The parent's rotation already turns this box with it; keeping the
        // declaration would rotate the wrapper a second time about its own center.
        style.transformRotate = nil
        return style
    }

    private static func visibleRuns(_ runs: [InlineRun]) -> [InlineRun] {
        var visible = runs
        while let last = visible.last,
              last.atomic == nil,
              !last.isHardBreak,
              last.text.allSatisfy({ $0 == " " || $0 == "\t" }) {
            visible.removeLast()
        }
        return visible
    }

    #if DEBUG
    /// BoxTreeBuilder owns unformatted runs only. A non-empty line array here
    /// means shaping escaped the InlineLayout call owned by BlockLayout.
    private static func assertUnformatted(_ box: BlockBox) {
        assert(box.lines.isEmpty, "BoxTreeBuilder must not create LayoutLine values")
        for child in box.children {
            assertUnformatted(child)
        }
    }
    #endif
}

extension BoxTreeBuilder {
    /// Total block-box count in a tree (lifecycle accounting).
    static func countBoxes(in box: BlockBox) -> Int {
        var count = 1
        for child in box.children {
            count += countBoxes(in: child)
        }
        return count
    }

    /// Copies DOM identity (tag/class/id/nodeID) onto a box for diagnostics.
    /// Layout never reads these.
    static func attachDebugIdentity(_ box: BlockBox, node: ComputedStyleNode) {
        box.debugTag = node.tag
        box.debugNodeID = node.nodeID
        box.debugID = node.anchorID
        if let element = node.semanticElement {
            box.debugClasses = element.classTokens
        }
    }
}
