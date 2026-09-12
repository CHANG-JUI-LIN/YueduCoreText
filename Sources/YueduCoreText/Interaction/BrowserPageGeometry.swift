import UIKit
import CoreText

public enum BrowserPageGeometry {
    public static func buildPageRanges(_ pages: [PageFragments], sourceText: String) -> [NSRange] {
        let ns = sourceText as NSString
        return pages.map { page in
            var minLocation = ns.length
            var maxEnd = 0
            func walk(_ fragments: [Fragment]) {
                for fragment in fragments {
                    switch fragment {
                    case .text(let t):
                        if t.sourceRange.length > 0 {
                            minLocation = min(minLocation, t.sourceRange.location)
                            maxEnd = max(maxEnd, t.sourceRange.location + t.sourceRange.length)
                        }
                    case .group(let children): walk(children)
                    default: break
                    }
                }
            }
            walk(page.fragments)
            guard maxEnd > minLocation else { return NSRange(location: minLocation, length: 0) }
            return NSRange(location: minLocation, length: maxEnd - minLocation)
        }
    }

    public static func rects(pages: [PageFragments], sourceText: String, range: NSRange) -> [(page: Int, rects: [CGRect])] {
        let ns = sourceText as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return [] }
        let rangeEnd = range.location + range.length

        var result: [(page: Int, rects: [CGRect])] = []
        for (pageIndex, page) in pages.enumerated() {
            var pageRects: [CGRect] = []
            func walk(_ fragments: [Fragment]) {
                for fragment in fragments {
                    switch fragment {
                    case .text(let t):
                        guard t.sourceRange.length > 0 else { continue }
                        let start = max(t.sourceRange.location, range.location)
                        let end = min(t.sourceRange.location + t.sourceRange.length, rangeEnd)
                        guard end > start else { continue }
                        if case .wholeRange = t.sourceMapping {
                            pageRects.append(t.rect.rawValue)
                            continue
                        }
                        if let line = t.ctLine,
                           let rect = preciseRect(
                               fragment: t, line: line,
                               selection: NSRange(location: start, length: end - start)
                           ) {
                            pageRects.append(rect)
                            continue
                        }
                        // Proportional fallback (no line artifact, or the
                        // fragment's range was trimmed off the line's range).
                        let fraction = Double(end - start) / Double(t.sourceRange.length)
                        let selectedWidth = CGFloat(fraction) * t.rect.width
                        let xOffset = CGFloat(Double(start - t.sourceRange.location) / Double(t.sourceRange.length)) * t.rect.width
                        pageRects.append(CGRect(
                            x: t.rect.minX + xOffset,
                            y: t.rect.minY,
                            width: selectedWidth,
                            height: t.rect.height
                        ))
                    case .group(let children): walk(children)
                    default: break
                    }
                }
            }
            walk(page.fragments)
            if !pageRects.isEmpty {
                result.append((page: pageIndex, rects: pageRects))
            }
        }
        return result
    }

    /// Precise selection rect for a sub-range of one text fragment, using the
    /// fragment's shaped line: `CTLineGetOffsetForStringIndex` yields exact
    /// typographic offsets (kerning, ligatures, RTL, emoji ZWJ clusters,
    /// combining marks) instead of proportional width estimation.
    ///
    /// The fragment's `sourceRange` is a slice of the chapter source; the line's
    /// own string range (in attributed space) is `CTLineGetStringRange(line)`.
    /// They align for normal runs; when leading whitespace was trimmed the run's
    /// range shifts, and this helper returns nil so callers fall back to
    /// proportional rects (whitespace-only discrepancy).
    private static func preciseRect(
        fragment t: TextFragment,
        line: CTLine,
        selection: NSRange
    ) -> CGRect? {
        guard case .linear(let shapedRange) = t.sourceMapping else { return nil }
        let selStart = selection.location
        let selEnd = selection.location + selection.length
        let sourceDeltaStart = selStart - t.sourceRange.location
        let sourceDeltaEnd = selEnd - t.sourceRange.location
        guard sourceDeltaStart >= 0,
              sourceDeltaEnd > sourceDeltaStart,
              sourceDeltaEnd <= shapedRange.length else {
            return nil
        }
        let shapedStart = shapedRange.location + sourceDeltaStart
        let shapedEnd = shapedRange.location + sourceDeltaEnd
        let lineRange = CTLineGetStringRange(line)
        guard shapedStart >= lineRange.location,
              shapedEnd <= lineRange.location + lineRange.length else {
            return nil
        }
        let pieceOrigin = CTLineGetOffsetForStringIndex(line, shapedRange.location, nil)
        let offsetStart = CTLineGetOffsetForStringIndex(line, shapedStart, nil) - pieceOrigin
        let offsetEnd = CTLineGetOffsetForStringIndex(line, shapedEnd, nil) - pieceOrigin

        // Horizontal only for now: the fragment rect already encodes the run's
        // baseline-aligned horizontal placement. Vertical mapping arrives with
        // the vertical-rl writing mode (Phase 3B).
        let x = t.rect.minX + offsetStart
        let width = max(1, offsetEnd - offsetStart)
        return CGRect(x: x, y: t.rect.minY, width: width, height: t.rect.height)
    }


    public static func pageIndex(forCharOffset charOffset: Int, ranges: [NSRange], sourceText: String) -> Int {
        guard !ranges.isEmpty else { return 0 }
        let nsLength = (sourceText as NSString).length
        let target = min(max(charOffset, 0), nsLength)
        var low = 0
        var high = ranges.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            let range = ranges[mid]
            if range.location > target {
                high = mid - 1
            } else if range.location + range.length <= target {
                // Source ranges are half-open: the next page's first offset
                // must never resolve back to the preceding page on a tap turn.
                best = mid
                low = mid + 1
            } else {
                return mid
            }
        }
        return best
    }

}
