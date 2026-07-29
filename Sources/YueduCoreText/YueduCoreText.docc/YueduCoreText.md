# ``YueduCoreText``

Model reading progress and text selections, and measure reader pipeline work
with local Points of Interest.

## Overview

Use ``ReaderContentUnitMap`` to convert a chapter-local UTF-16 position into
``ReaderContentMetrics`` for the whole publication. Manage a mutable selection
with ``TextSelectionManager``, and wrap measured work with
``ReaderPerfTrace``.

YueduCoreText intentionally leaves pagination, HTML parsing and rendering, and
UIKit reader components to its consumers.

### Concurrency

Content metrics, unit maps, performance stages, and performance metadata are
`Sendable`. ``TextSelectionManager`` is mutable and intentionally not
`Sendable`; confine each instance to one actor or serial queue.

### Privacy

``ReaderPerfTrace`` writes local Points of Interest signposts and does not
upload telemetry. Metadata must not contain book or chapter titles, book text,
URLs, personal data, or other user content.

## Topics

### Content metrics

- ``ReaderContentMetrics``
- ``ReaderContentUnitMap``

### Text selection

- ``TextSelectionManager``
- ``TextSelectionHandle``
- ``TextSelectionEndpoint``

### Performance tracing

- ``ReaderPerfTrace``
- ``ReaderPerfStage``
- ``ReaderPerfMetadata``
