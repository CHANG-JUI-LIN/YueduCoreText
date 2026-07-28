# YueduCoreText 0.2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release a standalone `YueduCoreText` core product containing stable content-progress, text-selection, and performance-tracing APIs already exercised by Yuedu Reader.

**Architecture:** Add a new Foundation/`os`-only SwiftPM target beside the existing typography target. Preserve the app-proven behavior while making every consumer-facing symbol explicitly public, test the public module boundary without `@testable`, and enforce that the core target cannot import UIKit, app globals, networking, persistence, or third-party frameworks.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, `os`, Swift Testing, iOS 17+, Xcode 16+.

---

### Task 1: Core product and content metrics

**Files:**
- Modify: `Package.swift`
- Create: `Sources/YueduCoreText/ReaderContentMetrics.swift`
- Create: `Tests/YueduCoreTextTests/ReaderContentMetricsTests.swift`

- [ ] **Step 1: Add the core product and write failing public-API tests**

Add a `YueduCoreText` library/target and `YueduCoreTextTests` test target to `Package.swift`. Create tests using `import YueduCoreText` (not `@testable`) that require:

```swift
let map = try #require(ReaderContentUnitMap(chapterUnitCounts: [100, 200]))
let metrics = try #require(map.metrics(
    spineIndex: 1,
    localCharacterOffset: 50,
    currentChapterCharacterCount: 100
))
#expect(metrics.currentUnitOffset == 200)
#expect(metrics.totalUnitCount == 300)
#expect(metrics.remainingUnitCount == 100)
```

Also cover negative counts, all-zero books, integer-overflow totals, invalid spine indices, missing character-count conversion, and local offsets clamped to the chapter end.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test \
  -scheme YueduCoreText \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO \
  -only-testing:'YueduCoreTextTests/ReaderContentMetricsTests'
```

Expected: build failure because `ReaderContentMetrics` and `ReaderContentUnitMap` are not defined in the public module.

- [ ] **Step 3: Implement the minimal public content-metrics API**

Move the app-proven implementation into `Sources/YueduCoreText/ReaderContentMetrics.swift` and expose:

```swift
public struct ReaderContentMetrics: Equatable, Sendable {
    public let currentUnitOffset: Int
    public let totalUnitCount: Int
    public var remainingUnitCount: Int { get }
}

public struct ReaderContentUnitMap: Equatable, Sendable {
    public init?(chapterUnitCounts: [Int])
    public var totalUnitCount: Int { get }
    public func metrics(
        spineIndex: Int,
        localCharacterOffset: Int,
        currentChapterCharacterCount: Int?
    ) -> ReaderContentMetrics?
}
```

Preserve the current UTF-16-to-unit proportional mapping and overflow rejection exactly.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: all `ReaderContentMetricsTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/YueduCoreText/ReaderContentMetrics.swift Tests/YueduCoreTextTests/ReaderContentMetricsTests.swift
git commit -m "feat: add content metrics core API"
```

### Task 2: Text-selection state API

**Files:**
- Create: `Sources/YueduCoreText/TextSelectionManager.swift`
- Create: `Tests/YueduCoreTextTests/TextSelectionManagerTests.swift`

- [ ] **Step 1: Write failing public-API tests**

Create tests using `import YueduCoreText` that cover forward and reverse selections, clamping, start/end handle crossing, clearing invalid ranges, and UTF-16 substring extraction:

```swift
let manager = TextSelectionManager()
manager.beginSelection(at: 4, maxLength: 10)
manager.updateSelection(to: 2, maxLength: 10)
#expect(manager.selectedRange == NSRange(location: 2, length: 3))

let text = NSAttributedString(string: "A😀中")
manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: text.length)
#expect(manager.selectedText(in: text) == "😀")
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test \
  -scheme YueduCoreText \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO \
  -only-testing:'YueduCoreTextTests/TextSelectionManagerTests'
```

Expected: build failure because `TextSelectionManager` is not defined.

- [ ] **Step 3: Implement the minimal public selection API**

Move the app-proven implementation into `Sources/YueduCoreText/TextSelectionManager.swift`. Make the type, initializer, read-only state, and mutation/query methods public:

```swift
public final class TextSelectionManager {
    public private(set) var anchorIndex: Int?
    public private(set) var focusIndex: Int?
    public var selectedRange: NSRange? { get }
    public var hasSelection: Bool { get }
    public var selectionBounds: (start: Int, end: Int)? { get }

    public init()
    public func beginSelection(at index: Int, maxLength: Int)
    public func setSelection(range: NSRange, maxLength: Int)
    public func updateSelection(to index: Int, maxLength: Int)
    public func updateSelectionStart(to index: Int, maxLength: Int)
    public func updateSelectionEnd(to index: Int, maxLength: Int)
    public func clear()
    public func selectedText(in attributedString: NSAttributedString) -> String?
}
```

Document that the mutable manager is consumer-confined and intentionally not `Sendable`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: all `TextSelectionManagerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/YueduCoreText/TextSelectionManager.swift Tests/YueduCoreTextTests/TextSelectionManagerTests.swift
git commit -m "feat: add text selection core API"
```

### Task 3: Performance tracing API

**Files:**
- Create: `Sources/YueduCoreText/ReaderPerfTrace.swift`
- Create: `Tests/YueduCoreTextTests/ReaderPerfTraceTests.swift`

- [ ] **Step 1: Write failing public-API tests**

Create public-module tests that lock the 22 stage raw values, deterministic metadata ordering, omission of absent values, and execution/return/error propagation for `span` and `spanAsync`:

```swift
#expect(Set(ReaderPerfStage.allCases.map(\.rawValue)) == expectedNames)
#expect(
    ReaderPerfMetadata(spineIndex: 0, characterCount: 0, writingMode: "verticalRTL")
        .logDescription
        == "spine=0 chars=0 writing=verticalRTL"
)
#expect(ReaderPerfTrace.span(.htmlParse) { 42 } == 42)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test \
  -scheme YueduCoreText \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO \
  -only-testing:'YueduCoreTextTests/ReaderPerfTraceTests'
```

Expected: build failure because the tracing types are not defined.

- [ ] **Step 3: Implement the minimal public tracing API**

Move the app-proven `ReaderPerfStage`, `ReaderPerfMetadata`, and `ReaderPerfTrace` implementations into `Sources/YueduCoreText/ReaderPerfTrace.swift`. Expose stage cases, `signpostName`, metadata fields/initializer/description, interval, and `begin`/`end`/`span`/`spanAsync` as public. Keep metadata content-free and keep `OSSignposter` private.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: all `ReaderPerfTraceTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/YueduCoreText/ReaderPerfTrace.swift Tests/YueduCoreTextTests/ReaderPerfTraceTests.swift
git commit -m "feat: add reader performance tracing API"
```

### Task 4: Dependency boundary and 0.2.0 documentation

**Files:**
- Modify: `Tests/YueduCoreTextTypographyTests/PackageBoundaryTests.swift`
- Create: `Tests/YueduCoreTextTests/CorePackageBoundaryTests.swift`
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Create: `CHANGELOG.md`
- Create: `Sources/YueduCoreText/YueduCoreText.docc/YueduCoreText.md`

- [ ] **Step 1: Write the core boundary test**

Scan every Swift file under `Sources/YueduCoreText` and fail on:

```swift
[
    "import UIKit",
    "import Readium",
    "import SwiftSoup",
    "import WebKit",
    "import Firebase",
    "import RealmSwift",
    "AppLogger",
    "GlobalSettings",
    "BookSourceSession",
]
```

Also assert the source directory is non-empty and the public tests import without `@testable`.

- [ ] **Step 2: Run all package tests**

Run:

```bash
xcodebuild test \
  -scheme YueduCoreText \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO
```

Expected: all typography and core tests pass.

- [ ] **Step 3: Document the 0.2.0 surface**

Update README integration examples to show both products, state that 0.2.0 adds content metrics, selection, and performance tracing, and keep paginator/HTML/UIKit explicitly out of scope. Add concurrency/privacy contracts:

- content structs are `Sendable`;
- selection manager is mutable and consumer-confined;
- trace metadata must not contain book text, title, URL, or personal data;
- the package still performs no networking, persistence, analytics upload, or telemetry.

Add `CHANGELOG.md` with `0.2.0` and `0.1.0` entries and a DocC landing page linking the three public API areas.

- [ ] **Step 4: Validate package metadata and formatting**

Run:

```bash
swift package describe
git diff --check
```

Expected: both products and both test targets appear; no whitespace errors.

- [ ] **Step 5: Re-run the full release gate**

Run the Step 2 command. Expected: all tests pass with zero failures.

- [ ] **Step 6: Commit**

```bash
git add README.md CONTRIBUTING.md CHANGELOG.md Sources/YueduCoreText/YueduCoreText.docc Tests
git commit -m "docs: prepare YueduCoreText 0.2.0"
```

### Task 5: Release candidate audit

**Files:**
- Inspect: `Package.swift`
- Inspect: `Sources/YueduCoreText/**`
- Inspect: `Sources/YueduCoreTextTypography/**`
- Inspect: `Tests/**`
- Inspect: `README.md`
- Inspect: `CHANGELOG.md`
- Inspect: `LICENSE`
- Inspect: `NOTICE`

- [ ] **Step 1: Confirm repository cleanliness and commit history**

```bash
git status --short --branch
git log --oneline --decorate main..HEAD
```

Expected: clean `release/0.2.0` branch with the planned commits only.

- [ ] **Step 2: Run the release test command**

```bash
xcodebuild test \
  -scheme YueduCoreText \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO
```

Expected: every package test passes.

- [ ] **Step 3: Verify the source boundary**

```bash
rg -n 'import (UIKit|Readium|SwiftSoup|WebKit|Firebase|RealmSwift)|AppLogger|GlobalSettings|BookSourceSession' Sources/YueduCoreText
```

Expected: no matches.

- [ ] **Step 4: Review API and release diff**

```bash
git diff --check main...HEAD
git diff --stat main...HEAD
git diff main...HEAD -- Package.swift README.md CHANGELOG.md Sources Tests
```

Expected: only the 0.2.0 core product, tests, and release documentation.

- [ ] **Step 5: Stop before external release mutations**

Present the verified release candidate and request approval before pushing `release/0.2.0`, merging to `main`, creating tag `0.2.0`, or creating a GitHub release. After the tag exists remotely, execute a separate Yuedu Reader consumer-migration plan that removes the three local source files and links the new `YueduCoreText` product.
