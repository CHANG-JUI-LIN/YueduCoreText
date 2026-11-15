import UIKit
import CoreText

public enum BrowserPageGeometry {
    public static func buildPageRanges(_ pages: [PageFragments], sourceText: String) -> [NSRange] {
        pages.map { sourceRange(of: $0, sourceText: sourceText) }
    }

    /// The source a page shows: its text and its pictures. A picture has a place in the
    /// source but no extent, so a page of nothing but pictures used to have no range at
    /// all and reported the chapter's end: every map page of a chapter, and the page after
    /// it, became one reading position, and a page turn resolved to the wrong page or to
    /// none. A CSS background is paint on every page, not content, and is left out —
    /// the same rule `BrowserScrollDocument` places offsets with in scroll mode.
    static func sourceRange(of page: PageFragments, sourceText: String) -> NSRange {
        let ns = sourceText as NSString
        var minLocation = ns.length
        var maxEnd = 0
        func include(_ range: NSRange) {
            minLocation = min(minLocation, range.location)
            maxEnd = max(maxEnd, range.location + range.length)
        }
        func walk(_ fragments: [Fragment]) {
            for fragment in fragments {
                switch fragment {
                case .text(let t) where t.sourceRange.length > 0: include(t.sourceRange)
                case .image(let i) where !i.isBackgroundPaint: include(i.sourceRange)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        walk(page.fragments)
        guard maxEnd > minLocation else { return NSRange(location: minLocation, length: 0) }
        return NSRange(location: minLocation, length: maxEnd - minLocation)
    }

    /// For each page, the added picture it starts with when it shows nothing of the source — a
    /// page of nothing but pictures the client added (`BrowserAddedContent`) — and nil for every
    /// other page.
    ///
    /// The picture is named by its index among the added pictures at its place in the source,
    /// counted in document order from 0. That names the same picture however the chapter is
    /// paginated, which is what lets such a page be a reading position: a page turn, a restore
    /// and the reader's progress resolve `(page range's location, this index)` back to the page
    /// through `pageIndex(forCharOffset:addedIndex:ranges:addedStarts:sourceText:)`. Without it
    /// the page shares its location with the page after it, or with the chapter's end, and a
    /// turn resolves to the wrong page or to none.
    public static func buildPageAddedStarts(_ pages: [PageFragments], sourceText: String) -> [Int?] {
        var seen: [Int: Int] = [:]
        return pages.map { page in
            let range = sourceRange(of: page, sourceText: sourceText)
            var added: [Int] = []
            func walk(_ fragments: [Fragment]) {
                for fragment in fragments {
                    switch fragment {
                    case .image(let image) where image.isAddedContent: added.append(image.sourceRange.location)
                    case .group(let children): walk(children)
                    default: break
                    }
                }
            }
            walk(page.fragments)
            let start = range.length == 0 && added.contains(range.location) ? seen[range.location, default: 0] : nil
            for location in added { seen[location, default: 0] += 1 }
            return start
        }
    }

    /// The page a reading position is on. With `addedIndex`, the position is inside the added
    /// pictures at `charOffset` (`buildPageAddedStarts`): the page of nothing but added pictures
    /// that holds that picture. Without one, or when no such page is there any more (the pictures
    /// are gone, or now share a page with text), the page of the source character itself.
    public static func pageIndex(forCharOffset charOffset: Int, addedIndex: Int?, ranges: [NSRange],
                                 addedStarts: [Int?], sourceText: String) -> Int {
        if let addedIndex, ranges.count == addedStarts.count {
            var found: Int?
            for (page, start) in addedStarts.enumerated() {
                guard let start, ranges[page].location == charOffset, start <= addedIndex else { continue }
                found = page
            }
            if let found { return found }
        }
        return pageIndex(forCharOffset: charOffset, ranges: ranges, sourceText: sourceText)
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
