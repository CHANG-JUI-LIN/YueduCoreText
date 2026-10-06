import CoreText
import Foundation
import UIKit
import YueduCoreTextTypography

/// An authored combined run, before layout.
struct CombinedUprightUnit {
    let text: String
    let style: ComputedStyle
    let sourceRange: NSRange
    let nodeID: Int
    let linkTarget: String?
}

/// A combined run laid out: one em along the column and across it, holding the run
/// set horizontally and, when wider than the cell, compressed to fit.
struct CombinedUprightBox {
    let unit: CombinedUprightUnit
    /// The cell's side: one em of the run's font.
    let em: CGFloat
    /// The run as drawn: horizontal, at most `em` wide.
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
}

enum CombinedUprightLayout {
    static func measure(
        unit: CombinedUprightUnit,
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)?,
        attributedSource: NSAttributedString?,
        cjkTypographyStyle: CJKTypographyStyle?
    ) -> CombinedUprightBox {
        let font = InlineLayout.resolvedFont(for: unit.style, resolver: fontResolver)
        let attributed: NSMutableAttributedString
        if let attributedSource {
            attributed = NSMutableAttributedString(attributedString: attributedSource.attributedSubstring(from: unit.sourceRange))
        } else {
            attributed = NSMutableAttributedString(string: unit.text,
                attributes: InlineLayout.textAttributes(for: unit.style, resolver: fontResolver))
        }
        if let cjkTypographyStyle {
            CJKTypography.applyFonts(to: attributed, style: cjkTypographyStyle)
        }
        let line = CombinedUpright.line(attributed, em: font.pointSize)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return CombinedUprightBox(unit: unit, em: font.pointSize, line: line, width: width, ascent: ascent, descent: descent)
    }
}
