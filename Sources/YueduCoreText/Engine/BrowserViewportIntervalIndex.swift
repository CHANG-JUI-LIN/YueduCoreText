import CoreGraphics

/// Geometry-only index; owns no CTLine, bitmap or additional content cache.
/// Query ties retain input order, matching a linear minimum-distance search.
struct BrowserViewportIntervalIndex {
    private struct Interval {
        let lower: CGFloat
        let upper: CGFloat
        let ordinal: Int
    }
    private var starts: [Interval] = []
    private var ends: [Interval] = []
    private var maximumEnds: [CGFloat] = []
    private var subtreeMaximumEnds: [CGFloat] = []

    init(_ ranges: [ClosedRange<CGFloat>] = []) {
        update(ranges)
    }

    mutating func update(_ ranges: [ClosedRange<CGFloat>]) {
        let intervals = ranges.enumerated().map { Interval(lower: $0.element.lowerBound,
            upper: $0.element.upperBound, ordinal: $0.offset) }
        starts = ordered(intervals, reusing: starts) { $0.lower == $1.lower ? $0.ordinal < $1.ordinal : $0.lower < $1.lower }
        ends = ordered(intervals, reusing: ends) { $0.upper == $1.upper ? $0.ordinal < $1.ordinal : $0.upper < $1.upper }
        var maximum = -CGFloat.infinity
        maximumEnds = starts.map { maximum = max(maximum, $0.upper); return maximum }
        subtreeMaximumEnds = Array(repeating: -.infinity, count: max(1, starts.count * 4))
        if !starts.isEmpty { buildMaximumEnds(node: 1, lower: 0, upper: starts.count) }
    }

    private mutating func buildMaximumEnds(node: Int, lower: Int, upper: Int) {
        if upper - lower == 1 { subtreeMaximumEnds[node] = starts[lower].upper; return }
        let middle = lower + (upper - lower) / 2
        buildMaximumEnds(node: node * 2, lower: lower, upper: middle)
        buildMaximumEnds(node: node * 2 + 1, lower: middle, upper: upper)
        subtreeMaximumEnds[node] = max(subtreeMaximumEnds[node * 2], subtreeMaximumEnds[node * 2 + 1])
    }

    /// Inclusive intersections, in original input order. Subtree maxima prune
    /// disjoint ranges even when one early float overlaps many later paragraphs.
    func intersecting(_ range: ClosedRange<CGFloat>) -> [Int] {
        guard !starts.isEmpty, range.lowerBound.isFinite, range.upperBound.isFinite else { return [] }
        let right = partition(starts.count) { starts[$0].lower <= range.upperBound }
        var result: [Int] = []
        func visit(node: Int, lower: Int, upper: Int) {
            guard lower < right, subtreeMaximumEnds[node] >= range.lowerBound else { return }
            if upper - lower == 1 { result.append(starts[lower].ordinal); return }
            let middle = lower + (upper - lower) / 2
            visit(node: node * 2, lower: lower, upper: middle)
            visit(node: node * 2 + 1, lower: middle, upper: upper)
        }
        visit(node: 1, lower: 0, upper: starts.count)
        return result.sorted()
    }

    private func ordered(_ intervals: [Interval], reusing previous: [Interval],
                         by precedes: (Interval, Interval) -> Bool) -> [Interval] {
        // Normal estimate corrections translate paragraphs without reordering
        // them. Validate the previous permutation in O(n); sort only if the
        // geometry really changes order (for example, overlapping floats).
        if previous.count == intervals.count {
            let updated = previous.map { intervals[$0.ordinal] }
            if zip(updated, updated.dropFirst()).allSatisfy({ precedes($0.0, $0.1) }) { return updated }
        }
        return intervals.sorted(by: precedes)
    }

    func nearest(to value: CGFloat) -> Int? {
        guard !starts.isEmpty, value.isFinite else { return nil }
        // First interval strictly to the right of the point.
        let right = partition(starts.count) { starts[$0].lower <= value }
        var cursor = right
        var containing: Int?
        // Prefix maxima preserve overlapping floats and nested geometry. For
        // ordinary sequential paragraphs this inspects just the local entry.
        while cursor > 0, maximumEnds[cursor - 1] >= value {
            cursor -= 1
            let interval = starts[cursor]
            if interval.upper >= value { containing = min(containing ?? interval.ordinal, interval.ordinal) }
        }
        if let containing { return containing }
        let end = partition(ends.count) { ends[$0].upper < value }
        var best = right < starts.count ? starts[right] : nil
        if end > 0 {
            let nearestEnd = ends[end - 1].upper
            // Equal ends are sorted by input order, not by traversal direction.
            let left = ends[partition(ends.count) { ends[$0].upper < nearestEnd }]
            if let candidate = best {
                let leftDistance = value - left.upper
                let rightDistance = candidate.lower - value
                if leftDistance < rightDistance || (leftDistance == rightDistance && left.ordinal < candidate.ordinal) {
                    best = left
                }
            } else { best = left }
        }
        return best?.ordinal
    }

    private func partition(_ count: Int, while predicate: (Int) -> Bool) -> Int {
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(middle) { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }
}
