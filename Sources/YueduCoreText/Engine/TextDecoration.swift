import CoreText
import UIKit

/// `text-decoration-line` (CSS Text Decoration 4 §2.1).
struct TextDecorationLines: OptionSet, Hashable, Sendable {
    let rawValue: UInt8
    static let underline = TextDecorationLines(rawValue: 1)
    static let overline = TextDecorationLines(rawValue: 2)
    static let lineThrough = TextDecorationLines(rawValue: 4)
}

/// `text-decoration-style`.
enum TextDecorationStyle: Equatable, Sendable {
    case solid, double, dotted, dashed, wavy
}

/// `text-decoration-thickness`: a length resolves against the font size of the
/// box that places the line, as WebKit resolves it against the painting box.
enum TextDecorationThickness: Equatable {
    case auto, fromFont, length(CSSLength)
}

/// `text-underline-position`, inherited. `under` sets the underline below
/// every box of the line that carries it; vertical writing always does, on
/// the left unless `right` asks for the other side.
struct TextUnderlinePosition: Equatable {
    var fromFont = false
    var under = false
    var right = false
}

/// The box that set a decoration, whose baseline and font place its lines
/// on every text run it holds.
final class TextDecorationAnchor {
    let style: ComputedStyle
    init(style: ComputedStyle) { self.style = style }
}

/// A decoration in effect on a box: set on it or on an ancestor, drawn in the
/// originating box's colour and style (CSS Text Decoration 4 §2.1). The lines
/// reach in-flow inline content and in-flow blocks; a block's own lines, and
/// an ancestor's lines once they reach a block, are placed by that block's
/// root inline box (`anchor` nil). A descendant's `none` removes nothing.
struct AppliedTextDecoration: Equatable {
    let lines: TextDecorationLines
    /// nil is the originating box's `color`, nil as well.
    let color: UIColor?
    let style: TextDecorationStyle
    let thickness: TextDecorationThickness
    let anchor: TextDecorationAnchor?

    static func == (lhs: AppliedTextDecoration, rhs: AppliedTextDecoration) -> Bool {
        lhs.lines == rhs.lines && lhs.color == rhs.color && lhs.style == rhs.style
            && lhs.thickness == rhs.thickness && lhs.anchor === rhs.anchor
    }
}

/// The CSS values of the `text-decoration` properties.
enum TextDecorationValue {
    static func lines(_ value: String) -> TextDecorationLines? {
        if value == "none" { return [] }
        var lines: TextDecorationLines = []
        for token in value.split(whereSeparator: \.isWhitespace) {
            guard let line = line(String(token)), !lines.contains(line) else { return nil }
            lines.insert(line)
        }
        return lines.isEmpty ? nil : lines
    }

    /// One line keyword; `blink` is valid and draws nothing.
    private static func line(_ token: String) -> TextDecorationLines? {
        switch token {
        case "underline": return .underline
        case "overline": return .overline
        case "line-through": return .lineThrough
        case "blink": return TextDecorationLines(rawValue: 0x80)
        default: return nil
        }
    }

    static func style(_ token: String) -> TextDecorationStyle? {
        switch token {
        case "solid": return .solid
        case "double": return .double
        case "dotted": return .dotted
        case "dashed": return .dashed
        case "wavy": return .wavy
        default: return nil
        }
    }

    static func thickness(_ token: String) -> TextDecorationThickness? {
        switch token {
        case "auto": return .auto
        case "from-font": return .fromFont
        default:
            guard let length = CSSLengthResolver.parse(token), length != .auto else { return nil }
            return .length(length)
        }
    }

    static func underlinePosition(_ value: String) -> TextUnderlinePosition? {
        var position = TextUnderlinePosition()
        let tokens = value.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens == ["auto"] { return position }
        if tokens == ["from-font"] { position.fromFont = true; return position }
        var side: String?
        for token in tokens {
            switch token {
            case "under" where !position.under: position.under = true
            case "left", "right":
                guard side == nil else { return nil }
                side = token
            default: return nil
            }
        }
        guard !tokens.isEmpty else { return nil }
        position.right = side == "right"
        return position
    }

    /// The `text-decoration` shorthand: line, style, colour and thickness in
    /// any order, each at most once; what it leaves out resets. nil drops an
    /// invalid declaration. `color` is `.some(nil)` for `currentColor`.
    static func shorthand(_ components: [String], color parseColor: (String) -> UIColor??)
        -> (lines: TextDecorationLines, style: TextDecorationStyle, color: UIColor?, thickness: TextDecorationThickness)? {
        var lines: TextDecorationLines?
        var style: TextDecorationStyle?
        var color: UIColor??
        var thickness: TextDecorationThickness?
        for component in components {
            let token = component.lowercased()
            if token == "none" {
                guard lines == nil else { return nil }
                lines = []
            } else if let line = line(token) {
                guard lines != [] else { return nil }
                guard !(lines ?? []).contains(line) else { return nil }
                lines = (lines ?? []).union(line)
            } else if let parsed = Self.style(token) {
                guard style == nil else { return nil }
                style = parsed
            } else if let parsed = Self.thickness(token) {
                guard thickness == nil else { return nil }
                thickness = parsed
            } else if let parsed = parseColor(component) {
                guard color == nil else { return nil }
                color = parsed
            } else {
                return nil
            }
        }
        return (lines ?? [], style ?? .solid, color ?? nil, thickness ?? .auto)
    }
}

extension ComputedStyle {
    /// The decorations in effect on this box: its parent's, then its own. A
    /// float or an inline-block takes none of its parent's (CSS Text
    /// Decoration 4 §2.1: not propagated to out-of-flow or atomic inline-level
    /// descendants); a block-level box takes them onto its root inline box.
    /// Called once the box's own cascade is complete.
    func decorationsInEffect(inheriting parent: [AppliedTextDecoration]) -> [AppliedTextDecoration] {
        var result: [AppliedTextDecoration]
        if cssFloat != .none || display == .inlineBlock {
            result = []
        } else if display == .inline {
            result = parent
        } else {
            result = parent.map {
                AppliedTextDecoration(lines: $0.lines, color: $0.color, style: $0.style,
                                      thickness: $0.thickness, anchor: nil)
            }
        }
        let drawn = textDecorationLine.intersection([.underline, .overline, .lineThrough])
        if !drawn.isEmpty {
            var anchorStyle = self
            anchorStyle.textDecorationsInEffect = result
            result.append(AppliedTextDecoration(
                lines: drawn, color: textDecorationColor ?? color, style: textDecorationStyle,
                thickness: textDecorationThickness,
                anchor: display == .inline ? TextDecorationAnchor(style: anchorStyle) : nil))
        }
        return result
    }
}

/// One line a text run draws: where it falls about the run's baseline before
/// device pixels, and how it is drawn (`TextDecorationPainter`).
struct TextDecorationPaint {
    enum Line: Equatable { case underline, overline, lineThrough }
    let line: Line
    let color: UIColor
    let style: TextDecorationStyle
    /// From the line's baseline toward its under side (down; left in
    /// vertical-rl), the decoration's over edge with both thicknesses auto.
    /// An overline moves by the auto thickness less its own, a line-through
    /// by half that, once both are whole device pixels (WebKit
    /// `TextBoxPainter`).
    let position: CGFloat
    let thickness: CGFloat
    /// `font-size / 16` of the box that places the line.
    let autoThickness: CGFloat
    /// The wave's reach either side of its axis and half its period.
    let waveAmplitude: CGFloat
    let waveStep: CGFloat
    /// An underline or overline across horizontal text breaks around the
    /// glyphs it crosses, ideographs aside (`text-decoration-skip-ink`).
    let skipsInk: Bool
    /// A fifth of the run's font height: the most a break reaches past the
    /// glyph it avoids.
    let inkDilationLimit: CGFloat

    func recolored(_ color: UIColor) -> TextDecorationPaint {
        TextDecorationPaint(line: line, color: color, style: style, position: position, thickness: thickness,
                            autoThickness: autoThickness, waveAmplitude: waveAmplitude, waveStep: waveStep,
                            skipsInk: skipsInk, inkDilationLimit: inkDilationLimit)
    }
}

/// Where a line's decorations fall, as WebKit places them (`TextBoxPainter`,
/// `InlineTextBoxStyle`, iOS 27.2). Every line is placed by the box that set
/// it: the inline box itself, or the root inline box once the line reached a
/// block. Its content box top is its baseline less its ascent rounded up;
/// the gap is `max(1, ceil(font-size / 32))`.
/// - Underline: the ascent plus the gap below the top, in horizontal writing;
///   vertical writing sets it under every box of the line that carries it,
///   on the left (`under`).
/// - Overline: at the top; the gap beyond it, in vertical writing.
/// - Line-through: two thirds of the ascent below the top.
///
/// Measured, S001 ua-all (17px PingFang, dpr 3): an underline's top 1⅓ below
/// the baseline at 1⅓ thick, 2 thick at 30px; a line-through 6⅓ above it;
/// an overline at the content box top; vertically, the underline 1 beyond
/// the content box's left edge, past a 30px child's (u-mixed).
enum TextDecorationLayout {
    /// `runs` with the decorations their styles put in effect, on a line
    /// whose root inline box is `root`.
    static func decorate(
        _ runs: [LineRun], root: ComputedStyle, writingMode: ReaderWritingMode,
        font resolveFont: (ComputedStyle) -> UIFont
    ) -> [LineRun] {
        guard runs.contains(where: { !$0.style.textDecorationsInEffect.isEmpty }) else { return runs }
        let vertical = writingMode != .horizontal
        return runs.map { run in
            guard !run.style.textDecorationsInEffect.isEmpty, isText(run) else { return run }
            var run = run
            let own = InlineLayout.roundedContentExtent(run.font)
            run.textDecorations = run.style.textDecorationsInEffect.flatMap { decoration in
                paints(decoration, run: run, runs: runs, root: root, vertical: vertical,
                       inkDilationLimit: (own.ascent + own.descent) / 5, font: resolveFont)
            }
            return run
        }
    }

    private static func isText(_ run: LineRun) -> Bool {
        !run.isAtomicUnit && !run.isDecorationEdge && run.width > 0
    }

    private static func paints(
        _ decoration: AppliedTextDecoration, run: LineRun, runs: [LineRun], root: ComputedStyle,
        vertical: Bool, inkDilationLimit: CGFloat, font resolveFont: (ComputedStyle) -> UIFont
    ) -> [TextDecorationPaint] {
        let anchorStyle = decoration.anchor?.style ?? root
        let font = resolveFont(anchorStyle)
        let extent = InlineLayout.roundedContentExtent(font)
        let size = font.pointSize
        let gap = max(1, ceil(size / 16 / 2))
        // Logical y toward the under side, from the line's baseline.
        let baseline = decoration.anchor == nil ? 0 : -anchorStyle.verticalAlignOffset
        let contentHeight = extent.ascent + extent.descent
        let top = baseline - (vertical ? contentHeight / 2 : extent.ascent)
        let position = anchorStyle.textUnderlinePosition
        let offset = anchorStyle.textUnderlineOffset == .auto ? nil
            : CSSLengthResolver.resolve(anchorStyle.textUnderlineOffset, emBase: size, remBase: size, percentBase: size)
        let thickness: CGFloat
        switch decoration.thickness {
        case .auto: thickness = size / 16
        case .fromFont: thickness = CTFontGetUnderlineThickness(font as CTFont)
        case .length(let length):
            thickness = CSSLengthResolver.resolve(length, emBase: size, remBase: size, percentBase: size) ?? size / 16
        }
        let wavy: CGFloat = decoration.style == .wavy ? 1 : 0

        func underline() -> CGFloat {
            if vertical || position.under {
                if vertical, position.right { return -((offset ?? 0) + gap) }
                // Below the content box of the lowest text in the line that
                // carries this decoration, the decorating box's own included.
                let bottom = runs.filter { isText($0) && $0.style.textDecorationsInEffect.contains(decoration) }
                    .map { other -> CGFloat in
                        let otherExtent = InlineLayout.roundedContentExtent(other.font)
                        return -other.style.verticalAlignOffset
                            + (vertical ? (otherExtent.ascent + otherExtent.descent) / 2 : otherExtent.descent)
                    }.max() ?? 0
                let ownBottom = top + contentHeight
                let desired = contentHeight + max(0, bottom - ownBottom) + (offset ?? 0) + gap
                return max(desired, extent.ascent)
            }
            if position.fromFont {
                return extent.ascent - CTFontGetUnderlinePosition(font as CTFont) + (offset ?? 0)
            }
            return extent.ascent + (offset ?? gap)
        }

        var result: [TextDecorationPaint] = []
        func add(_ line: TextDecorationPaint.Line, _ fromTop: CGFloat) {
            result.append(TextDecorationPaint(
                line: line, color: decoration.color ?? .black, style: decoration.style,
                position: top + fromTop, thickness: thickness, autoThickness: size / 16,
                waveAmplitude: size * 1.5 / 16, waveStep: size / 4.5,
                skipsInk: !vertical && line != .lineThrough && decoration.style != .wavy
                    && run.style.textDecorationSkipsInk,
                inkDilationLimit: inkDilationLimit))
        }
        if decoration.lines.contains(.underline) { add(.underline, underline() + wavy) }
        if decoration.lines.contains(.overline) {
            let over: CGFloat = vertical ? (position.right ? contentHeight + gap : -gap) : 0
            add(.overline, over - wavy)
        }
        if decoration.lines.contains(.lineThrough) { add(.lineThrough, 2 * extent.ascent / 3) }
        return result
    }
}
