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
    let positionX: BackgroundImageStyle.BackgroundPosition
    let positionY: BackgroundImageStyle.BackgroundPosition

    init?(_ background: BrowserLayoutDocument.RootBackground) {
        guard background.color != nil || background.image != nil else { return nil }
        color = background.color
        imageSource = background.image?.source
        isFixed = background.image?.attachment == .fixed
        positionX = background.image?.positionX ?? .percent(0)
        positionY = background.image?.positionY ?? .percent(0)
    }

    /// Where an image of `imageSize` goes on a page of `pageSize`: the rect
    /// paged layout draws it at.
    public func imageRect(for imageSize: CGSize, onPageOf pageSize: CGSize) -> CGRect {
        BrowserLayoutDocument.coverRect(for: imageSize, container: pageSize,
                                        positionX: positionX, positionY: positionY)
    }
}
