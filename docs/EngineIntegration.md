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
`.upToNextMinor(from: "0.11.0")` and link the `YueduCoreText` product.

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

## One parse per chapter

`BrowserChapterDocument(input:)` parses a chapter's markup and stylesheets once.
`evaluate(configuration:)` styles it for the reader configuration and returns a
`BrowserChapterEvaluation`: the admission verdict (`capabilities`, including font
requests) and the style tree that `HTMLLayoutDocument(evaluation:)` or
`BrowserLayoutSession(evaluation:)` lay out from. A host that decides the engine,
prepares fonts and then lays out therefore parses the chapter once, not three times;
`bodyInlineStyle` serves its font-scale policy from the same parse.

The tree's computed values belong to the configuration's cascade inputs (root font
size, families, colors, line height, spacing, bold, alignment). After admission a host
may add geometry, a font resolver captured after font preparation, or a diagnostic sink
through `rebound(to:)`; a configuration with different cascade inputs is refused
(`accepts(_:)` is false, the session initializers throw) and needs a new evaluation.
The document and evaluation are not Sendable. The document holds the DOM, which
SwiftSoup indexes while it is read, so two threads must never read it at once; the
evaluation holds the document and the configuration's closures, which belong to the
host. Use them on one executor at a time and drop them once the layout has taken them.
They move between isolation domains as `sending` values: `BrowserChapterDocument.parse(input:)`
and `BrowserChapterDocument.evaluate(_:configuration:writingMode:)` run on the global
concurrent executor and hand the result to the caller, so a main-actor host needs no
wrapper to parse and evaluate off the main thread.

`evaluate` takes the configuration as `sending` too, so the configuration must be
disconnected: nothing else may still reach it. One returned by an actor-isolated method
is not. The closures that method forms (`fontResolver`, `textTransform`, `onDiagnostic`)
belong to its actor, and so does the configuration that holds them; even a `-> sending`
result is refused there. Build the configuration in a nonisolated function, from
Sendable inputs the actor reads for it, with `@Sendable` resolvers:

```swift
struct ConfigurationInputs: Sendable {   // read on the host's actor
    var renderWidth: CGFloat
    var rootFontSize: CGFloat
    var fontResolver: (@Sendable ([String], Int, Bool, CGFloat) -> UIFont?)?
}

nonisolated func makeConfiguration(_ inputs: ConfigurationInputs) -> BrowserLayoutConfig {
    BrowserLayoutConfig(renderWidth: inputs.renderWidth, rootFontSize: inputs.rootFontSize,
                        fontResolver: inputs.fontResolver)
}

let document = try await BrowserChapterDocument.parse(input: input)
let configuration = makeConfiguration(inputs(fontScale: document.bodyInlineStyle))
let evaluation = await BrowserChapterDocument.evaluate(document, configuration: configuration)
// From here on, reach the document and the configuration only through `evaluation`.
```

The same holds for the evaluation itself: one the host stored in an actor-isolated
property belongs to that actor from then on, even after it is removed, and can no
longer be sent. Hand it from `evaluate` to the code that lays it out instead.

A document and every evaluation made from it (`rebound(to:)` included) share the DOM,
so the compiler moves them as one value.

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

Use https://github.com/CHANG-JUI-LIN/YueduCoreText with a minimum version of 0.11.0.
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
