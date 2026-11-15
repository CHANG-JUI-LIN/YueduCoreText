import Foundation

/// Pictures a client adds to a chapter that are not part of the book: a badge at the end of a
/// paragraph, a card under one or after the chapter.
///
/// The client writes them into the chapter's HTML as `<img>` elements carrying
/// `attributeName` (its value is not read), inline or `display: block`, inside an `<a href>`
/// when a tap should reach the client. The engine lays them out and draws them as any picture,
/// and gives them no character of the chapter's source text: the source text, every offset in
/// it, `pictureOffsets` and the paragraph ranges are exactly what they are without them. A
/// reading position, a bookmark or a highlight made with the pictures there means the same
/// place once they are gone, and the other way round.
///
/// A page that shows nothing but added pictures has no character to be found by, so such a page
/// is found by the picture it starts with: `BrowserPageGeometry.buildPageAddedStarts` and
/// `BrowserPageGeometry.pageIndex(forCharOffset:addedIndex:ranges:addedStarts:sourceText:)`.
public enum BrowserAddedContent {
    /// The attribute that marks an `<img>` as added by the client.
    public static let attributeName = "data-added-content"

    static func marks(_ node: ComputedStyleNode) -> Bool {
        node.semanticElement?.attribute(attributeName) != nil
    }
}

extension ImageFragment {
    /// A picture the client added (`BrowserAddedContent`): it has a place in the source and no
    /// character of it. Every picture of the book has one character; a CSS background has no
    /// place at all.
    public var isAddedContent: Bool { !isBackgroundPaint && sourceRange.length == 0 }
}
