import UIKit

/// `calc()` is computed for widths, side margins, side paddings and side insets, against the
/// containing block's width. In vertical text those properties are block-axis ones, whose
/// percentages layout treats as `auto` or resolves against nothing: a chapter that uses one
/// there is turned away.
enum CalcSupport {
    static func accepts(_ root: ComputedStyleNode, writingMode: ReaderWritingMode) -> Bool {
        guard writingMode != .horizontal else { return true }
        func usesCalc(_ node: ComputedStyleNode) -> Bool {
            let style = node.style
            let lengths: [CSSLength?] = [
                style.width, style.maxWidth, style.height, style.maxHeight,
                style.marginLeft, style.marginRight, style.marginTop, style.marginBottom,
                style.paddingLeft, style.paddingRight, style.paddingTop, style.paddingBottom,
                style.insetLeft, style.insetRight, style.insetTop, style.insetBottom,
            ]
            if lengths.contains(where: { if case .calc? = $0 { return true } else { return false } }) { return true }
            return node.children.contains { child in
                if case .element(let element) = child { return usesCalc(element) }
                return false
            }
        }
        return !usesCalc(root)
    }
}
