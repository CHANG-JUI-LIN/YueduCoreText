import CoreText
import Foundation

/// Where the boundaries between characters lie along a CTLine.
///
/// `CTLineGetOffsetForStringIndex` puts the boundary before a character halfway through
/// the kern of the character ahead of it. For letter spacing, a positive kern, that is
/// the middle of the gap. A negative kern — punctuation squeezed by
/// `CJKTypography.applySpacing` or moved by `applyPositions` — puts it inside the next
/// glyph instead: in 國？」國 with 」 squeezed by half an em, the second 國's boundary
/// fell a quarter em into it (measured 2026-10-06: glyph at 50 pt, boundary at
/// 54.9 pt), and selections, highlights and underlines cut the glyph there. Here the
/// boundary after a negative kern is where the next glyph starts; every other boundary
/// is CoreText's.
public enum GlyphBoundary {
    /// The offset along `line` of the boundary before the character at `index`.
    public static func offset(_ line: CTLine, at index: CFIndex) -> CGFloat {
        let caret = CTLineGetOffsetForStringIndex(line, index, nil)
        guard let kern = kern(before: index, in: line), kern < 0 else { return caret }
        return caret + kern / 2
    }

    /// The insertion index nearest `position` along `line`, by these boundaries: CoreText's
    /// answer, unless a boundary next to it moved.
    public static func index(_ line: CTLine, at position: CGFloat) -> CFIndex {
        let found = CTLineGetStringIndexForPosition(line, CGPoint(x: position, y: 0))
        guard found != kCFNotFound else { return found }
        let neighbours = [found - 1, found, found + 1]
        guard neighbours.contains(where: { (kern(before: $0, in: line) ?? 0) < 0 }) else { return found }
        let starts = glyphStarts(of: line)
        var best = found
        var bestDistance = abs(offset(line, at: found) - position)
        for candidate in [found - 1, found + 1] where starts.contains(candidate) {
            let distance = abs(offset(line, at: candidate) - position)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    /// The kern of the character at `index - 1`, from the left-to-right run that draws it.
    private static func kern(before index: CFIndex, in line: CTLine) -> CGFloat? {
        let previous = index - 1
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let range = CTRunGetStringRange(run)
            guard previous >= range.location, previous < range.location + range.length else { continue }
            guard !CTRunGetStatus(run).contains(.rightToLeft) else { return nil }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            return (attributes[NSAttributedString.Key.kern.rawValue] as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        return nil
    }

    /// The string indices where a glyph starts, and the line's end: the boundaries a hit
    /// may land on, never inside a surrogate pair or a cluster.
    private static func glyphStarts(of line: CTLine) -> Set<CFIndex> {
        var starts: Set<CFIndex> = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            starts.formUnion(indices)
        }
        let range = CTLineGetStringRange(line)
        starts.insert(range.location + range.length)
        return starts
    }
}
