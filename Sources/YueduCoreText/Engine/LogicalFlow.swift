import CoreText
import UIKit
import YueduCoreTextTypography

/// The existing line/fragment walker stores (inline, block) in CGPoint's (x, y)
/// slots. Keep those slots canonical until emission, including for vertical-rl.
/// CSS dimensions/edges are physical and are mapped once before box construction.
/// This adapter changes axes, not the block, line breaking or pagination algorithm.
enum LogicalFlow {
    static func size(_ physical: CGSize, mode: ReaderWritingMode) -> CGSize {
        mode == .horizontal ? physical : CGSize(width: physical.height, height: physical.width)
    }

    static func insets(_ physical: UIEdgeInsets, mode: ReaderWritingMode) -> UIEdgeInsets {
        mode == .horizontal ? physical : UIEdgeInsets(top: physical.right, left: physical.top,
                                                     bottom: physical.left, right: physical.bottom)
    }

    static func styleTree(_ node: ComputedStyleNode, mode: ReaderWritingMode) -> ComputedStyleNode {
        guard mode == .verticalRTL else { return node }
        var s = node.style
        let p = s
        s.width = p.height; s.height = p.width
        s.maxWidth = p.maxHeight; s.maxHeight = p.maxWidth
        s.minWidth = p.minHeight; s.minHeight = p.minWidth
        s.marginTop = p.marginRight; s.marginRight = p.marginBottom
        s.marginBottom = p.marginLeft; s.marginLeft = p.marginTop
        s.paddingTop = p.paddingRight; s.paddingRight = p.paddingBottom
        s.paddingBottom = p.paddingLeft; s.paddingLeft = p.paddingTop
        s.borderTopWidth = p.borderRightWidth; s.borderRightWidth = p.borderBottomWidth
        s.borderBottomWidth = p.borderLeftWidth; s.borderLeftWidth = p.borderTopWidth
        s.borderTopStyle = p.borderRightStyle; s.borderRightStyle = p.borderBottomStyle
        s.borderBottomStyle = p.borderLeftStyle; s.borderLeftStyle = p.borderTopStyle
        s.borderTopColor = p.borderRightColor; s.borderRightColor = p.borderBottomColor
        s.borderBottomColor = p.borderLeftColor; s.borderLeftColor = p.borderTopColor
        return ComputedStyleNode(tag: node.tag, semanticElement: node.semanticElement, style: s,
            children: node.children.map {
                if case .element(let child) = $0 { return .element(styleTree(child, mode: mode)) }
                return $0
            }, nodeID: node.nodeID, linkTarget: node.linkTarget, anchorID: node.anchorID,
            listItemOrdinal: node.listItemOrdinal)
    }

    static func documentExtent(_ root: BlockBox) -> CGFloat {
        max(0, root.frame.height + root.margins.top + root.margins.bottom)
    }

    /// The paged walker's logical insets for `config` on a page of `pageSize` (logical):
    /// the reader's, plus, for a chapter that asks to be centred and fits the page, what
    /// sets its painted content (`paintedExtent`) in the middle of the page's block extent
    /// (`BrowserLayoutConfig.centersSinglePage`). Only the start grows, and never by more
    /// than the whole chapter, margins and spacing included, leaves to spare, so it stays
    /// on one page.
    static func pageInsets(_ config: BrowserLayoutConfig, pageSize: CGSize, root: BlockBox) -> UIEdgeInsets {
        var result = insets(config.contentInsets, mode: config.writingMode)
        guard config.centersSinglePage, let painted = paintedExtent(root) else { return result }
        let available = pageSize.height - result.top - result.bottom
        let room = available - documentExtent(root)
        guard room > 0 else { return result }
        let shift = min(room, (available - (painted.end - painted.start)) / 2 - painted.start)
        // Under a point the page would not visibly move.
        if shift >= 1 { result.top += shift }
        return result
    }

    /// The block extent of what `root` paints, in the walker's document coordinates:
    /// from the top of its first line box or block image to the bottom of its last. Edge
    /// margins and the reader's spacing after the last paragraph
    /// (`BrowserLayoutConfig.paragraphSpacing`) paint nothing, so they have no say. Boxes
    /// are placed as `PageWalker` places them. Nil when the chapter has neither.
    static func paintedExtent(_ root: BlockBox) -> (start: CGFloat, end: CGFloat)? {
        var start = CGFloat.infinity
        var end = -CGFloat.infinity
        func visit(_ box: BlockBox, contentTop: CGFloat) {
            // A line with nothing on it, such as an empty anonymous block's, paints nothing.
            for line in box.lines where !line.runs.isEmpty && line.height > 0 {
                start = min(start, contentTop + line.top)
                end = max(end, contentTop + line.top + line.height)
            }
            if box.imageAttachment != nil {
                start = min(start, contentTop)
                end = max(end, contentTop + box.contentSize.height)
            }
            for child in box.children {
                visit(child, contentTop: contentTop + child.frame.minY + child.borders.top + child.padding.top)
            }
        }
        visit(root, contentTop: root.margins.top)
        return start < end ? (start, end) : nil
    }

    static func rect(_ logical: CGRect, blockExtent: CGFloat) -> CGRect {
        LogicalGeometry.physicalRect(LogicalRect(
            origin: LogicalPoint(inline: logical.minX, block: logical.minY),
            size: LogicalSize(inline: logical.width, block: logical.height)),
            mode: .verticalRTL, containerBlockExtent: blockExtent)
    }

    static func page(_ page: PageFragments, mode: ReaderWritingMode,
                     documentBlockExtent: CGFloat) -> PageFragments {
        guard mode == .verticalRTL else { return page }
        let extent = page.pageRect.height
        func fragment(_ value: Fragment) -> Fragment {
            switch value {
            case .group(let children): return .group(children.map(fragment))
            case .text(let t) where t.isCombinedUpright:
                return .text(combinedUpright(t, extent: extent, documentBlockExtent: documentBlockExtent))
            case .text(let t):
                // Decorations are measured from the baseline toward the line's
                // under side, which turns with it.
                var turned = TextFragment(sourceRange: t.sourceRange, nodeID: t.nodeID,
                    linkTarget: t.linkTarget, writingMode: mode,
                    rect: PageLocalRect(rawValue: rect(t.rect.rawValue, blockExtent: extent)),
                    documentRect: DocumentRect(rawValue: rect(t.documentRect.rawValue, blockExtent: documentBlockExtent)),
                    baselineY: extent - t.baselineY, font: t.font, color: t.color, ctLine: t.ctLine,
                    sourceMapping: t.sourceMapping, renderedTextOverride: t.renderedTextOverride)
                turned.textDecorations = t.textDecorations
                turned.textEmphasis = t.textEmphasis
                return .text(turned)
            case .fill(let f):
                return .fill(FillFragment(
                    rect: PageLocalRect(rawValue: rect(f.rect.rawValue, blockExtent: extent)),
                    documentRect: DocumentRect(rawValue: rect(f.documentRect.rawValue, blockExtent: documentBlockExtent)),
                    color: f.color, cornerRadius: f.cornerRadius,
                    borderTop: f.borderLeft, borderBottom: f.borderRight,
                    borderLeft: f.borderBottom, borderRight: f.borderTop,
                    nodeID: f.nodeID, writingMode: mode, fragmentPosition: f.fragmentPosition,
                    isBackgroundPaint: f.isBackgroundPaint, followsTextColor: f.followsTextColor))
            case .image(let i):
                return .image(ImageFragment(source: i.source, image: i.image, sourceRange: i.sourceRange,
                    nodeID: i.nodeID, linkTarget: i.linkTarget, writingMode: mode,
                    rect: PageLocalRect(rawValue: rect(i.rect.rawValue, blockExtent: extent)),
                    documentRect: DocumentRect(rawValue: rect(i.documentRect.rawValue, blockExtent: documentBlockExtent)),
                    alt: i.alt, isBackgroundPaint: i.isBackgroundPaint))
            }
        }
        return PageFragments(index: page.index,
            pageRect: PageLocalRect(rawValue: CGRect(origin: .zero, size: size(page.pageRect.rawValue.size, mode: mode))),
            fragments: page.fragments.map(fragment))
    }

    /// A 縦中横 cell, from the line's canonical axes to the page: one em square on
    /// the column's centre line, its text kept horizontal and centred in it both ways.
    /// The canonical rect is the line box at the cell's inline position, `baselineY`
    /// the column's centre line.
    private static func combinedUpright(_ t: TextFragment, extent: CGFloat, documentBlockExtent: CGFloat) -> TextFragment {
        let em = t.rect.rawValue.width
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = t.ctLine.map { CGFloat(CTLineGetTypographicBounds($0, &ascent, &descent, nil)) } ?? em
        func cell(_ line: CGRect, centre: CGFloat, blockExtent: CGFloat) -> CGRect {
            let square = rect(CGRect(x: line.minX, y: centre - em / 2, width: em, height: em), blockExtent: blockExtent)
            return CGRect(x: square.midX - width / 2, y: square.minY, width: width, height: square.height)
        }
        let page = cell(t.rect.rawValue, centre: t.baselineY, blockExtent: extent)
        let documentCentre = t.documentRect.rawValue.minY + (t.baselineY - t.rect.rawValue.minY)
        let document = cell(t.documentRect.rawValue, centre: documentCentre, blockExtent: documentBlockExtent)
        var fragment = TextFragment(sourceRange: t.sourceRange, nodeID: t.nodeID, linkTarget: t.linkTarget,
            writingMode: .horizontal, rect: PageLocalRect(rawValue: page),
            documentRect: DocumentRect(rawValue: document),
            baselineY: page.minY + (em + ascent - descent) / 2, font: t.font, color: t.color, ctLine: t.ctLine,
            sourceMapping: t.sourceMapping, renderedTextOverride: t.renderedTextOverride)
        fragment.isCombinedUpright = true
        fragment.textEmphasis = t.textEmphasis
        return fragment
    }
}

/// Vertical scope: normal-flow text, ruby, authored 縦中横, and images inline or as
/// blocks: upright, an inline one centred on the column's central baseline (WKWebView,
/// the app's fixture S005a). An image as a ruby's base, other replaced elements, floats,
/// inline-blocks and constrained block-axis dimensions need their own vertical acceptance
/// coverage before admission. Consumers receive a fact, never an empty page.
enum VerticalTextSupport {
    static func accepts(_ node: ComputedStyleNode, inRuby: Bool = false) -> Bool {
        // An img is `inline-block` by the UA sheet, and laid out as a replaced element
        // whatever its display; only another element's inline-block is a block container.
        let image = node.tag == "img"
        if ["svg", "video", "audio", "table"].contains(node.tag) || (image && inRuby) || node.style.isFloated
            || (node.style.display == .inlineBlock && !image) || node.style.maxWidth != nil { return false }
        switch node.style.width {
        case .auto, .px: break
        default: return false
        }
        // A combined run is one upright cell of plain text: never ruby, nor inside it.
        let ruby = inRuby || ["ruby", "rb", "rt", "rtc", "rp"].contains(node.tag)
        switch node.style.textCombineUpright {
        case .none: break
        case .unsupported: return false
        case .all, .digits: if ruby { return false }
        }
        return node.children.allSatisfy {
            if case .element(let child) = $0 { return accepts(child, inRuby: ruby) }
            return true
        }
    }
}
