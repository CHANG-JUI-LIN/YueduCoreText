import CoreGraphics

/// WebKit's unit for the sizes of boxes: 1/64 px.
///
/// A line's text is measured in floats; a box sized to content is as wide as
/// that content rounded up to the unit. The engine keeps floats throughout and
/// uses the unit only where the difference decides a line break (`RubyInlineLayout`).
enum LayoutUnit {
    /// A width measured from content, as the box sized to it holds it. (A value
    /// within a thousandth of a unit is taken as that unit: a sum of float
    /// advances that lands a rounding error above it is not a unit wider.)
    static func ceil(_ value: CGFloat) -> CGFloat {
        ((value * 64) - 0.001).rounded(.up) / 64
    }

    /// How far past its box a line's text may reach and still be on the line: half a
    /// unit. Measured, the app's fixture S021: a column its text fills exactly holds one
    /// ruby as wide as its one-character base (a third of a unit over at 14pt), and not two.
    static let fitTolerance: CGFloat = 1.0 / 128

    /// A length as a box holds it: truncated to the unit.
    static func floor(_ value: CGFloat) -> CGFloat {
        ((value * 64) + 0.001).rounded(.down) / 64
    }

    /// A `line-height` given as a number or a percentage, as WebKit computes it
    /// (`RenderStyle::computedLineHeight`, `minimumValueForLength`): the font size is
    /// taken as a layout unit, and so is the product. At 14pt (18.6667px) a line-height
    /// of 1.75 is 18.65625 × 1.75 = 32.6484, held as 32.640625, where the plain product
    /// is 32.6667. Measured, WKWebView iOS 27.2, 草枕: its columns are 32.640625 apart,
    /// and 250 of them had drifted 6.5px from WebKit's. (A length, `1.75em`, is a float
    /// and is not truncated.)
    static func lineHeight(fontSize: CGFloat, factor: CGFloat) -> CGFloat {
        floor(floor(fontSize) * factor)
    }
}
