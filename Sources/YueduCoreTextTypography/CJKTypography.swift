import CoreText
import Foundation
import UIKit

/// The CJK typography pass both of Yuedu Reader's engines run over text they are
/// about to shape, so a chapter looks the same whichever engine lays it out
/// (docs/superpowers/plans/2026-10-06-vertical-typography.md in the reader).
public enum CJKTypography {
    static let verticalForms = NSAttributedString.Key(kCTVerticalFormsAttributeName as String)
    static let runDelegate = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

    // MARK: Orientation

    /// Sets each character of vertical text upright or on its side, as CSS Writing
    /// Modes Level 3 does for `text-orientation: mixed` (§5.1, UAX #50):
    /// - `U` and `Tu` stand upright;
    /// - `Tr` stands upright when its font has a vertical alternate, and lies on its
    ///   side when it has none, as a bracket turned with the text;
    /// - `R`, such as Latin letters and ASCII digits, lies on its side.
    ///
    /// Upright means CoreText's vertical forms. Text on its side keeps horizontal
    /// forms and is centred on the column. Characters that carry a run delegate
    /// (images, ruby, notes) are the engine's own boxes and are left as they are.
    public static func applyOrientation(to text: NSMutableAttributedString, in range: NSRange? = nil) {
        let whole = range ?? NSRange(location: 0, length: text.length)
        guard whole.length > 0 else { return }
        let string = text.string as NSString
        var index = whole.location
        var runStart = index
        var runUpright: Bool?
        func flush(upTo end: Int) {
            guard let upright = runUpright, end > runStart else { return }
            let run = NSRange(location: runStart, length: end - runStart)
            if upright {
                text.addAttribute(verticalForms, value: true, range: run)
            } else {
                text.removeAttribute(verticalForms, range: run)
                centreSideways(text, in: run)
            }
        }
        while index < NSMaxRange(whole) {
            let character = string.rangeOfComposedCharacterSequence(at: index)
            let upright: Bool?
            if text.attribute(runDelegate, at: character.location, effectiveRange: nil) != nil {
                upright = nil
            } else {
                upright = isUpright(string.substring(with: character), at: character.location, in: text)
            }
            if upright != runUpright {
                flush(upTo: character.location)
                runStart = character.location
                runUpright = upright
            }
            index = NSMaxRange(character)
        }
        flush(upTo: NSMaxRange(whole))
    }

    /// Whether `character` stands upright in vertical text.
    static func isUpright(_ character: String, at location: Int, in text: NSAttributedString) -> Bool {
        guard let first = character.unicodeScalars.first else { return true }
        switch VerticalOrientation.of(first) {
        case .upright, .transformedUpright:
            return true
        case .rotated:
            return false
        case .transformedRotated:
            return VerticalAlternates.has(character, attributes: text.attributes(at: location, effectiveRange: nil))
        }
    }

    /// Centres text that lies on its side on the column.
    ///
    /// On its side, a run sits on its baseline, which in a vertical line is the
    /// column's centre line. Lowering it by half its font's ascent-to-descent box puts
    /// the box's middle there: measured within 0.03 em for SF, Georgia, PingFang and
    /// Hiragino, in a vertical CTFrame and in a quarter-turned CTLine alike, so both
    /// engines land the same. (The ideographic-centred baseline class the legacy engine
    /// used to add moved nothing.)
    ///
    /// The lowering adds to any baseline offset the text already has. The legacy engine
    /// raises all its text to centre it in the line height (2.6 pt at 17 pt and 1.5
    /// line spacing); replacing that offset left Latin runs 0.13–0.15 em off the column
    /// their upright neighbours were raised along.
    ///
    /// Dashes and ellipses are centred by their ink instead: fonts draw the dots of …
    /// on the baseline (PingFang, SF) or at mid-height (Hiragino), and the column wants
    /// them on its centre line either way.
    public static func centreSideways(_ text: NSMutableAttributedString, in range: NSRange) {
        let string = text.string as NSString
        var index = range.location
        while index < NSMaxRange(range) {
            let character = string.rangeOfComposedCharacterSequence(at: index)
            index = NSMaxRange(character)
            guard let value = text.attribute(.font, at: character.location, effectiveRange: nil),
                  let font = ctFont(value) else { continue }
            let glyphs = string.substring(with: character)
            let offset: CGFloat
            if let scalar = glyphs.unicodeScalars.first, centredByInk.contains(scalar.value),
               let ink = SidewaysInk.midY(of: glyphs, attributes: text.attributes(at: character.location, effectiveRange: nil)) {
                offset = -ink
            } else {
                offset = -(CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
            }
            let existing = (text.attribute(.baselineOffset, at: character.location, effectiveRange: nil) as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? 0
            text.addAttribute(.baselineOffset, value: existing + offset, range: character)
        }
    }

    /// Two-em dash, em dash, horizontal bar, two-dot leader, ellipsis, two- and
    /// three-em dash.
    static let centredByInk: Set<UInt32> = [0x2014, 0x2015, 0x2025, 0x2026, 0x2E3A, 0x2E3B]

    static func ctFont(_ value: Any) -> CTFont? {
        if let font = value as? UIFont { return font as CTFont }
        guard CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { return nil }
        return (value as! CTFont)
    }
}

/// How far above the baseline a character's ink is centred, in the font the line
/// draws it with: shaped with its own attributes, language included. Cached by
/// font, language and character.
enum SidewaysInk {
    private struct Key: Hashable { let font: String; let size: CGFloat; let language: String; let character: String }
    nonisolated(unsafe) private static var cache: [Key: CGFloat] = [:]
    private static let lock = NSLock()
    private static let language = NSAttributedString.Key(kCTLanguageAttributeName as String)

    static func midY(of character: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat? {
        let font = attributes[.font].flatMap(CJKTypography.ctFont)
        let key = Key(font: font.map { CTFontCopyPostScriptName($0) as String } ?? "",
                      size: font.map(CTFontGetSize) ?? 0,
                      language: attributes[language] as? String ?? "", character: character)
        if let cached = lock.withLock({ cache[key] }) { return cached }
        var shaping: [NSAttributedString.Key: Any] = [:]
        if let value = attributes[.font] { shaping[.font] = value }
        if let value = attributes[language] { shaping[language] = value }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: shaping))
        guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first, CTRunGetGlyphCount(run) > 0 else { return nil }
        var glyph: CGGlyph = 0
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        let drawing = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        var glyphs = [glyph]
        let bounds = CTFontGetBoundingRectsForGlyphs(drawing, .horizontal, &glyphs, nil, 1)
        guard !bounds.isNull, bounds.height > 0 else { return nil }
        lock.withLock { cache[key] = bounds.midY }
        return bounds.midY
    }
}

/// Whether a character has a vertical alternate in the font that draws it, found
/// the way the line will find it: shaped with its own attributes, language
/// included, once with vertical forms and once without. Cached by font, language
/// and character.
enum VerticalAlternates {
    private struct Key: Hashable { let font: String; let size: CGFloat; let language: String; let character: String }
    nonisolated(unsafe) private static var cache: [Key: Bool] = [:]
    private static let lock = NSLock()
    private static let language = NSAttributedString.Key(kCTLanguageAttributeName as String)

    static func has(_ character: String, attributes: [NSAttributedString.Key: Any]) -> Bool {
        let font = attributes[.font].flatMap(CJKTypography.ctFont)
        let key = Key(font: font.map { CTFontCopyPostScriptName($0) as String } ?? "",
                      size: font.map(CTFontGetSize) ?? 0,
                      language: attributes[language] as? String ?? "", character: character)
        if let cached = lock.withLock({ cache[key] }) { return cached }
        var plain: [NSAttributedString.Key: Any] = [:]
        if let value = attributes[.font] { plain[.font] = value }
        if let value = attributes[language] { plain[language] = value }
        func glyph(vertical: Bool) -> (CGGlyph, String)? {
            var shaping = plain
            if vertical { shaping[CJKTypography.verticalForms] = true }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: shaping))
            guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first, CTRunGetGlyphCount(run) > 0 else { return nil }
            var glyph: CGGlyph = 0
            CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            return (glyph, CTFontCopyPostScriptName(runFont) as String)
        }
        let result: Bool
        if let horizontal = glyph(vertical: false), let vertical = glyph(vertical: true) {
            result = horizontal.0 != vertical.0 || horizontal.1 != vertical.1
        } else {
            result = false
        }
        lock.withLock { cache[key] = result }
        return result
    }
}
