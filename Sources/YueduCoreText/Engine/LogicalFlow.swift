import UIKit

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
        s.marginTop = p.marginRight; s.marginRight = p.marginBottom
        s.marginBottom = p.marginLeft; s.marginLeft = p.marginTop
        s.paddingTop = p.paddingRight; s.paddingRight = p.paddingBottom
        s.paddingBottom = p.paddingLeft; s.paddingLeft = p.paddingTop
        s.borderTopWidth = p.borderRightWidth; s.borderRightWidth = p.borderBottomWidth
        s.borderBottomWidth = p.borderLeftWidth; s.borderLeftWidth = p.borderTopWidth
        s.borderTopStyle = p.borderRightStyle; s.borderRightStyle = p.borderBottomStyle
        s.borderBottomStyle = p.borderLeftStyle; s.borderLeftStyle = p.borderTopStyle
        return ComputedStyleNode(tag: node.tag, semanticElement: node.semanticElement, style: s,
            children: node.children.map {
                if case .element(let child) = $0 { return .element(styleTree(child, mode: mode)) }
                return $0
            }, nodeID: node.nodeID, linkTarget: node.linkTarget, anchorID: node.anchorID)
    }

    static func documentExtent(_ root: BlockBox) -> CGFloat {
        max(0, root.frame.height + root.margins.top + root.margins.bottom)
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
            case .text(let t):
                return .text(TextFragment(sourceRange: t.sourceRange, nodeID: t.nodeID,
                    linkTarget: t.linkTarget, writingMode: mode,
                    rect: PageLocalRect(rawValue: rect(t.rect.rawValue, blockExtent: extent)),
                    documentRect: DocumentRect(rawValue: rect(t.documentRect.rawValue, blockExtent: documentBlockExtent)),
                    baselineY: extent - t.baselineY, font: t.font, color: t.color, ctLine: t.ctLine,
                    sourceMapping: t.sourceMapping, renderedTextOverride: t.renderedTextOverride))
            case .fill(let f):
                return .fill(FillFragment(
                    rect: PageLocalRect(rawValue: rect(f.rect.rawValue, blockExtent: extent)),
                    documentRect: DocumentRect(rawValue: rect(f.documentRect.rawValue, blockExtent: documentBlockExtent)),
                    color: f.color, cornerRadius: f.cornerRadius,
                    borderTop: f.borderLeft, borderBottom: f.borderRight,
                    borderLeft: f.borderBottom, borderRight: f.borderTop,
                    nodeID: f.nodeID, writingMode: mode, fragmentPosition: f.fragmentPosition,
                    isBackgroundPaint: f.isBackgroundPaint))
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
}

/// Initial vertical scope: normal-flow text and ruby. Replaced elements, floats
/// and constrained block-axis dimensions need their own vertical acceptance
/// coverage before admission. Consumers receive a fact, never an empty page.
enum VerticalTextSupport {
    static func accepts(_ node: ComputedStyleNode) -> Bool {
        if ["img", "svg", "video", "audio", "table"].contains(node.tag) || node.style.isFloated
            || node.style.maxWidth != nil { return false }
        switch node.style.width {
        case .auto, .px: break
        default: return false
        }
        return node.children.allSatisfy {
            if case .element(let child) = $0 { return accepts(child) }
            return true
        }
    }
}
