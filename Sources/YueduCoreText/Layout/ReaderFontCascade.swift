import UIKit

/// Keeps the authored or reader-selected font as the primary face while supplying fallbacks for
/// characters it cannot draw. Replacing a CJK primary font with Georgia makes every ASCII digit
/// and Latin letter use Georgia even when the selected font contains those glyphs.
///
/// It names no CJK font. Han, kana and Hangul get their language's font from
/// `CJKTypography.applyFonts`; a fixed entry here drew every book's Han in PingFang SC,
/// Traditional and Japanese text included.
public enum ReaderFontCascade {
    private static let fallbackFontNames = [
        "Georgia",
        "AppleColorEmoji",
    ]

    /// Fallback descriptors carry the real point size, never `0`.
    ///
    /// `size: 0` is the usual "inherit the primary font's size" idiom, and it does
    /// inherit — but only while CoreText can use the descriptor as written. When the
    /// primary font carries a bold trait, CoreText re-matches every fallback against
    /// that trait (PingFangSC-Regular → PingFangSC-Semibold, when this list still
    /// named a CJK font), and the re-matched descriptor keeps the literal `size 0`,
    /// which resolves to CoreText's 12pt default. That is why switching 粗體 on once
    /// shrank every CJK glyph to 12pt while Latin text — drawn by the primary font
    /// itself — stayed at the reader size.
    public static func descriptors(size: CGFloat, isBoldRequested: Bool = false) -> [UIFontDescriptor] {
        fallbackFontNames.map { name in
            let descriptor = UIFontDescriptor(name: name, size: size)
            guard isBoldRequested else { return descriptor }
            // An explicit Regular cascade entry can remain Regular even when
            // the primary is Georgia-Bold. Resolve the same family-preserving
            // bold face as the primary, retaining the concrete cascade size.
            return FontTraits.boldVersion(
                of: UIFont(descriptor: descriptor, size: size), size: size
            ).fontDescriptor
        }
    }

    public static func attributes(size: CGFloat, isBoldRequested: Bool = false) -> [UIFontDescriptor.AttributeName: Any] {
        [.cascadeList: descriptors(size: size, isBoldRequested: isBoldRequested)]
    }

    /// `font` with only the publication's own fallbacks, as a web view
    /// cascades it: the reader's last-resort faces above dropped. For glyphs
    /// the engine places to match WebKit's shapes and sizes, such as
    /// emphasis marks, which Georgia would otherwise draw (a 17px PingFang
    /// paragraph's filled dot is Helvetica's in WebKit, 11 tall, not
    /// Georgia's 10).
    static func withoutReaderFallbacks(_ font: UIFont) -> UIFont {
        guard let cascade = font.fontDescriptor.object(forKey: .cascadeList) as? [UIFontDescriptor] else { return font }
        let authored = cascade.filter { descriptor in
            let name = descriptor.postscriptName
            return !fallbackFontNames.contains { name == $0 || name.hasPrefix($0 + "-") }
        }
        guard authored.count != cascade.count else { return font }
        return UIFont(descriptor: font.fontDescriptor.addingAttributes([.cascadeList: authored]), size: font.pointSize)
    }

    public static func preservingPrimary(_ font: UIFont, size: CGFloat, isBoldRequested: Bool = false) -> UIFont {
        // Publication CSS fallbacks precede the reader's last-resort coverage.
        // Preparation runs in the resolver and again in layout; replacing this
        // list loses author-selected faces on every missing primary glyph.
        let existing = font.fontDescriptor.object(forKey: .cascadeList) as? [UIFontDescriptor] ?? []
        let authored = existing.map { descriptor in
            guard isBoldRequested else { return descriptor.withSize(size) }
            return FontTraits.boldVersion(
                of: UIFont(descriptor: descriptor, size: size), size: size
            ).fontDescriptor
        }
        var names: Set<String> = [font.fontName]
        let cascade = (authored + descriptors(size: size, isBoldRequested: isBoldRequested))
            .filter { names.insert($0.postscriptName).inserted }
            .map { $0.withSize(size) }
        return UIFont(
            descriptor: font.fontDescriptor.addingAttributes(
                [.cascadeList: cascade]
            ),
            size: size
        )
    }
}
