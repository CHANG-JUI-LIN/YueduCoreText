import Foundation

/// Where a chapter's pictures sit in its source text, and the map from offsets saved
/// before they took up any.
///
/// Since 0.11 every picture (an `<img>`, inline, block or floated; an SVG wrapping one
/// image; a video's placeholder) takes one U+FFFC of the chapter's `sourceText`, whether or
/// not its image loads. A CSS background takes none. Up to 0.10 a picture had a place in
/// the source text but no extent: its place was the offset of whatever followed it, so a
/// page of pictures followed directly by text shared that text's position.
///
/// Every offset after a picture moved forward by one. A host that saved offsets against
/// 0.10 maps them with `migrated(_:)`, once, with the chapter's pictures from the layout
/// that will read them (`BrowserLayoutSession.pictureOffsets`,
/// `BrowserViewportChapterFacts.pictureOffsets`, `BrowserContinuousLayout.pictureOffsets`).
public struct BrowserPictureOffsets: Equatable, Sendable {
    /// Each picture's character in the 0.11 source text, ascending.
    public let offsets: [Int]

    public init(_ offsets: [Int]) {
        self.offsets = offsets
    }

    /// An offset saved against 0.10's source text, in 0.11's.
    ///
    /// It moves past every picture whose 0.10 place is at or before it. A 0.10 offset at a
    /// picture's place named the text after the picture — 0.10 resolved it there — so it
    /// still does.
    public func migrated(_ offset: Int) -> Int {
        offset + countOfOldPlaces { $0 <= offset }
    }

    /// A range saved against 0.10's source text, in 0.11's: its start as `migrated(_:)` maps
    /// an offset, its end before a picture whose place is the end. A picture inside the range
    /// stays inside it, so the range keeps every character it had and grows by its pictures.
    public func migrated(_ range: NSRange) -> NSRange {
        guard range.location != NSNotFound else { return range }
        let start = migrated(range.location)
        guard range.length > 0 else { return NSRange(location: start, length: 0) }
        let end = NSMaxRange(range)
        return NSRange(location: start, length: end + countOfOldPlaces { $0 < end } - start)
    }

    /// The 0.10 offset of a 0.11 offset, for a host that must still write the old one. An
    /// offset on a picture becomes the picture's old place; `migrated(_:)` takes that to the
    /// text after it, so only an offset on a picture does not come back.
    public func unmigrated(_ offset: Int) -> Int {
        offset - countOfPictures { $0 < offset }
    }

    // MARK: - Counting

    /// Pictures whose 0.10 place satisfies `isIncluded`. The k-th picture's 0.10 place is its
    /// 0.11 offset less the k pictures before it; those places never decrease, so the
    /// included ones are a prefix.
    private func countOfOldPlaces(where isIncluded: (Int) -> Bool) -> Int {
        partitionPoint { index in !isIncluded(offsets[index] - index) }
    }

    private func countOfPictures(where isIncluded: (Int) -> Bool) -> Int {
        partitionPoint { index in !isIncluded(offsets[index]) }
    }

    /// The first index for which `isPastPrefix` holds; it must hold for every index after.
    private func partitionPoint(_ isPastPrefix: (Int) -> Bool) -> Int {
        var low = 0
        var high = offsets.count
        while low < high {
            let mid = (low + high) / 2
            if isPastPrefix(mid) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
