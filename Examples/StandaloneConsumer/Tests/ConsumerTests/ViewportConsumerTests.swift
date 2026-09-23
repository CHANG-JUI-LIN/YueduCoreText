import Testing
import UIKit
import YueduCoreText

@MainActor
struct ViewportConsumerTests {
    @Test func viewportSnapshotsAndPaintFragmentsRemainUsableAfterRetirement() async throws {
        let html = "<body style='margin:0;background:#eeeeee'>"
            + (0..<120).map { "<p id='p\($0)'>Paragraph \($0) 中文 🌕 viewport content.</p>" }.joined()
            + "</body>"
        let owner = try BrowserViewportLayoutOwner(document: HTMLLayoutDocument(html: html,
            configuration: BrowserLayoutConfig(renderWidth: 300, renderHeight: 500)))
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 500)
        #expect(owner.facts.pageBackground?.color != nil)
        let first = try await owner.layout(in: viewport, anchorOffset: 0)
        let fragments = first.document.paintFragments(in: viewport, scale: 1)
        #expect(!fragments.isEmpty)
        #expect(first.retainedLineCount > 0)
        let anchor = try #require(owner.facts.anchorOffsets["p1"])
        #expect(first.documentY(for: anchor) >= 0)
        let context = try #require(CGContext(data: nil, width: 300, height: 500,
            bitsPerComponent: 8, bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for fragment in fragments {
            let drawing = fragment.displayListWithOwnTextLines()
            #expect(drawing.items.count == fragment.displayList.items.count)
            drawing.draw(in: context)
        }
        #expect(context.makeImage() != nil)
        let retired = await owner.discardRenderingResources()
        #expect(retired.retainedLineCount == 0)
        #expect(first.retainedLineCount > 0, "published snapshots must survive later actor transactions")
        let restored = try await owner.layout(in: viewport, anchorOffset: 0)
        #expect(restored.document.sourceText == first.document.sourceText)
        #expect(restored.document.paintFragments(in: viewport, scale: 1).map(\.id) == fragments.map(\.id))
    }
}
