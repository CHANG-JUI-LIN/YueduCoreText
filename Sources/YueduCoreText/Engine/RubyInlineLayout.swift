import CoreText
import Foundation
import UIKit
import YueduCoreTextTypography

struct RubyLinePiece {
    let text: String
    let style: ComputedStyle
    let sourceRange: NSRange
    let shapedRange: NSRange
    let nodeID: Int
    let linkTarget: String?
    let font: UIFont
    let x: CGFloat
    let width: CGFloat
}

struct RubyLine {
    let line: CTLine
    let pieces: [RubyLinePiece]
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    /// The content box of the fonts the cascade falls back to for its text, which an inline box
    /// at `line-height: normal` holds too (`InlineLayout`'s `textBox`).
    var fallbackAscent: CGFloat = 0
    var fallbackDescent: CGFloat = 0
}

/// The measured outer inline box. Its single advance is atomic to the parent
/// line breaker, while base and annotation retain independent shaped lines.
struct RubyBox {
    let unit: RubyInlineUnit
    let advance: CGFloat
    /// The room the ruby takes about its line's baseline on its block's first line: the base's
    /// inline box and its annotations, each where it is drawn.
    let ascent: CGFloat
    let descent: CGFloat
    /// The room it takes on every later line, as CSS Ruby 1 §4.4 sizes it: leading added on an
    /// annotation's side until three lines of this ruby would not overlap.
    var followingAscent: CGFloat = 0
    var followingDescent: CGFloat = 0
    /// The base's own inline box, its half-leading box: all its placeholder reports to Core
    /// Text. The annotations' room depends on the line (`InlineLayout`'s line box).
    var inlineBoxAscent: CGFloat = 0
    var inlineBoxDescent: CGFloat = 0
    let base: RubyLine
    let annotation: RubyLine
    let baseOffsetX: CGFloat
    let annotationOffsetX: CGFloat
    /// From the base's baseline to the annotation's, along the block axis (up is negative).
    let annotationBaselineOffset: CGFloat
    /// The unit's `outer` annotation.
    var outer: RubyLine? = nil
    var outerOffsetX: CGFloat = 0
    var outerBaselineOffset: CGFloat = 0
}

enum RubyInlineLayout {
    private struct InputPiece {
        let text: String
        let style: ComputedStyle
        let sourceRange: NSRange
        let nodeID: Int
        let linkTarget: String?
    }

    static func measure(
        unit: RubyInlineUnit,
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)?,
        attributedSource: NSAttributedString? = nil,
        writingMode: ReaderWritingMode = .horizontal,
        cjkTypographyStyle: CJKTypographyStyle? = nil
    ) -> RubyBox {
        let base = shape(
            unit.base.map {
                InputPiece(
                    text: $0.text,
                    style: $0.style,
                    sourceRange: $0.sourceRange,
                    nodeID: $0.nodeID,
                    linkTarget: $0.linkTarget
                )
            },
            fontResolver: fontResolver,
            attributedSource: attributedSource, writingMode: writingMode,
            cjkTypographyStyle: cjkTypographyStyle
        )
        let annotation = shape(
            unit.annotation.pieces.map {
                InputPiece(
                    text: $0.text,
                    style: $0.style,
                    sourceRange: unit.sourceRange,
                    nodeID: $0.nodeID,
                    linkTarget: $0.linkTarget ?? unit.linkTarget
                )
            },
            fontResolver: fontResolver, writingMode: writingMode,
            cjkTypographyStyle: cjkTypographyStyle
        )
        let outer = unit.outer.map { outer in
            shape(
                outer.pieces.map {
                    InputPiece(text: $0.text, style: $0.style, sourceRange: unit.sourceRange,
                               nodeID: $0.nodeID, linkTarget: $0.linkTarget ?? unit.linkTarget)
                },
                fontResolver: fontResolver, writingMode: writingMode,
                cjkTypographyStyle: cjkTypographyStyle
            )
        }
        let advance = max(base.width, annotation.width, outer?.width ?? 0)
        // Each side's annotations stack outward from the base's content box, the inner one first:
        // one over the base stands on what is under it, one under the base hangs from what is over it.
        // Measured, WKWebView iOS 27.2 (S001m, S001n; 17px PingFang at 1.5): an 8.5px annotation's
        // baseline 22 over the base's or 16 under it, 19 either side of a vertical line's centre,
        // and 13 further for a second one on the same side.
        var overEdge = base.ascent, underEdge = base.descent
        func place(_ line: RubyLine, position: RubyPosition) -> CGFloat {
            if position == .under {
                defer { underEdge += line.ascent + line.descent }
                return underEdge + line.ascent
            }
            defer { overEdge += line.ascent + line.descent }
            return -overEdge - line.descent
        }
        let annotationBaselineOffset = place(annotation, position: unit.position)
        // A block's first line holds the base's own inline box, its half-leading box, and the
        // annotations; an outer annotation on the side the inner one leaves free stands beyond
        // that box for the line's sake: two-sided readings grow a 1.5 line to 51.25, not the 51
        // their content and annotations reach.
        let leading = leadingBox(of: unit, base: base, fontResolver: fontResolver, writingMode: writingMode)
        var ascent = max(overEdge, leading.above), descent = max(underEdge, leading.below)
        let outerBaselineOffset = outer.map { line -> CGFloat in
            if unit.outerPosition == .under {
                descent += line.ascent + line.descent
            } else {
                ascent += line.ascent + line.descent
            }
            return place(line, position: unit.outerPosition)
        }
        // On later lines, each ruby container adds the leading its annotations need past its
        // line-height, all of it on its annotation's side, the outer container counting the inner
        // one's annotation too. Measured, WKWebView iOS 27.2 (S001m, S001n rows u2-ua): 18.75 under
        // a 1.5 line where the first line takes 19, 31.75 over it for 32, and a reading on each
        // side 31.75 either way where the first line takes 32 and 19.25.
        let inlineBox = leading.above + leading.below
        let content = base.ascent + base.descent
        var following = (ascent: leading.above, descent: leading.below)
        func grow(_ position: RubyPosition, by needed: CGFloat) {
            let extra = max(0, needed - inlineBox)
            if position == .under {
                following.descent = max(following.descent, leading.below + extra)
            } else {
                following.ascent = max(following.ascent, leading.above + extra)
            }
        }
        let innerHeight = annotation.ascent + annotation.descent
        grow(unit.position, by: content + innerHeight)
        if let outer { grow(unit.outerPosition, by: content + innerHeight + outer.ascent + outer.descent) }
        var box = RubyBox(
            unit: unit,
            advance: advance,
            ascent: ascent,
            descent: descent,
            base: base,
            annotation: annotation,
            baseOffsetX: (advance - base.width) / 2,
            annotationOffsetX: (advance - annotation.width) / 2,
            annotationBaselineOffset: annotationBaselineOffset
        )
        box.followingAscent = following.ascent
        box.followingDescent = following.descent
        box.inlineBoxAscent = leading.above
        box.inlineBoxDescent = leading.below
        if let outer, let outerBaselineOffset {
            box.outer = outer
            box.outerOffsetX = (advance - outer.width) / 2
            box.outerBaselineOffset = outerBaselineOffset
        }
        return box
    }

    /// The base's inline box about its baseline, half its leading either side of its content
    /// box (`InlineLayout.halfLeadingBox`); across a vertical line half its line-height either
    /// side of the central baseline, its content box at `normal`.
    private static func leadingBox(
        of unit: RubyInlineUnit,
        base: RubyLine,
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)?,
        writingMode: ReaderWritingMode
    ) -> (above: CGFloat, below: CGFloat) {
        guard let style = unit.base.first?.style else { return (base.ascent, base.descent) }
        if writingMode == .verticalRTL {
            let half = style.lineHeight.map { $0 / 2 } ?? max(base.ascent, base.fallbackAscent)
            return (half, half)
        }
        let box = InlineLayout.halfLeadingBox(InlineLayout.resolvedFont(for: style, resolver: fontResolver),
                                              lineHeight: style.lineHeight)
        guard style.lineHeight == nil else { return box }
        return (max(box.above, base.fallbackAscent), max(box.below, base.fallbackDescent))
    }

    private static func shape(
        _ inputs: [InputPiece],
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)?,
        attributedSource: NSAttributedString? = nil,
        writingMode: ReaderWritingMode = .horizontal,
        cjkTypographyStyle: CJKTypographyStyle? = nil
    ) -> RubyLine {
        let attributed = NSMutableAttributedString()
        var starts: [Int] = []
        var fonts: [UIFont] = []
        for input in inputs {
            starts.append(attributed.length)
            let font = InlineLayout.resolvedFont(for: input.style, resolver: fontResolver)
            fonts.append(font)
            if let attributedSource {
                attributed.append(attributedSource.attributedSubstring(from: input.sourceRange))
            } else {
                attributed.append(NSAttributedString(
                    string: input.text,
                    attributes: InlineLayout.textAttributes(for: input.style, resolver: fontResolver)
                ))
            }
        }
        if let cjkTypographyStyle {
            CJKTypography.apply(to: attributed, style: cjkTypographyStyle, vertical: writingMode == .verticalRTL)
        }
        if writingMode == .verticalRTL {
            attributed.addAttribute(kCTVerticalFormsAttributeName as NSAttributedString.Key,
                                    value: true, range: NSRange(location: 0, length: attributed.length))
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // WebKit's content box: each font's ascent and descent rounded up, as a line's text
        // boxes are measured (`InlineLayout.roundedContentExtent`), or across a vertical line
        // half its height either side of the central baseline.
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            guard let font = value as? UIFont else { return }
            let content = InlineLayout.roundedContentExtent(font)
            if writingMode == .verticalRTL {
                ascent = max(ascent, (content.ascent + content.descent) / 2)
                descent = ascent
            } else {
                ascent = max(ascent, content.ascent)
                descent = max(descent, content.descent)
            }
        }
        var fallbackAscent: CGFloat = 0
        var fallbackDescent: CGFloat = 0
        let string = attributed.string as NSString
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            guard let used = attributes[.font] as? UIFont else { return }
            let asked = attributes[CJKTypography.replacedFontAttribute] as? UIFont ?? used
            let language = attributes[kCTLanguageAttributeName as NSAttributedString.Key]
            for fallback in InlineLayout.fallbackFonts(for: asked, text: string.substring(with: range), language: language) {
                let content = InlineLayout.roundedContentExtent(fallback)
                if writingMode == .verticalRTL {
                    fallbackAscent = max(fallbackAscent, (content.ascent + content.descent) / 2)
                    fallbackDescent = fallbackAscent
                } else {
                    fallbackAscent = max(fallbackAscent, content.ascent)
                    fallbackDescent = max(fallbackDescent, content.descent)
                }
            }
        }
        let measured = inputs.indices.map { index -> RubyLinePiece in
            let start = starts[index]
            let end = start + (inputs[index].text as NSString).length
            let x0 = GlyphBoundary.offset(line, at: start)
            let x1 = GlyphBoundary.offset(line, at: end)
            return RubyLinePiece(
                text: inputs[index].text,
                style: inputs[index].style,
                sourceRange: inputs[index].sourceRange,
                shapedRange: NSRange(location: start, length: end - start),
                nodeID: inputs[index].nodeID,
                linkTarget: inputs[index].linkTarget,
                font: fonts[index],
                x: x0,
                width: max(0, x1 - x0)
            )
        }
        return RubyLine(
            line: line,
            pieces: measured,
            width: width,
            ascent: ascent,
            descent: descent,
            fallbackAscent: fallbackAscent,
            fallbackDescent: fallbackDescent
        )
    }
}

/// Retained by the outer placeholder's CTRunDelegate for as long as CoreText
/// retains the shaped parent line.
final class RubyRunDelegateBox {
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat

    init(_ ruby: RubyBox) {
        width = ruby.advance
        ascent = ruby.inlineBoxAscent
        descent = ruby.inlineBoxDescent
    }

    static let callbacks: CTRunDelegateCallbacks = {
        CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in
                _ = Unmanaged<RubyRunDelegateBox>.fromOpaque(pointer).takeRetainedValue()
            },
            getAscent: { pointer in
                Unmanaged<RubyRunDelegateBox>.fromOpaque(pointer).takeUnretainedValue().ascent
            },
            getDescent: { pointer in
                Unmanaged<RubyRunDelegateBox>.fromOpaque(pointer).takeUnretainedValue().descent
            },
            getWidth: { pointer in
                Unmanaged<RubyRunDelegateBox>.fromOpaque(pointer).takeUnretainedValue().width
            }
        )
    }()
}
