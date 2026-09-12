# Basic vertical-rl and shared ruby (0.4.0)

Available from the published 0.4.0 package. Consumers pass the writing mode
explicitly into capability checks and layout for paged and continuous reading.
Continuous vertical paint windows enter an RTL host in right-to-left order.
Unsupported content is reported to the consumer; the package owns no fallback
policy. Yuedu Reader retains its chapter-level legacy fallback in its adapter.

## Supported scope

Set `BrowserLayoutConfig.writingMode = .verticalRTL`. The explicit document
configuration owns the writing mode. With this configuration, authored
`writing-mode: vertical-rl` (including EPUB/WebKit spelling) is accepted.
Horizontal configuration continues to reject authored vertical layout.

- Normal-flow blocks/inline text; top-to-bottom text and right-to-left columns;
  native Core Text vertical glyph forms, CJK/kana, combining clusters,
  supplementary characters and sideways Latin.
- Existing whitespace, line-height, first-line text-indent and fragmentation;
  CSS physical height/max-height constrain the inline axis. Margin, padding,
  background and border edges retain physical CSS meaning.
- Incremental page emission/cancellation and continuous documents. Continuous
  content grows in physical **width**, with fixed viewport **height**.
- One ruby semantic/measurement model for both modes: group ruby, paired direct
  rt, adjacent ruby, optional rb/rp and styled inline base/annotation spans.
  Annotation size defaults to 50%; authored rt font size, family, weight and
  color pass through the existing cascade.
- Centered, separate ruby over horizontal text or right of vertical text.
  Each group is atomic to the parent line breaker; an oversized group may
  overflow its available inline extent rather than split its reading.

Vertical replaced elements/images, floats, max-width, non-pixel explicit block
widths, min-width/min-height, alternate nested writing modes, vertical-lr,
text-combine-upright and non-mixed text-orientation report unsupported.
Nested ruby, rtc, under/inter-character ruby and alternate alignment/merge are
also unsupported in both modes. Existing exclusions (tables, flex/grid,
positioned content, scripts, etc.) still apply. No full CSS Writing Modes or
EPUB compliance is claimed.

## One pipeline, axis conversion at the boundary

The frontend/cascade is unchanged except for retaining max-height and treating
rb as an inline element. `LogicalFlow` maps computed physical CSS sides into
canonical `(inline, block)` storage before box construction. The same
BlockLayout, InlineLayout, RubyInlineLayout and PageWalker calculate both modes.
Core Text receives vertical forms during shaping; retained metrics, glyph
matrices and source offsets describe the glyphs actually drawn.
`LogicalGeometry.physicalRect` converts logical fragments to physical
page/document coordinates. The painter uses Core Text's vertical run matrices;
it does not rotate Japanese characters independently.

Historical CGRect x/y slots inside the walker are canonical inline/block
coordinates, not physical vertical rectangles. Published results are converted:

- Page-local: top-left origin, x rightward, y downward, including content insets.
- Continuous: physical document coordinates; first column at the right edge.
- Tile: document coordinates translated by both tile-origin components.
- `DisplayTextItem.baselineY` keeps its API name but holds physical baseline
  **x** for vertical text (baseline **y** for horizontal text).
- Paged `documentRect` describes unfragmented flow, anchored at the flow's right
  edge; page relocation is reflected in `rect`. Use page-local geometry for
  page interactions, not a guessed page-index translation of documentRect.

Source indexes remain UTF-16 offsets in collapsed sourceText, never raw HTML
indexes. Readings do not enter sourceText. Base fragments map linearly;
annotation geometry maps atomically to the whole base. Styled annotation slices
retain their own shaped range with that atomic source mapping. Page selection
uses the same display geometry as hit testing. Links/anchors keep node identity.

Continuous vertical hosts use contentSize, documentPoint(forCharOffset:),
displayList.sourceRange(at:sourceText:) and items(in:). The older documentY and
charOffset(atDocumentY:) methods remain horizontal-host helpers.

## Ownership and verification

The serial-executor contract is unchanged. Page sessions are MainActor confined.
Continuous preparation/results stay on the consumer's serial executor. Retained
CTLines are used and released on that executor; results are not Sendable.
Resources are explicitly supplied; the engine never probes files or networks.
A new viewport/font requires a new document/session. Cancel the old session and
honor its generation before publishing results.

[VerticalExample.swift](../Examples/StandaloneConsumer/Sources/Consumer/VerticalExample.swift)
is compiled by the independent consumer using only public API.
VerticalLayoutTests checks exact bitmap equality with native CTFrameDraw, ruby
styles/ranges, reflow, pagination, continuous geometry and cancellation.
The Reader's optional corpus tests cover both the direct package/resource adapter
chain and importing the original EPUB into BookStore, opening EPUBPageRenderer,
and using its shared BrowserAuto instance from the scroll engine. Synthetic
Reader route tests also cover RTL tiles, source hits and chapter restoration.
