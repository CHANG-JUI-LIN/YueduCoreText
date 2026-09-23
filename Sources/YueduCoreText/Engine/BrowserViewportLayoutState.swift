import UIKit

/// Resource ownership for demand-driven continuous layout. Box layout still
/// resolves all margins, borders and float positions through BlockLayout.
/// Only inline shaping is demand-driven; geometry survives resource eviction.
final class BrowserViewportLayoutState {
    struct Geometry {
        let box: BlockBox
        let origin: CGPoint
        let range: NSRange
        let entryVersion: UInt64?
        let inlineWidth: CGFloat?
    }
    struct LineGeometry {
        let start: InlineLayoutCheckpoint
        let end: InlineLayoutCheckpoint
        let source: NSRange

        init(start: InlineLayoutCheckpoint, end: InlineLayoutCheckpoint, line: LayoutLine) {
            self.start = start; self.end = end
            let ranges = line.runs.map(\.sourceRange)
            let lower = ranges.map(\.location).min() ?? 0
            let upper = ranges.map { NSMaxRange($0) }.max() ?? lower
            source = NSRange(location: lower, length: upper - lower)
        }
    }
    final class Entry {
        var width: CGFloat = -1
        var floats: [ActiveFloat] = []
        var floatOffset: CGFloat = 0
        var cursor: InlineLayoutCursor?
        var geometry: [LineGeometry] = []
        var retained: [Int: LayoutLine] = [:]
        var complete = false
        var height: CGFloat = 0
        var context: InlineFormattingContext?
        var version: UInt64 = 0
    }
    var entries: [ObjectIdentifier: Entry] = [:]
    let fontCache = InlineFontCache()
    var geometry: [ObjectIdentifier: Geometry] = [:]
    private(set) var geometryRevision: UInt64 = 0
    private var paintedBoxes: [BlockBox] = []
    private var unresolvedFloatStart = CGFloat.infinity
    var viewport = CGRect.null
    var targetOffset: Int?
    var forceComplete = false
    private(set) var shapedLineCount = 0
    private(set) var revision = 0

    var retainedLineCount: Int { entries.values.reduce(0) { $0 + $1.retained.count } }
    var measuredLineCount: Int { entries.values.reduce(0) { $0 + $1.geometry.count } }
    var estimatedBoxCount: Int { entries.values.filter { !$0.complete }.count }

    /// Paint resources have the same lifetime as the retained layout lines,
    /// including ruby lines which are distinct from their containing CTLine.
    var retainedDrawingLineIDs: Set<ObjectIdentifier> {
        var result = Set<ObjectIdentifier>()
        for entry in entries.values {
            for line in entry.retained.values {
                if let ctLine = line.ctLine { result.insert(ObjectIdentifier(ctLine)) }
                for run in line.runs {
                    if let ruby = run.ruby {
                        result.insert(ObjectIdentifier(ruby.base.line))
                        result.insert(ObjectIdentifier(ruby.annotation.line))
                    }
                }
            }
        }
        return result
    }

    func height(for box: BlockBox) -> CGFloat { entries[ObjectIdentifier(box)]?.height ?? 0 }

    /// Rebind paint lines without re-running BlockLayout when every demanded
    /// line is already measured and resident. Validate the entire window first:
    /// a missing line or unresolved float must use the normal layout transaction.
    /// Geometry, widths and float contexts are immutable between those transactions.
    func restoreRetainedViewport(in bounds: CGRect, anchor: Int?, candidates: [Geometry], indexedRevision: UInt64) -> Bool {
        guard !forceComplete, !geometry.isEmpty, geometryRevision == indexedRevision,
              unresolvedFloatStart > bounds.maxY else { return false }
        var selected: [(BlockBox, [LayoutLine])] = []
        for g in candidates {
            guard let entry = entries[ObjectIdentifier(g.box)], entry.version == g.entryVersion,
                  entry.width == g.inlineWidth else { return false }
            let containsAnchor = anchor.map {
                NSLocationInRange($0, g.range) || $0 == NSMaxRange(g.range)
            } ?? false
            let localMin = max(0, bounds.minY - g.origin.y)
            let localMax = max(0, bounds.maxY - g.origin.y)
            // An estimate beyond the measured tail is not a paint-only change.
            guard entry.complete || (entry.geometry.last?.end.y ?? 0) > localMax else { return false }
            var first = entry.geometry.firstIndex { $0.end.y >= localMin } ?? entry.geometry.count
            if containsAnchor, let anchor {
                first = min(first, entry.geometry.firstIndex { NSMaxRange($0.source) > anchor } ?? entry.geometry.count)
            }
            var lines: [LayoutLine] = []
            for index in first..<entry.geometry.count {
                guard let line = entry.retained[index] else { return false }
                lines.append(line)
                let measured = entry.geometry[index]
                let reachedAnchor = anchor.map { measured.source.location > $0 || NSMaxRange(measured.source) > $0 } ?? true
                if measured.end.y > localMax && (!containsAnchor || reachedAnchor) { break }
            }
            selected.append((g.box, lines))
        }
        // Clear only surfaces from the preceding viewport, not every box in
        // the document. No mutation occurs until all candidates are validated.
        for box in paintedBoxes { box.lines = [] }
        for (box, lines) in selected { box.lines = lines }
        paintedBoxes = selected.compactMap { $0.1.isEmpty ? nil : $0.0 }
        viewport = bounds
        targetOffset = anchor
        return true
    }

    func lines(for box: BlockBox, context: InlineFormattingContext) -> [LayoutLine] {
        let id = ObjectIdentifier(box)
        let entry = entries[id] ?? Entry()
        entries[id] = entry
        let floats = context.floatContext?.activeFloats ?? []
        // A uniform translation without exclusions does not invalidate lines.
        let offset = floats.isEmpty ? 0 : context.blockOffsetY
        if entry.width != context.containingInlineSize || entry.floats != floats || entry.floatOffset != offset {
            entry.version &+= 1
            entry.width = context.containingInlineSize; entry.floats = floats; entry.floatOffset = offset
            entry.cursor = nil; entry.geometry.removeAll(); entry.retained.removeAll(); entry.complete = false
        }
        entry.context = context
        let count = box.inlineRuns.reduce(0) { $0 + ($1.text as NSString).length }
        let lineHeight = max(1, box.style.lineHeight ?? box.style.fontSize * 1.4)
        let estimatedLines = ceil(CGFloat(max(1, count)) / max(1, context.containingInlineSize / max(1, box.style.fontSize * 0.7)))
        let measuredEnd = entry.geometry.last?.end ?? InlineLayoutCheckpoint()
        if !entry.complete {
            let remaining = max(0, count - measuredEnd.characterIndex)
            entry.height = measuredEnd.y + ceil(CGFloat(remaining) / max(1, context.containingInlineSize / max(1, box.style.fontSize * 0.7))) * lineHeight
            if entry.geometry.isEmpty { entry.height = max(lineHeight, estimatedLines * lineHeight) }
        }
        let old = geometry[id]
        let y = old?.origin.y ?? 0
        let localMin = max(0, viewport.minY - y)
        let localMax = max(0, viewport.maxY - y)
        let containsTarget = targetOffset.map { offset in
            old.map { NSLocationInRange(offset, $0.range) || offset == NSMaxRange($0.range) } ?? false
        } ?? false
        // Float formatting contexts that precede the demand are dependencies,
        // including text floats. Their exact extent decides subsequent wrapping.
        var ancestor: BlockBox? = box
        var floatDependency = false
        while let candidate = ancestor {
            if candidate.isFloated, let g = geometry[ObjectIdentifier(candidate)], g.origin.y <= viewport.maxY {
                floatDependency = true; break
            }
            ancestor = candidate.parentBox
        }
        let resolveFloatExtent = floatDependency && !entry.complete
        let needed = forceComplete || containsTarget || resolveFloatExtent || (old != nil && y <= viewport.maxY && y + entry.height >= viewport.minY)
        guard needed else { return [] }
        if entry.cursor == nil {
            _ = InlineLayout.layoutLines(runs: box.inlineRuns, context: context) { entry.cursor = $0 }
        }
        guard let cursor = entry.cursor else { entry.complete = true; entry.height = 0; return [] }
        var first = entry.geometry.firstIndex { $0.end.y >= localMin } ?? entry.geometry.count
        if containsTarget, let targetOffset {
            first = min(first, entry.geometry.firstIndex { NSMaxRange($0.source) > targetOffset } ?? entry.geometry.count)
        }
        if forceComplete || resolveFloatExtent { first = 0 }
        cursor.checkpoint = first < entry.geometry.count ? entry.geometry[first].start : measuredEnd
        var index = first
        var output: [LayoutLine] = []
        while true {
            let checkpoint = cursor.checkpoint
            let line: LayoutLine
            if let cached = entry.retained[index], index < entry.geometry.count {
                line = cached; cursor.checkpoint = entry.geometry[index].end
            } else {
                guard let next = cursor.next() else {
                    entry.complete = true; entry.height = cursor.checkpoint.y
                    break
                }
                line = next; shapedLineCount += 1; revision += 1; entry.version &+= 1
                let measured = LineGeometry(start: checkpoint, end: cursor.checkpoint, line: line)
                if index == entry.geometry.count { entry.geometry.append(measured) }
                entry.retained[index] = line
            }
            output.append(line)
            index += 1
            let targetReached = targetOffset.map { offset in
                entry.geometry[index - 1].source.location > offset || NSMaxRange(entry.geometry[index - 1].source) > offset
            } ?? true
            if !forceComplete, !resolveFloatExtent, cursor.checkpoint.y > localMax,
               (!containsTarget || targetReached) { break }
        }
        if !entry.complete {
            let end = entry.geometry.last?.end ?? measuredEnd
            entry.height = end.y + ceil(CGFloat(max(0, count - end.characterIndex)) / max(1, context.containingInlineSize / max(1, box.style.fontSize * 0.7))) * lineHeight
        }
        return output
    }

    func updateGeometry(root: BlockBox, origin: CGPoint) {
        geometryRevision &+= 1
        geometry.removeAll(keepingCapacity: true)
        paintedBoxes.removeAll(keepingCapacity: true)
        unresolvedFloatStart = .infinity
        func visit(_ box: BlockBox, origin: CGPoint, isRoot: Bool = false, floatStart: CGFloat = .infinity) -> NSRange {
            // Match PageWalker: collapsed first-child margin is carried by the
            // root, whose frame origin stays zero. Child frames already include it.
            let content = isRoot
                ? CGPoint(x: origin.x + box.margins.left + box.borders.left + box.padding.left,
                          y: origin.y + box.margins.top)
                : CGPoint(x: origin.x + box.frame.minX + box.borders.left + box.padding.left,
                          y: origin.y + box.frame.minY + box.borders.top + box.padding.top)
            let dependencyStart = box.isFloated ? min(floatStart, content.y) : floatStart
            let entry = entries[ObjectIdentifier(box)]
            if !box.inlineRuns.isEmpty, entry?.complete != true {
                unresolvedFloatStart = min(unresolvedFloatStart, dependencyStart)
            }
            if !box.lines.isEmpty { paintedBoxes.append(box) }
            var ranges = box.inlineRuns.map(\.sourceRange)
            ranges += box.children.map { visit($0, origin: content, floatStart: dependencyStart) }.filter { $0.length > 0 }
            let start = ranges.map(\.location).min() ?? 0
            let end = ranges.map { NSMaxRange($0) }.max() ?? start
            let range = NSRange(location: start, length: end - start)
            geometry[ObjectIdentifier(box)] = Geometry(box: box, origin: content, range: range,
                entryVersion: entry?.version, inlineWidth: entry?.width)
            return range
        }
        _ = visit(root, origin: origin, isRoot: true)
    }

    func trim(to rect: CGRect) {
        for (id, entry) in entries {
            guard let g = geometry[id] else { continue }
            if rect.isNull || g.origin.y > rect.maxY || g.origin.y + entry.height < rect.minY {
                entry.version &+= 1
            }
            entry.retained = entry.retained.filter { _, line in
                line.top + line.height + g.origin.y >= rect.minY && line.top + g.origin.y <= rect.maxY
            }
            if entry.retained.isEmpty { entry.cursor = nil }
            g.box.lines = g.box.lines.filter {
                $0.top + $0.height + g.origin.y >= rect.minY && $0.top + g.origin.y <= rect.maxY
            }
        }
    }
}
