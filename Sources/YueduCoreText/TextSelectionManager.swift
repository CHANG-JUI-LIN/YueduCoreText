import Foundation

/// Manages a mutable, UTF-16-indexed text selection.
///
/// `TextSelectionManager` is a mutable reference type and is intentionally not
/// `Sendable`. Consumers must confine each instance to an actor or a serial
/// queue.
public final class TextSelectionManager {
    public private(set) var anchorIndex: Int?
    public private(set) var focusIndex: Int?

    public var selectedRange: NSRange? {
        guard let anchor = anchorIndex, let focus = focusIndex else { return nil }
        let start = min(anchor, focus)
        let end = max(anchor, focus)
        let (distance, distanceOverflow) = end.subtractingReportingOverflow(start)
        guard !distanceOverflow else { return nil }
        let (length, lengthOverflow) = distance.addingReportingOverflow(1)
        guard !lengthOverflow else { return nil }
        return NSRange(location: start, length: length)
    }

    public var hasSelection: Bool {
        guard let range = selectedRange else { return false }
        return range.length > 0
    }

    public var selectionBounds: (start: Int, end: Int)? {
        guard let range = selectedRange else { return nil }
        let (rangeEnd, overflow) = range.location.addingReportingOverflow(range.length - 1)
        guard !overflow else { return nil }
        return (range.location, rangeEnd)
    }

    public init() {}

    public func beginSelection(at index: Int, maxLength: Int) {
        guard maxLength > 0, index != NSNotFound else {
            clear()
            return
        }
        let clamped = clamp(index, maxLength: maxLength)
        anchorIndex = clamped
        focusIndex = clamped
    }

    public func setSelection(range: NSRange, maxLength: Int) {
        guard maxLength > 0,
              range.location != NSNotFound,
              range.length > 0
        else {
            clear()
            return
        }
        let (rangeEnd, overflow) = range.location.addingReportingOverflow(range.length - 1)
        guard !overflow else {
            clear()
            return
        }
        let start = clamp(range.location, maxLength: maxLength)
        let end = clamp(rangeEnd, maxLength: maxLength)
        anchorIndex = min(start, end)
        focusIndex = max(start, end)
    }

    public func updateSelection(to index: Int, maxLength: Int) {
        guard maxLength > 0 else {
            clear()
            return
        }
        guard index != NSNotFound else { return }
        guard anchorIndex != nil else { return }
        focusIndex = clamp(index, maxLength: maxLength)
    }

    public func updateSelectionStart(to index: Int, maxLength: Int) {
        guard maxLength > 0 else {
            clear()
            return
        }
        guard index != NSNotFound else { return }
        guard focusIndex != nil else { return }
        anchorIndex = clamp(index, maxLength: maxLength)
    }

    public func updateSelectionEnd(to index: Int, maxLength: Int) {
        guard maxLength > 0 else {
            clear()
            return
        }
        guard index != NSNotFound else { return }
        guard anchorIndex != nil else { return }
        focusIndex = clamp(index, maxLength: maxLength)
    }

    public func clear() {
        anchorIndex = nil
        focusIndex = nil
    }

    public func selectedText(in attributedString: NSAttributedString) -> String? {
        guard let range = selectedRange,
              range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              range.location <= attributedString.length,
              range.length <= attributedString.length - range.location
        else {
            return nil
        }
        return (attributedString.string as NSString).substring(with: range)
    }

    private func clamp(_ index: Int, maxLength: Int) -> Int {
        guard maxLength > 0 else { return 0 }
        return min(max(0, index), maxLength - 1)
    }
}
