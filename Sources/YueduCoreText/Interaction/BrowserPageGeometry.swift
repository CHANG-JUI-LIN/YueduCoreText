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
        let length = (sourceText as NSString).length
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= length else { return [] }
        return pages.enumerated().compactMap { index, page in
            let rects = DisplayListBuilder.build(for: page, sourceText: sourceText).selectionRects(for: range)
            return rects.isEmpty ? nil : (page: index, rects: rects)
        }
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
