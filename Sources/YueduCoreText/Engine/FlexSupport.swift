import UIKit

/// The flex layout the engine does: a container whose content is one flex item
/// made of text (CSS Flexbox §4: a run of text straight inside the container is
/// wrapped in an anonymous item). Books use it to centre a heading or a label,
/// `display: flex; justify-content: center` around a few words.
///
/// One item in a row is a box as wide as its content, placed along the line by
/// `justify-content`: exactly an inline-block on a line aligned that way, which
/// the engine already lays out. `singleItem` builds that anonymous inline-block
/// and `containerStyle` gives the container the matching line alignment. The
/// item's text keeps the container's own `text-align`, which it inherits.
///
/// In a column the item is as wide as the container unless `align-items` says
/// otherwise; `stretch`, the default, leaves an ordinary block.
///
/// A container with an element among its children has items of its own to
/// place; `accepts` turns it away. The cross-axis alignment of a container
/// with a fixed height is not applied: the item stays at the top.
enum FlexSupport {

    /// Where the single item goes on its line; nil when it fills the line.
    private static func lineAlignment(of container: ComputedStyle) -> NSTextAlignment? {
        let alignment = container.flexIsColumn ? container.alignItems : container.justifyContent
        switch alignment {
        case .stretch: return container.flexIsColumn ? nil : .left
        case .start: return .left
        case .center: return .center
        case .end: return .right
        }
    }

    /// The container's style for its own node: its lines are aligned as the
    /// item is placed. Children are styled from the unchanged style, so the
    /// item's text inherits the authored `text-align`.
    static func containerStyle(_ style: ComputedStyle) -> ComputedStyle {
        guard style.isFlexContainer, let alignment = lineAlignment(of: style) else { return style }
        var style = style
        style.textAlign = alignment
        return style
    }

    /// The anonymous item around `children`, when they are text and nothing
    /// else and the item does not simply fill the container.
    static func singleItem(of children: [StyleTreeChild], container: ComputedStyle, nodeID: Int,
                           linkTarget: String?) -> ComputedStyleNode? {
        guard container.isFlexContainer, lineAlignment(of: container) != nil, !children.isEmpty,
              children.allSatisfy({ if case .text = $0 { return true } else { return false } }),
              children.contains(where: { if case .text(let text) = $0 { return !text.allSatisfy(\.isWhitespace) } else { return false } })
        else { return nil }
        var style = BoxTreeBuilder.anonymousBlockStyle(inheriting: container)
        style.display = .inlineBlock
        style.isFlexContainer = false
        return ComputedStyleNode(tag: "", semanticElement: nil, style: style, children: children,
                                 nodeID: nodeID, linkTarget: linkTarget, anchorID: nil)
    }

    /// False when some flex container holds an element: more than the one
    /// item this layout places.
    static func accepts(_ node: ComputedStyleNode) -> Bool {
        if node.style.isFlexContainer {
            for child in node.children {
                guard case .element(let element) = child else { continue }
                // The anonymous item `singleItem` made.
                if element.tag.isEmpty, element.semanticElement == nil { continue }
                return false
            }
        }
        return node.children.allSatisfy {
            if case .element(let child) = $0 { return accepts(child) }
            return true
        }
    }
}
