import CoreGraphics
import UIKit

/// The `<html>` element's own box.
///
/// The box tree's root is `<body>`: `<html>` contributes what it lets its
/// children inherit, and its background is the canvas's (`canvasStyle`). A book can also
/// shape the page on it. The EPUB 3 sample every Japanese template descends
/// from writes `html { margin: auto 1em; padding: 1em 0; max-height: 28em }`:
/// in vertical text every column is at most 28em long and centred on the
/// page, and with the box ignored the text ran the page's full height.
///
/// It is not a box of its own in the tree, which would cost every chapter a
/// level of layout's recursion. Its width, margins, borders and padding are
/// resolved once against the page: `<body>` is laid out in the content width
/// that leaves, and what surrounds that content is added to `<body>`'s own
/// margins, which every consumer of the root box already reads as the root's
/// insets. Its borders take their room and are not painted, and its `height`
/// and `min-height` are not applied.
enum RootElementBox {

    /// Whether `style`, the `<html>` element's, shapes a box at all: the usual
    /// `html { margin: 0; padding: 0; height: 100% }` does not.
    static func hasBox(_ style: ComputedStyle) -> Bool {
        func isZero(_ length: CSSLength) -> Bool {
            switch length {
            case .px(let value), .pt(let value), .em(let value), .rem(let value),
                 .percent(let value), .vh(let value), .vw(let value): return value == 0
            case .auto, .calc: return false
            }
        }
        if case .auto = style.width {} else { return true }
        if style.maxWidth != nil || style.maxHeight != nil || style.minWidth != nil { return true }
        if style.borderTopWidth + style.borderRightWidth + style.borderBottomWidth + style.borderLeftWidth > 0 { return true }
        return ![style.marginTop, style.marginRight, style.marginBottom, style.marginLeft,
                 style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].allSatisfy(isZero)
    }

    /// Whether `style`, the `<html>` element's, paints a background. It is the
    /// canvas's (CSS Backgrounds §2.11.2): the page's, edge to edge. Only when
    /// `<html>` has none does `<body>`'s take that place; beside one, `<body>`'s
    /// is an ordinary box's and paints its own box.
    static func hasBackground(_ style: ComputedStyle) -> Bool {
        style.backgroundColor != nil || style.backgroundImage != nil
    }

    /// The style whose background the page shows.
    static func canvasStyle(for root: BlockBox) -> ComputedStyle {
        if let html = root.rootElementStyle, hasBackground(html) { return html }
        return root.style
    }

    /// Whether `root`, the `<body>` box, paints its own background as a box.
    static func bodyPaintsBackground(_ root: BlockBox) -> Bool {
        root.rootElementStyle.map(hasBackground) ?? false
    }

    /// Gives `root` the `<html>` element's style, on the canonical axes. In a
    /// function of its own, and the callers below too: whole styles on the
    /// frame that calls layout are stack every level of nesting stands on.
    @inline(never)
    static func attach(_ style: [ComputedStyle], to root: BlockBox, mode: ReaderWritingMode) {
        root.rootElementStyle = style.first.map { LogicalFlow.style($0, mode: mode) }
    }

    /// The width `root` (the `<body>` box) is laid out in: the page's, or what
    /// the `<html>` element's box leaves of it.
    @inline(never)
    static func contentWidth(for root: BlockBox, pageWidth: CGFloat, rootFontSize: CGFloat) -> CGFloat {
        guard let sides = sides(for: root, pageWidth: pageWidth, rootFontSize: rootFontSize) else { return pageWidth }
        return sides.contentWidth
    }

    /// After `root` is laid out: what the `<html>` element puts around its
    /// content joins `root`'s margins. Layout resolves those afresh, so this
    /// follows every layout of the root.
    @inline(never)
    static func addInsets(to root: BlockBox, pageWidth: CGFloat, rootFontSize: CGFloat) {
        guard let sides = sides(for: root, pageWidth: pageWidth, rootFontSize: rootFontSize) else { return }
        root.margins.top += sides.margins.top + sides.borders.top + sides.padding.top
        root.margins.bottom += sides.margins.bottom + sides.borders.bottom + sides.padding.bottom
        root.margins.left += sides.margins.left + sides.borders.left + sides.padding.left
        root.margins.right += sides.margins.right + sides.borders.right + sides.padding.right
    }

    private static func sides(for root: BlockBox, pageWidth: CGFloat, rootFontSize: CGFloat) -> BlockLayout.Sides? {
        guard let style = root.rootElementStyle, hasBox(style) else { return nil }
        return BlockLayout.resolveSides(BlockBox(style: style), containerWidth: pageWidth,
                                        rootFontSize: rootFontSize, writingMode: .horizontal)
    }
}
