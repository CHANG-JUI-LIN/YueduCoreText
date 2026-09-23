import CoreText
import Foundation

extension BrowserPaintFragment {
    /// This fragment's display list with text lines of the calling thread's own,
    /// for painting it on a thread other than the one that prepared it.
    ///
    /// Core Text layout objects (CTLine) are used by one thread at a time. The
    /// prepared lines stay shared: the preparing thread measures paint bounds
    /// with them, and later fragments of the same text reuse them. The copies are
    /// built from the same immutable drawing text, so glyphs and positions are
    /// identical. Call this on the drawing thread.
    public func displayListWithOwnTextLines() -> DisplayList {
        DisplayList(items: displayList.items.map { item in
            guard case .text(var text) = item else { return item }
            // `paintFragments` prepares every text item it emits. Preparing one
            // here would read the layout line, which the preparing thread owns.
            guard let prepared = text.preparedDrawing else {
                preconditionFailure("paint fragments carry prepared text drawing")
            }
            text.preparedDrawing = TextDrawingResources(copying: prepared)
            return .text(text)
        })
    }
}
