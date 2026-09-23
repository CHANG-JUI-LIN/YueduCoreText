# Viewport integration in 0.6.0

The new continuous API is optional. Existing `HTMLLayoutDocument` page sessions
and prepared continuous documents retain their entry points.

`ReaderPerfStage` gains five viewport cases: `viewportReuse`, `viewportGeometry`,
`viewportTrim`, `viewportPaintEviction` and `viewportRetirement`. Update any
exhaustive switches or enumerated stage lists in consumer code.

## Layout ownership

Create `BrowserViewportLayoutOwner` from an `HTMLLayoutDocument` in a background
task. Its initializer performs CSS cascade and box-tree construction on the
calling thread. Transfer the document into the owner and do not use it elsewhere.
Await `layout(in:anchorOffset:)` to request a document-space viewport and read the
returned `BrowserViewportSnapshot`. The actor serializes layout and resource
retirement. Its `facts` and `initialSnapshot` are available without entering the
actor.

`BrowserViewportSession` is the lower-level synchronous API, created with
`HTMLLayoutDocument.makeViewportSession()`. A caller using it directly must
serialize every access, including layout and resource retirement.

## Geometry and painting

Offscreen geometry can be estimated. Retain the reading position as a source
UTF-16 offset, then use snapshot position lookup to preserve its screen position
when installing new geometry. Do not persist a tile index or an estimated page
number as the reading position.

Use `snapshot.document.paintFragments(in:scale:)` to obtain paint fragments.
Fragment identity, paint order, rendering bounds and text paint phase serve
different purposes: preserve their supplied ordering and bounds. A fragment's
display list is a drawing snapshot, not a mutable layout session.

Core Text line instances must not be used concurrently by hit testing and
drawing. Use `displayListWithOwnTextLines()` for the drawing worker's copy; keep
the snapshot's geometry and interaction resources under their existing owner.
Retire drawing resources through the layout owner when no longer needed, and
bound host-owned raster caches separately.

## Canvas backgrounds

Viewport display lists exclude the propagated html/body canvas background.
Draw `facts.pageBackground` behind the chapter, including the reader margins.
Resolve its `imageSource` using the publication's resource resolver, size it
with `imageRect(for:onPageOf:)` against the visible page, and honor `isFixed` by
keeping the background attached to the viewport. Do not size a cover background
image against the estimated height of the entire chapter.

This release does not add EPUB container parsing, a scroll view, a raster cache,
or full CSS support. Hosts continue to own those integration decisions.
