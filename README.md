# YueduCoreText

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

**Native HTML/CSS layout and drawing for iOS, powered by Core Text.**

Turn HTML/XHTML, CSS and prepared resources into paginated pages or a continuous document. Draw the result into a `CGContext` and query text, link and selection geometry. You do not need Yuedu Reader source code or a WebView.

Use it to build a native document or reading interface when you need control over drawing and interaction. Your app supplies resources and hosts the result; the package owns parsing, styling, layout, pagination and painting.

[0.4.0 release](https://github.com/CHANG-JUI-LIN/YueduCoreText/releases/tag/0.4.0) · [Runnable example](Examples/StandaloneConsumer) · [Integration guide](docs/EngineIntegration.md) · [Changelog](CHANGELOG.md)

## Requirements and installation

- iOS 17+, Swift tools 6.0+, Xcode 16+. Requires Apple UIKit, Core Text and Core Graphics; this is an iOS package.
- The HTML/CSS engine is available from **0.3.0**. Versions through 0.2.1 provide the earlier utilities only.
- The main product depends on `YueduCoreTextTypography` and **SwiftSoup 2.13.7**.

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/CHANG-JUI-LIN/YueduCoreText`, and add the **YueduCoreText** product to your target. For 0.4.x, choose **Up to Next Minor Version** starting at **0.4.0**.

For a Swift package, add this to `Package.dependencies`:

```swift
.package(
    url: "https://github.com/CHANG-JUI-LIN/YueduCoreText",
    .upToNextMinor(from: "0.4.0")
)
```

Then add this to your target's `dependencies`:

```swift
.product(name: "YueduCoreText", package: "YueduCoreText")
```

0.x minor releases may change public APIs; the constraint above stays within 0.4.x. Select `YueduCoreTextTypography` instead if you only need the typography utilities.

## Render your first page

This complete function is compiled in [Example.swift](Examples/StandaloneConsumer/Sources/Consumer/Example.swift). Call `try await renderExample()` from a main-actor context. It returns a 320 × 480 bitmap, source text and link regions; wrap the image with `UIImage(cgImage:)` to display it in UIKit.

```swift
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
```

`layoutNextPage()` returns one page at a time and `nil` at the end. Keep the session for subsequent pages; `finish()` requests all remaining pages. A display list retains the prepared drawing results, so drawing it again does not repeat parsing or layout.

The example renders one pixel per logical point. A production host chooses its drawing scale. `renderWidth`/`renderHeight` describe the content area; nonzero `contentInsets` add space around it, which the host must include in its page canvas.

## Images and continuous scrolling

Pass an already prepared `UIImage` to this example. It is also compiled in Example.swift, using the imports above:

```swift
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
```

Use `contentSize` for your scroll container. For another viewport, pass its **document-space** rectangle to `items(in:)`; the returned display list is translated to that viewport's local origin. Clip drawing to the viewport. The continuous document is laid out as a continuous flow, not stitched page images.

Load resources before layout:

- The convenience initializer accepts ordered external CSS strings and an image dictionary. Inline styles and `<style>` elements are parsed from HTML. It does not fetch `<link>` stylesheets or expand remote `@import` URLs for you.
- Image lookup tries the literal `src` first. If `baseURL` is supplied, it also tries the absolute URL as a dictionary key. This convenience `baseURL` resolves image keys; it is not a general stylesheet or link rewriting service.
- Use `CSSFrontendInput` and `AuthorStylesheet` when you need stylesheet source identities, ordering and load-failure information, plus `imageLoader` for explicit resource lookup. Resolve imports and stylesheet-relative URLs before handing resources to the engine.
- Register custom or embedded fonts yourself, then supply `BrowserLayoutConfig.fontResolver` if CSS families need mapping. The engine does not download or register font files automatically.

## Text, links and selection

| Need | API / contract |
|---|---|
| Source text | `session.sourceText` or `continuous.sourceText` |
| Selection rectangles | `displayList.selectionRects(for: NSRange)` |
| Text at a point | `displayList.sourceRange(at:sourceText:)` |
| Link regions | `LinkInteractionRegionSet.build(from:spineIndex:anchors:)` |
| Anchor offsets | `session.anchorOffsets` or `continuous.anchorOffsets` |
| Page text ranges | `BrowserPageGeometry.buildPageRanges(_:sourceText:)` |

All text offsets address the engine's whitespace-collapsed **sourceText in UTF-16**, not raw HTML offsets or Swift `String.count`. Use `NSString`/`NSRange` when working with them. In the single-document example, `spineIndex: 0` is simply the host's document identifier; no EPUB container is required.

Page display lists use top-left, y-down **page coordinates**. Continuous display lists use **document coordinates**. Tile results use **tile-local coordinates**. Your host converts view/window coordinates; hit testing and drawing must use the same space. Ruby annotation geometry maps to the owning base-text range.

## Supported scope

| Area | 0.4.0 |
|---|---|
| Layout | Horizontal and basic vertical-rl block/inline flow, supported px/em/% dimensions, margins/padding, white-space and text-indent |
| Pagination | Incremental page sessions, page image fitting and continuous document layout |
| Rich content | Supported left/right float and clear, horizontal/vertical-rl ruby subset, raster images and raster-image SVG wrappers |
| Painting | Text, images, backgrounds, borders and supported inline decoration |
| Interaction and semantics | Source ranges, anchors, links/noterefs, selection geometry, supported footnote payloads, media placeholders and authored pronunciation descriptors |

These are implemented subsets, not a complete CSS compatibility matrix. **Tables, flex/grid, positioned layout, advanced vertical HTML document layout, general vector SVG, MathML and scripts are unsupported.** Supported float/ruby structures are also limited. The high-level document API checks capabilities and reports unsupported input; it does not silently switch to a Reader backend.

EPUB ZIP/OPF/spine management, network loading, reader controls, gestures, notes storage and media/TTS playback belong to your app. Version **0.4.0** adds basic `vertical-rl` text and shared ruby. See the [compiled vertical consumer](Examples/StandaloneConsumer/Sources/Consumer/VerticalExample.swift) and [scope/coordinate contract](docs/VerticalLayout.md). No full EPUB/CSS compliance or DTCoreText feature parity is claimed.

## Configuration, errors and lifetime

`BrowserLayoutConfig` carries content dimensions/insets, root font size/families, colors, spacing, default alignment and an optional font resolver. Create a new document/session when the viewport, resources or configuration changes; these results do not observe app settings automatically.

- `makePageSession()` and incremental sessions are **MainActor-confined**. The async page API does not promise background execution.
- Continuous preparation is synchronous on the caller's serial executor. Keep the document, Core Text artifacts and drawing on their owning executor; results are intentionally not `Sendable`.
- Image/font resolvers must return prepared resources, without waiting on asynchronous I/O. There is no automatic network loader or global document engine.
- `cancel()` prevents subsequent page emission and releases unfinished session state. Completed pages remain owned by their consumers. Discard obsolete results when your host's generation changes.
- `HTMLLayoutError` distinguishes `unsupported`, `resourceFailure`, `layoutFailure` and `cancelled`. Lower-level pipeline operations may also throw `BrowserLayoutFailure`; handle remaining errors as well. Required missing `<img>` resources and supplied failed stylesheets are reported; a missing paint-only background image may be omitted, so verify prepared assets yourself.

See the [integration guide](docs/EngineIntegration.md) for advanced input, ownership and adapter details.

## Other products and APIs

- **YueduCoreTextTypography:** CJK punctuation compression, smart punctuation, vertical normalization/glyph helpers, Latin hyphenation language tagging and framesetter creation.
- **YueduCoreText:** also exposes `ReaderContentMetrics` / `ReaderContentUnitMap`, `TextSelectionManager` and `ReaderPerfTrace`. Names containing “Reader” do not require the Yuedu Reader app.

`TextSelectionManager` is mutable and must stay on one actor or serial queue. Performance tracing uses local Points of Interest signposts, not uploads; do not put document text, titles, URLs or personal data in trace metadata.

## Examples, tests and known limitations

Clone this repository, select an installed simulator with `xcrun simctl list devices available`, and substitute its UUID below. No Reader checkout is needed.

```sh
export YUEDU_TEST_DESTINATION='platform=iOS Simulator,id=<simulator-uuid>'
xcodebuild -scheme YueduCoreText-Package \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO test
cd Examples/StandaloneConsumer
xcodebuild -scheme YueduCoreTextConsumer \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO test
```

The example is a small library with tests, not a ready-made reader app. It uses the repository's local package; the same public APIs are available in the published 0.4.0 dependency.

CI runs both the package tests and the standalone public-API consumer on iOS Simulator, and retains `.xcresult` artifacts. See [CI runs](https://github.com/CHANG-JUI-LIN/YueduCoreText/actions) for the tested revision, toolchain and outcome. No real-device performance claim is made.

For a bug report, [open an issue](https://github.com/CHANG-JUI-LIN/YueduCoreText/issues) with a minimal HTML/CSS sample, configuration, package/Xcode/iOS versions, expected result and screenshot. Supply only resources you have permission to share.

## License

[MPL-2.0](LICENSE). See [source provenance and dependency notice](ENGINE-NOTICE.md). Yuedu name and branding rights are not granted by the source license.
