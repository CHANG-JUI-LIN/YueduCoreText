import UIKit

/// The positioned layout the engine does.
///
/// `position: relative` makes a box the containing block of its absolutely
/// positioned children; its own offsets are not applied. `position: absolute`
/// is laid out for the shape books build interface panels from: a label
/// pinned inside the block that holds it, by `top` and `left` or `right`.
///
/// A positioned box is walked and painted where it stands in the document,
/// like every box, so pages keep their text in reading order. One declared
/// before a sibling it overlaps is therefore painted under it, where CSS 2.1
/// Appendix E paints positioned boxes last; `z-index` is parsed and not yet
/// applied.
///
/// `accepts` turns away what that does not cover:
/// - a box whose parent is not positioned (its containing block is further up),
///   or is not a block made of blocks (the box would sit among lines of text);
/// - a box with no `top`, or neither `left` nor `right`: its place would be
///   where the flow left it, which the engine does not track for it;
/// - a percentage `top`, which needs the containing block's height;
/// - vertical writing.
///
/// `fixed` and `sticky` are turned away from the declaration itself
/// (`BrowserLayoutCapabilityScanner`).
enum PositionSupport {
    static func accepts(_ root: ComputedStyleNode, writingMode: ReaderWritingMode) -> Bool {
        func visit(_ node: ComputedStyleNode) -> Bool {
            guard !node.style.isHidden else { return true }
            for child in node.children {
                guard case .element(let element) = child else { continue }
                if element.style.isAbsolutelyPositioned, !element.style.isHidden,
                   !canPlace(element, in: node, writingMode: writingMode) { return false }
                if !visit(element) { return false }
            }
            return true
        }
        return visit(root)
    }

    private static func canPlace(_ element: ComputedStyleNode, in parent: ComputedStyleNode,
                                 writingMode: ReaderWritingMode) -> Bool {
        guard writingMode == .horizontal,
              element.style.display == .block,
              parent.style.display == .block,
              parent.style.position == .relative || parent.style.position == .absolute,
              let top = element.style.insetTop,
              element.style.insetLeft != nil || element.style.insetRight != nil
        else { return false }
        if case .percent = top { return false }
        // The parent holds blocks only, so nothing of it is a line of text.
        return parent.children.allSatisfy { child in
            switch child {
            case .text(let text): return text.allSatisfy(\.isWhitespace)
            case .element(let sibling):
                return sibling.style.isHidden || sibling.style.display == .block || sibling.style.display == .table
            }
        }
    }
}
