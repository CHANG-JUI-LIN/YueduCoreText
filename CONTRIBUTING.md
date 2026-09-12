# Contributing to YueduCoreText

Thanks for helping improve native long-form reading on Apple platforms.

## Development requirements

- Xcode 16 or later
- Swift 6
- An iOS 17 or later Simulator

Run the standalone test suite before opening a pull request:

```bash
xcodebuild test \
  -scheme YueduCoreText-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO
```

Changes to vertical typography must preserve UTF-16 offsets. Performance
changes need reproducible before/after measurements, including the Xcode
version, build configuration, device, corpus, median, and p95. Performance
metadata must not contain personal data, a book or chapter title, book text, or
a URL. Do not include copyrighted books, application secrets, or private test
documents in issues or fixtures.

## Dependency boundary

YueduCoreTextTypography remains independent of the main engine and third-party parsing.
The YueduCoreText core target may use Foundation, `os`, UIKit/CoreText/CoreGraphics,
Typography and the pinned SwiftSoup
frontend. Readium, Firebase, WebKit, application settings/storage/networking and app logging
remain forbidden. Internal algorithm tests may use @testable; the separate consumer and
legacy public utility tests must use only the published public API surface.

## Contributions and releases

By submitting a contribution, you agree to license it under MPL-2.0 and confirm
that you have the right to do so. Releases follow semantic versioning. During
the 0.x series, a minor version may contain API changes; migration notes are
required for any public API change.
