import CoreGraphics

/// How far `vertical-align: super` and `sub` move a box's baseline from its parent's, as WebKit
/// moves it (`InlineLineBoxVerticalAligner`): by the parent's font size, not the box's own, a
/// third of it and 1 more up, a fifth of it and 1 more down. In `vertical-rl`, up is right.
/// Measured, WKWebView iOS 26.5 (the app's S013 and S013a fixtures, 17px parent): a superscript
/// 6.66 up, a subscript 4.39 down, at 13.8125px and at 8.5px alike.
public enum VerticalAlignShift {
    public static func superscript(parentFontSize: CGFloat) -> CGFloat {
        parentFontSize / 3 + 1
    }

    public static func `subscript`(parentFontSize: CGFloat) -> CGFloat {
        parentFontSize / 5 + 1
    }
}
