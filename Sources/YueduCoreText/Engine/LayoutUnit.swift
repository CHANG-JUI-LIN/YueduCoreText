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
}
