# Changelog

All notable changes to YueduCoreText are documented in this file.

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
