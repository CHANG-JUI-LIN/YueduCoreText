# Engine integration and ownership

Version 0.3.0 contains the extracted engine. Version 0.2.1 does not contain
HTMLLayoutDocument. Consumers can resolve the 0.3.0 tag directly from GitHub.

## Standalone consumers

Start with the README in [English](../README.md), [繁體中文](../README.zh-Hant.md)
or [简体中文](../README.zh-Hans.md). Each contains the same compiled pagination,
bitmap, image and continuous-viewport examples, plus installation and testing commands.
Only YueduCoreText and its declared dependencies are required; the Reader repository
and the optional workspace described below are not needed by other apps.

`Examples/StandaloneConsumer` is a separate library/test package that imports only
public APIs. Its local path dependency supports development in this repository.
To use the published release in your own consumer, declare the GitHub URL with
`.upToNextMinor(from: "0.3.0")` and link the `YueduCoreText` product.

## Execution contract

- Configuration and resource closures belong to the document; there is no shared engine
  or implicit file/network loader. Preload only the requested document's resources.
- CSSFrontendInput retains original source ordering/diagnostics. Imported CSS and fonts
  may be prepared asynchronously by the consumer before layout. The Reader's adapter
  still handles its publication URL/font rules; the core CSS parser/cascade is unchanged.
- HTMLLayoutDocument's convenience image lookup uses literal source first, then baseURL.
  Missing required images or failed supplied stylesheets are observable resource failures.
- BrowserLayoutSession remains MainActor-confined. It prepares the core tree once and
  walks page boundaries incrementally. Its generation token belongs to the consumer.
- Continuous preparation runs synchronously on the caller's serial executor. Layout,
  CTLine artifacts and drawing must stay on their owning executor; results are not Sendable.
  Batch internal async APIs explicitly inherit their caller actor using Swift 6 isolation.
- CTLine/CTFrame/CTFramesetter values are created and retained by their layout operation
  and result owners. No detached task transports these objects. No new background queue
  is started. Drawing uses retained layout/geometry; it does not run parsing or pagination.
- cancel() makes subsequent page calls throw cancellation and releases unfinished pipeline
  state. Already emitted pages remain valid until their consumers release them. Dropping
  the session releases its completed-page cache. Reader additionally guards async commits
  using its existing generation checks; task cancellation does not authorize stale results.
- Metrics and diagnostic counters use locks; they do not own document/resource caches.

## Adapter and drawing boundary

Reader retains chapter/spine management, CoreTextPageEngine fallback, browserAuto policy,
fixed-layout EPUB, legacy vertical/TXT/online paths, bars/background preferences, navigation,
gestures, annotations and playback. It receives package fragments/display items and uses
package source/geometry queries. Its optional regex text transform changes attributes only;
its decoration closure draws Reader-specific effects, never a whole document/page.

Package block/inline, float/ruby, line breaking, fragmentation, continuous flow, CSS
backgrounds/borders/images and source mapping are the only production implementations.
Lexbor remains experimental in the Reader test target; it is not a package dependency.

## Remote integration

Use https://github.com/CHANG-JUI-LIN/YueduCoreText with a minimum version of 0.3.0.
Reader's normal Yuedu-Reader.xcodeproj resolves that published dependency; the sibling
workspace is optional for engine development. Normal remote verification must use the
project without the local override and must inspect the resolved version and revision.
Do not edit Package.resolved by hand or modify SourcePackages/checkouts.

## Optional: developing Yuedu Reader and the engine together

Place the original checkouts beside each other:

```
parent/
  Yuedu-reader/
  YueduCoreText/
```

Open `Yuedu-reader/Yuedu-Engine.xcworkspace`. Its relative package reference overrides
that project's existing remote package identity. Do not add a second same-named package
to the App target, and do not edit Xcode's SourcePackages/checkouts.

Set `YUEDU_TEST_DESTINATION` to an installed iOS Simulator (use `xcrun simctl list devices available`).
For example, `platform=iOS Simulator,id=<installed-device-uuid>`.

From Yuedu-reader:

```sh
xcodebuild -workspace Yuedu-Engine.xcworkspace -scheme Yuedu-Reader \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:'yuedu appTests/BrowserLayoutPageEngineTests' test
```

From YueduCoreText:

```sh
xcodebuild -scheme YueduCoreText-Package -destination "$YUEDU_TEST_DESTINATION" \
  -parallel-testing-enabled NO test
cd Examples/StandaloneConsumer
xcodebuild -scheme YueduCoreTextConsumer -destination "$YUEDU_TEST_DESTINATION" \
  -parallel-testing-enabled NO test
```

The consumer package depends only on the package two directories above it. It can be
run from a clean directory containing this repository's Package.swift, Sources, Tests,
Examples and LICENSE, without the Reader repository. No Reader scheme participates.
