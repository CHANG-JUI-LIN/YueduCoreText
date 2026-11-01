# Changelog

All notable changes to YueduCoreText are documented in this file.

## [0.11.0] - 2026-11-01

Every picture takes one character of the chapter's source text, so a page of pictures has a position of its own. This moves the offsets after a picture: a host that saved offsets against 0.10 maps them once (see Migration). Also the layout work merged since 0.10.1: inline-blocks, separated-borders tables, viewport units, letter-spacing, `vertical-align: super/sub` and `rotate()`.

### Changed

- **Every picture takes one U+FFFC of `sourceText`.** An `<img>` (inline, block or floated), an SVG wrapping one image, and a video's placeholder each append one U+FFFC where they stand, whether or not the image loads, so a load failure never moves the offsets after it. A CSS background takes none. Up to 0.10 a picture had a place in the source text but no extent: its place was the offset of whatever followed it. An illustration page between two paragraphs (the white space between the blocks collapses away) therefore shared the next page's position, and a page turn or a restore on it resolved to the page after it. Each picture page now resolves to itself, in paged and in scroll mode.
- A picture's line run, page fragment and display item carry that character's range (length 1). An id on a picture resolves to its character.
- Paragraph ranges hold text only, as before: a picture's character is never part of a paragraph that text selection extends to.
- An inline-block is an atomic box on its line (CSS 2.1 §9.2.2). It was laid out as an ordinary inline box, so a chat bubble written as an inline-block holding a `<p>` lost its background, border, padding and rounded corners. A vertical chapter holding a non-replaced inline-block is refused by admission.
- A block inside an inline box splits it into anonymous blocks instead of vanishing (CSS 2.1 §9.2.1.1); `<span><p>…</p></span>` used to lose the paragraph.

### Added

- `BrowserPictureOffsets`: a chapter's picture characters (`offsets`), and the map from offsets saved against 0.10 (`migrated(_:)` for an offset or a range) and back (`unmigrated(_:)`). Available as `BrowserLayoutSession.pictureOffsets`, `BrowserViewportChapterFacts.pictureOffsets` and `BrowserContinuousLayout.pictureOffsets`.
- Separated-borders table layout (CSS 2.1 §17): row groups with `thead`/`tfoot` reordering, shrink-to-fit width, column sizing with colspan distribution, `border-spacing`, and cell `vertical-align`. Rowspan, nested tables, `border-collapse: collapse` and vertical tables still fall back.
- `vh`/`vw` units, in replaced sizes and in explicit block, table-cell and table heights; CSS `max-height` on replaced elements.
- Authored `letter-spacing`, negative values included; it wins over the reader-configured default.
- `vertical-align: super/sub` as baseline shifts of inline and inline-block boxes, computed from the parent's font size as WebKit does.
- Paint-time `transform: rotate()`.
- `width: auto` floats shrink to fit.

### Fixed

- Floats are placed against their containing block's inline range; a floated parent keeps its first child's margin inside it; a parent's float and margins no longer leak into anonymous blocks.
- Explicit block heights beyond px literals resolve; an inline image's used size resolves against the fragment height; first-child margin folds are re-accounted after child layout.
- Synthetic bold uses a WebKit-style offset second pass and widens glyph advances for it.

### Migration

Offsets into `sourceText` (reading positions, highlights, bookmarks, anchors a host stored) saved against 0.10 or earlier point one character early for every picture before them. Map each one once, with the pictures of the layout that will read it:

```swift
let pictures = session.pictureOffsets              // after the session has laid out a page
let offset = pictures.migrated(savedOffset)
let highlight = pictures.migrated(savedRange)
```

An offset at a picture's 0.10 place named the text after the picture — 0.10 resolved it there — and still does. A range keeps every character it had and takes in the pictures inside it; a picture at either end stays out. Record that an offset has been mapped: mapping it twice moves it again. A host that must keep writing 0.10 offsets for older readers gets them with `unmigrated(_:)`; only an offset on a picture does not round-trip.

### Compatibility

- Source text, page source ranges and every offset after a picture change. Chapters with no pictures are unaffected.
- No API is removed or renamed. `BrowserViewportChapterFacts` gained a stored property; hosts never construct it.

## [0.10.2] - 2026-11-01

Pages of pictures: no blank page in front of a full-page picture, and a picture page no longer reports the chapter's end as its position.

### Fixed

- A picture that does not fit the room left on a page no longer moves to the next page when nothing has been drawn on its page yet. Moving it only left that page blank — a full-page map under the 8pt body margin was preceded by an empty page. The picture stays and is scaled, aspect kept, into the room the page has left (CSS Fragmentation §4.4: no break before a fragmentainer's first content). Pages that already carry content still move it as before.
- A page's source range counts its pictures, not only its text. A page holding nothing but pictures had no range and reported the chapter's end, so every picture page of a chapter shared one position with the page after it, and a page turn or a restore resolved to the wrong page. `BrowserPageGeometry.buildPageRanges` and the page session's offset-targeted layout now share one implementation; CSS background paint is left out, as in scroll mode.
- A block-level picture (`display: block`, or floated) carries its place in the source text, as an inline picture does. It was always offset 0, so its page claimed the chapter's first position in paged and in scroll mode.

### Compatibility

- No API changes, and the source text is unchanged, so saved character offsets keep their meaning. A page that held only pictures now resolves to the place of its first picture instead of the chapter's end.

### Known issues

- A picture has a place in the source text but no extent. When a page of pictures is followed directly by text — an illustration between two paragraphs, where the white space between the blocks collapses away — the picture's place is the next paragraph's first character, and the two pages share one position: such a page resolves to the page after it. Telling them apart needs every picture to take up source text, which moves the offsets after it; that is planned for 0.11, with a migration for saved offsets. `ImagePagePaginationTests` records the case as a known issue.

## [0.10.1] - 2026-10-16

Documentation: what a host must hand `BrowserChapterDocument.evaluate(_:configuration:writingMode:)`.

### Documentation

- The configuration parameter is `sending`, so the configuration must be disconnected. A configuration returned by an actor-isolated method is not, because the closures that method forms (`fontResolver`, `textTransform`, `onDiagnostic`) belong to its actor. Swift 6 rejects that call with "sending 'configuration' risks causing data races", and marking the method `-> sending` is refused as well. Build the configuration in a nonisolated function from Sendable inputs, with `@Sendable` resolvers. The 0.10.0 migration note and the integration guide's example now say so.
- An evaluation kept in an actor-isolated property belongs to that actor, even after it is removed, and can no longer be sent. Hand it from `evaluate` straight to the code that lays it out.

### Compatibility

- No code changes; 0.10.0 and 0.10.1 build and lay out identically.

## [0.10.0] - 2026-10-16

A chapter's document and evaluation move between isolation domains (Yuedu Reader's Swift 6 concurrency cleanup).

### Added

- `BrowserChapterDocument.parse(input:)` and `BrowserChapterDocument.evaluate(_:configuration:writingMode:)`: async forms of `init(input:)` and `evaluate(configuration:writingMode:)` that run on the global concurrent executor and return their result as `sending`. A host on the main actor parses and evaluates a chapter off it and receives the document and the evaluation back with no Sendable wrapper; the compiler checks that nothing else still holds them.
- `CSSFrontendInput`, `AuthorStylesheet`, `StylesheetIdentity` and `CSSFrontendDiagnostic` are `Sendable`. They are plain values.

### Not Sendable, by design

- `BrowserChapterDocument` and `BrowserChapterEvaluation` stay non-Sendable. The document keeps the SwiftSoup DOM, which writes its own indexes while it is read, so two threads reading it race. An evaluation keeps that document and a `BrowserLayoutConfig` whose closures (`fontResolver`, `textTransform`, `onDiagnostic`) belong to the host. Both are used on one executor at a time and move between isolation domains as `sending` values. A document and every evaluation made from it, `rebound(to:)` included, share the DOM and move together.

### Migration

- A host that moved them out of `Task.detached` through an `@unchecked Sendable` box can drop the box: `let document = try await BrowserChapterDocument.parse(input: input)`, read `document.bodyInlineStyle` if it needs it, then `let evaluation = await BrowserChapterDocument.evaluate(document, configuration: configuration)`. After that call, reach the document and the configuration only through the evaluation.
- The configuration passed to `evaluate` must be disconnected (see 0.10.1). One returned by an actor-isolated method is not: build it in a nonisolated function from Sendable inputs, with `@Sendable` resolvers.
- The new functions run at the caller's task priority, where `Task.detached(priority:)` set its own.

### Compatibility

- `init(input:)` and `evaluate(configuration:writingMode:)` are unchanged, and evaluations lay out exactly as before.
- iOS 17, Swift tools 6.0 (Xcode 16) and SwiftSoup 2.13.7 requirements are unchanged.

## [0.9.0] - 2026-10-12

Bottom-justified pages (Yuedu Reader's 底部對齊).

### Added

- `BrowserLayoutConfig.bottomJustify`: on a page that ends because its next text line no longer fits, the space left below the last line is spread evenly over the page's line gaps — line k moves down by k × leftover ÷ (lines − 1) — so the first line keeps its place and the last line's ink sits on the content bottom. The page's fragments carry the moved geometry, so painting, hit testing, selection, links and highlights need no change. Decoration boxes follow the lines they hold.
- A page keeps its lines when it ends at a forced break, an image, a float or a box start; when it is the document's last page; when the line that moved on is more than twice the last line's box (a display-size heading); when its last line is a block image; and when a box opens below its last line. Horizontal pages only: vertical writing and continuous scrolling are never justified.

### Compatibility

- Off by default; with `bottomJustify` false, pages lay out exactly as before.
- Not a cascade input: a configuration that adds it to an evaluation's configuration is still accepted.
- iOS 17, Swift tools 6.0 and SwiftSoup 2.13.7 requirements are unchanged.

## [0.8.0] - 2026-10-08

CSS logical properties (Yuedu Reader's `docs/superpowers/plans/2026-10-07-aozora-complete-support.md`, Phase 2a).

### Added

- `margin-inline-start`, `margin-inline-end`, `margin-block-start`, `margin-block-end`, the matching `padding-` properties, `inline-size`, `max-inline-size` and `min-inline-size`, as CSS Logical Properties 1 has them with `direction: ltr`. Inline-start is the left edge in horizontal-tb and the top in vertical-rl; block-start the top and the right. The cascade maps each declaration to its physical side for `BrowserLayoutConfig.writingMode` when it applies it, so a logical and a physical declaration of the same side resolve by the cascade, the later one winning. One stylesheet written with them is right in both writing modes.
- `min-inline-size` sets a minimum inline size that wins over the maximum (CSS 2 §10.4). Physical `min-width` is still not parsed, and vertical admission still refuses physical `min-height` and `min-width`.

### Changed

- The writing mode is a cascade input. `BrowserChapterDocument.evaluate(configuration:writingMode:)` styles the chapter for the writing mode it judges, and the evaluation's `configuration` carries that mode; `BrowserChapterEvaluation.accepts(_:)` and `rebound(to:)` refuse a configuration in the other writing mode, which needs a new evaluation. Hosts that already evaluate with their configuration's writing mode see no difference.

### Compatibility

- Chapters without logical properties lay out exactly as before.
- iOS 17, Swift tools 6.0 and SwiftSoup 2.13.7 requirements are unchanged.

## [0.7.0] - 2026-10-07

W3C vertical typography (Yuedu Reader's `docs/superpowers/plans/2026-10-06-vertical-typography.md`).

### Added

- `VerticalOrientation`: each character's UAX #50 `Vertical_Orientation`, from a table generated out of the Unicode Character Database 18.0.0 by `scripts/vertical_orientation.py`. The data's license is in `NOTICE`.
- `ChineseScript` and `CJKTypographyStyle`: whether text is Traditional or Simplified Chinese, or Japanese, read from its characters; each style's language tag and reference font.
- `BrowserLayoutConfig.cjkTypographyStyle`, the style a host decided for the chapter's text. nil keeps the previous behaviour.
- `CJKTypography.applyOrientation(to:in:)` and `centreSideways(_:in:)`: vertical text set as CSS Writing Modes 3 `text-orientation: mixed` sets it.
- `CJKTypographyStyle.korean`, from Hangul text or a declared `ko`.
- `CJKTypography.applyPositions(to:style:vertical:in:)`: 、。，．：；？！ moved to where the style's system font sets them — centred for Taiwan and Hong Kong, after the text for the Mainland (CLREQ), JLREQ's places for Japanese — when the font that draws them puts them elsewhere. Both fonts are measured from drawings; the mark moves by baseline offset and a pair of opposite kerns, so every advance stays. `CJKTypography.apply(to:style:vertical:in:)` runs fonts, then positions.
- `CJKTypography.applyFonts(to:style:in:)`: CJK text tagged with its language and drawn in that language's font — PingFang TC, PingFang SC, Hiragino Sans or Apple SD Gothic Neo for Han; Hiragino Sans for kana; Apple SD Gothic Neo for Hangul. Dashes, ellipses, quotation marks and middle dots next to CJK text go with it, as do symbols the text's fonts lack. A character the font or its cascade has keeps that font. `CJKTypography.replacedFontAttribute` records the font a range had before.
- `CJKTypography.applySpacing(to:style:vertical:in:)`: a pair of adjacent marks involving a bracket takes 1.5 em instead of 2 (CLREQ), the space coming first from between them, then for Chinese from the bracket's far side, so the bracket stays against its text. ：；？！ in vertical text, and ？！ in Taiwan and Hong Kong's horizontal text, keep their squares. Japanese squeezes only between the marks and keeps middle dots and dividing marks whole (JLREQ §3.1.4), so ？」 stays 2 em. The blanks come from each mark's measured ink, each spent once, and the squeeze is kerning, so ink never meets ink. `apply` runs fonts, positions, then spacing.
- Authored `text-combine-upright` (縦中横) in vertical text: `all`, `digits` / `digits 2`–`4`, and the prefixed `-webkit-text-combine: horizontal`, `-epub-text-combine(-horizontal)` and `-ms-text-combine-horizontal`. Each text node, or each short digit run of it, is one upright em square on the column, its characters kept in `sourceText` and drawn horizontally in the square. `TextCombineUpright` (parsing and digit segmentation) and `CombinedUpright.line` (the composition: letter-spacing ignored, scaled horizontally into the em when wider) are public, so the reader's legacy engine sets cells by the same rules. The capability scanner no longer rejects these values; it still rejects unknown ones, and 縦中横 inside or around ruby.
- `GlyphBoundary.offset(_:at:)` and `index(_:at:)`: the boundaries between characters along a CTLine as the glyphs stand. After a negative kern — a squeezed or moved mark — `CTLineGetOffsetForStringIndex` puts the boundary half the kern inside the next glyph (國？」國: glyph at 50 pt, boundary at 54.9 pt); here it is where that glyph starts. Other boundaries are CoreText's.
- `ReaderPerfStage.cjkTypographyPrepare` (`cjk.typography.prepare`): a Points of Interest interval around inline layout's CJK pass, with the text's length and writing mode.

### Changed

- Vertical lines no longer set every character upright. Latin letters, ASCII digits and other `R` characters lie on their side, centred on the column; `Tr` characters such as brackets and ー use the font's vertical alternate, or lie on their side when it has none.
- `CJKTypography.centreSideways` adds to a run's existing baseline offset instead of replacing it.
- With a `cjkTypographyStyle`, inline layout and ruby run `apply` (fonts, punctuation positions and spacing) in both writing modes. A range's CJK stand-in does not count as a font of its own when line boxes are sized.
- Text without a family that resolves is set in the system font, not PingFang SC, and `ReaderFontCascade` no longer names PingFang SC or STHeiti SC. On iOS the system font's own fallback follows the device's languages, so CJK text should come with a `cjkTypographyStyle`.
- The kern `applyPositions` and `applySpacing` put on the character before a mark covers the whole character. On half of a surrogate pair it split the glyph (𠀀 drew as two missing glyphs, 0.6 em wider); a combining sequence, which CoreText kerns by no consistent rule, is left alone.
- `BrowserTextGeometry` rects, carets and hits, fragment advances inside a run, and ruby base extents use `GlyphBoundary`: selections, highlights and narration no longer cut a quarter em off the character after a squeezed mark.
- `CJKTypographyProcessor.apply` no longer compresses punctuation: it converts quotes and nothing else. Its own rules took up to an em between a closing and an opening mark, and spacing now belongs to `CJKTypography.applySpacing`. The processor's lists stay for line breaking.

## [0.6.2] - 2026-10-06

### Added

- `BrowserChapterDocument` and `BrowserChapterEvaluation`: a chapter's markup and stylesheets are parsed once, styled once for a configuration, and that one evaluation carries both the admission verdict (`capabilities`, with font requests) and the style tree a session lays out from. `HTMLLayoutDocument(evaluation:)` and `BrowserLayoutSession(evaluation:)` start from it instead of parsing the chapter again; `bodyInlineStyle` lets a host read its font-scale policy from the same parse.
- `BrowserChapterEvaluation.accepts(_:)` / `rebound(to:)`: a session may add geometry, a font resolver or a diagnostic sink to the configuration after admission, but never change the cascade inputs the tree was computed for; a mismatch is refused, never laid out from stale values.

### Changed

- Admission judges matched declarations from the cascade's own rule matching (plus the elements the cascade never styles) rather than matching every rule against every element a second time. The verdict, its order, text-indent usage and font requests are unchanged; `BrowserLayoutCapabilityScanner` keeps its entry points as thin wrappers over the shared evaluation.
- Pipeline metrics of a reused evaluation carry its `htmlParse` / `cssCollect` / `cssParse` / `styleTree` stage times.

### Compatibility

- Existing scanner, `HTMLLayoutDocument(input:configuration:)` and `BrowserLayoutSession(input:config:)` entry points are unchanged and still parse on their own.
- iOS 17, Swift tools 6.0 and SwiftSoup 2.13.7 requirements are unchanged.

## [0.6.1] - 2026-09-30

### Added

- `BrowserFontRequest` and capability-result `fontRequests`, collected from the existing computed-style tree, including inherited struts, visible descendants, ruby and materialized first-letter styles.
- A configuration-aware capability scan for effective font family, weight and italic demand. Hosts can prepare only referenced faces after accepting a chapter and before capturing their font resolver.

### Compatibility

- Existing ordered-input and HTML/CSS scanner entry points remain available, including the original two-argument function signature.
- Font registration, EPUB resource ownership and fallback policy remain host responsibilities; the scanner performs no resource I/O.
- iOS 17, Swift tools 6.0 and SwiftSoup 2.13.7 requirements are unchanged.

## [0.6.0] - 2026-09-23

### Added

- Demand-driven continuous layout through `BrowserViewportSession`, with retained geometry, bounded drawing resources, source-position lookup and immutable published snapshots.
- `BrowserViewportLayoutOwner` for serialized background layout and resource retirement, plus transaction diagnostics.
- Stable `BrowserPaintFragment` identities, separate text paint phases and independently owned Core Text lines for background drawing.
- `BrowserPageBackground` metadata so continuous hosts can draw authored canvas backgrounds at viewport size, including fixed attachment.

### Fixed

- Reuse final resolved fonts, measured line geometry and unchanged display items during viewport layout.
- Use one half-leading calculation for paragraph struts and text runs, removing floating-point differences between equivalent line boxes.
- Discard the part of an inline image's line box below the image that crosses a page break, so consecutive page-tall images no longer leave an empty page between them.
- Apply reader rule line-heights to ruby and vertical lines again, and let a rule that only enlarges the font grow its line box, so enlarged glyphs no longer overlap the previous line.
- Preserve reader line-height decorations, source indices and drawing bounds while retaining or retiring viewport resources.

### Migration

- Existing paged and prepared continuous APIs remain available. See [viewport integration](docs/ViewportIntegration.md) before adopting the new continuous API.
- Viewport geometry can contain estimated offscreen extents. Hosts must preserve the canonical UTF-16 source anchor when committing updated geometry.
- Draw `facts.pageBackground` behind the chapter; viewport display lists omit the propagated canvas background. Keep layout, hit-testing and drawing ownership separate as described in the migration guide.
- iOS 17, Swift tools 6.0 and SwiftSoup 2.13.7 requirements are unchanged.

## [0.5.1] - 2026-09-13

### Fixed

- Avoid a short-circuit autoclosure in diagnostic fragment traversal so Swift 6.3 Release builds compile without sending-data-race errors.
- Add a Release build for iOS devices to CI alongside Simulator regression tests.

## [0.5.0] - 2026-09-13

### Fixed

- Honor authored first-letter styles through the normal frontend, float/inline layout and drawing pipeline.
- Preserve root inheritance, global stylesheet ordering, signed and pt indentation, explicit horizontal line heights and absolute minimum block heights.
- Connect language-aware automatic/manual hyphenation to line selection and painting while preserving UTF-16 source and selection geometry.
- Preserve author alignment, paragraph-tail alignment and source whitespace around overflowing words.

### Added

- Adjacent/general sibling selectors and first-of-type matching.
- Ordered-input capability scanner overload and optional local typography diagnostics.
- English publishing regression fixtures, actual Reader corpus integration, and an independent public API consumer test.

### Migration

- Selector combinators gain two enum cases; clients with exhaustive switches must handle them.
- See [English typography migration](docs/EnglishTypography.md#migration-from-04x) for source order and geometry changes.
- iOS 17, Swift tools 6.0 and SwiftSoup 2.13.7 requirements are unchanged. This remains a supported CSS subset.

## [0.4.0] - 2026-09-12

### Added

- Basic normal-flow `vertical-rl` text layout through the existing logical-axis
  pipeline, including native Core Text vertical glyph forms and pagination.
- Shared horizontal/vertical ruby measurement, styling and source mapping.
- Continuous vertical document geometry, including public
  `BrowserScrollDocument.documentPoint(forCharOffset:)`, physical content size,
  selection and hit testing for right-to-left hosts.
- Compiled public-API vertical consumer and bitmap, ruby, geometry, reflow and
  cancellation regressions. Unsupported vertical content remains explicit;
  this release does not claim full CSS Writing Modes or EPUB compatibility.

### Changed

- English, Traditional Chinese and Simplified Chinese integration guides now
  describe the released engine, resources, drawing and coordinate contracts.
- CI validates both the package and independent consumer. Typography tests now
  cover valid full-em punctuation compression using actual glyph geometry.
- iOS 17, Swift tools 6.0, SwiftSoup 2.13.7 and existing utility products remain.

## [0.3.0] - 2026-09-12

### Added

- Standalone native HTML/XHTML and CSS parsing, style computation, box layout,
  Core Text shaping, incremental pagination, continuous layout and drawing.
- Public HTMLLayoutDocument, configuration/resource inputs, display lists,
  UTF-16 source mapping, link/anchor/selection geometry and semantic descriptors.
- Existing BrowserLayout float/ruby, images, backgrounds, borders and inline
  decoration support, with explicit unsupported/resource/cancellation results.
- A separately compiled public-only iOS consumer example and engine regressions.

### Changed

- The main product now depends on YueduCoreTextTypography and SwiftSoup 2.13.7.
- Existing typography, selection, content-metrics and tracing APIs are retained.
- Reader-specific EPUB container management, fallback policy, settings, storage,
  navigation and playback remain outside the package. This is not full CSS/EPUB
  compatibility, vertical HTML layout, or DTCoreText feature equivalence.
- Minimum declared requirements remain iOS 17 and Swift tools 6.0.

## [0.2.1] - 2026-08-01

### Fixed

- Bound adjacent CJK punctuation compression to the shaped glyphs' actual ink
  gap, preventing combinations such as `……】` from overlapping across system,
  EPUB, and fallback fonts.

## [0.2.0] - 2026-07-28

### Added

- `ReaderContentMetrics` and `ReaderContentUnitMap` for overflow-safe,
  chapter-local to book-wide content progress.
- `TextSelectionManager` and `TextSelectionEndpoint` for mutable UTF-16
  selection state using stable endpoint tokens while visual handles cross.
- `ReaderPerfTrace` for content-free, local Points of Interest intervals.

### Changed

- Hardened content metrics and selection operations at integer extremes,
  invalid ranges, `NSNotFound`, and empty content boundaries.

## [0.1.0]

### Added

- `YueduCoreTextTypography`, including CJK punctuation processing, vertical
  normalization and glyph classification, language-aware hyphenation, and Core
  Text framesetter creation.
