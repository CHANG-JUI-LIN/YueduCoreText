import Foundation

/// How a character is set in vertical text: its UAX #50 `Vertical_Orientation`,
/// which CSS Writing Modes Level 3 follows for `text-orientation: mixed`.
///
/// The ranges are generated from the Unicode Character Database by
/// `scripts/vertical_orientation.py`; see `VerticalOrientationTable.swift`.
public enum VerticalOrientation: Sendable, Equatable {
    /// `R`: rotated 90° clockwise, as horizontal text turned on its side.
    /// Latin letters and ASCII digits, for example.
    case rotated
    /// `U`: upright. Han, kana, full-width letters and digits.
    case upright
    /// `Tu`: upright, drawn with the font's vertical alternate when it has one.
    /// Full-width commas, full stops, question and exclamation marks.
    case transformedUpright
    /// `Tr`: the font's vertical alternate, or rotated when the font has none.
    /// Brackets, ー, the full-width colon and semicolon.
    case transformedRotated

    /// The orientation of `scalar`; `R` unless the data says otherwise.
    public static func of(_ scalar: Unicode.Scalar) -> VerticalOrientation {
        let value = scalar.value
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = ranges[middle]
            if value < range.lower {
                high = middle - 1
            } else if value > range.upper {
                low = middle + 1
            } else {
                return range.value
            }
        }
        return .rotated
    }

    /// The orientation of a character: that of its first scalar, as CSS Writing
    /// Modes 3 §5.1 treats a typographic character unit.
    public static func of(_ character: Character) -> VerticalOrientation {
        character.unicodeScalars.first.map(of) ?? .rotated
    }
}
