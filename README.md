# YueduCoreText

YueduCoreText is an iOS-native HTML/CSS layout and rendering engine using UIKit,
Core Graphics and Core Text. It parses HTML/XHTML and ordered stylesheets, computes
styles, builds and lays out a box tree, paginates or produces continuous geometry,
and draws text, images, backgrounds and borders without Yuedu Reader sources.

**Version 0.3.0 adds the standalone HTML/CSS engine.** Versions through 0.2.1
contain the earlier utilities only.
This does not claim full CSS/EPUB compatibility or DTCoreText feature equivalence.

`YueduCoreTextTypography` contains:

- CJK punctuation compression and smart punctuation;
- vertical CJK normalization and glyph classification;
- per-font vertical punctuation fallback detection;
- explicit Latin hyphenation language tagging;
- a Core Text framesetter factory for unbounded long-form layout.

Version 0.2.0 adds the `YueduCoreText` product with three public API areas:

- content progress through `ReaderContentMetrics` and
  `ReaderContentUnitMap`;
- UTF-16 text-selection state through `TextSelectionManager`;
- local Points of Interest instrumentation through `ReaderPerfTrace`.

## Requirements

- iOS 17 or later
- Swift 6
- Xcode 16 or later

## Integration

Add `https://github.com/CHANG-JUI-LIN/YueduCoreText` as a Swift Package
dependency with a minimum version of **0.3.0**, then link `YueduCoreText`
(or the independent `YueduCoreTextTypography` product for typography utilities).

The compiled, public-only example below lives in
[Examples/StandaloneConsumer/Sources/Consumer/Example.swift](Examples/StandaloneConsumer/Sources/Consumer/Example.swift).
Its separate package depends only on YueduCoreText and tests parsing, pagination,
drawing, images, source/selection/link geometry, reflow, unsupported content and cancellation.

```swift
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
```

## Scope and dependencies

Implemented BrowserLayout subsets include horizontal block/inline layout, percentage/em/px
widths and box metrics, supported left/right floats and clear, the existing horizontal ruby
subset, white-space modes, text-indent, images (including raster SVG wrappers), backgrounds,
borders, inline decoration, anchors, links/noterefs, footnote payloads, video placeholders
and authored pronunciation descriptions. The capability scanner uses the same CSS parser
and style builder as layout. Unsupported tables, flex/grid, positioned layouts, general
vector SVG, MathML, scripted content and vertical document layout are reported; they are
not silently delegated to a Reader backend.

EPUB ZIP/OPF/spine/container management, Readium, publication fetching, storage, book-source
networking, reader settings/UI, gesture handling, notes and TTS playback remain consumer
responsibilities. The existing Typography product still offers its vertical text utilities;
that does **not** imply vertical HTML document layout support in this engine.

The main product depends on YueduCoreTextTypography and **SwiftSoup 2.13.7** (pinned to the
Reader baseline). It uses the existing SwiftSoup/CSSParser/cascade; no Lexbor production
frontend, WebView renderer or automatic network loader is included.

## Resources, results and coordinates

Pass ordered `CSSFrontendInput` / `AuthorStylesheet` values, or HTML plus ordered CSS strings.
Input keeps linked stylesheet identities, load-failure diagnostics and compatibility order.
Resource preparation is explicit: consumers resolve stylesheet imports/URLs and register
fonts before synchronous layout, then supply `imageLoader` and `fontResolver` (or preloaded
images keyed by source/absolute URL through the convenience initializer). There is no hidden
network, file scan, whole-book preload or semaphore bridge. The Reader's chapter-scoped
resource adapter continues to handle its existing import/font/URL semantics.

`BrowserLayoutSession` emits one page per `layoutNextPage()`, with retained completed pages,
sourceText, anchors, footnotes, media and pronunciation descriptions. `prepareContinuous()`
builds the same core pipeline; its prepared result exposes the computed background image
source so resources can be loaded before `makeDocument()`. Continuous flow is not a stack
of paginated snapshots. Page image fitting and continuous geometry deliberately differ.

`PageFragments` and `DisplayList` use top-left, y-down **page canvas coordinates**.
`BrowserScrollDocument.displayList` uses **document coordinates**; `items(in:)` translates a
viewport/tile rect to tile-local coordinates without relayout. A host owns view/window
transforms. `DisplayList.draw(in:)` accepts a CGContext already configured for those logical
coordinates and uses exactly those same display artifacts for selection/link queries.

Text ranges index collapsed **sourceText in UTF-16**, not raw HTML and not String.count.
Shaped trailing spaces may be absent from visible page ranges while remaining in sourceText.
Ruby annotation geometry maps to its owning base range. HTMLLayoutError distinguishes
unsupported input, resource failure, layout failure and cancellation; BrowserLayoutFailure
also preserves the original detailed pipeline failure cases.

See [ENGINE-NOTICE.md](ENGINE-NOTICE.md) for source provenance and
[docs/EngineIntegration.md](docs/EngineIntegration.md) for execution and local integration.

## API and concurrency

The 0.x releases use semantic versioning, but may refine public APIs between
minor releases. UTF-16 length preservation is a compatibility guarantee for
vertical normalization and smart punctuation APIs because reading positions
are character-offset based.

`ReaderContentMetrics`, `ReaderContentUnitMap`, performance stages, and
performance metadata are `Sendable`. `TextSelectionManager` is mutable and
intentionally not `Sendable`; confine each instance to its consumer's actor or
serial queue.

Create and consume each Core Text framesetter/frame within one layout operation
or queue. Paged BrowserLayoutSession retains the existing MainActor contract. Batch document methods
inherit their caller's actor; continuous preparation is synchronous on the caller's serial
executor. CTLine/CTFrame/CTFramesetter artifacts must be created, read, drawn and released
under that ownership contract; layout results are intentionally not Sendable. Do not move
one document/session across concurrent tasks. cancel() prevents subsequent page emission
and releases unfinished tree/walker state; completed values live as long as their owners.
Reader uses its existing generation tokens to discard obsolete results. The engine does
not create detached work or move every layout onto MainActor.

An optional textTransform receives the evaluated attributed text before shaping; it must
preserve its string and UTF-16 length. Reader regex settings stay outside the package.
An optional textDecoration hook paints consumer-specific overlays only; HTML/CSS layout
and painting require no callbacks to Reader. Font and image resolvers must return already
prepared resources and must not block on asynchronous IO.

## Privacy

`ReaderPerfTrace` writes only local Points of Interest signposts. Performance
metadata must never contain book text, a book or chapter title, a URL, or
personal data. The package does not upload trace data.

## Testing

Run the package tests on an iOS Simulator:

```bash
xcodebuild test \
  -scheme YueduCoreText-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO
```

## License

Mozilla Public License 2.0. See [LICENSE](LICENSE). The Yuedu name and branding
are not granted by the source license.

EPUB container management, Reader UI, networking and persistent storage are out of scope.
