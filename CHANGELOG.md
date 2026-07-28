# Changelog

All notable changes to YueduCoreText are documented in this file.

## [0.2.0] - 2026-07-28

### Added

- `ReaderContentMetrics` and `ReaderContentUnitMap` for overflow-safe,
  chapter-local to book-wide content progress.
- `TextSelectionManager` for mutable UTF-16 selection state using stable
  endpoint tokens while visual handles cross.
- `ReaderPerfTrace` for content-free, local Points of Interest intervals.

### Changed

- Replaced separate start/end selection mutations with the reviewed
  `TextSelectionEndpoint` token API so one gesture keeps controlling the same
  logical endpoint through repeated crossings.
- Hardened content metrics and selection operations at integer extremes,
  invalid ranges, `NSNotFound`, and empty content boundaries.

## [0.1.0]

### Added

- `YueduCoreTextTypography`, including CJK punctuation processing, vertical
  normalization and glyph classification, language-aware hyphenation, and Core
  Text framesetter creation.
