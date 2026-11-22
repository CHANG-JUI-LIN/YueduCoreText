import UIKit

/// What the engine makes of `display: flex`, before layout (`FlexLayout`).
///
/// A flex container's children are flex items (CSS Flexbox §4): each element
/// child, made a block whatever its `display` was, and each run of text
/// straight inside the container, wrapped in an anonymous block. White space
/// between items is not rendered. `itemStyle` and `items` make the style tree
/// say so, so the box tree holds one block box per item.
///
/// `accepts` turns away what the layout does not place: reversed directions
/// and `order`, which paint items out of source order, and vertical text.
enum FlexSupport {

    /// `style` as the child of a flex container computes it: blockified, and
    /// neither floated nor shifted on a line (CSS Flexbox §4, CSS Display §2.7).
    static func itemStyle(_ style: ComputedStyle, in container: ComputedStyle) -> ComputedStyle {
        guard container.isFlexContainer, !style.isHidden, !style.isAbsolutelyPositioned else { return style }
        var style = style
        if style.display == .inline || style.display == .inlineBlock { style.display = .block }
        style.cssFloat = .none
        style.cssClear = .none
        style.verticalAlignOffset = 0
        return style
    }

    /// Children that stay inline content whatever their `display`: the box
    /// tree reads them by tag. As items they go in an anonymous block.
    private static func staysInline(_ node: ComputedStyleNode) -> Bool {
        node.tag == "ruby" || node.tag == "svg"
    }

    /// The container's children as items: text runs and the inline-only
    /// elements wrapped, white space dropped, elements kept.
    static func items(of children: [StyleTreeChild], container: ComputedStyle, nextNodeID: inout Int,
                      linkTarget: String?) -> [StyleTreeChild] {
        var result: [StyleTreeChild] = []
        var text: [StyleTreeChild] = []
        func wrap(_ content: [StyleTreeChild]) {
            let style = BoxTreeBuilder.anonymousBlockStyle(inheriting: container)
            result.append(.element(ComputedStyleNode(
                tag: "", semanticElement: nil, style: style, children: content,
                nodeID: nextNodeID, linkTarget: linkTarget, anchorID: nil)))
            nextNodeID += 1
        }
        func flushText() {
            let hasInk = text.contains {
                if case .text(let string) = $0 { return !string.allSatisfy(\.isWhitespace) }
                return false
            }
            if hasInk { wrap(text) }
            text = []
        }
        for child in children {
            switch child {
            case .text:
                text.append(child)
            case .element(let node):
                flushText()
                if staysInline(node) { wrap([child]) } else { result.append(child) }
            }
        }
        flushText()
        return result
    }

    /// The anonymous item `items` made.
    private static func isAnonymousItem(_ node: ComputedStyleNode) -> Bool {
        node.tag.isEmpty && node.semanticElement == nil
    }

    private static func acceptsItem(_ node: ComputedStyleNode) -> Bool {
        let style = node.style
        // A line break between items, an item out of source order, an item
        // positioned against the container, and table parts with no table.
        if node.tag == "br" || style.flex.order != 0 || style.isAbsolutelyPositioned || style.isInlineTable {
            return false
        }
        switch style.display {
        case .tableRowGroup, .tableHeaderGroup, .tableFooterGroup, .tableRow, .tableCell: return false
        default: return true
        }
    }

    /// False when some flex container is one the layout does not place.
    static func accepts(_ node: ComputedStyleNode, writingMode: ReaderWritingMode) -> Bool {
        if node.style.isFlexContainer {
            let elements = node.children.compactMap { child -> ComputedStyleNode? in
                if case .element(let element) = child { return element }
                return nil
            }
            if writingMode == .horizontal {
                guard elements.allSatisfy(acceptsItem) else { return false }
            } else {
                // Vertical text has no flex layout. A column that stretches its
                // one run of text is the block it would be anyway.
                guard node.style.flexIsColumn, node.style.alignItems == .stretch,
                      elements.allSatisfy(isAnonymousItem), elements.count <= 1 else { return false }
            }
        }
        return node.children.allSatisfy {
            if case .element(let child) = $0 { return accepts(child, writingMode: writingMode) }
            return true
        }
    }
}
