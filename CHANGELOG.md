# Changelog

All notable changes to YueduCoreText are documented in this file.

## [Unreleased]

W3C vertical typography (Yuedu Reader's `docs/superpowers/plans/2026-10-06-vertical-typography.md`).

### Added

- `VerticalOrientation`: each character's UAX #50 `Vertical_Orientation`, from a table generated out of the Unicode Character Database 18.0.0 by `scripts/vertical_orientation.py`. The data's license is in `NOTICE`.
- `ChineseScript` and `CJKTypographyStyle`: whether text is Traditional or Simplified Chinese, or Japanese, read from its characters; each style's language tag and reference font.
- `BrowserLayoutConfig.cjkTypographyStyle`, the style a host decided for the chapter's text. nil keeps the previous behaviour.
- `CJKTypography.applyOrientation(to:in:)` and `centreSideways(_:in:)`: vertical text set as CSS Writing Modes 3 `text-orientation: mixed` sets it.
- `CJKTypographyStyle.korean`, from Hangul text or a declared `ko`.
- `CJKTypography.applyFonts(to:style:in:)`: CJK text tagged with its language and drawn in that language's font — PingFang TC, PingFang SC, Hiragino Sans or Apple SD Gothic Neo for Han; Hiragino Sans for kana; Apple SD Gothic Neo for Hangul. Dashes, ellipses, quotation marks and middle dots next to CJK text go with it, as do symbols the text's fonts lack. A character the font or its cascade has keeps that font. `CJKTypography.replacedFontAttribute` records the font a range had before.

### Changed

- Vertical lines no longer set every character upright. Latin letters, ASCII digits and other `R` characters lie on their side, centred on the column; `Tr` characters such as brackets and ー use the font's vertical alternate, or lie on their side when it has none.
- `CJKTypography.centreSideways` adds to a run's existing baseline offset instead of replacing it.
- With a `cjkTypographyStyle`, inline layout and ruby run `applyFonts` in both writing modes. A range's CJK stand-in does not count as a font of its own when line boxes are sized.
- Text without a family that resolves is set in the system font, not PingFang SC, and `ReaderFontCascade` no longer names PingFang SC or STHeiti SC. On iOS the system font's own fallback follows the device's languages, so CJK text should come with a `cjkTypographyStyle`.

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
