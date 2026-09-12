import CoreGraphics
import UIKit
import YueduCoreText

/// This example is compiled as its own module, with no Reader source or testable import.
@MainActor
public func renderExample() async throws -> (image: CGImage, text: String, links: [LinkInteractionRegion]) {
    let document = HTMLLayoutDocument(
        html: "<html><body><p id='intro'>Hello <a href='#intro'>世界 🌕</a></p></body></html>",
        css: ["body { margin:0; } p { padding:8px; border:2px solid blue; }"])
    let session = try document.makePageSession()
    guard let page = try await session.layoutNextPage() else { throw HTMLLayoutError.layoutFailure("No first page") }
    let list = DisplayListBuilder.build(for: page, sourceText: session.sourceText)
    guard let context = CGContext(data: nil, width: 320, height: 480, bitsPerComponent: 8,
                                  bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw HTMLLayoutError.layoutFailure("Bitmap allocation")
    }
    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
    list.draw(in: context)
    guard let image = context.makeImage() else { throw HTMLLayoutError.layoutFailure("Bitmap snapshot") }
    let links = LinkInteractionRegionSet.build(from: list, spineIndex: 0, anchors: session.pipelineLinkAnchors)
    return (image, session.sourceText, links.regions)
}
