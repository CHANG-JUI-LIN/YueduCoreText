import CoreGraphics
import UIKit
import YueduCoreText

@MainActor
public func renderExample() async throws -> (
    image: CGImage, text: String, links: [LinkInteractionRegion]
) {
    let size = CGSize(width: 320, height: 480)
    let document = HTMLLayoutDocument(
        html: "<p id='intro'>Hello <a href='#intro'>世界 🌕</a></p>",
        css: ["body { margin: 0; } p { margin: 0; padding: 8px; border: 2px solid blue; }"],
        configuration: BrowserLayoutConfig(
            renderWidth: size.width, renderHeight: size.height, rootFontSize: 17
        )
    )
    let session = try document.makePageSession()
    guard let page = try await session.layoutNextPage() else {
        throw HTMLLayoutError.layoutFailure("No first page")
    }
    let list = DisplayListBuilder.build(for: page, sourceText: session.sourceText)
    guard let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw HTMLLayoutError.layoutFailure("Bitmap allocation")
    }
    // A raw bitmap context needs top-left, y-down coordinates.
    // UIKit drawing contexts already use that orientation; do not flip them again.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    list.draw(in: context)
    guard let image = context.makeImage() else {
        throw HTMLLayoutError.layoutFailure("Bitmap snapshot")
    }
    let links = LinkInteractionRegionSet.build(
        from: list, spineIndex: 0, anchors: session.pipelineLinkAnchors
    )
    return (image, session.sourceText, links.regions)
}

@MainActor
public func makeContinuousExample(image: UIImage) throws -> BrowserScrollDocument {
    let document = HTMLLayoutDocument(
        html: "<p id='start'>Hello 世界</p><img src='illustration.png' alt='Illustration'/>",
        css: ["body { margin: 0; } img { width: 120px; height: auto; }"],
        configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 480),
        images: ["illustration.png": image]
    )
    return try document.prepareContinuous().makeDocument()
}

@MainActor
public func drawFirstViewport(of document: BrowserScrollDocument, in context: CGContext) {
    let viewport = CGRect(x: 0, y: 0, width: document.contentSize.width, height: 480)
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: CGRect(origin: .zero, size: viewport.size))
    // The caller supplies a top-left, y-down context, as in renderExample().
    document.items(in: viewport).draw(in: context)
}
