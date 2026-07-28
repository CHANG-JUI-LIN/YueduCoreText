import Foundation
import Testing
import YueduCoreText

@Suite("Text selection manager public API")
struct TextSelectionManagerTests {
    @Test("Creates a forward selection")
    func createsForwardSelection() {
        let manager = TextSelectionManager()

        manager.beginSelection(at: 2, maxLength: 10)
        manager.updateSelection(to: 5, maxLength: 10)

        #expect(manager.anchorIndex == 2)
        #expect(manager.focusIndex == 5)
        #expect(manager.selectedRange == NSRange(location: 2, length: 4))
        #expect(manager.hasSelection)
        let bounds = manager.selectionBounds
        #expect(bounds?.start == 2)
        #expect(bounds?.end == 5)
    }

    @Test("Creates a reverse selection")
    func createsReverseSelection() {
        let manager = TextSelectionManager()

        manager.beginSelection(at: 5, maxLength: 10)
        manager.updateSelection(to: 2, maxLength: 10)

        #expect(manager.anchorIndex == 5)
        #expect(manager.focusIndex == 2)
        #expect(manager.selectedRange == NSRange(location: 2, length: 4))
        let bounds = manager.selectionBounds
        #expect(bounds?.start == 2)
        #expect(bounds?.end == 5)
    }

    @Test(
        "Clamps selection start indexes",
        arguments: [
            (index: -4, expected: 0),
            (index: 12, expected: 4),
        ]
    )
    func clampsSelectionStart(index: Int, expected: Int) {
        let manager = TextSelectionManager()

        manager.beginSelection(at: index, maxLength: 5)

        #expect(manager.anchorIndex == expected)
        #expect(manager.focusIndex == expected)
        #expect(manager.selectedRange == NSRange(location: expected, length: 1))
    }

    @Test(
        "Clamps selection updates",
        arguments: [
            (index: -4, expected: 0),
            (index: 12, expected: 4),
        ]
    )
    func clampsSelectionUpdate(index: Int, expected: Int) {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 2, maxLength: 5)

        manager.updateSelection(to: index, maxLength: 5)

        #expect(manager.focusIndex == expected)
    }

    @Test("Clears when setSelection receives an invalid maximum length")
    func clearsForInvalidMaximumLength() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(range: NSRange(location: 0, length: 1), maxLength: 0)

        #expect(!manager.hasSelection)
    }

    @Test("Clears when setSelection receives an empty range")
    func clearsForEmptyRange() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(range: NSRange(location: 1, length: 0), maxLength: 3)

        #expect(!manager.hasSelection)
    }

    @Test("Clears when setSelection range arithmetic would overflow")
    func clearsForOverflowingRange() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(
            range: NSRange(location: Int.max, length: 2),
            maxLength: Int.max
        )

        #expect(!manager.hasSelection)
    }

    @Test("Start handle crossing the end becomes a forward selection")
    func startHandleCrossesEnd() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 2, length: 3), maxLength: 10)

        manager.updateSelectionStart(to: 7, maxLength: 10)

        #expect(manager.anchorIndex == 4)
        #expect(manager.focusIndex == 7)
        #expect(manager.selectedRange == NSRange(location: 4, length: 4))
    }

    @Test("End handle crossing the start becomes a reverse selection")
    func endHandleCrossesStart() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 2, length: 3), maxLength: 10)

        manager.updateSelectionEnd(to: 0, maxLength: 10)

        #expect(manager.anchorIndex == 0)
        #expect(manager.focusIndex == 2)
        #expect(manager.selectedRange == NSRange(location: 0, length: 3))
    }

    @Test("Clears all selection state")
    func clearsSelection() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 2, maxLength: 5)

        manager.clear()

        #expect(manager.anchorIndex == nil)
        #expect(manager.focusIndex == nil)
        #expect(manager.selectedRange == nil)
        #expect(manager.selectionBounds == nil)
        #expect(!manager.hasSelection)
    }

    @Test("Extracts selected text using UTF-16 indexes")
    func extractsEmojiUsingUTF16Indexes() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: 4)
        let attributedString = NSAttributedString(string: "A😀中")

        #expect(manager.selectedText(in: attributedString) == "😀")
    }

    @Test("Returns nil when selection exceeds the attributed string")
    func rejectsSelectionOutsideAttributedString() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 3), maxLength: 4)

        #expect(manager.selectedText(in: NSAttributedString(string: "ab")) == nil)
    }
}
