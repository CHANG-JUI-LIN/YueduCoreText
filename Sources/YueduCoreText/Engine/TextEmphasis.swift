import CoreText
import Foundation
import UIKit
import YueduCoreTextTypography

/// The marks a text run draws: one per character that takes one, centred on
/// it, on the side `offset` points to (`TextEmphasisPainter`).
struct TextEmphasisPaint {
    let mark: String
    /// Half the text's size, in the font the text's own cascade draws the
    /// mark in (WebKit `emphasisMarkFontData`).
    let font: UIFont
    /// nil is the text's own colour, which a theme change recolours with it.
    let color: UIColor?
    /// From the baseline toward the under side (down; left in vertical-rl):
    /// horizontally the mark's baseline, vertically the line through its centre.
    let offset: CGFloat
    /// One mark for the whole text, on its column's centre line, centred on
    /// its em square: a 縦中横 cell, whose text is drawn horizontally. WebKit
    /// gives each cell one mark, punctuation too (measured, iOS 27.2: `12`,
    /// `123` and `!?` cells each one, where `傍點` takes them).
    var cell = false

    func recolored(_ color: UIColor?) -> TextEmphasisPaint {
        TextEmphasisPaint(mark: mark, font: font, color: color, offset: offset, cell: cell)
    }
}

/// Where a run's marks go and how much room they take, as WebKit places them
/// (`TextBoxPainter`, `InlineLevelBox` annotations; measured, WKWebView iOS
/// 27.2, the app's S001i and S001j fixtures). The mark is the text's font at
/// half its size; its height is its content area, its ascent and descent each
/// rounded up. It sits outside the text's content box, on its side:
/// - horizontally, under: its baseline the text's descent and its own ascent
///   below the text's; over: the text's ascent and its own descent above;
/// - vertically, its centre line half the text's content area and half its
///   own height right of the central baseline (left for `left`).
/// The line grows to hold it: 17px PingFang with Hiragino's ﹅ at 1.5 is 35.25
/// tall (25.5 without), with Helvetica's • 36.25.
enum TextEmphasisLayout {
    struct Placement {
        /// The mark is on the line's over side (above; right in vertical-rl).
        let over: Bool
        /// How far from the baseline (horizontal) or the central baseline
        /// (vertical) the mark's far edge reaches, on its side.
        let reach: CGFloat
        let paint: TextEmphasisPaint
    }

    static func placement(style: ComputedStyle, font: UIFont, vertical: Bool, fonts: InlineFontCache) -> Placement? {
        guard let emphasis = style.textEmphasisStyle else { return nil }
        let mark = emphasis.mark(vertical: vertical)
        guard !mark.isEmpty else { return nil }
        let markFont = fonts.markFont(mark, style: style, text: font)
        let markExtent = InlineLayout.roundedContentExtent(markFont)
        let markHeight = markExtent.ascent + markExtent.descent
        let text = InlineLayout.roundedContentExtent(font)
        let over = vertical ? style.textEmphasisPosition.right
            : style.textEmphasisPosition.isOver(language: style.language)
        let reach: CGFloat
        let offset: CGFloat
        if vertical {
            let half = (text.ascent + text.descent) / 2
            reach = half + markHeight
            offset = (half + markHeight / 2) * (over ? -1 : 1)
        } else if over {
            reach = text.ascent + markHeight
            offset = -(text.ascent + markExtent.descent)
        } else {
            reach = text.descent + markHeight
            offset = text.descent + markExtent.ascent
        }
        let paint = TextEmphasisPaint(mark: mark, font: markFont,
                                      color: style.textEmphasisColor ?? style.color, offset: offset)
        return Placement(over: over, reach: reach, paint: paint)
    }

    /// Whether `run` draws marks its style asks for: text or a 縦中横 cell, not
    /// a generated counter or quotation mark, a picture or an inline-block.
    /// A ruby base takes them only on the side its annotation leaves free.
    static func marks(_ run: InlineRun) -> Bool {
        run.style.textEmphasisStyle != nil && run.decorationEdge == nil && !run.isGeneratedText
            && run.atomic == nil && run.inlineBlock == nil
    }

    /// `runs` with the marks their styles ask for (`placement`).
    static func mark(_ runs: [LineRun], writingMode: ReaderWritingMode,
                     font resolveFont: (ComputedStyle) -> UIFont, fonts: InlineFontCache) -> [LineRun] {
        guard runs.contains(where: { $0.style.textEmphasisStyle != nil }) else { return runs }
        let vertical = writingMode != .horizontal
        return runs.map { run in
            guard run.style.textEmphasisStyle != nil, !run.isDecorationEdge, run.generatedText == nil,
                  run.atomic == nil, run.inlineBlock == nil, run.width > 0,
                  let placement = placement(style: run.style, font: resolveFont(run.style), vertical: vertical,
                                            fonts: fonts),
                  !(run.ruby != nil && placement.over)
            else { return run }
            var run = run
            run.textEmphasis = placement.paint
            run.textEmphasis?.cell = run.combined != nil
            return run
        }
    }

    /// The font `text`'s cascade draws `mark` in at half `text`'s size, the
    /// publication's fallbacks and then the system's, as in WebKit.
    static func markFont(_ mark: String, text: UIFont, language: String?) -> UIFont {
        let half = ReaderFontCascade.withoutReaderFallbacks(text).withSize(text.pointSize / 2)
        var attributes: [NSAttributedString.Key: Any] = [.font: half]
        if let language { attributes[kCTLanguageAttributeName as NSAttributedString.Key] = language }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: mark, attributes: attributes))
        guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
              let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName]
        else { return half }
        return value as! CTFont as UIFont
    }
}
