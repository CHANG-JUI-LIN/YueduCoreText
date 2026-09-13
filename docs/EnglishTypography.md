# English publishing CSS (0.5.0)

These corrections are included in 0.5.0. Version 0.4.0 does not contain them. Use `.upToNextMinor(from: "0.5.0")` for remote integration.

The existing Current CSS frontend, native block/inline layout, incremental paginator and continuous layout remain the production pipeline. No Lexbor cutover or WebView fallback is involved.

Implemented corrections:

- Adjacent/general element siblings (`+`, `~`), `:first-of-type`, and global rule order across stylesheets. A complete `AuthorStylesheet` input uses its active DOM-order projection; processed inline sheets are not replayed from HTML.
- Root `html` font, line height, indentation and language participate in inheritance. Signed px/pt/em/rem/% indentation and `inherit`/`initial`/`unset` are resolved before line breaking. Relative lengths inherit their computed length; percentages retain their containing-block basis. Invalid indentation does not erase an earlier valid declaration. `hanging`, `each-line`, calc and other unsupported values remain distinguishable from invalid declarations.
- Horizontal inline boxes use half-leading rather than clamping every authored line height to glyph ink bounds. Parent struts, inline images and ruby continue contributing to the line box. Reader extra line spacing is added once between lines. Absolute minimum block heights preserve authored heading space.
- Inherited `hyphens:none/manual/auto` and content `lang`/`xml:lang` reach the actual line breaker. Auto uses the platform's locale-specific hyphenation dictionary only for declared languages. Manual soft hyphens become visible only at a selected break. Candidate widths include the visible hyphen before justification. Unknown languages do not default to English.
- Generated hyphens belong to presentation, not `sourceText`. A linear source mapping can have one trailing presentation character; source hit testing clamps to the actual source range. Copy/search/TTS continue using the original UTF-16 text, including authored soft hyphens.
- `text-align-last` is applied to paragraph tails and hard breaks. Wrapped justified lines retain justification; they are not silently converted to left alignment by a fill-ratio threshold.
- `:first-letter`/`::first-letter` rules are consumed by the normal frontend. Opening punctuation and the first grapheme are placed in an inline/float box, preserving nested styles and source ranges. Float initials use intrinsic shaped width and the existing exclusion/fragmentation path. This is not a replacement float implementation.

The existing standalone consumer includes a public-API-only English example test. The host supplies HTML/CSS, prepared resources and `BrowserLayoutConfig`, then calls `HTMLLayoutDocument.makePageSession()` or `prepareContinuous()`. Drawing and interaction use the returned display lists.

`BrowserLayoutConfig.onDiagnostic` is optional and local to the document. It reports stylesheet identities/order, matched declarations, computed typography, used box/line geometry and font metrics. It does not send telemetry or include chapter text. Treat CSS resource identifiers as private data if persisting the callback output. The engine's existing executor and cancellation contracts are unchanged.

## Boundaries

This is a publishing subset, not full CSS conformance. Arbitrary `font` shorthand, `hanging`/`each-line` indentation, general shrink-to-fit floats, advanced first-letter layouts spanning block/replaced/ruby boundaries, and percentage min-height with an indefinite containing block are not newly supported. Advanced vertical layout is unchanged. Unspecified indentation remains zero; the engine does not infer indentation from a reference reader screenshot. Auto hyphenation is enabled only when authored CSS requests it.

Compatibility references: [CSS Text 3, 14 August 2026 CR Draft](https://www.w3.org/TR/2026/CRD-css-text-3-20260814/), [CSS 2.2 inline height/leading](https://www.w3.org/TR/CSS22/visudet.html#line-height), [CSS 2.2 first-letter](https://www.w3.org/TR/CSS22/selector.html#first-letter). Geometry fixes are backed by targeted tests; antialiasing or identical pagination across different readers is not an acceptance criterion.

## Migration from 0.4.x

- `CSSSelector.Combinator` adds `adjacentSibling` and `generalSibling`. Update exhaustive switches in clients that inspect selectors.
- `BrowserLayoutCapabilityScanner.scan(input:writingMode:)` accepts the same ordered `CSSFrontendInput` as layout. Prefer this overload when providing authored stylesheet identities; the existing string-array overload remains available.
- `BrowserLayoutConfig.onDiagnostic` is optional and defaults to nil. Existing construction remains valid.
- Indentation values may now be signed and styles inherit computed relative lengths. Corrected line heights, minimum heights and hyphenation change geometry and pagination; keep reading positions as source UTF-16 offsets, not saved page numbers.
- A full author stylesheet projection is applied once in document order. The string-array convenience API retains external-sheet then inline-style collection semantics.
