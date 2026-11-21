import UIKit

/// A chapter's html/body background. CSS propagates it to the canvas — for a
/// reader, the whole screen, margins included — instead of painting it inside
/// the content box. Paged layout injects it into every page
/// (`BrowserLayoutSession.injectBodyBackground`); a continuous chapter has no
/// page to inject it into, so its scroll host draws it behind the chapter.
public struct BrowserPageBackground: @unchecked Sendable, Equatable {
    public let color: UIColor?
    public let imageSource: String?
    /// `background-attachment: fixed`: placed against the screen and still
    /// while the text scrolls over it.
    public let isFixed: Bool
    private let background: BrowserLayoutDocument.RootBackground
    private let rootFontSize: CGFloat

    init?(_ background: BrowserLayoutDocument.RootBackground, rootFontSize: CGFloat) {
        guard background.color != nil || background.image != nil else { return nil }
        color = background.color
        imageSource = background.image?.source
        isFixed = background.image?.attachment == .fixed
        self.background = background
        self.rootFontSize = rootFontSize
    }

    public static func == (lhs: BrowserPageBackground, rhs: BrowserPageBackground) -> Bool {
        lhs.color == rhs.color && lhs.background.image == rhs.background.image
            && lhs.background.fontSize == rhs.background.fontSize && lhs.rootFontSize == rhs.rootFontSize
    }

    /// How an image of `imageSize` covers a page of `pageSize`: its first
    /// tile, the axes it repeats along, and the page as its clip — the same
    /// placement paged layout paints. nil when nothing of it shows.
    public func imageTiling(for imageSize: CGSize, onPageOf pageSize: CGSize) -> BackgroundTiling? {
        background.tiling(for: imageSize, canvas: pageSize, rootFontSize: rootFontSize)
    }

    /// The first tile of `imageTiling(for:onPageOf:)`: the whole placement of
    /// an image that does not repeat.
    public func imageRect(for imageSize: CGSize, onPageOf pageSize: CGSize) -> CGRect {
        imageTiling(for: imageSize, onPageOf: pageSize)?.tile ?? .zero
    }
}
