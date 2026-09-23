import UIKit

/// A checkpoint contains no CoreText objects. Recreating an evicted paragraph's
/// typesetter can resume here without rebreaking its preceding lines.
struct InlineLayoutCheckpoint {
    var characterIndex = 0
    var y: CGFloat = 0
    var lineCount = 0
}

final class InlineLayoutCursor {
    var checkpoint = InlineLayoutCheckpoint()
    /// Actual breaker attempts, distinct from emitted lines or CPU samples.
    private(set) var lineBreakAttempts = 0
    private let advance: (inout InlineLayoutCheckpoint, inout Int) -> LayoutLine?
    init(advance: @escaping (inout InlineLayoutCheckpoint, inout Int) -> LayoutLine?) { self.advance = advance }
    func next() -> LayoutLine? { advance(&checkpoint, &lineBreakAttempts) }
}

struct InlineFontKey: Hashable {
    let families: [String]
    let size: CGFloat
    let weight: Int
    let bold: Bool
    let italic: Bool
    init(_ style: ComputedStyle) {
        families = style.fontFamilies; size = style.fontSize
        weight = style.fontWeight; bold = style.configBold; italic = style.isItalic
    }
}

/// Owned by one viewport session, whose resolver/configuration is immutable.
/// Final fonts include the cascade and synthetic traits, not just the resolver's
/// base font. A cursor may be evicted without rebuilding identical fonts in the
/// next paragraph. Access is serialized with the session's layout operations.
final class InlineFontCache {
    private var fonts: [InlineFontKey: UIFont] = [:]
    var count: Int { fonts.count }

    func resolve(_ style: ComputedStyle, make: () -> UIFont) -> UIFont {
        let key = InlineFontKey(style)
        if let font = fonts[key] { return font }
        let font = make()
        if fonts.count < 128 { fonts[key] = font }
        return font
    }
}
