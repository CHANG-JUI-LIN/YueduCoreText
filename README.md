# YueduCoreText

YueduCoreText is an iOS-native Core Text toolkit for long-form reader
typography and content state. Its public API is exercised by standalone package
tests and is designed for adoption by reader applications.

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
dependency, then link the products needed by your target:

```swift
import YueduCoreTextTypography
import YueduCoreText

let normalized = "(直排)".normalizedForVerticalLayout()
let framesetter = CoreTextFramesetterFactory.make(for: attributedString)

let unitMap = ReaderContentUnitMap(chapterUnitCounts: [120, 240])
let selection = TextSelectionManager()
let page = ReaderPerfTrace.span(.renderPage) {
    renderCurrentPage()
}
```

## Scope

This package deliberately does not include publication parsing, persistence,
book-source networking, reader settings, or application UI. Pagination and
paginator implementations, HTML parsing and rendering, and UIKit reader
components are explicitly out of scope. Consumers remain responsible for those
layers.

The package performs no networking, persistence, analytics upload, or
telemetry. It has no third-party runtime dependencies.

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
or queue. The package does not introduce hidden actors, dispatch queues, global
settings, or retry paths.

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
